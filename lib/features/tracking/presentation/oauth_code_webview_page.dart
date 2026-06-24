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
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
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
