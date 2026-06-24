import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/platform/tv_platform.dart';
import '../../../core/widgets/tv_web_cursor.dart';
import '../data/oauth_token_bundle.dart';

/// In-app WebView login for the OAuth2 authorization-code flow (MAL, Shikimori).
///
/// Loads [authUrl], then watches navigation for the redirect URI and returns
/// the captured `code` via [OAuthCodeResult]. The redirect is recognised by the
/// presence of a `code` query parameter on [redirectUri]'s host/path (or any
/// navigation carrying `?code=`), so no OS-level deep-link wiring is required.
class OAuthCodeWebViewPage extends StatefulWidget {
  const OAuthCodeWebViewPage({
    required this.authUrl,
    required this.redirectUri,
    required this.title,
    this.oobCodePathPrefix,
    super.key,
  });

  final String authUrl;
  final String redirectUri;
  final String title;

  /// For out-of-band flows (Shikimori): the path prefix of the page that shows
  /// the authorization code, e.g. `/oauth/authorize/`. When the WebView lands on
  /// `<host><prefix><code>`, the trailing segment is captured as the code.
  final String? oobCodePathPrefix;

  @override
  State<OAuthCodeWebViewPage> createState() => _OAuthCodeWebViewPageState();
}

class _OAuthCodeWebViewPageState extends State<OAuthCodeWebViewPage> {
  // A real mobile browser User-Agent. The default WebView UA contains "; wv)",
  // which MyAnimeList/Shikimori and the Cloudflare-fronted auth proxy treat as
  // an embedded/bot browser and answer with a blank page — the white screen.
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  late final WebViewController _controller;
  late final Uri _redirect;
  bool _loading = true;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _redirect = Uri.parse(widget.redirectUri);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            if (mounted) setState(() => _loading = false);
            if (TvPlatform.isAndroidTv) {
              await TvWebCursor.inject(_controller);
            }
            await _tryCaptureFromPage();
          },
          onUrlChange: (UrlChange change) {
            final String? url = change.url;
            if (url != null) _maybeComplete(url);
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_maybeComplete(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: _onWebResourceError,
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  /// Best-effort capture of the code from the page that actually loaded, for
  /// the case where the final redirect (often a server-side 302 to a custom
  /// scheme like `app://`) is not surfaced through the navigation callbacks.
  Future<void> _tryCaptureFromPage() async {
    if (_completed) return;
    try {
      final Object href = await _controller.runJavaScriptReturningResult(
        'window.location.href',
      );
      _maybeComplete(href.toString().replaceAll('"', ''));
    } catch (_) {
      // Some WebView platforms restrict script execution while navigating.
    }
  }

  void _onWebResourceError(WebResourceError error) {
    // A failure loading the custom-scheme redirect (e.g. app://mirushin/auth)
    // is expected — the WebView can't open it — so capture the code from the
    // URL instead of treating it as an error.
    final String? url = error.url;
    if (url != null && _maybeComplete(url)) return;
    // Only surface main-frame failures; subresource errors (analytics, fonts,
    // …) on the login page are harmless and must not hide the form.
    if (error.isForMainFrame == false) return;
    if (_completed || !mounted) return;
    setState(() {
      _loading = false;
      _error = error.description.isNotEmpty
          ? error.description
          : 'Error ${error.errorCode}';
    });
  }

  bool _maybeComplete(String url) {
    if (_completed) return false;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;

    String? code = uri.queryParameters['code'];
    final String? state = uri.queryParameters['state'];

    // Out-of-band flow (Shikimori): the code is the trailing path segment of
    // e.g. https://shikimori.one/oauth/authorize/<code>.
    final String? prefix = widget.oobCodePathPrefix;
    if (code == null && prefix != null && uri.path.startsWith(prefix)) {
      final String tail = uri.path.substring(prefix.length);
      if (tail.isNotEmpty && !tail.contains('/')) {
        code = tail;
      }
    }

    final bool matchesRedirect =
        uri.scheme == _redirect.scheme &&
        uri.host == _redirect.host &&
        (uri.path == _redirect.path || _redirect.path.isEmpty);

    if ((matchesRedirect || code != null) &&
        code != null &&
        code.trim().isNotEmpty) {
      _completed = true;
      Navigator.of(context).pop(
        OAuthCodeResult(code: code.trim(), state: state),
      );
      return true;
    }
    return false;
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _controller.loadRequest(Uri.parse(widget.authUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: <Widget>[
          TvWebCursor(
            controller: _controller,
            enabled: TvPlatform.isAndroidTv,
            child: WebViewWidget(controller: _controller),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) _ErrorOverlay(message: _error!, onRetry: _retry),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 40),
                const SizedBox(height: 12),
                Text(
                  context.t('Could not load the login page.'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.t('Retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
