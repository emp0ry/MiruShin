import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../app/localization/app_localizations.dart';
import '../application/cloudflare_challenge_service.dart';
import '../data/cloudflare_challenge.dart';

/// Interactive Cloudflare challenge solver.
///
/// Mirrors the proven reference recipe (Sora/Shirox's `CloudflareBypassManager`):
///
/// - Navigates to the **site root** `scheme://host/`, not the API endpoint the
///   fetch was aimed at. Cloudflare's JS challenge / Turnstile only runs in a
///   real document context; an API URL just returns the challenge body.
/// - Sets **no custom User-Agent**. Turnstile fingerprints the real browser, so
///   spoofing the UA makes Cloudflare reject the challenge even after the user
///   taps. Instead the page captures the WebView's *native* UA and reports it,
///   because `cf_clearance` is bound to the UA and must be replayed on later
///   requests.
/// - Reads cookies from **this WebView's own store** (via `webViewController`)
///   so a fresh challenge isn't confused by stale cookies elsewhere.
///
/// As soon as a `cf_clearance` cookie appears it captures every cookie for the
/// host plus the native UA and reports them through [onResult]; the host removes
/// the overlay. Hosted in an [OverlayEntry] (not a route) so unrelated
/// navigation — e.g. a source-resolution flow popping its own routes — can't
/// tear it down before the user solves.
class CloudflareChallengePage extends StatefulWidget {
  const CloudflareChallengePage({
    required this.url,
    required this.onResult,
    super.key,
  });

  final Uri url;
  final ValueChanged<CloudflareSolveResult?> onResult;

  @override
  State<CloudflareChallengePage> createState() =>
      _CloudflareChallengePageState();
}

class _CloudflareChallengePageState extends State<CloudflareChallengePage>
    with WidgetsBindingObserver {
  static const Duration _timeout = Duration(minutes: 3);
  static const Duration _pollInterval = Duration(milliseconds: 700);
  // On Windows/WebView2, onLoadStop and onProgressChanged may not fire
  // reliably. Hide the spinner after this fallback delay regardless.
  static const Duration _loadingFallback = Duration(seconds: 6);

  /// After this many consecutive cookie-read failures we assume the WebView
  /// engine is unavailable (e.g. the native plugin isn't registered because the
  /// app was hot-restarted after adding it, or the platform has no support) and
  /// bail out instead of spamming the log for the full timeout window.
  static const int _maxConsecutiveErrors = 5;

  /// Number of consecutive polls a fresh `cf_clearance` must persist before we
  /// accept it even if [_stillOnChallenge] keeps reporting true (a Windows/
  /// WebView2 stale-title workaround). At [_pollInterval] this is ~8 seconds.
  static const int _windowsClearanceConfirmPolls = 12;
  static const Duration _windowsClearanceIdleDelay = Duration(seconds: 2);
  static const Duration _windowsVerificationCooldown = Duration(seconds: 3);

  CookieManager _cookies = CookieManager.instance();
  WebViewEnvironment? _webViewEnvironment;
  InAppWebViewController? _controller;
  HeadlessInAppWebView? _popupWebView;
  InAppWebViewController? _popupController;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  Timer? _loadingFallbackTimer;
  int _consecutiveErrors = 0;
  // Consecutive polls in which a cf_clearance cookie has been present.
  int _clearanceSeen = 0;
  DateTime? _clearanceFirstSeenAt;
  DateTime _lastWebViewActivityAt = DateTime.now();
  bool _verificationInFlight = false;
  DateTime? _lastVerificationAt;
  bool _completed = false;
  bool _loading = true;
  // Becomes true once the pre-navigation cookie flush is done (or timed out).
  // Only then is the InAppWebView widget inserted with initialUrlRequest so
  // the first navigation already starts clean, without an async loadUrl call
  // inside onWebViewCreated (which can silently no-op on Windows/WebView2).
  bool _ready = false;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The page we actually load: the site root, where the challenge can run.
  late final WebUri _rootUri = WebUri(
    Uri(scheme: widget.url.scheme, host: widget.url.host, path: '/').toString(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkForClearance());
    _timeoutTimer = Timer(_timeout, () => _finish(null));
    _loadingFallbackTimer = Timer(_loadingFallback, () {
      if (mounted && _loading) setState(() => _loading = false);
    });
    _prepareWebView();
  }

  Future<void> _prepareWebView() async {
    if (!_isWindows) return;
    if (_isWindows) {
      try {
        final WebViewEnvironment environment = await WebViewEnvironment.create()
            .timeout(const Duration(seconds: 3));
        if (_completed) {
          unawaited(environment.dispose());
          return;
        }
        _webViewEnvironment = environment;
        _cookies = CookieManager.instance(webViewEnvironment: environment);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[Cloudflare] WebView2 environment create failed: $error');
        }
      }
    }
    await _preClearCookies();
  }

  Future<void> _preClearCookies() async {
    try {
      // Delete without webViewController — the WebView2 instance doesn't exist
      // yet, and using webViewController in onWebViewCreated can race against
      // WebView2 initialisation and silently block the subsequent navigation.
      await _cookies
          .deleteCookies(url: _rootUri)
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {}
    if (mounted && !_completed) setState(() => _ready = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Set _completed first so any in-flight _checkForClearance call aborts
    // after its current await instead of continuing into plugin calls that
    // may be mid-teardown (avoids a native crash on Windows/WebView2 exit).
    _completed = true;
    _controller = null;
    _popupController = null;
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _loadingFallbackTimer?.cancel();
    final HeadlessInAppWebView? popupWebView = _popupWebView;
    _popupWebView = null;
    if (popupWebView != null) {
      unawaited(popupWebView.dispose());
    }
    final WebViewEnvironment? environment = _webViewEnvironment;
    _webViewEnvironment = null;
    if (environment != null) {
      unawaited(environment.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Dismiss the challenge before the engine tears down so the WebView2
    // environment is cleaned up while plugin channels are still alive.
    if (state == AppLifecycleState.detached) {
      _finish(null);
    }
  }

  /// Reads cookies for the root host, merging the available sources.
  ///
  /// On Windows/WebView2, CookieManager reads from its WebViewEnvironment and
  /// ignores the controller argument. The challenge WebView is therefore bound
  /// to [_webViewEnvironment], and we also ask the visible controller through
  /// DevTools as a final fallback. On iOS/macOS the controller read is
  /// canonical; this deliberately matches the v2.1.0 flow that worked there.
  Future<List<Cookie>> _readCookies() async {
    if (!_isWindows) {
      return _safeGetCookies(withController: true);
    }

    final Map<String, Cookie> merged = <String, Cookie>{
      for (final Cookie c in await _safeGetCookies(withController: false))
        c.name: c,
      for (final Cookie c in await _safeGetCookies(withController: true))
        c.name: c,
      for (final Cookie c in await _readDevToolsCookies(_controller)) c.name: c,
      for (final Cookie c in await _readDevToolsCookies(_popupController))
        c.name: c,
    };
    return merged.values.toList(growable: false);
  }

  /// A single getCookies call guarded by a timeout so it cannot hang the poll.
  Future<List<Cookie>> _safeGetCookies({required bool withController}) async {
    try {
      return await _cookies
          .getCookies(
            url: _rootUri,
            webViewController: withController ? _controller : null,
          )
          .timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () => const <Cookie>[],
          );
    } catch (_) {
      return const <Cookie>[];
    }
  }

  Future<List<Cookie>> _readDevToolsCookies(
    InAppWebViewController? controller,
  ) async {
    if (!_isWindows) return const <Cookie>[];
    if (controller == null) return const <Cookie>[];
    try {
      final Object? result = await controller
          .callDevToolsProtocolMethod(
            methodName: 'Network.getCookies',
            parameters: <String, dynamic>{
              'urls': <String>[_rootUri.toString()],
            },
          )
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      final Object? rawCookies = result is Map ? result['cookies'] : null;
      if (rawCookies is! List) return const <Cookie>[];
      return rawCookies
          .map(_cookieFromDevTools)
          .whereType<Cookie>()
          .toList(growable: false);
    } catch (_) {
      return const <Cookie>[];
    }
  }

  Cookie? _cookieFromDevTools(Object? raw) {
    if (raw is! Map) return null;
    final Object? name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    final Object? expires = raw['expires'];
    return Cookie(
      name: name,
      value: raw['value'],
      domain: raw['domain'] is String ? raw['domain'] as String : null,
      path: raw['path'] is String ? raw['path'] as String : null,
      isSecure: raw['secure'] is bool ? raw['secure'] as bool : null,
      isHttpOnly: raw['httpOnly'] is bool ? raw['httpOnly'] as bool : null,
      isSessionOnly: raw['session'] is bool ? raw['session'] as bool : null,
      expiresDate: expires is num && expires > 0
          ? (expires * 1000).round()
          : null,
    );
  }

  Future<void> _checkForClearance() async {
    if (_completed || _controller == null) return;
    try {
      final List<Cookie> cookies = await _readCookies();
      // Re-check after the await: dispose may have run while we were waiting.
      if (_completed) return;
      _consecutiveErrors = 0;
      final bool cleared = cookies.any((Cookie c) => c.name == 'cf_clearance');
      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] poll: ${cookies.length} cookies, '
          'cf_clearance=$cleared, names=${cookies.map((Cookie c) => c.name).toList()}',
        );
      }
      if (!cleared) {
        _clearanceSeen = 0;
        _clearanceFirstSeenAt = null;
        return;
      }
      _clearanceSeen++;
      _clearanceFirstSeenAt ??= DateTime.now();

      // A cf_clearance cookie alone isn't proof we passed. Cloudflare/WebView2
      // can expose it before the visible Turnstile/CAPTCHA step has completed,
      // so Windows also verifies the document no longer looks like a challenge
      // and has settled before auto-closing.
      final bool stillChallenging = await _stillOnChallenge();
      if (stillChallenging) {
        if (_isWindows) _windowsClearanceSettled();
        return;
      }
      if (_isWindows && !_windowsClearanceSettled()) {
        return;
      }

      final String header = cookies
          .where((Cookie c) => '${c.value}'.isNotEmpty)
          .map((Cookie c) => '${c.name}=${c.value}')
          .join('; ');
      // cf_clearance is bound to the UA that solved it — capture the WebView's
      // real UA so the runtime can replay it on subsequent requests.
      final String userAgent = await _readUserAgent();
      if (_isWindows &&
          !await _verifyWindowsClearance(
            cookies: header,
            userAgent: userAgent,
          )) {
        return;
      }
      _finish((cookies: header, userAgent: userAgent));
    } catch (error) {
      if (_completed) return;
      _consecutiveErrors++;
      if (kDebugMode && _consecutiveErrors == 1) {
        debugPrint('[Cloudflare] cookie poll failed: $error');
      }
      // The WebView engine isn't answering (most often: a native plugin added
      // this session needs a full app relaunch, not a hot restart). Give up
      // rather than spam the poll until the timeout.
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        if (kDebugMode) {
          debugPrint(
            '[Cloudflare] WebView unavailable after $_consecutiveErrors '
            'attempts; aborting. If you just added the plugin, fully relaunch '
            'the app (cold start), not a hot restart.',
          );
        }
        _finish(null);
      }
    }
  }

  bool _windowsClearanceSettled() {
    final DateTime now = DateTime.now();
    final DateTime? firstSeen = _clearanceFirstSeenAt;
    final Duration cookieAge = firstSeen == null
        ? Duration.zero
        : now.difference(firstSeen);
    final Duration idleFor = now.difference(_lastWebViewActivityAt);
    final bool settled =
        _clearanceSeen >= _windowsClearanceConfirmPolls &&
        idleFor >= _windowsClearanceIdleDelay;

    if (!settled && kDebugMode) {
      debugPrint(
        '[Cloudflare] waiting for Windows clearance settle: '
        'seen=$_clearanceSeen/$_windowsClearanceConfirmPolls, '
        'cookieAge=${cookieAge.inMilliseconds}ms, '
        'idle=${idleFor.inMilliseconds}ms',
      );
    }
    return settled;
  }

  Future<bool> _verifyWindowsClearance({
    required String cookies,
    required String userAgent,
  }) async {
    if (!_isWindows) return true;
    if (cookies.trim().isEmpty || userAgent.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] Windows clearance verify waiting: '
          'cookies=${cookies.trim().isNotEmpty}, ua=${userAgent.trim().isNotEmpty}',
        );
      }
      return false;
    }
    if (_verificationInFlight) return false;

    final DateTime now = DateTime.now();
    final DateTime? lastVerification = _lastVerificationAt;
    if (lastVerification != null &&
        now.difference(lastVerification) < _windowsVerificationCooldown) {
      return false;
    }

    _lastVerificationAt = now;
    _verificationInFlight = true;
    try {
      final Response<String> response =
          await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              followRedirects: true,
              validateStatus: (_) => true,
              responseType: ResponseType.plain,
            ),
          ).getUri<String>(
            Uri.parse(_rootUri.toString()),
            options: Options(
              responseType: ResponseType.plain,
              headers: <String, String>{
                'User-Agent': userAgent,
                'Cookie': cookies,
                'Accept':
                    'text/html,application/xhtml+xml,application/json,text/plain,*/*',
              },
            ),
          );
      final Map<String, dynamic> headers = _responseHeaderMap(response);
      final String body = response.data ?? '';
      final bool challenged =
          CloudflareChallenge.isChallenge(response.statusCode, headers, body) ||
          _headersShowChallenge(headers) ||
          _bodyShowsChallenge(body);

      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] Windows clearance verify: '
          'status=${response.statusCode} challenged=$challenged '
          'url=${response.realUri}',
        );
      }
      return !challenged;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cloudflare] Windows clearance verify failed: $error');
      }
      return false;
    } finally {
      _verificationInFlight = false;
    }
  }

  Map<String, dynamic> _responseHeaderMap(Response<dynamic> response) {
    final Map<String, dynamic> map = <String, dynamic>{};
    response.headers.forEach((String name, List<String> values) {
      if (values.isEmpty) return;
      map[name] = values.length == 1 ? values.first : values;
    });
    return map;
  }

  bool _headersShowChallenge(Map<String, dynamic> headers) {
    return _headerValue(
      headers,
      'cf-mitigated',
    ).toLowerCase().contains('challenge');
  }

  String _headerValue(Map<String, dynamic> headers, String name) {
    final String target = name.toLowerCase();
    for (final MapEntry<String, dynamic> entry in headers.entries) {
      if (entry.key.toLowerCase() != target) continue;
      final Object? value = entry.value;
      if (value is List) return value.join(', ');
      return value?.toString() ?? '';
    }
    return '';
  }

  bool _bodyShowsChallenge(String body) {
    final String haystack = body.toLowerCase();
    return _windowsChallengeMarkers.any(haystack.contains);
  }

  void _markWebViewActivity() {
    _lastWebViewActivityAt = DateTime.now();
  }

  Future<String> _readUserAgent() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) return '';
    try {
      final String ua = _normalizeUserAgent(
        await controller.evaluateJavascript(source: 'navigator.userAgent'),
      );
      if (ua.isNotEmpty) return ua;
    } catch (_) {
      // Try the WebView2 DevTools API below.
    }
    if (!_isWindows) return '';
    try {
      final Object? result = await controller
          .callDevToolsProtocolMethod(methodName: 'Browser.getVersion')
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      if (result is Map) {
        return _normalizeUserAgent(result['userAgent']);
      }
    } catch (_) {}
    return '';
  }

  String _normalizeUserAgent(Object? raw) {
    if (raw is! String) return '';
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    try {
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is String && decoded.trim().isNotEmpty) {
        return decoded.trim();
      }
    } catch (_) {}
    return trimmed;
  }

  Future<bool?> _windowsDomShowsChallenge(
    InAppWebViewController controller,
  ) async {
    if (!_isWindows) return null;
    try {
      final Object? raw = await controller
          .evaluateJavascript(
            source: r'''
(() => {
  const text = (document.body?.innerText || '').toLowerCase();
  const html = (document.documentElement?.innerHTML || '').toLowerCase();
  const selectors = [
    '#challenge-stage',
    '#challenge-running',
    '#challenge-spinner',
    '#cf-challenge-running',
    '#cf-please-wait',
    '.cf-turnstile',
    '[name="cf-turnstile-response"]',
    'form[action*="__cf_chl"]',
    'iframe[src*="challenges.cloudflare.com"]',
    'iframe[src*="turnstile"]',
    'script[src*="/cdn-cgi/challenge-platform"]'
  ];
  return {
    readyState: document.readyState,
    title: document.title || '',
    href: location.href || '',
    hasSelector: selectors.some((selector) => document.querySelector(selector) !== null),
    text: text.slice(0, 5000),
    html: html.slice(0, 12000)
  };
})()
''',
          )
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      final Map<String, dynamic>? state = _objectMap(raw);
      if (state == null) return null;

      final String readyState = '${state['readyState']}'.toLowerCase();
      final String href = '${state['href']}'.toLowerCase();
      final String title = '${state['title']}'.toLowerCase();
      final String text = '${state['text']}'.toLowerCase();
      final String html = '${state['html']}'.toLowerCase();
      final bool hasSelector = state['hasSelector'] == true;
      final String haystack = '$title\n$href\n$text\n$html';
      final bool hasMarker = _windowsChallengeMarkers.any(haystack.contains);

      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] dom: ready=$readyState '
          'selector=$hasSelector marker=$hasMarker '
          'title="$title" href="$href"',
        );
      }

      if (readyState == 'loading') return true;
      if (hasSelector || hasMarker) return true;
      if (title.trim().isEmpty && text.trim().isEmpty) return true;
      return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cloudflare] DOM challenge probe failed: $error');
      }
      return null;
    }
  }

  static const List<String> _windowsChallengeMarkers = <String>[
    'cdn-cgi/challenge-platform',
    '__cf_chl',
    'cf_chl',
    'cf-browser-verification',
    'cf-turnstile',
    'turnstile',
    'just a moment',
    'verify you are human',
    'verifying you are human',
    'confirm you are human',
    'this may take a few seconds',
    'verification is taking longer',
    'please stand by',
    'checking your browser',
    'checking if the site connection is secure',
    'review the security of your connection',
    'needs to review the security',
    'enable javascript and cookies to continue',
    'cloudflare ray id',
    'performance & security by cloudflare',
  ];

  Map<String, dynamic>? _objectMap(Object? raw) {
    if (raw is Map) {
      return raw.map((Object? key, Object? value) => MapEntry('$key', value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  /// Whether the WebView is still showing the Cloudflare interstitial (so a
  /// present cf_clearance cookie can't yet be trusted).
  Future<bool> _stillOnChallenge() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) return true;
    try {
      final String title =
          (await controller.getTitle().timeout(
            const Duration(milliseconds: 1000),
            onTimeout: () => '',
          ))?.toLowerCase() ??
          '';
      final String url =
          (await controller.getUrl().timeout(
            const Duration(milliseconds: 1000),
            onTimeout: () => null,
          ))?.toString() ??
          '';
      if (kDebugMode) {
        debugPrint('[Cloudflare] state: title="$title" url="$url"');
      }
      if (_isWindows && title.isEmpty) return true;
      // Cloudflare's interstitial title is "Just a moment..." in all locales.
      if (title.contains('just a moment')) return true;
      if (url.contains('__cf_chl')) return true;
      final bool? domShowsChallenge = await _windowsDomShowsChallenge(
        controller,
      );
      if (domShowsChallenge != null) return domShowsChallenge;
      return _isWindows;
    } catch (_) {
      // If we can't read the state, assume still challenging and keep waiting.
      return true;
    }
  }

  void _finish(CloudflareSolveResult? result) {
    if (_completed) return;
    _completed = true;
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    widget.onResult(result);
  }

  Future<bool?> _handleCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    if (kDebugMode) {
      debugPrint(
        '[Cloudflare] onCreateWindow: '
        '${createWindowAction.request.url} '
        'windowId=${createWindowAction.windowId}',
      );
    }
    if (!_isWindows) return false;

    await _popupWebView?.dispose();
    _popupController = null;

    final HeadlessInAppWebView popupWebView = HeadlessInAppWebView(
      windowId: createWindowAction.windowId,
      webViewEnvironment: _webViewEnvironment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        thirdPartyCookiesEnabled: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (InAppWebViewController popupController) {
        _popupController = popupController;
        _markWebViewActivity();
        if (kDebugMode) {
          debugPrint('[Cloudflare] popup WebView created');
        }
      },
      onLoadStart: (_, WebUri? url) {
        _markWebViewActivity();
        if (kDebugMode) {
          debugPrint('[Cloudflare] popup onLoadStart: $url');
        }
      },
      onLoadStop: (_, WebUri? url) {
        _markWebViewActivity();
        if (kDebugMode) {
          debugPrint('[Cloudflare] popup onLoadStop: $url');
        }
        unawaited(_checkForClearance());
      },
      onProgressChanged: (_, int progress) {
        if (progress < 100) _markWebViewActivity();
      },
      onUpdateVisitedHistory: (_, WebUri? url, _) {
        _markWebViewActivity();
        if (kDebugMode) {
          debugPrint('[Cloudflare] popup history: $url');
        }
      },
      onCloseWindow: (_) {
        _disposePopupWebView();
      },
      onReceivedError: (_, _, WebResourceError error) {
        _markWebViewActivity();
        if (kDebugMode) {
          debugPrint(
            '[Cloudflare] popup onReceivedError: '
            '${error.type} ${error.description}',
          );
        }
      },
    );

    _popupWebView = popupWebView;
    try {
      await popupWebView.run();
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cloudflare] popup WebView failed: $error');
      }
      _popupWebView = null;
      _popupController = null;
      // Returning false lets flutter_inappwebview_windows run its default
      // behavior, which loads the popup request in the main WebView and causes
      // Cloudflare's verification page to restart. Treat it as handled even if
      // the child WebView failed to attach.
      return true;
    }
  }

  void _disposePopupWebView() {
    final HeadlessInAppWebView? popupWebView = _popupWebView;
    _popupWebView = null;
    _popupController = null;
    if (popupWebView != null) {
      unawaited(popupWebView.dispose());
    }
    unawaited(_checkForClearance());
  }

  Widget _buildDefaultWebView() {
    return InAppWebView(
      // No initialUrlRequest: we clear stale cookies first, then load (below),
      // exactly like v2.1.0. The challenge must write cf_clearance into the same
      // controller-backed store CookieManager.getCookies reads.
      // No custom userAgent on purpose — see the class doc.
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (InAppWebViewController controller) async {
        _controller = controller;
        try {
          await _cookies.deleteCookies(
            url: _rootUri,
            webViewController: controller,
          );
        } catch (_) {
          // Best-effort; the challenge still overwrites on success.
        }
        if (!_completed) {
          await controller.loadUrl(urlRequest: URLRequest(url: _rootUri));
        }
      },
      onLoadStop: (_, _) {
        if (mounted) setState(() => _loading = false);
        unawaited(_checkForClearance());
      },
      onProgressChanged: (_, int progress) {
        if (mounted) setState(() => _loading = progress < 100);
      },
      onReceivedError: (_, _, _) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  Widget _buildWindowsWebView() {
    return ColoredBox(
      color: Colors.white,
      // The InAppWebView is only inserted once _preClearCookies()
      // finishes so initialUrlRequest fires on a clean cookie store,
      // without a racing async loadUrl call inside onWebViewCreated
      // (which silently no-ops on Windows/WebView2 in some cases).
      child: _ready
          ? InAppWebView(
              // No custom userAgent on purpose — see the class doc.
              key: const ValueKey<String>('cloudflare-main-webview'),
              webViewEnvironment: _webViewEnvironment,
              initialUrlRequest: URLRequest(url: _rootUri),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                supportMultipleWindows: true,
                thirdPartyCookiesEnabled: true,
                transparentBackground: true,
              ),
              onWebViewCreated: (InAppWebViewController controller) {
                _controller = controller;
                _markWebViewActivity();
                if (kDebugMode) {
                  debugPrint('[Cloudflare] onWebViewCreated');
                }
              },
              onCreateWindow: _handleCreateWindow,
              onLoadStart: (_, WebUri? url) {
                _markWebViewActivity();
                if (kDebugMode) {
                  debugPrint('[Cloudflare] onLoadStart: $url');
                }
                if (mounted) setState(() => _loading = true);
              },
              onLoadStop: (_, WebUri? url) {
                _markWebViewActivity();
                if (kDebugMode) {
                  debugPrint('[Cloudflare] onLoadStop: $url');
                }
                if (mounted) setState(() => _loading = false);
                unawaited(_checkForClearance());
              },
              onProgressChanged: (_, int progress) {
                if (progress < 100) _markWebViewActivity();
                if (mounted) {
                  setState(() => _loading = progress < 100);
                }
              },
              onUpdateVisitedHistory: (_, WebUri? url, _) {
                _markWebViewActivity();
                if (kDebugMode) {
                  debugPrint('[Cloudflare] history: $url');
                }
              },
              onReceivedError: (_, _, WebResourceError error) {
                _markWebViewActivity();
                if (kDebugMode) {
                  debugPrint(
                    '[Cloudflare] onReceivedError: '
                    '${error.type} ${error.description}',
                  );
                }
                if (mounted) setState(() => _loading = false);
              },
            )
          : const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // BackButtonListener catches the Android system-back even though this lives
    // in an overlay rather than a route, so back cancels the challenge instead
    // of popping the page underneath it.
    return BackButtonListener(
      onBackButtonPressed: () async {
        _finish(null);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t('Security check')),
          leading: IconButton(
            autofocus: true,
            icon: const Icon(Icons.close_rounded),
            tooltip: context.t('Cancel'),
            onPressed: () => _finish(null),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                context.t(
                  'Complete the verification to continue. This closes by itself.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
        body: Column(
          children: <Widget>[
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _isWindows
                  ? _buildWindowsWebView()
                  : _buildDefaultWebView(),
            ),
          ],
        ),
      ),
    );
  }
}
