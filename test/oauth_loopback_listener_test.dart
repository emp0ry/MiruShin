import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/presentation/google_drive_login_flow.dart';
import 'package:mirushin/features/tracking/data/anilist_oauth_listener.dart';
import 'package:mirushin/features/tracking/data/oauth_code_listener.dart';
import 'package:mirushin/features/tracking/data/oauth_token_bundle.dart';
import 'package:mirushin/shared/models/anilist_models.dart';

void main() {
  test(
    'authorization-code listener accepts an IPv4 localhost callback',
    () async {
      final int port = await _unusedPort();
      final OAuthCodeListener listener = await startOAuthCodeListener(
        port: port,
      );
      try {
        await _get(
          Uri.parse(
            'http://127.0.0.1:$port/token?code=mal-code&state=expected-state',
          ),
        );

        final OAuthCodeResult? result = await listener.wait();
        expect(result?.code, 'mal-code');
        expect(result?.state, 'expected-state');
      } finally {
        await listener.cancel();
      }
    },
  );

  test(
    'authorization-code listener finishes immediately on OAuth error',
    () async {
      final int port = await _unusedPort();
      final OAuthCodeListener listener = await startOAuthCodeListener(
        port: port,
      );
      try {
        await _get(Uri.parse('http://127.0.0.1:$port/?error=access_denied'));

        expect(await listener.wait(), isNull);
      } finally {
        await listener.cancel();
      }
    },
  );

  test(
    'Google Drive flow keeps callback listener alive while waiting',
    () async {
      final int port = await _unusedPort();
      final OAuthCodeListener listener = await startOAuthCodeListener(
        port: port,
      );
      final Future<OAuthCodeResult?> pending = waitForGoogleDriveOAuthCallback(
        listener,
      );

      // Let the flow enter its wait before simulating the browser redirect. The
      // regression used to close the server at this exact point.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _get(
        Uri.parse(
          'http://127.0.0.1:$port/'
          '?code=google-code&state=google-state',
        ),
      );

      final OAuthCodeResult? result = await pending;
      expect(result?.code, 'google-code');
      expect(result?.state, 'google-state');
    },
  );

  test(
    'AniList listener captures the fragment-forwarded token over IPv4',
    () async {
      final int port = await _unusedPort();
      final AniListOAuthListener listener = await startAniListOAuthListener(
        port: port,
      );
      try {
        await _get(
          Uri.parse(
            'http://127.0.0.1:$port/token'
            '?access_token=anilist-token&expires_in=120',
          ),
        );

        final AniListOAuthResult? result = await listener.wait();
        expect(result?.accessToken, 'anilist-token');
        expect(result?.expiresAt.isAfter(DateTime.now()), isTrue);
      } finally {
        await listener.cancel();
      }
    },
  );
}

Future<int> _unusedPort() async {
  final ServerSocket socket = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = socket.port;
  await socket.close();
  return port;
}

Future<void> _get(Uri uri) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(uri);
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}
