import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:dio/dio.dart';

import '../domain/sora_models.dart';
import '../domain/sora_parsers.dart';
import 'sora_addon_store.dart';

@JS('eval')
external JSAny? _jsEval(JSString code);

class SoraJsRuntime {
  SoraJsRuntime({required SoraAddonStore store, Dio? dio, String? webProxyUrl})
    : _store = store,
      _webProxyUrl =
          (webProxyUrl ?? const String.fromEnvironment('MIRUSHIN_WEB_PROXY'))
              .trim();

  static const int _maxLoadedModules = 1;
  static const int _callDrainTimeoutMs = 900;

  final SoraAddonStore _store;
  final String _webProxyUrl;
  final Map<String, _LoadedSoraModule> _loaded = <String, _LoadedSoraModule>{};
  final List<String> _loadOrder = <String>[];
  Future<void> _jsTail = Future<void>.value();

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
        drainTimeoutMs: 0,
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
        drainTimeoutMs: 0,
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
      return _withWebProxy(
        SoraResolvedStreams(
          addonId: addon.id,
          episode: episode,
          candidates: parseSoraStreamCandidates(payload),
          raw: payload,
        ),
      );
    });
  }

  Future<SoraResolvedStreams> refreshStream({
    required SoraInstalledAddon addon,
    required SoraEpisode episode,
    String? voiceover,
  }) => extractStreams(addon: addon, episode: episode, voiceover: voiceover);

  void invalidate(String addonId) {
    unawaited(_serialized<void>(() async => _dispose(addonId)));
  }

  void invalidateAll() {
    unawaited(_serialized<void>(() async => _disposeAll()));
  }

  void cancelActiveSearches() {
    // Browser fetches cannot be force-cancelled from here without an
    // AbortController per request. The provider epoch still makes queued
    // searches skip before entering JS.
  }

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

  Future<void> _dispose(String addonId) async {
    _loadOrder.remove(addonId);
    _loaded.remove(addonId)?.dispose();
  }

  Future<void> _disposeAll() async {
    for (final _LoadedSoraModule module in _loaded.values) {
      module.dispose();
    }
    _loaded.clear();
    _loadOrder.clear();
  }

  Future<Object?> _call({
    required SoraInstalledAddon addon,
    required List<String> functionNames,
    required List<Object?> args,
    bool required = true,
    int drainTimeoutMs = _callDrainTimeoutMs,
  }) async {
    final _LoadedSoraModule module = await _load(addon);
    final String argsJson = jsonEncode(args);
    for (final String functionName in functionNames) {
      module.activeFunctionName = functionName;
      final String expression =
          '''
        (async () => {
          const module = globalThis.__miruSoraModules[${jsonEncode(addon.id)}];
          const fn = module && module[${jsonEncode(functionName)}];
          if (typeof fn !== 'function') return JSON.stringify({ "__miruMissingFunction": true });
          const args = $argsJson;
          const value = await fn.apply(null, args);
          try {
            await globalThis.__miruSoraDrainPendingTasks($drainTimeoutMs);
          } catch (_) {}
          return String(globalThis.__miruSoraSerializeResult(value));
        })()
      ''';
      try {
        final String result = await _evaluatePromiseString(expression);
        final Object? decoded = decodeSoraPayload(result);
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

    await _dispose(addon.id);
    final String source = await _store.readScript(addon);
    final String moduleSource = _prepareModuleSource(source);
    final String wrapper =
        '''
      ${_bridgeScript(addon)}
      globalThis.__miruSoraModules = globalThis.__miruSoraModules || {};
      (function() {
        const module = { exports: {} };
        const exports = module.exports;
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
    try {
      _evaluateVoid(wrapper, sourceUrl: addon.scriptPath);
    } on Object catch (error) {
      throw SoraAddonException(
        'Failed to load ${addon.manifest.sourceName}: $error',
      );
    }

    final _LoadedSoraModule loaded = _LoadedSoraModule(
      scriptPath: addon.scriptPath,
    );
    _loaded[addon.id] = loaded;
    _loadOrder.add(addon.id);
    while (_loaded.length > _maxLoadedModules) {
      await _dispose(_loadOrder.first);
    }
    return loaded;
  }

  String _bridgeScript(SoraInstalledAddon addon) {
    return '''
      globalThis.__miruSoraBaseUrl = ${jsonEncode(addon.manifest.baseUrl)};
      globalThis.__miruSoraSearchBaseUrl = ${jsonEncode(addon.manifest.searchBaseUrl)};
      globalThis.__miruSoraWebProxyUrl = ${jsonEncode(_webProxyUrl)};
      globalThis.__miruSoraPendingTasks = globalThis.__miruSoraPendingTasks || new Set();
      globalThis.__miruSoraOriginalFetch = globalThis.__miruSoraOriginalFetch ||
        (typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : null);

      function __miruSoraTrackPromise(promise) {
        const tracked = Promise.resolve(promise);
        globalThis.__miruSoraPendingTasks.add(tracked);
        tracked.then(
          function() { globalThis.__miruSoraPendingTasks.delete(tracked); },
          function() { globalThis.__miruSoraPendingTasks.delete(tracked); }
        );
        return promise;
      }

      function __miruSoraDelay(milliseconds) {
        const bounded = Math.max(0, Math.min(Number(milliseconds) || 0, 250));
        return new Promise(function(resolve) { setTimeout(resolve, bounded); });
      }

      globalThis.__miruSoraDrainPendingTasks = async function(timeoutMs) {
        const deadline = Date.now() + Math.max(0, Number(timeoutMs) || 0);
        while (globalThis.__miruSoraPendingTasks.size > 0 && Date.now() < deadline) {
          const pending = Array.from(globalThis.__miruSoraPendingTasks);
          await Promise.race([
            Promise.all(pending.map(function(task) {
              return Promise.resolve(task).then(function() {}, function() {});
            })),
            __miruSoraDelay(25)
          ]);
        }
        return globalThis.__miruSoraPendingTasks.size;
      };

      function __miruSoraHeaders(headers) {
        const merged = {};
        if (headers && typeof headers === 'object') {
          for (const key of Object.keys(headers)) {
            if (headers[key] !== undefined && headers[key] !== null) {
              const lower = String(key).toLowerCase();
              if (lower === 'user-agent' || lower === 'host' || lower === 'referer') continue;
              merged[key] = String(headers[key]);
            }
          }
        }
        return merged;
      }

      function __miruSoraResolveUrl(url) {
        const target = String(url);
        const base = String(
          globalThis.__miruSoraBaseUrl ||
          globalThis.__miruSoraSearchBaseUrl ||
          (globalThis.location && globalThis.location.href) ||
          ''
        );
        try {
          return new URL(target, base || undefined).toString();
        } catch (_) {
          return target;
        }
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
          url: __miruSoraResolveUrl(url),
          headers: __miruSoraHeaders(normalizedHeaders),
          method: String(normalizedMethod || 'GET').toUpperCase(),
          body: normalizedBody
        };
      }

      function __miruSoraProxyUrl(url) {
        const proxy = String(globalThis.__miruSoraWebProxyUrl || '').trim();
        if (!proxy) return String(url);
        const target = String(url);
        if (proxy.indexOf('{rawUrl}') !== -1) {
          return proxy.split('{rawUrl}').join(target);
        }
        if (proxy.indexOf('{url}') !== -1) {
          return proxy.split('{url}').join(encodeURIComponent(target));
        }
        return proxy + encodeURIComponent(target);
      }

      function __miruSoraShouldBlockRequest(payload) {
        const requestUrl = String(payload && payload.url ? payload.url : '');
        const requestMethod = String(payload && payload.method ? payload.method : 'GET').toUpperCase();
        return requestMethod === 'POST' &&
          /\\/\\/[^/]*supabase\\.co\\/rest\\/v1\\/app_logs(?:\\?|\$|\\/)/i.test(requestUrl);
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
        if (!globalThis.__miruSoraOriginalFetch) {
          throw new Error('Browser fetch API is not available.');
        }
        const requestUrl = __miruSoraProxyUrl(payload.url);
        const options = {
          method: payload.method,
          headers: payload.headers,
          credentials: 'omit'
        };
        if (payload.body !== null && payload.method !== 'GET' && payload.method !== 'HEAD') {
          options.body = typeof payload.body === 'string'
            ? payload.body
            : JSON.stringify(payload.body);
        }
        const response = await globalThis.__miruSoraOriginalFetch(requestUrl, options);
        const responseBody = await response.text();
        return {
          ok: response.ok,
          status: response.status,
          url: response.url || requestUrl,
          headers: {},
          body: responseBody
        };
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
    ''';
  }

  void _evaluateVoid(String code, {String? sourceUrl}) {
    final String script = sourceUrl == null
        ? code
        : '$code\n//# sourceURL=${sourceUrl.replaceAll('\n', '')}';
    _jsEval(script.toJS);
  }

  Future<String> _evaluatePromiseString(String code) async {
    final JSAny? value = _jsEval(code.toJS);
    if (value == null) return 'null';
    final JSAny? resolved = await (value as JSPromise<JSAny?>).toDart;
    if (resolved == null) return 'null';
    return (resolved as JSString).toDart;
  }

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

  bool _isMissingFunction(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      return decoded['__miruMissingFunction'] == true;
    }
    if (decoded is Map) {
      return decoded['__miruMissingFunction'] == true;
    }
    return false;
  }

  Future<List<Object?>> _episodeCallArgs(
    SoraInstalledAddon addon,
    SoraSearchResult result,
  ) async {
    final String href = result.href.trim();
    if (_isAsyncModule(addon) || !_looksLikeUrl(href)) {
      return <Object?>[result.href];
    }

    await _load(addon);
    final String requestUrl = _proxyUrl(
      _resolveUrl(href, addon.manifest.baseUrl),
    );
    final String html = await _evaluatePromiseString('''
      (async () => {
        const fetchFn = globalThis.__miruSoraOriginalFetch ||
          (typeof globalThis.fetch === 'function' ? globalThis.fetch.bind(globalThis) : null);
        if (!fetchFn) return '';
        const response = await fetchFn(${jsonEncode(requestUrl)}, {
          method: 'GET',
          headers: ${jsonEncode(_defaultEpisodeHeaders(addon))},
          credentials: 'omit'
        });
        return String(await response.text());
      })()
    ''');
    return <Object?>[html];
  }

  Map<String, String> _defaultEpisodeHeaders(SoraInstalledAddon addon) {
    return <String, String>{
      'Accept': 'text/html,application/json;q=0.9,*/*;q=0.8',
      'Accept-Language': _acceptLanguage(addon.manifest.language),
    };
  }

  String _acceptLanguage(String language) {
    final String code = language.trim().isEmpty ? 'en' : language.trim();
    return '$code,en;q=0.9,ru;q=0.8,ja;q=0.7,*;q=0.5';
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

  String _resolveUrl(String value, String baseUrl) {
    final Uri? parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }
    final Uri? base = Uri.tryParse(baseUrl);
    if (base != null && base.hasScheme) {
      return base.resolve(value).toString();
    }
    return value;
  }

  String _proxyUrl(String url) {
    final String trimmed = url.trim();
    final String proxy = _webProxyUrl.trim();
    if (trimmed.isEmpty || proxy.isEmpty) return url;
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return url;
    if (proxy.contains('{rawUrl}')) {
      return proxy.replaceAll('{rawUrl}', trimmed);
    }
    if (proxy.contains('{url}')) {
      return proxy.replaceAll('{url}', Uri.encodeComponent(trimmed));
    }
    return '$proxy${Uri.encodeComponent(trimmed)}';
  }

  SoraResolvedStreams _withWebProxy(SoraResolvedStreams streams) {
    if (_webProxyUrl.isEmpty) return streams;
    return SoraResolvedStreams(
      addonId: streams.addonId,
      episode: streams.episode,
      raw: streams.raw,
      candidates: <SoraStreamCandidate>[
        for (final SoraStreamCandidate candidate in streams.candidates)
          SoraStreamCandidate(
            title: candidate.title,
            url: _proxyUrl(candidate.url),
            headers: candidate.headers,
            voiceover: candidate.voiceover,
            raw: candidate.raw,
            subtitles: <SoraSubtitle>[
              for (final SoraSubtitle subtitle in candidate.subtitles)
                SoraSubtitle(
                  url: _proxyUrl(subtitle.url),
                  language: subtitle.language,
                  label: subtitle.label,
                ),
            ],
          ),
      ],
    );
  }
}

class _LoadedSoraModule {
  _LoadedSoraModule({required this.scriptPath});

  final String scriptPath;
  String? activeFunctionName;

  void dispose() {}
}
