import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../application/watch_party_connection_settings.dart';
import '../domain/watch_party_models.dart';
import 'relay_api.dart';
import 'relay_protocol.dart';
import 'watch_party_transport.dart';

class SelfHostedRelayHostConnection {
  const SelfHostedRelayHostConnection({
    required this.transport,
    required this.credentials,
  });

  final SelfHostedRelayTransport transport;
  final RelayRoomCredentials credentials;
}

class SelfHostedRelayTransport implements WatchPartyTransport {
  SelfHostedRelayTransport._({
    required Uri relay,
    required String roomId,
    required String token,
    required WatchPartyRole role,
  }) : _relay = relay,
       _roomId = roomId,
       _token = token,
       _role = role,
       _sessionId = _randomToken(18);

  static const List<Duration> _reconnectDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
  ];

  final Uri _relay;
  final String _roomId;
  final String _token;
  final WatchPartyRole _role;
  final String _sessionId;
  final StreamController<WatchPartyIncomingMessage> _messages =
      StreamController<WatchPartyIncomingMessage>.broadcast();
  final StreamController<WatchPartyTransportUpdate> _updates =
      StreamController<WatchPartyTransportUpdate>.broadcast();
  final StreamController<List<WatchPartyParticipant>> _participants =
      StreamController<List<WatchPartyParticipant>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Completer<void>? _welcome;
  bool _connected = false;
  bool _closing = false;
  bool _fatal = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  List<WatchPartyParticipant> _currentParticipants =
      const <WatchPartyParticipant>[];

  static Future<SelfHostedRelayHostConnection> createHost(
    Uri relay, {
    WatchPartyRelayApi? api,
  }) async {
    final RelayRoomCredentials credentials = await (api ?? WatchPartyRelayApi())
        .createRoom(relay);
    final SelfHostedRelayTransport transport = SelfHostedRelayTransport._(
      relay: relay,
      roomId: credentials.roomId,
      token: credentials.hostToken,
      role: WatchPartyRole.host,
    );
    await transport._connect(initial: true);
    return SelfHostedRelayHostConnection(
      transport: transport,
      credentials: credentials,
    );
  }

  static Future<SelfHostedRelayTransport> join({
    required Uri relay,
    required String roomId,
    required String joinToken,
  }) async {
    final SelfHostedRelayTransport transport = SelfHostedRelayTransport._(
      relay: relay,
      roomId: roomId,
      token: joinToken,
      role: WatchPartyRole.guest,
    );
    await transport._connect(initial: true);
    return transport;
  }

  String get roomId => _roomId;
  Uri get relay => _relay;
  List<WatchPartyParticipant> get currentParticipants => _currentParticipants;

  @override
  Stream<WatchPartyIncomingMessage> get messages => _messages.stream;
  @override
  Stream<WatchPartyTransportUpdate> get updates => _updates.stream;
  @override
  Stream<List<WatchPartyParticipant>> get participants => _participants.stream;
  @override
  bool get isConnected => _connected;

  Future<void> _connect({required bool initial}) async {
    if (_closing || _fatal) return;
    _reconnectTimer?.cancel();
    _updates.add(
      WatchPartyTransportUpdate(
        initial
            ? WatchPartyConnectionStatus.connecting
            : WatchPartyConnectionStatus.reconnecting,
      ),
    );
    final WebSocketChannel channel = WebSocketChannel.connect(
      WatchPartyRelayUrl.webSocketEndpoint(
        _relay,
        '/rooms/${Uri.encodeComponent(_roomId)}/connect',
      ),
    );
    _channel = channel;
    _welcome = Completer<void>();
    try {
      await channel.ready.timeout(const Duration(seconds: 10));
      _channelSub = channel.stream.listen(
        _handleMessage,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[WatchPartyRelay] socket error: $error');
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
      channel.sink.add(
        jsonEncode(<String, Object>{
          'v': WatchPartyRelayProtocol.version,
          'type': 'authenticate',
          'data': <String, Object>{
            'role': _role.name,
            'token': _token,
            'sessionId': _sessionId,
          },
        }),
      );
      await _welcome!.future.timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      await _channelSub?.cancel();
      _channelSub = null;
      await channel.sink.close();
      if (initial) {
        throw error is WatchPartyRelayException
            ? error
            : const WatchPartyRelayException('Could not connect to the relay.');
      }
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String ||
        utf8.encode(raw).length >
            WatchPartyRelayProtocol.maximumClientMessageBytes) {
      _fatalError('The relay sent an invalid message.');
      return;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final Map<String, dynamic> message = decoded.map(
        (dynamic key, dynamic value) => MapEntry('$key', value),
      );
      if (message['v'] != WatchPartyRelayProtocol.version) {
        _fatalError(
          'This relay uses an unsupported Watch with Friends protocol version.',
        );
        return;
      }
      final String type = '${message['type'] ?? ''}';
      final Map<String, dynamic> data = _asMap(message['data']);
      switch (type) {
        case 'welcome':
          _connected = true;
          _reconnectAttempt = 0;
          if (!(_welcome?.isCompleted ?? true)) _welcome!.complete();
          _updates.add(
            const WatchPartyTransportUpdate(
              WatchPartyConnectionStatus.connected,
            ),
          );
          _emitParticipants(data['participants']);
        case 'event':
          final Map<String, dynamic> rawEvent = _asMap(data['event']);
          _messages.add(
            WatchPartyIncomingMessage(
              WatchPartyEvent.fromJson(rawEvent),
              senderParticipantId: data['senderParticipantId'] as String?,
            ),
          );
        case 'participantJoined':
          _emitParticipantNotice(data, joined: true);
        case 'participantLeft':
          _emitParticipantNotice(data, joined: false);
        case 'participantUpdated':
          _emitParticipantNotice(data, joined: false);
        case 'participants':
          _emitParticipants(data['participants']);
        case 'hostDisconnected':
          _updates.add(
            const WatchPartyTransportUpdate(
              WatchPartyConnectionStatus.reconnecting,
              hostConnected: false,
            ),
          );
        case 'hostReconnected':
          _updates.add(
            const WatchPartyTransportUpdate(
              WatchPartyConnectionStatus.connected,
            ),
          );
        case 'roomClosed':
          _fatalError(
            '${data['message'] ?? 'Watch party ended because the host disconnected.'}',
          );
        case 'error':
          final String code = '${data['code'] ?? ''}';
          final String text = _friendlyRelayError(
            code,
            '${data['message'] ?? ''}',
          );
          if (data['fatal'] == true) {
            _fatalError(text);
          } else {
            _updates.add(
              WatchPartyTransportUpdate(
                _connected
                    ? WatchPartyConnectionStatus.connected
                    : WatchPartyConnectionStatus.error,
                error: text,
              ),
            );
          }
      }
    } on Object {
      _fatalError('The relay sent an invalid message.');
    }
  }

  void _emitParticipantNotice(
    Map<String, dynamic> data, {
    required bool joined,
  }) {
    final Map<String, dynamic> raw = _asMap(data['participant']);
    if (raw.isEmpty) return;
    final WatchPartyParticipant participant = WatchPartyParticipant.fromJson(
      raw,
    );
    if (joined && participant.role == WatchPartyRole.guest) {
      _messages.add(
        WatchPartyIncomingMessage(
          WatchPartyEvent(type: WatchPartyEventType.helloRequest),
          senderParticipantId: participant.id,
        ),
      );
    }
  }

  void _emitParticipants(dynamic raw) {
    if (raw is! List) return;
    _currentParticipants = raw
        .whereType<Map>()
        .map(
          (Map<dynamic, dynamic> item) => WatchPartyParticipant.fromJson(
            item.map((dynamic key, dynamic value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
    _participants.add(_currentParticipants);
  }

  void _handleDisconnect() {
    if (_closing || _fatal) return;
    _connected = false;
    _updates.add(
      const WatchPartyTransportUpdate(WatchPartyConnectionStatus.reconnecting),
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closing || _fatal || _reconnectTimer?.isActive == true) return;
    if (_reconnectAttempt >= _reconnectDelays.length) {
      _fatalError('Relay connection lost.');
      return;
    }
    final Duration delay = _reconnectDelays[_reconnectAttempt++];
    _reconnectTimer = Timer(delay, () => unawaited(_connect(initial: false)));
  }

  void _fatalError(String message) {
    if (_fatal || _closing) return;
    _fatal = true;
    _connected = false;
    if (!(_welcome?.isCompleted ?? true)) {
      _welcome!.completeError(WatchPartyRelayException(message));
    }
    _updates.add(
      WatchPartyTransportUpdate(
        WatchPartyConnectionStatus.error,
        error: message,
      ),
    );
    unawaited(_channel?.sink.close());
  }

  @override
  Future<void> send(
    WatchPartyEvent event, {
    String? targetParticipantId,
  }) async {
    final WebSocketChannel? channel = _channel;
    if (!_connected || channel == null) return;
    channel.sink.add(
      jsonEncode(<String, Object>{
        'v': WatchPartyRelayProtocol.version,
        'type': 'event',
        'data': <String, Object>{
          'event': event.toJson(),
          'targetParticipantId': ?targetParticipantId,
        },
      }),
    );
  }

  @override
  Future<void> resume() async {
    if (_connected || _closing || _fatal) return;
    _reconnectAttempt = 0;
    await _connect(initial: false);
  }

  @override
  Future<void> disconnect({bool closeRoom = false}) async {
    if (_closing) return;
    if (closeRoom && _connected && _role == WatchPartyRole.host) {
      _channel?.sink.add(
        jsonEncode(<String, Object>{
          'v': WatchPartyRelayProtocol.version,
          'type': 'closeRoom',
          'data': const <String, Object>{},
        }),
      );
    }
    _closing = true;
    _connected = false;
    _reconnectTimer?.cancel();
    await _channelSub?.cancel();
    await _channel?.sink.close(1000, 'client leaving');
    await _messages.close();
    await _updates.close();
    await _participants.close();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((dynamic key, dynamic item) => MapEntry('$key', item));
  }

  static String _friendlyRelayError(String code, String fallback) {
    return switch (code) {
      'room_not_found' => 'Room not found or expired.',
      'room_full' => 'This watch party is full.',
      'permission_denied' => 'The host has not allowed that action.',
      'authentication_failed' => 'Relay room authentication failed.',
      'protocol_mismatch' =>
        'This relay uses an unsupported Watch with Friends protocol version.',
      'host_unavailable' => 'Host disconnected. Waiting for reconnection…',
      _ => fallback.isEmpty ? 'Relay connection failed.' : fallback,
    };
  }

  static String _randomToken(int byteLength) {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(
      byteLength,
      (_) => random.nextInt(256),
      growable: false,
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
