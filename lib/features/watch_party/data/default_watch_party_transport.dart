import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../domain/watch_party_models.dart';
import 'watch_party_transport.dart';
import 'webrtc_sync_service.dart';

/// Thin adapter over the established one-peer WebRTC transport. Signaling is
/// intentionally left unchanged in [WatchPartyController].
class DefaultWatchPartyTransport implements WatchPartyTransport {
  DefaultWatchPartyTransport(this._service, {required WatchPartyRole role}) {
    _messageSub = _service.messages.listen(
      (WatchPartyEvent event) =>
          _messages.add(WatchPartyIncomingMessage(event)),
    );
    _openSub = _service.channelOpen.listen(_onOpen);
    _connectionSub = _service.connectionState.listen(_onConnection);
  }

  final WebRtcSyncService _service;
  final StreamController<WatchPartyIncomingMessage> _messages =
      StreamController<WatchPartyIncomingMessage>.broadcast();
  final StreamController<WatchPartyTransportUpdate> _updates =
      StreamController<WatchPartyTransportUpdate>.broadcast();
  final StreamController<List<WatchPartyParticipant>> _participants =
      StreamController<List<WatchPartyParticipant>>.broadcast();
  StreamSubscription<WatchPartyEvent>? _messageSub;
  StreamSubscription<bool>? _openSub;
  StreamSubscription<RTCPeerConnectionState>? _connectionSub;
  bool _disposed = false;
  bool _hasOpened = false;

  @override
  Stream<WatchPartyIncomingMessage> get messages => _messages.stream;
  @override
  Stream<WatchPartyTransportUpdate> get updates => _updates.stream;
  @override
  Stream<List<WatchPartyParticipant>> get participants => _participants.stream;
  @override
  bool get isConnected => _service.isOpen;

  void _onOpen(bool open) {
    if (!open || _disposed) return;
    _hasOpened = true;
    _updates.add(
      const WatchPartyTransportUpdate(WatchPartyConnectionStatus.connected),
    );
    _participants.add(<WatchPartyParticipant>[
      WatchPartyParticipant(
        id: 'host',
        role: WatchPartyRole.host,
        connected: true,
      ),
      WatchPartyParticipant(
        id: 'guest',
        role: WatchPartyRole.guest,
        connected: true,
      ),
    ]);
  }

  void _onConnection(RTCPeerConnectionState value) {
    if (_disposed) return;
    final WatchPartyConnectionStatus? status = switch (value) {
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
        WatchPartyConnectionStatus.reconnecting,
      RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
        WatchPartyConnectionStatus.error,
      RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
        WatchPartyConnectionStatus.closed,
      RTCPeerConnectionState.RTCPeerConnectionStateConnected when _hasOpened =>
        WatchPartyConnectionStatus.connected,
      _ => null,
    };
    if (status != null) {
      _updates.add(
        WatchPartyTransportUpdate(
          status,
          error: status == WatchPartyConnectionStatus.error
              ? 'Connection lost.'
              : null,
        ),
      );
    }
  }

  @override
  Future<void> send(WatchPartyEvent event, {String? targetParticipantId}) =>
      _service.send(event);

  @override
  Future<void> resume() async {}

  @override
  Future<void> disconnect({bool closeRoom = false}) async {
    if (_disposed) return;
    _disposed = true;
    await _messageSub?.cancel();
    await _openSub?.cancel();
    await _connectionSub?.cancel();
    await _service.dispose();
    await _messages.close();
    await _updates.close();
    await _participants.close();
  }
}
