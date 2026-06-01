import 'dart:async';
import 'dart:convert';

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

  // Single shared QuickJS/JavaScriptCore context for all addon modules.
  // Created lazily on first use. Never disposed during normal operation —
  // creating and destroying per-addon contexts caused SIGSEGV in QuickJS on
  // Linux (the dispose path races with pending promise callbacks).
  JavascriptRuntime? _sharedRuntime;

  JavascriptRuntime _runtime() {
    final JavascriptRuntime? existing = _sharedRuntime;
    if (existing != null) return existing;
    final JavascriptRuntime rt = getJavascriptRuntime(xhr: false);
    _installSharedBridge(rt);
    _sharedRuntime = rt;
    return rt;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<List<SoraSearchResult>> searchResults({
    required SoraInstalledAddon addon,
    required String keyword,
    required String languageCode,
    required List<SoraTitleVariant> titleVariants,
  }) {
    return _serialized(() async {
      final Object? payload = await _call(
        addon: addon,
        functionNames: const <String>['searchResults', 'search', 'searchAnime'],
        args: <Object?>[keyword],
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
      final Object? payload = await _call(
        addon: addon,
        functionNames: const <String>[
          'extractEpisodes',
          'getEpisodes',
          'episodes',
        ],
        args: <Object?>[result.href],
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
    for (final String functionName in functionNames) {
      module.activeFunctionName = functionName;
      final String expression =
          '''
        (async () => {
          globalThis.__miruCurrentAddonId = ${jsonEncode(addon.id)};
          const module = globalThis.__miruSoraModules && globalThis.__miruSoraModules[${jsonEncode(addon.id)}];
          const fn = module && module[${jsonEncode(functionName)}];
          if (typeof fn !== 'function') return { "__miruMissingFunction": true };
          const args = $argsJson;
          const value = await fn.apply(null, args);
          return globalThis.__miruSoraSerializeResult(value);
        })()
      ''';
      try {
        final JsEvalResult initial = rt.evaluate(expression);
        final JsEvalResult resolved = await rt.handlePromise(initial);
        final Object? decoded = decodeSoraPayload(resolved.stringResult);
        if (_isMissingFunction(decoded)) {
          continue;
        }
        return decoded;
      } finally {
        module.activeFunctionName = null;
      }
    }
    if (!required) {
      return null;
    }
    throw SoraAddonException(
      '${addon.manifest.sourceName} does not expose ${functionNames.first}().',
    );
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
          extractDetails:
            (typeof extractDetails === 'function' && extractDetails) ||
            exported.extractDetails || defaults.extractDetails,
          extractEpisodes:
            (typeof extractEpisodes === 'function' && extractEpisodes) ||
            exported.extractEpisodes || defaults.extractEpisodes,
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

    runtime.onMessage('MiruSoraHttpFetch', (dynamic args) async {
      final Map<String, dynamic> payload = _asMap(args);
      final String addonId = _string(payload['__addonId']);
      final _LoadedSoraModule? module = _loaded[addonId];
      if (module == null || module._disposed) {
        return jsonEncode(<String, dynamic>{
          '__miruResponse': true,
          'status': 0,
          'headers': <String, dynamic>{},
          'body': '',
          'error': 'addon disposed',
        });
      }
      return _httpFetchBody(module.addon, payload);
    });

    runtime.onMessage('MiruSoraDelay', (dynamic args) async {
      final Map<String, dynamic> payload = _asMap(args);
      final String addonId = _string(payload['__addonId']);
      final int ms = _int(
        payload['milliseconds'],
        fallback: 16,
      ).clamp(0, 60000).toInt();
      final _LoadedSoraModule? module = _loaded[addonId];
      if (module == null || module._disposed) return 'cancelled';
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
      return 'true';
    });

    runtime.onMessage('MiruSoraNetworkFetch', (dynamic args) async {
      final Map<String, dynamic> payload = _asMap(args);
      final String addonId = _string(payload['__addonId']);
      final _LoadedSoraModule? module = _loaded[addonId];
      if (module == null || module._disposed) {
        return jsonEncode(<String, Object?>{
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
      }
      return _networkFetch(module.addon, payload);
    });

    runtime.evaluate(_bridgeScript());
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
      globalThis.__miruSoraPendingTasks = globalThis.__miruSoraPendingTasks || new Set();

      function __miruSoraTrackPromise(promise) {
        const tracked = Promise.resolve(promise);
        globalThis.__miruSoraPendingTasks.add(tracked);
        tracked.then(
          function() { globalThis.__miruSoraPendingTasks.delete(tracked); },
          function() { globalThis.__miruSoraPendingTasks.delete(tracked); }
        );
        return promise;
      }

      async function __miruSoraDelay(milliseconds) {
        const bounded = Math.max(0, Math.min(Number(milliseconds) || 0, 60000));
        await sendMessage(
          'MiruSoraDelay',
          JSON.stringify({ milliseconds: bounded, __addonId: globalThis.__miruCurrentAddonId })
        );
      }

      globalThis.__miruSoraDrainPendingTasks = async function(timeoutMs) {
        const deadline = Date.now() + Math.max(0, Number(timeoutMs) || 0);
        while (globalThis.__miruSoraPendingTasks.size > 0 && Date.now() < deadline) {
          const pending = Array.from(globalThis.__miruSoraPendingTasks);
          if (pending.length === 0) break;
          await Promise.race(
            pending.map(function(task) {
              return Promise.resolve(task).then(function() {}, function() {});
            })
          );
        }
        return globalThis.__miruSoraPendingTasks.size;
      };

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
        const raw = await sendMessage('MiruSoraHttpFetch', JSON.stringify(msgPayload));
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
        const task = (async function() {
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
        return __miruSoraTrackPromise(task);
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
          const capturedAddonId = globalThis.__miruCurrentAddonId;
          const task = __miruSoraDelay(Math.max(0, Math.min(Number(delay) || 0, 60000))).then(function() {
            if (!globalThis.__miruSoraTimers[id]) return;
            delete globalThis.__miruSoraTimers[id];
            try { callback.apply(globalThis, args); } catch (_) {}
          });
          __miruSoraTrackPromise(task);
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
        const task = (async function() {
          const payload = __miruSoraNormalizeNetworkFetch(url, timeoutOrOptions, headers, cutoff);
          const raw = await sendMessage('MiruSoraNetworkFetch', JSON.stringify(payload));
          try {
            return JSON.parse(typeof raw === 'string' ? raw : '{}');
          } catch (_) {
            return { originalUrl: String(url), requests: [], html: null, cookies: null, success: false };
          }
        })();
        return __miruSoraTrackPromise(task);
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
    return name == 'searchResults' || name == 'search' || name == 'searchAnime';
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
