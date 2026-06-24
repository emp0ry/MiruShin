import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'oauth_token_bundle.dart';

/// Desktop callback server for the OAuth2 authorization-code flow used by the
/// MyAnimeList and Shikimori trackers. The redirect URI points at
/// `http://localhost:<port>/token`; the browser arrives with `?code=...` which
/// is captured directly (no URL-fragment dance, unlike AniList's implicit flow).
class OAuthCodeListener {
  OAuthCodeListener(this._servers, this._completer);

  final List<HttpServer> _servers;
  final Completer<OAuthCodeResult?> _completer;

  Future<OAuthCodeResult?> wait() {
    return _completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );
  }

  Future<void> cancel() async {
    if (!_completer.isCompleted) {
      _completer.complete(null);
    }
    for (final HttpServer server in _servers) {
      try {
        await server.close(force: true);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}

// Ensures only one desktop listener is alive at a time.
OAuthCodeListener? _activeListener;

Future<OAuthCodeListener> startOAuthCodeListener({required int port}) async {
  final OAuthCodeListener? previous = _activeListener;
  _activeListener = null;
  await previous?.cancel();

  final List<HttpServer> servers = await _bindServers(port);
  final Completer<OAuthCodeResult?> completer = Completer<OAuthCodeResult?>();

  Future<void> closeServers() async {
    for (final HttpServer server in servers) {
      try {
        await server.close(force: true);
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<void> handleRequest(HttpRequest request) async {
    final String? code = request.uri.queryParameters['code'];
    final String? state = request.uri.queryParameters['state'];

    request.response.headers.contentType = ContentType.html;
    request.response.write(code != null && code.trim().isNotEmpty
        ? _successPage
        : _failurePage);
    await request.response.close();

    if (!completer.isCompleted && code != null && code.trim().isNotEmpty) {
      completer.complete(OAuthCodeResult(code: code.trim(), state: state));
      _activeListener = null;
      await closeServers();
    }
  }

  for (final HttpServer server in servers) {
    server.listen(handleRequest);
  }

  final OAuthCodeListener listener = OAuthCodeListener(servers, completer);
  _activeListener = listener;
  return listener;
}

Future<List<HttpServer>> _bindServers(int port) async {
  if (!Platform.isLinux) {
    try {
      return <HttpServer>[
        await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          port,
          v6Only: false,
          shared: true,
        ),
      ];
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Tracker OAuth] Failed to bind localhost:$port: $error');
      }
      rethrow;
    }
  }

  final List<HttpServer> servers = <HttpServer>[];
  Object? lastError;

  try {
    servers.add(
      await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true),
    );
  } catch (error) {
    lastError = error;
  }

  try {
    servers.add(
      await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        port,
        v6Only: true,
        shared: true,
      ),
    );
  } catch (error) {
    lastError = error;
  }

  if (servers.isEmpty) {
    throw lastError ?? StateError('Failed to bind localhost:$port');
  }

  return servers;
}

const String _successPage = '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>MiruShin Login</title>
    <style>
      :root { color-scheme: light dark; }
      body { margin: 0; min-height: 100vh; display: grid; place-items: center;
        font-family: system-ui, -apple-system, Segoe UI, sans-serif;
        background: Canvas; color: CanvasText; }
      .card { max-width: 560px; margin: 24px; border: 1px solid rgba(127,127,127,0.35);
        border-radius: 16px; padding: 20px; background: rgba(127,127,127,0.08); }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Success</h1>
      <p>You can close this tab and return to MiruShin.</p>
    </div>
    <script>try { history.replaceState({}, document.title, '/'); } catch (e) {}</script>
  </body>
</html>
''';

const String _failurePage = '''
<!DOCTYPE html>
<html>
  <head><meta charset="utf-8" /><title>MiruShin Login</title></head>
  <body>
    <p>No authorization code was found. You can close this tab and try again.</p>
  </body>
</html>
''';
