import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';

import '../domain/sora_models.dart';
import '../domain/sora_parsers.dart';
import 'sora_addon_store.dart';

class SoraJsRuntime {
  SoraJsRuntime({required SoraAddonStore store, Dio? dio, String? webProxyUrl})
    : _store = store,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 16),
              receiveTimeout: const Duration(seconds: 28),
              followRedirects: true,
              validateStatus: (_) => true,
            ),
          );

  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36 MiruShin/1.0';

  static const int _maxSearchBodyBytes = 96 * 1024;
  // Episode APIs can include many voiceover/player entries in one JSON body.
  static const int _maxBodyBytes = 8 * 1024 * 1024;


  final SoraAddonStore _store;
  final Dio _dio;
  final Map<String, _LoadedSoraModule> _loaded = <String, _LoadedSoraModule>{};
  final List<String> _loadOrder = <String>[];
  Future<void> _jsTail = Future<void>.value();

  // Pending host→JS request bookkeeping. We never hand a Dart Future across the
  // flutter_js bridge (the `_dartToJs(Future)` → promise-capability → native
  // resolve-callback path is what corrupts QuickJS under heavy fetch load and
  // SIGSEGVs on Linux). Instead every async hop is a synchronous channel
  // message plus a pure-JS promise resolved later via `evaluate('__miruResolve…')`.
  int _reqSeq = 0;
  // Active `_call` completers keyed by call id; completed by the synchronous
  // `MiruSoraCallDone` channel message rather than `handlePromise`.
  final Map<String, Completer<String>> _pendingCalls =
      <String, Completer<String>>{};

  // Single shared QuickJS/JavaScriptCore context for all addon modules.
  // Created lazily on first use. Never disposed during normal operation —
  // creating and destroying per-addon contexts caused SIGSEGV in QuickJS on
  // Linux (the dispose path races with pending promise callbacks).
  JavascriptRuntime? _sharedRuntime;

  // Persistent QuickJS event-loop pump.
  //
  // flutter_js's QuickJS binding (QuickJsRuntime2) ships WITHOUT a running
  // event loop — its `dispatch()` has the `await for (port)` loop commented
  // out, so pending JS jobs only drain while `handlePromise`'s short-lived
  // 20ms timer is alive. The moment the awaited promise settles, that timer is
  // cancelled. Any background task an addon fired but didn't await (a
  // fire-and-forget `fetchv2`, a `setTimeout`) later completes on the Dart side
  // and re-enters QuickJS via the promise-resolve callback in
  // `_dartToJs(Future)` — which enqueues reaction jobs that nothing pumps.
  // Those stale jobs run interleaved with the next evaluation after GC has
  // moved/freed objects, jumping through a dangling function pointer → SIGSEGV
  // (the libquickjs_c_bridge crash seen on Linux). JavaScriptCore on
  // iOS/macOS has its own internal microtask loop, so it never hits this.
  //
  // The fix is to be that event loop: continuously drain pending jobs for the
  // whole life of the runtime so every promise resolution runs promptly in a
  // consistent VM, exactly like JSC does internally. Only needed on the
  // QuickJS platforms; JSC drains itself.
  Timer? _pump;

  static bool get _usesQuickJs =>
      Platform.isLinux || Platform.isWindows || Platform.isAndroid;

  JavascriptRuntime _runtime() {
    final JavascriptRuntime? existing = _sharedRuntime;
    if (existing != null) return existing;
    final JavascriptRuntime rt = getJavascriptRuntime(xhr: false);
    _installSharedBridge(rt);
    _sharedRuntime = rt;
    if (_usesQuickJs) {
      _pump ??= Timer.periodic(const Duration(milliseconds: 10), (_) {
        final JavascriptRuntime? r = _sharedRuntime;
        if (r == null) return;
        try {
          r.executePendingJob();
        } catch (_) {
          // A throw here must never crash the pump; the next tick retries.
        }
      });
    }
    return rt;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<List<SoraSearchResult>> searchResults({
    required SoraInstalledAddon addon,
    required String keyword,
    required String languageCode,
    required List<SoraTitleVariant> titleVariants,
    bool Function()? shouldCancel,
  }) {
    return _serialized(() async {
      if (shouldCancel?.call() ?? false) {
        return const <SoraSearchResult>[];
      }
      final Object? payload = await _call(
        addon: addon,
        functionNames: const <String>[
          'searchResults',
          'searchContent',
          'search',
          'searchAnime',
          'searchAnimes',
          'searchResult',
        ],
        args: <Object?>[keyword],
        settlePending: false,
      );
      return parseSoraSearchResults(
        payload: payload,
        addonId: addon.id,
        addonName: addon.manifest.sourceName,
        languageCode: languageCode,
        query: keyword,
        titleVariants: titleVariants,
      );
    });
  }

  Future<SoraSourceDetails> extractDetails({
    required SoraInstalledAddon addon,
    required SoraSearchResult result,
  }) {
    return _serialized(() async {
      final Object? payload = await _call(
        addon: addon,
        functionNames: const <String>[
          'extractDetails',
          'getContentData',
          'getDetails',
          'details',
        ],
        args: <Object?>[result.href],
        required: false,
      );
      return parseSoraDetails(payload, result.title);
    });
  }

  Future<List<SoraEpisode>> extractEpisodes({
    required SoraInstalledAddon addon,
    required SoraSearchResult result,
  }) {
    return _serialized(() async {
      final List<Object?> args = await _episodeCallArgs(addon, result);
      final Object? payload = await _call(
        addon: addon,
        functionNames: const <String>[
          'extractEpisodes',
          'extractChapters',
          'extractChapterList',
          'getChapters',
          'getChapterList',
          'getEpisodes',
          'episodes',
        ],
        args: args,
        settlePending: false,
      );
      final List<SoraEpisode> episodes = parseSoraEpisodes(payload);
      if (episodes.isNotEmpty) {
        return episodes;
      }
      return <SoraEpisode>[
        SoraEpisode(
          number: 1,
          href: result.href,
          title: result.title,
          image: result.image,
          description: '',
          duration: '',
        ),
      ];
    });
  }

  Future<SoraResolvedStreams> extractStreams({
    required SoraInstalledAddon addon,
    required SoraEpisode episode,
    String? voiceover,
  }) {
    return _serialized(() async {
      final List<Object?> args = <Object?>[
        episode.href,
        if (voiceover != null && voiceover.trim().isNotEmpty) voiceover.trim(),
      ];
      final Object? payload = await _call(
        addon: addon,
        functionNames: const <String>[
          'extractStreamUrl',
          'extractStream',
          'getStreamUrl',
          'streams',
        ],
        args: args,
      );
      return SoraResolvedStreams(
        addonId: addon.id,
        episode: episode,
        candidates: parseSoraStreamCandidates(payload),
        raw: payload,
      );
    });
  }

  Future<SoraResolvedStreams> refreshStream({
    required SoraInstalledAddon addon,
    required SoraEpisode episode,
    String? voiceover,
  }) => extractStreams(addon: addon, episode: episode, voiceover: voiceover);

  void invalidate(String addonId) {
    unawaited(_serialized<void>(() async => _removeModule(addonId)));
  }

  void invalidateAll() {
    unawaited(_serialized<void>(() async => _removeAllModules()));
  }

  void cancelActiveSearches() {
    for (final _LoadedSoraModule module in _loaded.values) {
      if (!module.isSearchCall) continue;
      module.cancelPendingFetches();
      module.cancelPendingDelays();
    }
  }

  // ── Internal queue ────────────────────────────────────────────────────────

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final Future<void> previous = _jsTail;
    final Completer<void> gate = Completer<void>();
    _jsTail = gate.future;
    try {
      await previous.catchError((Object _) {});
      return await action();
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  // ── Module lifecycle ──────────────────────────────────────────────────────

  void _removeModule(String addonId) {
    _loadOrder.remove(addonId);
    final _LoadedSoraModule? module = _loaded.remove(addonId);
    module?.cancelPendingDelays();
    module?.cancelPendingFetches();
    module?._disposed = true;
    // Remove from the shared JS namespace so the old code is GC'd.
    try {
      _sharedRuntime?.evaluate(
        'if(globalThis.__miruSoraModules)'
        ' delete globalThis.__miruSoraModules[${jsonEncode(addonId)}];',
      );
    } catch (_) {}
  }

  void _removeAllModules() {
    for (final _LoadedSoraModule module in _loaded.values) {
      module.cancelPendingDelays();
      module.cancelPendingFetches();
      module._disposed = true;
    }
    _loaded.clear();
    _loadOrder.clear();
    try {
      _sharedRuntime?.evaluate('globalThis.__miruSoraModules = {};');
    } catch (_) {}
  }

  // ── JS call ───────────────────────────────────────────────────────────────

  Future<Object?> _call({
    required SoraInstalledAddon addon,
    required List<String> functionNames,
    required List<Object?> args,
    bool required = true,
    bool settlePending = true,
  }) async {
    final _LoadedSoraModule module = await _load(addon);
    final JavascriptRuntime rt = _runtime();

    // Set per-call addon context so message-bridge handlers know which addon
    // is active. Safe because all JS calls are serialized.
    rt.evaluate(
      'globalThis.__miruCurrentAddonId=${jsonEncode(addon.id)};'
      'globalThis.__miruSoraBaseUrl=${jsonEncode(addon.manifest.baseUrl)};'
      'globalThis.__miruSoraSearchBaseUrl=${jsonEncode(addon.manifest.searchBaseUrl)};',
    );

    final String argsJson = jsonEncode(args);
    try {
      for (final String functionName in functionNames) {
        module.activeFunctionName = functionName;
        final Object? decoded = await _invokeFunction(
          rt: rt,
          addon: addon,
          functionName: functionName,
          argsJson: argsJson,
        );
        module.activeFunctionName = null;
        if (_isMissingFunction(decoded)) {
          continue;
        }
        return decoded;
      }
      if (!required) {
        return null;
      }
      throw SoraAddonException(
        '${addon.manifest.sourceName} does not expose ${functionNames.first}().',
      );
    } finally {
      // Let any fire-and-forget background tasks (un-awaited fetchv2 /
      // setTimeout) this call spawned settle BEFORE releasing the serialize
      // lock, so none of them resolve later against the next addon's mutated
      // global context.
      if (settlePending) {
        await _settlePending(rt, module);
      }
    }
  }

  // Runs a single addon function and waits for its result via a synchronous
  // `MiruSoraCallDone` channel message — NOT `handlePromise`. The async IIFE
  // resolves entirely inside QuickJS (driven by the persistent pump); host I/O
  // is dispatched through synchronous channel messages and resolved back into
  // JS via `evaluate('__miruResolve…')`. No Dart Future ever crosses the
  // flutter_js bridge, so the crashing `_dartToJs(Future)` path is never hit.
  Future<Object?> _invokeFunction({
    required JavascriptRuntime rt,
    required SoraInstalledAddon addon,
    required String functionName,
    required String argsJson,
  }) async {
    final String callId = 'c${_reqSeq++}';
    final Completer<String> completer = Completer<String>();
    _pendingCalls[callId] = completer;

    final String expression =
        '''
      (function() {
        var __cid = ${jsonEncode(callId)};
        Promise.resolve().then(function() {
          globalThis.__miruCurrentAddonId = ${jsonEncode(addon.id)};
          var module = globalThis.__miruSoraModules && globalThis.__miruSoraModules[${jsonEncode(addon.id)}];
          var fn = module && module[${jsonEncode(functionName)}];
          if (typeof fn !== 'function') {
            return { "__miruMissingFunction": true };
          }
          var args = $argsJson;
          return Promise.resolve(fn.apply(null, args));
        }).then(function(value) {
          globalThis.__miruSoraCallDone(__cid, true, globalThis.__miruSoraSerializeResult(value));
        }, function(err) {
          globalThis.__miruSoraCallDone(__cid, false, String(err && err.message ? err.message : err));
        });
      })();
    ''';

    try {
      final JsEvalResult initial = rt.evaluate(expression);
      if (initial.isError) {
        throw SoraAddonException(
          'Failed to invoke ${addon.manifest.sourceName}.$functionName: '
          '${initial.stringResult}',
        );
      }
      // Drive the engine until the call settles. The pump already runs on
      // QuickJS; we also nudge it here so JSC (no pump) makes progress.
      final String payload = await _awaitCall(rt, completer);
      return _decodeCallPayload(payload);
    } finally {
      _pendingCalls.remove(callId);
    }
  }

  Future<String> _awaitCall(
    JavascriptRuntime rt,
    Completer<String> completer,
  ) async {
    // Safety valve: an addon that never resolves must not hang the queue.
    const Duration callTimeout = Duration(seconds: 45);
    final Stopwatch sw = Stopwatch()..start();
    while (!completer.isCompleted) {
      try {
        rt.executePendingJob();
      } catch (_) {}
      if (sw.elapsed >= callTimeout) {
        if (!completer.isCompleted) {
          completer.complete(
            jsonEncode(<String, Object?>{'ok': false, 'error': 'timeout'}),
          );
        }
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    return completer.future;
  }

  Object? _decodeCallPayload(String payload) {
    Map<String, dynamic> envelope;
    try {
      final Object? parsed = jsonDecode(payload);
      envelope = parsed is Map
          ? parsed.map(
              (Object? k, Object? v) => MapEntry<String, dynamic>('$k', v),
            )
          : <String, dynamic>{};
    } catch (_) {
      envelope = <String, dynamic>{};
    }
    final bool ok = envelope['ok'] == true;
    if (!ok) {
      final String error = _string(envelope['error'], fallback: 'addon error');
      throw SoraAddonException(error);
    }
    final Object? result = envelope['result'];
    if (result is String) {
      return decodeSoraPayload(result);
    }
    return result;
  }

  // Wait for background host requests spawned during this call to settle, so a
  // straggler can't resolve against the next addon's context. Resolution is
  // pure-JS (`evaluate('__miruResolve…')`), so there is no crash risk here —
  // this is purely for correctness/cleanliness.
  Future<void> _settlePending(
    JavascriptRuntime rt,
    _LoadedSoraModule module,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    const Duration budget = Duration(seconds: 5);
    const Duration hardStop = Duration(seconds: 7);
    bool cancelled = false;
    while (true) {
      int size;
      try {
        rt.executePendingJob();
        final JsEvalResult r = rt.evaluate(
          '(globalThis.__miruSoraPendingResolvers ? '
          'Object.keys(globalThis.__miruSoraPendingResolvers).length : 0)',
        );
        size = int.tryParse(r.stringResult.trim()) ?? 0;
      } catch (_) {
        return;
      }
      if (size <= 0) return;
      if (!cancelled && sw.elapsed >= budget) {
        module.cancelPendingFetches();
        module.cancelPendingDelays();
        cancelled = true;
      }
      if (sw.elapsed >= hardStop) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }

  Future<_LoadedSoraModule> _load(SoraInstalledAddon addon) async {
    final _LoadedSoraModule? cached = _loaded[addon.id];
    if (cached != null && cached.scriptPath == addon.scriptPath) {
      _loadOrder.remove(addon.id);
      _loadOrder.add(addon.id);
      return cached;
    }
    // Remove any stale version of this module (script changed).
    _removeModule(addon.id);

    final String source = await _store.readScript(addon);
    final JavascriptRuntime rt = _runtime();
    final String moduleSource = _prepareModuleSource(source);
    final String wrapper =
        '''
      globalThis.__miruSoraModules = globalThis.__miruSoraModules || {};
      (function() {
        const module = { exports: {} };
        var exports = module.exports;
        const global = globalThis;
        $moduleSource
        const exported = module.exports || {};
        const defaults = exported.default || {};
        globalThis.__miruSoraModules[${jsonEncode(addon.id)}] = {
          searchResults:
            (typeof searchResults === 'function' && searchResults) ||
            exported.searchResults || defaults.searchResults,
          searchContent:
            (typeof searchContent === 'function' && searchContent) ||
            exported.searchContent || defaults.searchContent,
          searchResult:
            (typeof searchResult === 'function' && searchResult) ||
            exported.searchResult || defaults.searchResult,
          searchAnimes:
            (typeof searchAnimes === 'function' && searchAnimes) ||
            exported.searchAnimes || defaults.searchAnimes,
          extractDetails:
            (typeof extractDetails === 'function' && extractDetails) ||
            exported.extractDetails || defaults.extractDetails,
          getContentData:
            (typeof getContentData === 'function' && getContentData) ||
            exported.getContentData || defaults.getContentData,
          extractEpisodes:
            (typeof extractEpisodes === 'function' && extractEpisodes) ||
            exported.extractEpisodes || defaults.extractEpisodes,
          extractChapters:
            (typeof extractChapters === 'function' && extractChapters) ||
            exported.extractChapters || defaults.extractChapters,
          extractChapterList:
            (typeof extractChapterList === 'function' && extractChapterList) ||
            exported.extractChapterList || defaults.extractChapterList,
          getChapters:
            (typeof getChapters === 'function' && getChapters) ||
            exported.getChapters || defaults.getChapters,
          getChapterList:
            (typeof getChapterList === 'function' && getChapterList) ||
            exported.getChapterList || defaults.getChapterList,
          extractStreamUrl:
            (typeof extractStreamUrl === 'function' && extractStreamUrl) ||
            exported.extractStreamUrl || defaults.extractStreamUrl,
          search:
            (typeof search === 'function' && search) ||
            exported.search || defaults.search,
          getDetails:
            (typeof getDetails === 'function' && getDetails) ||
            exported.getDetails || defaults.getDetails,
          details:
            (typeof details === 'function' && details) ||
            exported.details || defaults.details,
          getEpisodes:
            (typeof getEpisodes === 'function' && getEpisodes) ||
            exported.getEpisodes || defaults.getEpisodes,
          episodes:
            (typeof episodes === 'function' && episodes) ||
            exported.episodes || defaults.episodes,
          extractStream:
            (typeof extractStream === 'function' && extractStream) ||
            exported.extractStream || defaults.extractStream,
          getStreamUrl:
            (typeof getStreamUrl === 'function' && getStreamUrl) ||
            exported.getStreamUrl || defaults.getStreamUrl,
          streams:
            (typeof streams === 'function' && streams) ||
            exported.streams || defaults.streams
        };
      })();
    ''';
    final JsEvalResult result = rt.evaluate(
      wrapper,
      sourceUrl: addon.scriptPath,
    );
    if (result.isError) {
      throw SoraAddonException(
        'Failed to load ${addon.manifest.sourceName}: ${result.stringResult}',
      );
    }
    final _LoadedSoraModule loaded = _LoadedSoraModule(
      addon: addon,
      scriptPath: addon.scriptPath,
      logs: <String>[],
    );
    _loaded[addon.id] = loaded;
    _loadOrder.add(addon.id);
    return loaded;
  }

  // ── Shared bridge (installed once per runtime) ────────────────────────────

  void _installSharedBridge(JavascriptRuntime runtime) {
    runtime.onMessage('MiruSoraLog', (dynamic args) {
      final Map<String, dynamic> payload = _asMap(args);
      final String addonId = _string(payload['__addonId']);
      final dynamic msgs = payload['messages'];
      final String message = msgs is List
          ? msgs.join(' ')
          : msgs?.toString() ?? '';
      if (message.trim().isNotEmpty) {
        _loaded[addonId]?.logs.add(message);
      }
      return null;
    });

    // Completion of a top-level `_call`. Synchronous: just complete the Dart
    // completer the JS side resolved into. Never returns a Future.
    runtime.onMessage('MiruSoraCallDone', (dynamic args) {
      final Map<String, dynamic> payload = _asMap(args);
      final String callId = _string(payload['__cid']);
      final Completer<String>? completer = _pendingCalls[callId];
      if (completer != null && !completer.isCompleted) {
        completer.complete(
          jsonEncode(<String, Object?>{
            'ok': payload['ok'] == true,
            'result': payload['result'],
            'error': payload['error'],
          }),
        );
      }
      return null;
    });

    // ── Async host requests ──────────────────────────────────────────────
    // Each handler is SYNCHRONOUS (returns an ack string, never a Future).
    // The real work runs in the background and resolves the pure-JS promise
    // via `evaluate('__miruSoraResolve(id, …)')`. This avoids the
    // `_dartToJs(Future)` promise-capability path that corrupts QuickJS.
    runtime.onMessage('MiruSoraHttpFetch', (dynamic args) {
      final Map<String, dynamic> payload = _asMap(args);
      final String reqId = _string(payload['__reqId']);
      final String addonId = _string(payload['__addonId']);
      unawaited(_dispatchHttpFetch(reqId, addonId, payload));
      return 'ok';
    });

    runtime.onMessage('MiruSoraDelay', (dynamic args) {
      final Map<String, dynamic> payload = _asMap(args);
      final String reqId = _string(payload['__reqId']);
      final String addonId = _string(payload['__addonId']);
      unawaited(_dispatchDelay(reqId, addonId, payload));
      return 'ok';
    });

    runtime.onMessage('MiruSoraNetworkFetch', (dynamic args) {
      final Map<String, dynamic> payload = _asMap(args);
      final String reqId = _string(payload['__reqId']);
      final String addonId = _string(payload['__addonId']);
      unawaited(_dispatchNetworkFetch(reqId, addonId, payload));
      return 'ok';
    });

    runtime.evaluate(_bridgeScript());
  }

  // Resolve a pending JS promise by calling back into JS via `evaluate` — the
  // stable path. `raw` is passed as a JS string the bridge JSON-parses.
  void _resolveJs(String reqId, String raw) {
    if (reqId.isEmpty) return;
    final JavascriptRuntime? rt = _sharedRuntime;
    if (rt == null) return;
    try {
      rt.evaluate(
        'globalThis.__miruSoraResolve && '
        'globalThis.__miruSoraResolve(${jsonEncode(reqId)}, ${jsonEncode(raw)});',
      );
      // Nudge the engine so the resolved promise's continuations run promptly
      // (QuickJS has the pump; JSC drains on evaluate, this is belt-and-braces).
      rt.executePendingJob();
    } catch (_) {}
  }

  Future<void> _dispatchHttpFetch(
    String reqId,
    String addonId,
    Map<String, dynamic> payload,
  ) async {
    final _LoadedSoraModule? module = _loaded[addonId];
    String body;
    if (module == null || module._disposed) {
      body = jsonEncode(<String, dynamic>{
        '__miruResponse': true,
        'status': 0,
        'headers': <String, dynamic>{},
        'body': '',
        'error': 'addon disposed',
      });
    } else {
      try {
        body = await _httpFetchBody(module.addon, payload);
      } catch (error) {
        body = jsonEncode(<String, dynamic>{
          '__miruResponse': true,
          'status': 0,
          'headers': <String, dynamic>{},
          'body': '',
          'error': error.toString(),
        });
      }
    }
    _resolveJs(reqId, body);
  }

  Future<void> _dispatchDelay(
    String reqId,
    String addonId,
    Map<String, dynamic> payload,
  ) async {
    final int ms = _int(
      payload['milliseconds'],
      fallback: 16,
    ).clamp(0, 60000).toInt();
    final _LoadedSoraModule? module = _loaded[addonId];
    if (module == null || module._disposed) {
      _resolveJs(reqId, 'cancelled');
      return;
    }
    final Completer<void> c = Completer<void>();
    module._delayCompleters.add(c);
    try {
      await Future.any(<Future<void>>[
        Future<void>.delayed(Duration(milliseconds: ms)),
        c.future,
      ]);
    } finally {
      module._delayCompleters.remove(c);
      if (!c.isCompleted) c.complete();
    }
    _resolveJs(reqId, 'true');
  }

  Future<void> _dispatchNetworkFetch(
    String reqId,
    String addonId,
    Map<String, dynamic> payload,
  ) async {
    final _LoadedSoraModule? module = _loaded[addonId];
    String body;
    if (module == null || module._disposed) {
      body = jsonEncode(<String, Object?>{
        'originalUrl': _string(payload['url']),
        'requests': <String>[],
        'html': null,
        'cookies': null,
        'success': false,
        'error': 'addon disposed',
        'cutoffTriggered': false,
        'cutoffUrl': null,
        'htmlCaptured': false,
        'cookiesCaptured': false,
        'elementsClicked': <String>[],
        'waitResults': <String, bool>{},
      });
    } else {
      try {
        body = await _networkFetch(module.addon, payload);
      } catch (error) {
        body = jsonEncode(<String, Object?>{
          'originalUrl': _string(payload['url']),
          'requests': <String>[],
          'html': null,
          'cookies': null,
          'success': false,
          'error': error.toString(),
          'cutoffTriggered': false,
          'cutoffUrl': null,
          'htmlCaptured': false,
          'cookiesCaptured': false,
          'elementsClicked': <String>[],
          'waitResults': <String, bool>{},
        });
      }
    }
    _resolveJs(reqId, body);
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Future<String> _httpFetchBody(
    SoraInstalledAddon addon,
    Map<String, dynamic> payload,
  ) async {
    try {
      final Uri uri = _resolveUrl(
        _string(payload['url']),
        addon.manifest.baseUrl,
      );
      final Map<String, String> headers = <String, String>{
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/json,text/plain,*/*',
        'Accept-Language': _acceptLanguage(addon.manifest.language),
        if (addon.manifest.baseUrl.trim().isNotEmpty)
          'Referer': addon.manifest.baseUrl,
        ..._stringMap(payload['headers']),
      };
      final String method = _string(
        payload['method'],
        fallback: 'GET',
      ).toUpperCase();
      final Object? rawBody = payload['body'];
      final Object? body = rawBody is Map || rawBody is List
          ? jsonEncode(rawBody)
          : rawBody;
      final _LoadedSoraModule? module = _loaded[addon.id];
      final bool searchCall = module?.isSearchCall ?? false;
      final CancelToken cancelToken = CancelToken();
      module?.registerCancelToken(cancelToken);
      final Response<String> response;
      try {
        response = await _dio.requestUri<String>(
          uri,
          data: body,
          options: Options(
            method: method,
            responseType: ResponseType.plain,
            headers: headers,
            receiveTimeout: searchCall
                ? const Duration(seconds: 10)
                : const Duration(seconds: 20),
            followRedirects: true,
            validateStatus: (_) => true,
          ),
          cancelToken: cancelToken,
        );
      } finally {
        module?.unregisterCancelToken(cancelToken);
      }
      final Map<String, dynamic> responseHeaders = <String, dynamic>{};
      response.headers.forEach((String name, List<String> values) {
        if (values.isEmpty) return;
        responseHeaders[name] = values.length == 1 ? values.first : values;
      });
      return jsonEncode(<String, dynamic>{
        '__miruResponse': true,
        'status': response.statusCode ?? 0,
        'headers': responseHeaders,
        'body': _truncateBody(addon, response.data ?? ''),
      });
    } on Object catch (error) {
      return jsonEncode(<String, dynamic>{
        '__miruResponse': true,
        'status': 0,
        'headers': <String, dynamic>{},
        'body': '',
        'error': error.toString(),
      });
    }
  }

  Future<String> _networkFetch(
    SoraInstalledAddon addon,
    Map<String, dynamic> payload,
  ) async {
    final String originalUrl = _string(payload['url']);
    final Set<String> requests = <String>{};
    try {
      final Uri uri = _resolveUrl(originalUrl, addon.manifest.baseUrl);
      requests.add(uri.toString());
      final String htmlContent = _string(payload['htmlContent']);
      final String body;
      Uri responseUri = uri;
      if (htmlContent.isNotEmpty) {
        body = htmlContent;
      } else {
        final int timeoutSec =
            _int(payload['timeoutSeconds'], fallback: 7).clamp(1, 30).toInt();
        final Map<String, String> headers = <String, String>{
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/json,text/plain,*/*',
          'Accept-Language': _acceptLanguage(addon.manifest.language),
          ..._stringMap(payload['headers']),
        };
        final _LoadedSoraModule? module = _loaded[addon.id];
        final CancelToken cancelToken = CancelToken();
        module?.registerCancelToken(cancelToken);
        final Response<String> response;
        try {
          response = await _dio.requestUri<String>(
            uri,
            options: Options(
              method: 'GET',
              responseType: ResponseType.plain,
              headers: headers,
              receiveTimeout: Duration(seconds: timeoutSec),
              followRedirects: true,
              validateStatus: (_) => true,
            ),
            cancelToken: cancelToken,
          );
        } finally {
          module?.unregisterCancelToken(cancelToken);
        }
        responseUri = response.realUri;
        requests.add(responseUri.toString());
        body = response.data ?? '';
      }
      for (final String u in _extractNetworkUrls(body, responseUri)) {
        requests.add(u);
      }
      final String cutoff = _string(payload['cutoff']).toLowerCase();
      final String cutoffUrl = cutoff.isEmpty
          ? ''
          : requests.firstWhere(
              (String r) => r.toLowerCase().contains(cutoff),
              orElse: () => '',
            );
      return jsonEncode(<String, Object?>{
        'originalUrl': originalUrl,
        'requests': requests.toList(),
        'html': _bool(payload['returnHTML']) ? body : null,
        'cookies': null,
        'success': true,
        'cutoffTriggered': cutoffUrl.isNotEmpty,
        'cutoffUrl': cutoffUrl.isEmpty ? null : cutoffUrl,
        'htmlCaptured': _bool(payload['returnHTML']),
        'cookiesCaptured': false,
        'elementsClicked': const <String>[],
        'waitResults': const <String, bool>{},
      });
    } on Object catch (error) {
      return jsonEncode(<String, Object?>{
        'originalUrl': originalUrl,
        'requests': requests.toList(),
        'html': null,
        'cookies': null,
        'success': false,
        'error': error.toString(),
        'cutoffTriggered': false,
        'cutoffUrl': null,
        'htmlCaptured': false,
        'cookiesCaptured': false,
        'elementsClicked': const <String>[],
        'waitResults': const <String, bool>{},
      });
    }
  }

  Iterable<String> _extractNetworkUrls(String body, Uri baseUri) sync* {
    final String normalized = body
        .replaceAll(r'\/', '/')
        .replaceAllMapped(
          RegExp(r'\\u([0-9A-Fa-f]{4})'),
          (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAll('&amp;', '&');
    for (final RegExpMatch match in RegExp(
      r'''https?://[^\s"'<>\\]+''',
      caseSensitive: false,
    ).allMatches(normalized)) {
      final String? raw = match.group(0);
      if (raw == null) continue;
      final String cleaned = raw.replaceAll(RegExp(r'[,;)\]\}]+$'), '').trim();
      if (cleaned.isEmpty) continue;
      final Uri? parsed = Uri.tryParse(cleaned);
      if (parsed != null && parsed.hasScheme) yield parsed.toString();
    }
  }

  bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return fallback;
  }

  // ── Bridge script (installed once on the shared runtime) ─────────────────
  //
  // Key difference from the old per-module bridge: every sendMessage call
  // includes `__addonId: globalThis.__miruCurrentAddonId` so the Dart-side
  // handler can route to the correct addon's cancel tokens / logs without
  // needing a separate JavascriptRuntime per addon.

  String _bridgeScript() {
    return r'''
      globalThis.__miruSoraBaseUrl = '';
      globalThis.__miruSoraSearchBaseUrl = '';
      globalThis.__miruCurrentAddonId = '';
      globalThis.__miruSoraPendingResolvers = globalThis.__miruSoraPendingResolvers || {};
      globalThis.__miruSoraReqSeq = globalThis.__miruSoraReqSeq || 0;

      // Resolve a pending host-request promise. Called FROM DART via
      // evaluate('__miruSoraResolve(...)') — the stable bridge path. A Dart
      // Future is never handed back across the bridge (that path corrupts
      // QuickJS), so every async result arrives through here as a string.
      globalThis.__miruSoraResolve = function(id, raw) {
        var r = globalThis.__miruSoraPendingResolvers[id];
        if (!r) return;
        delete globalThis.__miruSoraPendingResolvers[id];
        try { r(raw); } catch (_) {}
      };

      // Report a top-level call's result to Dart through a SYNCHRONOUS channel
      // message (completes a Dart Completer). Replaces handlePromise, which
      // relied on converting this JS promise back into a Dart Future.
      globalThis.__miruSoraCallDone = function(cid, ok, result) {
        try {
          sendMessage('MiruSoraCallDone', JSON.stringify({
            __cid: cid,
            ok: !!ok,
            result: ok ? result : undefined,
            error: ok ? undefined : String(result)
          }));
        } catch (_) {}
      };

      // Start an async host request and return a PURE-JS promise. The host
      // channel handler returns synchronously; the real result is delivered
      // later via __miruSoraResolve. No Dart Future crosses the bridge.
      function __miruAwaitHost(channel, payload) {
        var id = 'r' + (globalThis.__miruSoraReqSeq++);
        return new Promise(function(resolve) {
          globalThis.__miruSoraPendingResolvers[id] = resolve;
          var msg;
          try {
            msg = JSON.stringify(Object.assign({ __reqId: id }, payload));
          } catch (_) {
            msg = JSON.stringify({ __reqId: id });
          }
          try {
            sendMessage(channel, msg);
          } catch (e) {
            delete globalThis.__miruSoraPendingResolvers[id];
            resolve('');
          }
        });
      }

      async function __miruSoraDelay(milliseconds) {
        const bounded = Math.max(0, Math.min(Number(milliseconds) || 0, 60000));
        await __miruAwaitHost('MiruSoraDelay', {
          milliseconds: bounded,
          __addonId: globalThis.__miruCurrentAddonId
        });
      }

      function __miruSoraHeaders(headers) {
        const merged = {};
        if (headers && typeof headers === 'object') {
          for (const key of Object.keys(headers)) {
            if (headers[key] !== undefined && headers[key] !== null) {
              merged[key] = String(headers[key]);
            }
          }
        }
        return merged;
      }

      function __miruSoraNormalizeRequest(url, headers, method, body) {
        let normalizedHeaders = headers || {};
        let normalizedMethod = method || 'GET';
        let normalizedBody = body === undefined ? null : body;
        if (headers && typeof headers === 'object' &&
            (headers.headers || headers.method || headers.body !== undefined)) {
          normalizedHeaders = headers.headers || {};
          normalizedMethod = headers.method || normalizedMethod;
          normalizedBody = headers.body === undefined ? normalizedBody : headers.body;
        }
        return {
          url: String(url),
          headers: __miruSoraHeaders(normalizedHeaders),
          method: String(normalizedMethod || 'GET'),
          body: normalizedBody
        };
      }

      async function __miruSoraNativeFetch(url, headers, method, body) {
        const payload = __miruSoraNormalizeRequest(url, headers, method, body);
        if (__miruSoraShouldBlockRequest(payload)) {
          return {
            ok: true,
            status: 204,
            url: String(payload.url || url),
            headers: {},
            body: ''
          };
        }
        const msgPayload = Object.assign({}, payload, { __addonId: globalThis.__miruCurrentAddonId });
        const raw = await __miruAwaitHost('MiruSoraHttpFetch', msgPayload);
        let status = 200, responseHeaders = {}, responseBody = typeof raw === 'string' ? raw : '';
        try {
          if (typeof raw === 'string') {
            const parsed = JSON.parse(raw);
            if (parsed && parsed.__miruResponse === true) {
              status = typeof parsed.status === 'number' ? (parsed.status || 0) : 200;
              responseHeaders = parsed.headers || {};
              responseBody = typeof parsed.body === 'string' ? parsed.body : '';
            }
          }
        } catch (_) {}
        return {
          ok: status >= 200 && status < 300,
          status: status,
          url: String(payload.url || url),
          headers: responseHeaders,
          body: responseBody
        };
      }

      function __miruSoraShouldBlockRequest(payload) {
        const requestUrl = String(payload && payload.url ? payload.url : '');
        const requestMethod = String(payload && payload.method ? payload.method : 'GET').toUpperCase();
        return requestMethod === 'POST' &&
          /\/\/[^/]*supabase\.co\/rest\/v1\/app_logs(?:\?|$|\/)/i.test(requestUrl);
      }

      globalThis.fetchv2 = function(url, headers, method, body) {
        return (async function() {
          const native = await __miruSoraNativeFetch(url, headers, method, body);
          const responseBody = native && native.body != null ? String(native.body) : '';
          return {
            ok: !!(native && native.ok),
            status: native && native.status ? native.status : 0,
            url: native && native.url ? native.url : String(url),
            headers: native && native.headers ? native.headers : {},
            body: responseBody,
            text: async function() { return responseBody; },
            json: async function() { return JSON.parse(responseBody || 'null'); },
            toString: function() { return responseBody; },
            valueOf: function() { return responseBody; },
            [Symbol.toPrimitive]: function() { return responseBody; }
          };
        })();
      };

      globalThis.__miruSoraSerializeResult = function(value) {
        if (value === undefined || value === null) return 'null';
        if (typeof value === 'string') return value;
        try {
          if (Array.isArray(value) && value.length > 80) {
            return JSON.stringify(value.slice(0, 80));
          }
          return JSON.stringify(value);
        } catch (_) {
          return String(value);
        }
      };

      globalThis.fetch = async function(url, headers) {
        const response = await globalThis.fetchv2(url, headers);
        return await response.text();
      };

      globalThis.atob = globalThis.atob || function(value) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        let str = String(value).replace(/=+$/, '');
        let output = '';
        if (str.length % 4 == 1) throw new Error('Invalid base64 string');
        for (let bc = 0, bs, buffer, idx = 0;
          buffer = str.charAt(idx++);
          ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
          bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0
        ) {
          buffer = chars.indexOf(buffer);
        }
        return output;
      };

      globalThis.btoa = globalThis.btoa || function(value) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
        let str = String(value);
        let output = '';
        for (let block = 0, charCode, idx = 0, map = chars;
          str.charAt(idx | 0) || (map = '=', idx % 1);
          output += map.charAt(63 & block >> 8 - idx % 1 * 8)
        ) {
          charCode = str.charCodeAt(idx += 3 / 4);
          if (charCode > 0xFF) throw new Error('Invalid character');
          block = block << 8 | charCode;
        }
        return output;
      };

      if (typeof globalThis.setTimeout !== 'function') {
        globalThis.__miruSoraTimerSeq = 1;
        globalThis.__miruSoraTimers = {};
        globalThis.setTimeout = function(callback, delay) {
          const args = Array.prototype.slice.call(arguments, 2);
          const id = globalThis.__miruSoraTimerSeq++;
          globalThis.__miruSoraTimers[id] = true;
          __miruSoraDelay(Math.max(0, Math.min(Number(delay) || 0, 60000))).then(function() {
            if (!globalThis.__miruSoraTimers[id]) return;
            delete globalThis.__miruSoraTimers[id];
            try { callback.apply(globalThis, args); } catch (_) {}
          });
          return id;
        };
        globalThis.clearTimeout = function(id) {
          delete globalThis.__miruSoraTimers[id];
        };
        globalThis.setInterval = function() { return 0; };
        globalThis.clearInterval = function() {};
      }

      globalThis.Buffer = globalThis.Buffer || {
        from: function(data, encoding) {
          const enc = String(encoding || '').toLowerCase();
          let binary = String(data == null ? '' : data);
          if (enc === 'base64' || enc === 'base64url') {
            if (enc === 'base64url') {
              binary = binary.replace(/-/g, '+').replace(/_/g, '/');
            }
            try { binary = atob(binary); } catch (_) { binary = ''; }
          }
          return {
            _data: binary,
            toString: function(outputEncoding) {
              const out = String(outputEncoding || 'utf-8').toLowerCase();
              if (out === 'binary' || out === 'latin1') return this._data;
              try {
                return decodeURIComponent(
                  Array.prototype.map.call(this._data, function(ch) {
                    return '%' + ('00' + ch.charCodeAt(0).toString(16)).slice(-2);
                  }).join('')
                );
              } catch (_) { return this._data; }
            },
            length: binary.length
          };
        },
        isBuffer: function() { return false; },
        concat: function(bufs) {
          const result = (bufs || []).map(function(b) {
            return b && typeof b._data === 'string' ? b._data : String(b == null ? '' : b);
          }).join('');
          return {
            _data: result,
            toString: function(enc) {
              return globalThis.Buffer.from(result).toString(enc);
            },
            length: result.length
          };
        }
      };

      function __miruSoraNormalizeNetworkFetch(url, timeoutOrOptions, headers, cutoff) {
        let options = {};
        if (timeoutOrOptions && typeof timeoutOrOptions === 'object' && !Array.isArray(timeoutOrOptions)) {
          options = timeoutOrOptions;
        } else {
          options = { timeoutSeconds: timeoutOrOptions, headers: headers || {}, cutoff: cutoff || '' };
        }
        return {
          url: String(url),
          timeoutSeconds: Math.max(1, Math.min(Number(options.timeoutSeconds) || 7, 30)),
          headers: __miruSoraHeaders(options.headers || {}),
          cutoff: options.cutoff == null ? '' : String(options.cutoff),
          returnHTML: !!options.returnHTML,
          htmlContent: options.htmlContent == null ? '' : String(options.htmlContent),
          __addonId: globalThis.__miruCurrentAddonId
        };
      }

      globalThis.networkFetch = globalThis.networkFetch || function(url, timeoutOrOptions, headers, cutoff) {
        return (async function() {
          const payload = __miruSoraNormalizeNetworkFetch(url, timeoutOrOptions, headers, cutoff);
          const raw = await __miruAwaitHost('MiruSoraNetworkFetch', payload);
          try {
            return JSON.parse(typeof raw === 'string' ? raw : '{}');
          } catch (_) {
            return { originalUrl: String(url), requests: [], html: null, cookies: null, success: false };
          }
        })();
      };
      globalThis.networkFetchSimple = globalThis.networkFetchSimple || globalThis.networkFetch;

      const __miruOriginalConsole = globalThis.console || {};
      globalThis.console = {
        log: function() {
          sendMessage('MiruSoraLog', JSON.stringify({
            messages: Array.prototype.slice.call(arguments),
            __addonId: globalThis.__miruCurrentAddonId
          }));
          if (__miruOriginalConsole.log) __miruOriginalConsole.log.apply(null, arguments);
        },
        warn: function() {
          sendMessage('MiruSoraLog', JSON.stringify({
            messages: Array.prototype.slice.call(arguments),
            __addonId: globalThis.__miruCurrentAddonId
          }));
          if (__miruOriginalConsole.warn) __miruOriginalConsole.warn.apply(null, arguments);
        },
        error: function() {
          sendMessage('MiruSoraLog', JSON.stringify({
            messages: Array.prototype.slice.call(arguments),
            __addonId: globalThis.__miruCurrentAddonId
          }));
          if (__miruOriginalConsole.error) __miruOriginalConsole.error.apply(null, arguments);
        }
      };
    ''';
  }

  // ── Module source preparation ─────────────────────────────────────────────

  String _prepareModuleSource(String source) {
    return source
        .replaceAllMapped(
          RegExp(r'export\s+default\s+'),
          (Match _) => 'module.exports.default = ',
        )
        .replaceAllMapped(
          RegExp(r'export\s+(async\s+function|function)\s+([A-Za-z0-9_]+)'),
          (Match match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAllMapped(
          RegExp(r'export\s+(const|let|var)\s+'),
          (Match match) => '${match.group(1)} ',
        );
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  bool _isMissingFunction(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      return decoded['__miruMissingFunction'] == true;
    }
    if (decoded is Map) {
      return decoded['__miruMissingFunction'] == true;
    }
    return false;
  }

  Uri _resolveUrl(String value, String baseUrl) {
    final Uri? parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    final Uri? base = Uri.tryParse(baseUrl);
    if (base != null && base.hasScheme) {
      return base.resolve(value);
    }
    throw SoraAddonException('Fetch URL is not valid: $value');
  }

  Future<List<Object?>> _episodeCallArgs(
    SoraInstalledAddon addon,
    SoraSearchResult result,
  ) async {
    final String href = result.href.trim();
    if (_isAsyncModule(addon) || !_looksLikeUrl(href)) {
      return <Object?>[result.href];
    }

    final String html = await _fetchEpisodeHtml(addon, href);
    return <Object?>[html];
  }

  Future<String> _fetchEpisodeHtml(
    SoraInstalledAddon addon,
    String href,
  ) async {
    final Uri uri = _resolveUrl(href, addon.manifest.baseUrl);
    final Response<String> response = await _dio.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        headers: _defaultEpisodeHeaders(addon),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true,
        validateStatus: (_) => true,
      ),
    );
    return response.data ?? '';
  }

  Map<String, String> _defaultEpisodeHeaders(SoraInstalledAddon addon) {
    return <String, String>{
      'User-Agent': _userAgent,
      'Accept': 'text/html,application/json;q=0.9,*/*;q=0.8',
      'Accept-Language': _acceptLanguage(addon.manifest.language),
      if (addon.manifest.baseUrl.trim().isNotEmpty)
        'Referer': addon.manifest.baseUrl,
    };
  }

  bool _isAsyncModule(SoraInstalledAddon addon) {
    return _boolManifest(addon, 'asyncJS');
  }

  bool _boolManifest(SoraInstalledAddon addon, String key) {
    final Object? value = addon.manifest.raw[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase().trim() == 'true';
    return false;
  }

  bool _looksLikeUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is String) {
      try {
        return _asMap(jsonDecode(value));
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? mapValue) =>
            MapEntry<String, dynamic>(key.toString(), mapValue),
      );
    }
    return <String, dynamic>{};
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    return value.map(
      (Object? key, Object? mapValue) => MapEntry<String, String>(
        key.toString(),
        mapValue == null ? '' : mapValue.toString(),
      ),
    )..removeWhere((String _, String value) => value.trim().isEmpty);
  }

  String _acceptLanguage(String language) {
    final String code = language.trim().isEmpty ? 'en' : language.trim();
    return '$code,en;q=0.9,ru;q=0.8,ja;q=0.7,*;q=0.5';
  }

  String _truncateBody(SoraInstalledAddon addon, String body) {
    final bool searchCall = _loaded[addon.id]?.isSearchCall ?? false;
    final int maxBytes = searchCall ? _maxSearchBodyBytes : _maxBodyBytes;
    if (body.length <= maxBytes) return body;
    return body.substring(0, maxBytes);
  }

  String _string(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return fallback;
  }

  int _int(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }
}

class _LoadedSoraModule {
  _LoadedSoraModule({
    required this.addon,
    required this.scriptPath,
    required this.logs,
  });

  final SoraInstalledAddon addon;
  final String scriptPath;
  final List<String> logs;
  String? activeFunctionName;
  bool _disposed = false;
  final Set<CancelToken> _cancelTokens = <CancelToken>{};
  final List<Completer<void>> _delayCompleters = <Completer<void>>[];

  void cancelPendingDelays() {
    for (final Completer<void> c in _delayCompleters.toList()) {
      if (!c.isCompleted) c.complete();
    }
    _delayCompleters.clear();
  }

  bool get isSearchCall {
    final String name = activeFunctionName ?? '';
    return name == 'searchResults' ||
        name == 'searchContent' ||
        name == 'search' ||
        name == 'searchAnime' ||
        name == 'searchAnimes' ||
        name == 'searchResult';
  }

  void registerCancelToken(CancelToken token) {
    if (_disposed) {
      token.cancel('Sora runtime is disposing.');
      return;
    }
    _cancelTokens.add(token);
  }

  void unregisterCancelToken(CancelToken token) {
    _cancelTokens.remove(token);
  }

  void cancelPendingFetches() {
    for (final CancelToken token in _cancelTokens.toList(growable: false)) {
      if (!token.isCancelled) {
        token.cancel('Sora runtime disposed before fetch completed.');
      }
    }
    _cancelTokens.clear();
  }
}
