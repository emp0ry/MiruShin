import 'dart:async';
import 'dart:convert';

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
/// Completion is confirmed from both cookie state and the live document. This
/// also works when a platform keeps the HttpOnly `cf_clearance` cookie hidden
/// from Dart: after an actual challenge was observed, a stable clean document
/// proves that the shared browser session is ready. The host then removes the
/// overlay. It is hosted in an [OverlayEntry] (not a route), so a source flow
/// that pops its own routes cannot tear it down before the user solves it.
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

  /// A browser may expose a cookie just before its final navigation settles.
  /// Require stable observations on every platform before removing the WebView.
  static const int _clearanceConfirmPolls = 3;
  static const int _cleanPageConfirmPolls = 2;
  static const Duration _completionIdleDelay = Duration(milliseconds: 500);

  final CookieManager _cookies = CookieManager.instance();
  InAppWebViewController? _controller;
  int? _popupWindowId;
  InAppWebViewController? _popupController;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  Timer? _loadingFallbackTimer;
  Timer? _controllerStartupTimer;
  int _consecutiveErrors = 0;
  // Consecutive polls in which a cf_clearance cookie has been present.
  int _clearanceSeen = 0;
  int _cleanPageSeen = 0;
  bool _challengeObserved = false;
  DateTime? _clearanceFirstSeenAt;
  DateTime _lastWebViewActivityAt = DateTime.now();
  bool _clearanceCheckInFlight = false;
  bool _finishRequested = false;
  CloudflareSolveResult? _pendingFinishResult;
  bool _completed = false;
  bool _loading = true;
  bool _mainFrameLoading = true;
  int? _mainFrameHttpStatus;
  String _observedDocumentTitle = '';
  // Becomes true once the pre-navigation cookie flush is done (or timed out).
  // Only then is the InAppWebView widget inserted with initialUrlRequest so
  // the first navigation already starts clean, without an async loadUrl call
  // inside onWebViewCreated (which can silently no-op on Windows/WebView2).
  bool _ready = false;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The page we actually load: the site root, where the challenge can run.
  late final WebUri _rootUri = WebUri(
    Uri(
      scheme: widget.url.scheme,
      host: widget.url.host,
      port: widget.url.hasPort ? widget.url.port : null,
      path: '/',
    ).toString(),
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
    _controllerStartupTimer = Timer(const Duration(seconds: 15), () {
      if (!_completed && _controller == null) {
        if (kDebugMode) {
          debugPrint('Embedded browser controller did not start; aborting.');
        }
        _finish(null);
      }
    });
    _prepareWebView();
  }

  Future<void> _prepareWebView() async {
    await _preClearCookies();
  }

  Future<void> _preClearCookies() async {
    try {
      // Delete before the platform view exists. Clearing and loading from
      // onWebViewCreated can race controller initialization on some engines.
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
    _controllerStartupTimer?.cancel();
    _popupWindowId = null;
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

  /// Reads cookies for the challenge host, merging the available sources.
  ///
  /// Query both the root and current/redirected URL through the visible
  /// controller and the shared platform store. Windows additionally has a
  /// DevTools fallback for WebView2 cookies.
  Future<List<Cookie>> _readCookies() async {
    final Map<String, Cookie> merged = <String, Cookie>{};
    void addAll(Iterable<Cookie> cookies) {
      for (final Cookie cookie in cookies) {
        _mergeCookie(merged, cookie);
      }
    }

    final List<InAppWebViewController> controllers = <InAppWebViewController>[
      if (_controller case final InAppWebViewController controller) controller,
      if (_popupController case final InAppWebViewController controller)
        controller,
    ];
    final Set<String> urls = <String>{_rootUri.toString()};
    for (final InAppWebViewController controller in controllers) {
      urls.addAll(await _cookieUrls(controller));
    }
    for (final String rawUrl in urls) {
      final WebUri url = WebUri(rawUrl);
      addAll(await _safeGetCookies(url: url));
      for (final InAppWebViewController controller in controllers) {
        addAll(await _safeGetCookies(url: url, controller: controller));
      }
    }
    addAll(await _readDevToolsCookies(_controller));
    addAll(await _readDevToolsCookies(_popupController));
    addAll(await _readDocumentCookies(_controller));
    addAll(await _readDocumentCookies(_popupController));

    return merged.values.toList(growable: false);
  }

  void _mergeCookie(Map<String, Cookie> merged, Cookie cookie) {
    final String value = _cookieValue(cookie);
    if (cookie.name.isEmpty || value.isEmpty) return;
    final Cookie? existing = merged[cookie.name];
    if (existing == null ||
        _cookieValue(existing).isEmpty ||
        cookie.name == 'cf_clearance') {
      merged[cookie.name] = cookie;
    }
  }

  /// A single getCookies call guarded by a timeout so it cannot hang the poll.
  Future<List<Cookie>> _safeGetCookies({
    WebUri? url,
    InAppWebViewController? controller,
  }) async {
    try {
      return await _cookies
          .getCookies(url: url ?? _rootUri, webViewController: controller)
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
    final List<Cookie> cookies = <Cookie>[];
    try {
      await controller
          .callDevToolsProtocolMethod(methodName: 'Network.enable')
          .timeout(const Duration(milliseconds: 1000), onTimeout: () => null);
    } catch (_) {}

    final List<String> urls = await _cookieUrls(controller);
    final Set<String> allowedHosts = urls
        .map(Uri.tryParse)
        .whereType<Uri>()
        .map((Uri uri) => uri.host.toLowerCase())
        .where((String host) => host.isNotEmpty)
        .toSet();
    cookies.addAll(
      await _readDevToolsCookieMethod(
        controller,
        methodName: 'Network.getCookies',
        parameters: <String, dynamic>{'urls': urls},
      ),
    );
    cookies.addAll(
      await _readDevToolsCookieMethod(
        controller,
        methodName: 'Network.getAllCookies',
      ),
    );
    cookies.addAll(
      await _readDevToolsCookieMethod(
        controller,
        methodName: 'Storage.getCookies',
      ),
    );

    final Map<String, Cookie> merged = <String, Cookie>{};
    for (final Cookie cookie in cookies.where(
      (Cookie cookie) => _cookieMatchesAnyHost(cookie, allowedHosts),
    )) {
      _mergeCookie(merged, cookie);
    }
    return merged.values.toList(growable: false);
  }

  Future<List<String>> _cookieUrls(InAppWebViewController controller) async {
    final Set<String> urls = <String>{_rootUri.toString()};
    try {
      final WebUri? current = await controller.getUrl().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => null,
      );
      if (current != null && current.host == _rootUri.host) {
        urls.add(current.toString());
      } else if (current != null && current.host.isNotEmpty) {
        // WebView2 may finish a challenge on a redirected/canonical host. Its
        // clearance cookie is correctly scoped to that host, not the original
        // URL, so include the current URL in the DevTools query and filter.
        urls.add(current.toString());
      }
    } catch (_) {}
    return urls.toList(growable: false);
  }

  Future<List<Cookie>> _readDevToolsCookieMethod(
    InAppWebViewController controller, {
    required String methodName,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final Object? result = await controller
          .callDevToolsProtocolMethod(
            methodName: methodName,
            parameters: parameters,
          )
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
      final Object? rawCookies = _objectMap(result)?['cookies'];
      if (rawCookies is! List) return const <Cookie>[];
      final List<Cookie> cookies = rawCookies
          .map(_cookieFromDevTools)
          .whereType<Cookie>()
          .toList(growable: false);
      if (kDebugMode && cookies.any((Cookie c) => c.name == 'cf_clearance')) {
        debugPrint(
          '[Cloudflare] $methodName found cf_clearance '
          '(${cookies.length} cookies)',
        );
      }
      return cookies;
    } catch (_) {
      return const <Cookie>[];
    }
  }

  Future<List<Cookie>> _readDocumentCookies(
    InAppWebViewController? controller,
  ) async {
    if (controller == null) return const <Cookie>[];
    try {
      final String raw = _normalizeUserAgent(
        await controller
            .evaluateJavascript(source: 'document.cookie')
            .timeout(const Duration(milliseconds: 1000), onTimeout: () => ''),
      );
      if (raw.isEmpty) return const <Cookie>[];
      return raw
          .split(';')
          .map((String part) {
            final int equals = part.indexOf('=');
            if (equals <= 0) return null;
            final String name = part.substring(0, equals).trim();
            final String value = part.substring(equals + 1).trim();
            if (name.isEmpty || value.isEmpty) return null;
            return Cookie(name: name, value: value, domain: _rootUri.host);
          })
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
    final Object? value = raw['value'];
    if (value == null || '$value'.isEmpty) return null;
    final Object? expires = raw['expires'];
    return Cookie(
      name: name,
      value: '$value',
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

  bool _cookieMatchesAnyHost(Cookie cookie, Set<String> allowedHosts) {
    final String? rawDomain = cookie.domain;
    if (rawDomain == null || rawDomain.isEmpty) return true;
    final String domain = rawDomain.toLowerCase().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );
    return allowedHosts.any(
      (String host) => host == domain || host.endsWith('.$domain'),
    );
  }

  String _cookieValue(Cookie cookie) {
    final Object? value = cookie.value;
    if (value == null) return '';
    final String text = '$value'.trim();
    if (text.toLowerCase() == 'null') return '';
    return text;
  }

  Future<void> _checkForClearance() async {
    if (_completed || _controller == null) return;
    // Timer ticks and WebView load events can arrive together. Keep exactly one
    // controller transaction active so view removal cannot race a native call.
    if (_finishRequested || _clearanceCheckInFlight) return;
    _clearanceCheckInFlight = true;
    try {
      // Do not inspect cookies or evaluate the challenge DOM while Cloudflare
      // is still running. Besides being unnecessary, repeatedly driving the
      // DevTools/runtime domains makes an embedded browser look automated and
      // can keep modern Cloudflare precursor checks in a verification loop.
      final bool stillChallenging = await _stillOnChallenge();
      if (_completed || _finishRequested) return;
      if (stillChallenging) {
        _clearanceSeen = 0;
        _clearanceFirstSeenAt = null;
        _cleanPageSeen = 0;
        return;
      }

      final List<Cookie> cookies = await _readCookies();
      // Re-check after the await: dispose may have run while we were waiting.
      if (_completed || _finishRequested) return;
      _consecutiveErrors = 0;
      final bool cleared = cookies.any(
        (Cookie c) => c.name == 'cf_clearance' && _cookieValue(c).isNotEmpty,
      );
      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] poll: ${cookies.length} cookies, '
          'cf_clearance=$cleared, names=${cookies.map((Cookie c) => c.name).toList()}',
        );
      }
      if (cleared) {
        _clearanceSeen++;
        _clearanceFirstSeenAt ??= DateTime.now();
      } else {
        _clearanceSeen = 0;
        _clearanceFirstSeenAt = null;
      }

      _cleanPageSeen++;
      final bool cookieReady = cleared && _clearanceSettled();
      final bool browserSessionReady =
          _challengeObserved &&
          _cleanPageSeen >= _cleanPageConfirmPolls &&
          DateTime.now().difference(_lastWebViewActivityAt) >=
              _completionIdleDelay;
      if (!cookieReady && !browserSessionReady) {
        return;
      }

      final String header = cookies
          .where((Cookie c) => _cookieValue(c).isNotEmpty)
          .map((Cookie c) => '${c.name}=${_cookieValue(c)}')
          .join('; ');
      // cf_clearance is bound to the user agent that solved it. Capture the
      // WebView's user agent so the runtime can replay subsequent requests.
      final String userAgent = await _readUserAgent();
      final Uri effectiveUri = await _effectiveUri();
      if (_completed || _finishRequested) return;
      _finish((
        cookies: header,
        effectiveUri: effectiveUri,
        userAgent: userAgent,
      ));
    } catch (error) {
      if (_completed || _finishRequested) return;
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
    } finally {
      _clearanceCheckInFlight = false;
      if (_finishRequested && !_completed) {
        _completeFinish(_pendingFinishResult);
      }
    }
  }

  bool _clearanceSettled() {
    final DateTime now = DateTime.now();
    final DateTime? firstSeen = _clearanceFirstSeenAt;
    final Duration cookieAge = firstSeen == null
        ? Duration.zero
        : now.difference(firstSeen);
    final Duration idleFor = now.difference(_lastWebViewActivityAt);
    final bool settled =
        _clearanceSeen >= _clearanceConfirmPolls &&
        idleFor >= _completionIdleDelay;

    if (!settled && kDebugMode) {
      debugPrint(
        '[Cloudflare] waiting for clearance settle: '
        'seen=$_clearanceSeen/$_clearanceConfirmPolls, '
        'cookieAge=${cookieAge.inMilliseconds}ms, '
        'idle=${idleFor.inMilliseconds}ms',
      );
    }
    return settled;
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

  Future<Uri> _effectiveUri() async {
    final InAppWebViewController? controller = _controller;
    if (controller != null) {
      try {
        final WebUri? current = await controller.getUrl().timeout(
          const Duration(milliseconds: 1000),
          onTimeout: () => null,
        );
        final Uri? uri = Uri.tryParse(current?.toString() ?? '');
        if (uri != null &&
            uri.host.isNotEmpty &&
            (uri.scheme == 'http' || uri.scheme == 'https')) {
          return uri;
        }
      } catch (_) {}
    }
    return Uri.parse(_rootUri.toString());
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

  Future<bool?> _domShowsChallenge(InAppWebViewController controller) async {
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
      final bool hasMarker = CloudflareChallenge.isChallengeDocument(
        title: title,
        url: href,
        text: text,
        html: html,
      );

      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] dom: ready=$readyState '
          'selector=$hasSelector marker=$hasMarker '
          'title="$title" href="$href"',
        );
      }

      if (CloudflareChallenge.isChallengeDocument(
        title: title,
        url: href,
        text: text,
        html: html,
        hasSelector: hasSelector,
        isLoading: readyState == 'loading',
      )) {
        _challengeObserved = true;
        return true;
      }
      if (title.trim().isEmpty && text.trim().isEmpty) return true;
      return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Cloudflare] DOM challenge probe failed: $error');
      }
      return null;
    }
  }

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
    if (_mainFrameLoading) return true;
    try {
      String title = _observedDocumentTitle.trim().toLowerCase();
      if (title.isEmpty) {
        title =
            (await controller.getTitle().timeout(
              const Duration(milliseconds: 1000),
              onTimeout: () => '',
            ))?.toLowerCase() ??
            '';
      }
      final String url =
          (await controller.getUrl().timeout(
            const Duration(milliseconds: 1000),
            onTimeout: () => null,
          ))?.toString() ??
          '';
      if (kDebugMode) {
        debugPrint(
          '[Cloudflare] state: title="$title" url="$url" '
          'status=$_mainFrameHttpStatus',
        );
      }
      if (title.isEmpty) return true;
      if (CloudflareChallenge.isChallengeDocument(title: title, url: url) ||
          _mainFrameHttpStatus == 403 ||
          _mainFrameHttpStatus == 503) {
        _challengeObserved = true;
        return true;
      }
      final bool? domShowsChallenge = await _domShowsChallenge(controller);
      if (domShowsChallenge != null) return domShowsChallenge;
      return true;
    } catch (_) {
      // If we can't read the state, assume still challenging and keep waiting.
      return true;
    }
  }

  void _finish(CloudflareSolveResult? result) {
    if (_completed || _finishRequested) return;
    _finishRequested = true;
    _pendingFinishResult = result;
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _loadingFallbackTimer?.cancel();
    _controllerStartupTimer?.cancel();

    // A pending native WebView operation owns callbacks into its controller.
    // Let it settle before the overlay removes and disposes the platform view.
    if (_clearanceCheckInFlight) return;
    _completeFinish(result);
  }

  void _completeFinish(CloudflareSolveResult? result) {
    if (_completed) return;
    _completed = true;
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
    if (mounted && !_completed) {
      setState(() {
        _popupWindowId = createWindowAction.windowId;
        _popupController = null;
      });
      _markWebViewActivity();
    }
    return true;
  }

  void _disposePopupWebView() {
    if (mounted && !_completed) {
      setState(() {
        _popupWindowId = null;
        _popupController = null;
      });
    } else {
      _popupController = null;
      _popupWindowId = null;
    }
    unawaited(_checkForClearance());
  }

  Widget _buildPopupWebView(int windowId) {
    // A real InAppWebView with this windowId completes the platform new-window
    // contract. Keep it tiny so it does not cover the main challenge.
    return Positioned(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      child: InAppWebView(
        key: ValueKey<String>('cloudflare-popup-webview-$windowId'),
        windowId: windowId,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: true,
          supportMultipleWindows: true,
          thirdPartyCookiesEnabled: true,
          transparentBackground: false,
        ),
        onWebViewCreated: (InAppWebViewController popupController) {
          _popupController = popupController;
          _markWebViewActivity();
          if (kDebugMode) {
            debugPrint('[Cloudflare] popup WebView created');
          }
        },
        onCreateWindow: _handleCreateWindow,
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
      ),
    );
  }

  Widget _buildCloudflareWebView() {
    final int? popupWindowId = _popupWindowId;
    return ColoredBox(
      color: Colors.white,
      // Insert the view only after _preClearCookies() finishes so the initial
      // request starts with a clean store and no racing async loadUrl call.
      child: Stack(
        children: <Widget>[
          _ready
              ? InAppWebView(
                  // No custom userAgent is set. See the class documentation.
                  key: const ValueKey<String>('cloudflare-main-webview'),
                  initialUrlRequest: URLRequest(url: _rootUri),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    supportMultipleWindows: true,
                    thirdPartyCookiesEnabled: true,
                    transparentBackground: false,
                  ),
                  onWebViewCreated: (InAppWebViewController controller) {
                    _controller = controller;
                    _controllerStartupTimer?.cancel();
                    _markWebViewActivity();
                    if (kDebugMode) {
                      debugPrint('[Cloudflare] onWebViewCreated');
                    }
                  },
                  onCreateWindow: _handleCreateWindow,
                  onLoadStart: (_, WebUri? url) {
                    _markWebViewActivity();
                    _mainFrameLoading = true;
                    _mainFrameHttpStatus = null;
                    _observedDocumentTitle = '';
                    if (kDebugMode) {
                      debugPrint('[Cloudflare] onLoadStart: $url');
                    }
                    if (mounted) setState(() => _loading = true);
                  },
                  onLoadStop: (_, WebUri? url) {
                    _markWebViewActivity();
                    _mainFrameLoading = false;
                    _mainFrameHttpStatus = null;
                    if (kDebugMode) {
                      debugPrint('[Cloudflare] onLoadStop: $url');
                    }
                    if (mounted) setState(() => _loading = false);
                    unawaited(_checkForClearance());
                  },
                  onProgressChanged: (_, int progress) {
                    if (progress < 100) _markWebViewActivity();
                    _mainFrameLoading = progress < 100;
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
                  onTitleChanged: (_, String? title) {
                    _observedDocumentTitle = title?.trim() ?? '';
                    _markWebViewActivity();
                    if (CloudflareChallenge.isChallengeDocument(
                      title: _observedDocumentTitle,
                    )) {
                      _challengeObserved = true;
                    }
                    unawaited(_checkForClearance());
                  },
                  onReceivedHttpError: (_, request, errorResponse) {
                    if (request.isForMainFrame != false) {
                      _mainFrameLoading = false;
                      _mainFrameHttpStatus = errorResponse.statusCode;
                      _markWebViewActivity();
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
          if (popupWindowId != null) _buildPopupWebView(popupWindowId),
        ],
      ),
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
            Expanded(child: _buildCloudflareWebView()),
          ],
        ),
      ),
    );
  }
}
