import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/watch_party/application/watch_party_connection_settings.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_models.dart';
import 'package:mirushin/features/watch_party/domain/watch_party_qr.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('relay URL policy', () {
    test('normalizes secure endpoints and private development endpoints', () {
      expect(
        WatchPartyRelayUrl.parse('wss://Relay.Example.com/base/').toString(),
        'https://relay.example.com/base',
      );
      expect(
        WatchPartyRelayUrl.parse('http://192.168.1.20:8787/').toString(),
        'http://192.168.1.20:8787',
      );
      expect(
        WatchPartyRelayUrl.parse('ws://localhost:8787').toString(),
        'http://localhost:8787',
      );
    });

    test('rejects unsafe schemes, credentials, and public plaintext URLs', () {
      for (final String value in <String>[
        'file:///tmp/relay',
        'javascript:alert(1)',
        'data:text/plain,no',
        'http://relay.example.com',
        'http://fcloud.example.com',
        'https://user:password@relay.example.com',
        'https://relay.example.com?token=secret',
      ]) {
        expect(() => WatchPartyRelayUrl.parse(value), throwsFormatException);
      }
    });
  });

  test(
    'connection mode defaults safely and persists an explicit relay',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer first = ProviderContainer();
      addTearDown(first.dispose);
      expect(
        (await first.read(watchPartyConnectionSettingsProvider.future)).mode,
        WatchPartyConnectionMode.defaultConnection,
      );

      await first
          .read(watchPartyConnectionSettingsProvider.notifier)
          .saveRelay('https://relay.example.com/');
      final ProviderContainer restored = ProviderContainer();
      addTearDown(restored.dispose);
      final WatchPartyConnectionSettings value = await restored.read(
        watchPartyConnectionSettingsProvider.future,
      );
      expect(value.mode, WatchPartyConnectionMode.selfHostedRelay);
      expect(value.relayUrl, 'https://relay.example.com');

      await restored
          .read(watchPartyConnectionSettingsProvider.notifier)
          .resetToDefault();
      expect(
        restored.read(watchPartyConnectionSettingsProvider).value?.mode,
        WatchPartyConnectionMode.defaultConnection,
      );
    },
  );

  test('relay invite carries guest routing data but never a host token', () {
    final WatchPartyInvite invite = WatchPartyInvite(
      roomId: 'AbCdEfGhIjKlMnOp',
      mode: WatchPartyConnectionMode.selfHostedRelay,
      relayUrl: Uri.parse('https://relay.example.com'),
      joinToken: 'guest_join_token_1234567890',
    );
    final String encoded = invite.encode();
    expect(
      encoded,
      'https://relay.example.com/join?room=AbCdEfGhIjKlMnOp'
      '&token=guest_join_token_1234567890',
    );
    expect(encoded, contains('guest_join_token_1234567890'));
    expect(encoded, isNot(contains('hostToken')));
    expect(encoded, isNot(contains('relay=')));
    expect(encoded, isNot(contains('transport=')));

    final WatchPartyInvite decoded = WatchPartyInvite.tryParse(encoded)!;
    expect(decoded.isRelay, isTrue);
    expect(decoded.roomId, invite.roomId);
    expect(decoded.relayUrl, invite.relayUrl);
    expect(decoded.joinToken, invite.joinToken);
  });

  test('relay invite preserves a configured base path', () {
    final WatchPartyInvite invite = WatchPartyInvite(
      roomId: 'AbCdEfGhIjKlMnOp',
      mode: WatchPartyConnectionMode.selfHostedRelay,
      relayUrl: Uri.parse('https://relay.example.com/mirushin/relay'),
      joinToken: 'guest_join_token_1234567890',
    );
    final String encoded = invite.encode();
    expect(
      encoded,
      'https://relay.example.com/mirushin/relay/join'
      '?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890',
    );
    expect(WatchPartyInvite.tryParse(encoded)?.relayUrl, invite.relayUrl);
  });

  test('internal bridge and legacy relay invites remain readable', () {
    const String httpsInvite =
        'https://relay.example.com/base/join?room=AbCdEfGhIjKlMnOp'
        '&token=guest_join_token_1234567890';
    final String bridge = Uri(
      scheme: 'mirushin',
      host: 'watch-party',
      path: '/join',
      queryParameters: const <String, String>{'invite': httpsInvite},
    ).toString();
    final WatchPartyInvite bridged = WatchPartyInvite.tryParse(bridge)!;
    expect(bridged.relayUrl.toString(), 'https://relay.example.com/base');

    const String legacy =
        'mirushin:///watch-party/join?room=AbCdEfGhIjKlMnOp'
        '&transport=relay&relay=https%3A%2F%2Frelay.example.com%2Fbase'
        '&token=guest_join_token_1234567890';
    final WatchPartyInvite decodedLegacy = WatchPartyInvite.tryParse(legacy)!;
    expect(decodedLegacy.relayUrl.toString(), 'https://relay.example.com/base');
  });

  test('relay invites reject invalid routes, fields, and extra parameters', () {
    for (final String value in <String>[
      'https://evil.example/watch-party/join?transport=relay&room=AbCdEfGhIjKlMnOp&relay=https%3A%2F%2Frelay.example.com&token=guest_join_token_1234567890',
      'https://relay.example.com/join?room=short&token=guest_join_token_1234567890',
      'https://relay.example.com/join?room=AbCdEfGhIjKlMnOp&token=short',
      'https://relay.example.com/join?room=AbCdEfGhIjKlMnOp&token=guest_join_token_1234567890&hostToken=secret',
      'mirushin://watch-party/join?invite=mirushin%3A%2F%2Fwatch-party%2Fjoin%3Fcode%3DABC123',
    ]) {
      expect(WatchPartyInvite.tryParse(value), isNull, reason: value);
    }
  });

  test('legacy default QR payload remains backward compatible', () {
    const String code = 'ABC123';
    expect(encodeWatchPartyQr(code), 'mirushin://watch-party/join?code=ABC123');
    final WatchPartyInvite decoded = WatchPartyInvite.tryParse(
      encodeWatchPartyQr(code),
    )!;
    expect(decoded.roomId, code);
    expect(decoded.mode, WatchPartyConnectionMode.defaultConnection);
  });

  test('room state represents multiple participants and relay host loss', () {
    final WatchPartyRoomState state = WatchPartyRoomState(
      role: WatchPartyRole.guest,
      status: WatchPartyConnectionStatus.reconnecting,
      connectionMode: WatchPartyConnectionMode.selfHostedRelay,
      hostConnected: false,
      participants: <WatchPartyParticipant>[
        const WatchPartyParticipant(
          id: 'host',
          role: WatchPartyRole.host,
          connected: false,
        ),
        for (int index = 1; index <= 4; index++)
          WatchPartyParticipant(
            id: 'guest-$index',
            role: WatchPartyRole.guest,
            connected: true,
          ),
      ],
    );
    expect(
      state.participants.where((participant) => participant.connected),
      hasLength(4),
    );
    expect(state.hostConnected, isFalse);
  });
}
