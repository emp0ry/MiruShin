import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../application/watch_party_connection_settings.dart';
import 'relay_protocol.dart';

class RelayRoomCredentials {
  const RelayRoomCredentials({
    required this.roomId,
    required this.hostToken,
    required this.joinToken,
  });

  final String roomId;
  final String hostToken;
  final String joinToken;
}

class WatchPartyRelayApi {
  WatchPartyRelayApi({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<RelayHealthResult> testConnection(String rawUrl) async {
    final Uri relay = WatchPartyRelayUrl.parse(rawUrl);
    Response<dynamic> response;
    try {
      response = await _dio.getUri<dynamic>(
        WatchPartyRelayUrl.endpoint(relay, '/health'),
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
    } on Object {
      throw const WatchPartyRelayException('Relay unreachable.');
    }
    final Map<String, dynamic>? health = _map(response.data);
    if (health == null ||
        health['service'] != WatchPartyRelayProtocol.service) {
      throw const WatchPartyRelayException(
        'This server is not a MiruShin Watch with Friends relay.',
      );
    }
    final int version = (health['protocolVersion'] as num?)?.toInt() ?? -1;
    if (version != WatchPartyRelayProtocol.version) {
      throw const WatchPartyRelayException(
        'This relay uses an unsupported Watch with Friends protocol version.',
        code: 'unsupported_protocol',
      );
    }
    await _probeWebSocket(relay);
    return RelayHealthResult(protocolVersion: version);
  }

  Future<RelayRoomCredentials> createRoom(Uri relay) async {
    try {
      final Response<dynamic> response = await _dio.postUri<dynamic>(
        WatchPartyRelayUrl.endpoint(relay, '/rooms'),
        data: <String, Object>{
          'protocol': WatchPartyRelayProtocol.protocol,
          'version': WatchPartyRelayProtocol.version,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final Map<String, dynamic>? data = _map(response.data);
      final String roomId = '${data?['roomId'] ?? ''}';
      final String hostToken = '${data?['hostToken'] ?? ''}';
      final String joinToken = '${data?['joinToken'] ?? ''}';
      if (roomId.isEmpty || hostToken.isEmpty || joinToken.isEmpty) {
        throw const WatchPartyRelayException(
          'The relay returned an invalid room.',
        );
      }
      return RelayRoomCredentials(
        roomId: roomId,
        hostToken: hostToken,
        joinToken: joinToken,
      );
    } on WatchPartyRelayException {
      rethrow;
    } on DioException catch (error) {
      throw WatchPartyRelayException(_relayHttpError(error));
    } on Object {
      throw const WatchPartyRelayException('Could not create the relay room.');
    }
  }

  Future<void> _probeWebSocket(Uri relay) async {
    final WebSocketChannel channel = WebSocketChannel.connect(
      WatchPartyRelayUrl.webSocketEndpoint(relay, '/probe'),
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 8));
      final dynamic raw = await channel.stream.first.timeout(
        const Duration(seconds: 8),
      );
      final Map<String, dynamic>? message = raw is String
          ? _map(jsonDecode(raw))
          : null;
      if (message?['type'] != 'probeOk' ||
          message?['v'] != WatchPartyRelayProtocol.version) {
        throw const WatchPartyRelayException(
          'This relay does not provide a compatible WebSocket endpoint.',
        );
      }
    } on WatchPartyRelayException {
      rethrow;
    } on Object {
      throw const WatchPartyRelayException(
        'The relay health check passed, but its WebSocket is unavailable.',
      );
    } finally {
      await channel.sink.close();
    }
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((dynamic key, dynamic item) => MapEntry('$key', item));
    }
    return null;
  }

  static String _relayHttpError(DioException error) {
    final Map<String, dynamic>? data = _map(error.response?.data);
    return switch ('${data?['code'] ?? ''}') {
      'room_limit' => 'The relay cannot create another room right now.',
      'rate_limited' => 'The relay is receiving too many room requests.',
      _ => 'Relay unavailable.',
    };
  }
}
