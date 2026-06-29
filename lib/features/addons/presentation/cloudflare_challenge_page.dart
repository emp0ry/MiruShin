import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../app/localization/app_localizations.dart';
import '../application/cloudflare_challenge_service.dart';

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

  final CookieManager _cookies = CookieManager.instance();
  InAppWebViewController? _controller;
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  Timer? _loadingFallbackTimer;
  int _consecutiveErrors = 0;
  bool _completed = false;
  bool _loading = true;
  // Becomes true once the pre-navigation cookie flush is done (or timed out).
  // Only then is the InAppWebView widget inserted with initialUrlRequest so
  // the first navigation already starts clean, without an async loadUrl call
  // inside onWebViewCreated (which can silently no-op on Windows/WebView2).
  bool _ready = false;

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
    _preClearCookies();
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
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _loadingFallbackTimer?.cancel();
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

  Future<void> _checkForClearance() async {
    if (_completed || _controller == null) return;
    try {
      final List<Cookie> cookies = await _cookies.getCookies(
        url: _rootUri,
        webViewController: _controller,
      );
      // Re-check after the await: dispose may have run while we were waiting.
      if (_completed) return;
      _consecutiveErrors = 0;
      final bool cleared = cookies.any((Cookie c) => c.name == 'cf_clearance');
      if (!cleared) return;

      // A cf_clearance cookie alone isn't proof we passed — a stale one may
      // linger in the shared store (it's HttpOnly, so we can't pre-delete it).
      // Only accept once the page is genuinely past the wall: the challenge
      // interstitial keeps the title "Just a moment…" and a `__cf_chl` URL until
      // it completes and reloads the real page with a fresh, valid cookie.
      if (await _stillOnChallenge()) return;

      final String header = cookies
          .where((Cookie c) => '${c.value}'.isNotEmpty)
          .map((Cookie c) => '${c.name}=${c.value}')
          .join('; ');
      // cf_clearance is bound to the UA that solved it — capture the WebView's
      // real UA so the runtime can replay it on subsequent requests.
      String userAgent = '';
      try {
        final Object? ua = await _controller?.evaluateJavascript(
          source: 'navigator.userAgent',
        );
        if (ua is String) userAgent = ua;
      } catch (_) {
        // Non-fatal: an empty UA just means the runtime keeps its default.
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

  /// Whether the WebView is still showing the Cloudflare interstitial (so a
  /// present cf_clearance cookie can't yet be trusted).
  Future<bool> _stillOnChallenge() async {
    final InAppWebViewController? controller = _controller;
    if (controller == null) return true;
    try {
      final String title = (await controller.getTitle())?.toLowerCase() ?? '';
      // Cloudflare's interstitial title is "Just a moment..." in all locales.
      if (title.contains('just a moment')) return true;
      final String url = (await controller.getUrl())?.toString() ?? '';
      return url.contains('__cf_chl');
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
              // White background under the WebView so the dark Flutter surface
              // never shows through during WebView2 inter-frame gaps (Windows)
              // or WKWebView transparent-background loading states (iOS/macOS).
              child: ColoredBox(
                color: Colors.white,
                // The InAppWebView is only inserted once _preClearCookies()
                // finishes so initialUrlRequest fires on a clean cookie store,
                // without a racing async loadUrl call inside onWebViewCreated
                // (which silently no-ops on Windows/WebView2 in some cases).
                child: _ready
                    ? InAppWebView(
                        // No custom userAgent on purpose — see the class doc.
                        initialUrlRequest: URLRequest(url: _rootUri),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          thirdPartyCookiesEnabled: true,
                          transparentBackground: true,
                        ),
                        onWebViewCreated: (InAppWebViewController controller) {
                          _controller = controller;
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
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
