import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watch party controls are translated in every supported locale', () {
    const List<String> keys = <String>[
      'Watch with Friends',
      'Watch party',
      'Create or join a room to watch the same episode in sync. Each device plays its own local stream; only playback control is shared.',
      'Watch the same episode together, in sync.',
      'Each device plays its own local stream. Only playback control is shared. The host controls play, pause, seek, speed and the episode/source.',
      'Create a room',
      'Join a room',
      'You are the host',
      'You joined as a guest',
      'Room',
      'Leave party',
      'Share this code or QR with your friend.',
      'QR unavailable',
      'Room code copied',
      'Copy invite link',
      'Invite link copied',
      'Create new room',
      'Connected! Open an episode and your friend will follow along.',
      'Enter the 6-character room code, or paste a relay invite link from the host.',
      'Join',
      'Scan QR',
      'Enter code manually',
      'Play / pause',
      'Seek',
      'Speed',
      'Change stream',
      'Your controls',
      'Guest permissions',
      'Not connected',
      'Waiting for the other device…',
      'Connecting…',
      'Connected',
      'Reconnecting…',
      'Disconnected',
      'Something went wrong',
      'Custom relay',
      'This Watch with Friends room uses a custom relay:',
      'Custom relays are operated by third parties and are not controlled by MiruShin. They can observe watch-party synchronization data. Video and audio are not sent through the relay.',
      'Trust this exact relay origin',
      'Host',
      'Host disconnected. Waiting for reconnection…',
      'participants',
      'participants connected',
      'Connection Mode',
      'Default stays peer-to-peer. Select a relay only when the default connection does not work on your network.',
      'Self-hosted Relay',
      'Relay URL',
      'Custom relays are operated by third parties. Prefer HTTPS; HTTP is accepted only for local/private development servers.',
      'Test Connection',
      'Reset to Default',
      'Relay settings saved.',
      'Relay connection successful. Protocol version: {version}',
      'Default connection restored.',
      'Default connection selected.',
      'Enter a valid relay URL.',
      'Relay URLs cannot contain a query or fragment.',
      'Use an HTTPS or WSS relay URL.',
      'Unencrypted relay URLs are allowed only for localhost or private networks.',
      'Relay unreachable.',
      'This server is not a MiruShin Watch with Friends relay.',
      'This relay uses an unsupported Watch with Friends protocol version.',
      'This relay does not provide a compatible WebSocket endpoint.',
      'The relay health check passed, but its WebSocket is unavailable.',
    ];

    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in keys) {
        expect(
          values[key],
          isA<String>().having(
            (String value) => value.trim(),
            '$locale translation for "$key"',
            isNotEmpty,
          ),
        );
        if (locale != 'en') {
          expect(
            values[key],
            isNot(key),
            reason: '$locale must not fall back to English for "$key"',
          );
        }
      }
    }
  });
}
