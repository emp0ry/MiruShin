import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/platform/tv_platform.dart';
import '../../../core/widgets/tv_web_cursor.dart';
import '../data/oauth_token_bundle.dart';

/// In-app WebView login for the OAuth2 authorization-code flow (MAL, Shikimori).
///
/// Loads [authUrl], then watches navigation for the redirect URI and returns
/// the captured `code` via [OAuthCodeResult]. The redirect is recognised by the
/// presence of a `code` query parameter on [redirectUri]'s host/path (or any
/// navigation carrying `?code=`), so no OS-level deep-link wiring is required.
///
/// Navigation to the redirect target itself is always *prevented*: for the
/// mobile custom-scheme redirect (`app://mirushin/auth`) letting the WebView
/// load it would fail with `ERR_UNKNOWN_URL_SCHEME` and leave a blank page; for
/// the https callback it would briefly flash the bare callback page. This
/// mirrors the working AniList login page.
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
  late final WebViewController _controller;
  late final Uri _redirect;
  bool _loading = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _redirect = Uri.parse(widget.redirectUri);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
            _maybeComplete(request.url);
            // Never actually navigate to the redirect target. The WebView
            // can't load app:// (ERR_UNKNOWN_URL_SCHEME → blank), and the
            // code/state is already captured from the URL above.
            if (_completed || _isRedirectTarget(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            if (kDebugMode) {
              debugPrint(
                '[Tracker OAuth] WebView error '
                '${error.errorCode} (${error.errorType}) on '
                '${error.url}: ${error.description}',
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  /// Best-effort capture from the page that actually loaded, for flows where
  /// the final redirect arrives via JavaScript rather than a navigation event.
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

  /// Whether [url] is the OAuth redirect target (so the WebView must not try to
  /// load it). Matches the redirect scheme/host/path or the OOB code page.
  bool _isRedirectTarget(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String? prefix = widget.oobCodePathPrefix;
    if (prefix != null && uri.path.startsWith(prefix)) return true;
    return uri.scheme == _redirect.scheme &&
        uri.host == _redirect.host &&
        (_redirect.path.isEmpty || uri.path == _redirect.path);
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
      if (mounted) {
        Navigator.of(context).pop(
          OAuthCodeResult(code: code.trim(), state: state),
        );
      }
      return true;
    }
    return false;
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
        ],
      ),
    );
  }
}
