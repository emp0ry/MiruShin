import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../shared/models/anilist_models.dart';

class AniListOAuthListener {
  AniListOAuthListener(this._servers, this._completer);

  final List<HttpServer> _servers;
  final Completer<AniListOAuthResult?> _completer;

  Future<AniListOAuthResult?> wait() {
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
AniListOAuthListener? _activeListener;

Future<AniListOAuthListener> startAniListOAuthListener({
  required int port,
}) async {
  // Cancel any previous listener before rebinding the port.
  final AniListOAuthListener? previous = _activeListener;
  _activeListener = null;
  await previous?.cancel();

  final List<HttpServer> servers = await _bindOAuthServers(port);
  final Completer<AniListOAuthResult?> completer =
      Completer<AniListOAuthResult?>();

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
    if (request.uri.path == '/') {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_fragmentCapturePage);
      await request.response.close();
      return;
    }

    if (request.uri.path == '/token') {
      String? token = request.uri.queryParameters['access_token'];
      String? expiresIn = request.uri.queryParameters['expires_in'];

      if (request.method.toUpperCase() == 'POST') {
        final List<int> bytes = await request.fold<List<int>>(
          <int>[],
          (List<int> previous, List<int> element) => previous..addAll(element),
        );
        final Map<String, String> body = Uri.splitQueryString(
          utf8.decode(bytes),
        );
        token = body['access_token'] ?? token;
        expiresIn = body['expires_in'] ?? expiresIn;
      }

      request.response.headers.contentType = ContentType.html;
      request.response.write(_successPage);
      await request.response.close();

      final int validSeconds = int.tryParse(expiresIn ?? '') ?? 31536000;
      if (!completer.isCompleted && token != null && token.trim().isNotEmpty) {
        completer.complete(
          AniListOAuthResult(
            accessToken: token.trim(),
            expiresAt: DateTime.now().add(Duration(seconds: validSeconds)),
          ),
        );
        _activeListener = null;
        await closeServers();
      }
      return;
    }

    request.response.statusCode = 404;
    await request.response.close();
  }

  for (final HttpServer server in servers) {
    server.listen(handleRequest);
  }

  final AniListOAuthListener listener = AniListOAuthListener(
    servers,
    completer,
  );
  _activeListener = listener;
  return listener;
}

Future<List<HttpServer>> _bindOAuthServers(int port) async {
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
        debugPrint('[AniList OAuth] Failed to bind localhost:$port: $error');
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
    if (kDebugMode) {
      debugPrint('[AniList OAuth] Failed to bind 127.0.0.1:$port: $error');
    }
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
    if (kDebugMode) {
      debugPrint('[AniList OAuth] Failed to bind [::1]:$port: $error');
    }
  }

  if (servers.isEmpty) {
    throw lastError ?? StateError('Failed to bind localhost:$port');
  }

  return servers;
}

const String _fragmentCapturePage = '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>AniList Login</title>
    <style>
      :root { color-scheme: light dark; }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        font-family: system-ui, -apple-system, Segoe UI, sans-serif;
        background: Canvas;
        color: CanvasText;
      }
      .card {
        max-width: 560px;
        margin: 24px;
        border: 1px solid rgba(127, 127, 127, 0.35);
        border-radius: 16px;
        padding: 20px;
        background: rgba(127, 127, 127, 0.08);
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>AniList Login</h1>
      <p id="status">Completing login...</p>
    </div>
    <script>
      (function () {
        var status = document.getElementById('status');
        var hash = new URLSearchParams((window.location.hash || '').replace(/^#/, ''));
        var token = hash.get('access_token');
        var expiresIn = hash.get('expires_in') || '';
        if (!token) {
          status.textContent = 'No access token was found. You can close this tab.';
          return;
        }
        window.location.replace('/token?access_token=' + encodeURIComponent(token) +
          (expiresIn ? '&expires_in=' + encodeURIComponent(expiresIn) : ''));
      })();
    </script>
  </body>
</html>
''';

const String _successPage = '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>AniList Login</title>
    <style>
      :root { color-scheme: light dark; }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        font-family: system-ui, -apple-system, Segoe UI, sans-serif;
        background: Canvas;
        color: CanvasText;
      }
      .card {
        max-width: 560px;
        margin: 24px;
        border: 1px solid rgba(127, 127, 127, 0.35);
        border-radius: 16px;
        padding: 20px;
        background: rgba(127, 127, 127, 0.08);
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Success</h1>
      <p>You can close this tab and return to MiruShin.</p>
    </div>
    <script>
      try { history.replaceState({}, document.title, '/'); } catch (e) {}
    </script>
  </body>
</html>
''';
