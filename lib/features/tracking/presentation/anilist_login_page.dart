import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/anilist_models.dart';

class AniListLoginPage extends StatefulWidget {
  const AniListLoginPage({required this.authUrl, super.key});

  final String authUrl;

  @override
  State<AniListLoginPage> createState() => _AniListLoginPageState();
}

class _AniListLoginPageState extends State<AniListLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AniListOAuth',
        onMessageReceived: (JavaScriptMessage message) {
          _maybeCompleteFromRawParams(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            if (mounted) {
              setState(() => _loading = false);
            }
            await _tryCaptureFromPage();
          },
          onUrlChange: (UrlChange change) {
            final String? url = change.url;
            if (url != null) {
              _maybeCompleteFromUrl(url);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            _maybeCompleteFromUrl(request.url);
            final Uri? uri = Uri.tryParse(request.url);
            if (uri != null &&
                uri.scheme == AppConstants.aniListRedirectScheme &&
                uri.host == AppConstants.aniListRedirectHost &&
                uri.path == AppConstants.aniListRedirectPath) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  Future<void> _tryCaptureFromPage() async {
    if (_completed) {
      return;
    }

    try {
      await _controller.runJavaScript('''
        (function () {
          var raw = (window.location.hash || '').replace(/^#/, '');
          if (raw && raw.indexOf('access_token=') !== -1) {
            AniListOAuth.postMessage(raw);
          }
        })();
      ''');
    } catch (_) {
      // Some WebView platforms restrict script execution while navigating.
    }

    try {
      final Object href = await _controller.runJavaScriptReturningResult(
        'window.location.href',
      );
      _maybeCompleteFromUrl(href.toString().replaceAll('"', ''));
    } catch (_) {
      // Best-effort recovery.
    }
  }

  void _maybeCompleteFromUrl(String url) {
    final int fragmentIndex = url.indexOf('#');
    final int queryIndex = url.indexOf('?');
    if (fragmentIndex >= 0) {
      _maybeCompleteFromRawParams(url.substring(fragmentIndex + 1));
    } else if (queryIndex >= 0) {
      _maybeCompleteFromRawParams(url.substring(queryIndex + 1));
    }
  }

  void _maybeCompleteFromRawParams(String raw) {
    if (_completed || raw.isEmpty) {
      return;
    }

    Map<String, String> params;
    try {
      params = Uri.splitQueryString(raw);
    } catch (_) {
      return;
    }

    final String? token = params['access_token'];
    if (token == null || token.trim().isEmpty) {
      return;
    }

    final int expiresIn = int.tryParse(params['expires_in'] ?? '') ?? 31536000;
    _completed = true;
    Navigator.of(context).pop(
      AniListOAuthResult(
        accessToken: token.trim(),
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AniList Login')),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
