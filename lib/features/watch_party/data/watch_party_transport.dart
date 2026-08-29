import '../domain/watch_party_models.dart';

class WatchPartyIncomingMessage {
  const WatchPartyIncomingMessage(this.event, {this.senderParticipantId});

  final WatchPartyEvent event;
  final String? senderParticipantId;
}

class WatchPartyTransportUpdate {
  const WatchPartyTransportUpdate(
    this.status, {
    this.error,
    this.hostConnected = true,
  });

  final WatchPartyConnectionStatus status;
  final String? error;
  final bool hostConnected;
}

/// Delivery boundary shared by the established P2P connection and the
/// optional self-hosted relay. Playback and permission logic lives above it.
abstract interface class WatchPartyTransport {
  Stream<WatchPartyIncomingMessage> get messages;
  Stream<WatchPartyTransportUpdate> get updates;
  Stream<List<WatchPartyParticipant>> get participants;
  bool get isConnected;

  Future<void> send(WatchPartyEvent event, {String? targetParticipantId});
  Future<void> resume();
  Future<void> disconnect({bool closeRoom = false});
}
