import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../domain/watch_party_models.dart';

/// Wraps a single [RTCPeerConnection] + a reliable ordered [RTCDataChannel].
/// The Worker is used only to exchange the offer/answer/ICE candidates; once
/// the channel opens every [WatchPartyEvent] travels directly peer-to-peer.
class WebRtcSyncService {
  WebRtcSyncService();

  // Public STUN only (no TURN initially), as required for the first version.
  static const Duration _iceGatheringTimeout = Duration(seconds: 8);
  static const List<Map<String, dynamic>> _iceServers = <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': <String>[
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
      ],
    },
  ];

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;

  final StreamController<WatchPartyEvent> _messages =
      StreamController<WatchPartyEvent>.broadcast();
  final StreamController<bool> _channelOpen =
      StreamController<bool>.broadcast();
  final StreamController<RTCPeerConnectionState> _connection =
      StreamController<RTCPeerConnectionState>.broadcast();

  Stream<WatchPartyEvent> get messages => _messages.stream;
  Stream<bool> get channelOpen => _channelOpen.stream;
  Stream<RTCPeerConnectionState> get connectionState => _connection.stream;

  bool get isOpen => _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final RTCPeerConnection pc = await createPeerConnection(<String, dynamic>{
      'iceServers': _iceServers,
    });
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (!_connection.isClosed) _connection.add(state);
    };
    pc.onDataChannel = (RTCDataChannel channel) => _bindChannel(channel);
    _pc = pc;
  }

  /// Host side: create the DataChannel + offer.
  Future<Map<String, dynamic>> createOffer() async {
    await _ensurePeerConnection();
    final RTCDataChannel channel = await _pc!.createDataChannel(
      'mirushin-sync',
      RTCDataChannelInit()..ordered = true,
    );
    _bindChannel(channel);
    final RTCSessionDescription offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    final RTCSessionDescription complete = await _completeLocalDescription(
      offer,
    );
    return <String, dynamic>{'sdp': complete.sdp, 'type': complete.type};
  }

  /// Guest side: consume the host offer and produce an answer.
  Future<Map<String, dynamic>> createAnswer(Map<String, dynamic> offer) async {
    await _ensurePeerConnection();
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    final RTCSessionDescription answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    final RTCSessionDescription complete = await _completeLocalDescription(
      answer,
    );
    return <String, dynamic>{'sdp': complete.sdp, 'type': complete.type};
  }

  /// Waits briefly for STUN ICE candidates to be embedded in the local SDP.
  /// That lets signaling use one offer + one answer instead of trickling dozens
  /// of `/candidates` requests through the Worker.
  Future<RTCSessionDescription> _completeLocalDescription(
    RTCSessionDescription fallback,
  ) async {
    final RTCPeerConnection? pc = _pc;
    if (pc == null) return fallback;
    await _waitForIceGatheringComplete(pc);
    return await pc.getLocalDescription() ?? fallback;
  }

  Future<void> _waitForIceGatheringComplete(RTCPeerConnection pc) async {
    final RTCIceGatheringState? current = await pc.getIceGatheringState();
    if (current == RTCIceGatheringState.RTCIceGatheringStateComplete) return;

    final Completer<void> completer = Completer<void>();
    final void Function(RTCIceGatheringState state)? previous =
        pc.onIceGatheringState;

    pc.onIceGatheringState = (RTCIceGatheringState state) {
      previous?.call(state);
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };

    try {
      await completer.future.timeout(_iceGatheringTimeout);
    } on TimeoutException {
      debugPrint('[WatchParty] ICE gathering timed out; using partial SDP.');
    } finally {
      pc.onIceGatheringState = previous;
    }
  }

  /// Host side: apply the guest answer.
  Future<void> setRemoteAnswer(Map<String, dynamic> answer) async {
    await _pc?.setRemoteDescription(
      RTCSessionDescription(
        answer['sdp'] as String?,
        answer['type'] as String?,
      ),
    );
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> candidate) async {
    final RTCPeerConnection? pc = _pc;
    if (pc == null) return;
    await pc.addCandidate(
      RTCIceCandidate(
        candidate['candidate'] as String?,
        candidate['sdpMid'] as String?,
        (candidate['sdpMLineIndex'] as num?)?.toInt(),
      ),
    );
  }

  void _bindChannel(RTCDataChannel channel) {
    _channel = channel;
    channel.onDataChannelState = (RTCDataChannelState state) {
      if (!_channelOpen.isClosed) {
        _channelOpen.add(state == RTCDataChannelState.RTCDataChannelOpen);
      }
    };
    channel.onMessage = (RTCDataChannelMessage message) {
      if (!message.isBinary) {
        _handleText(message.text);
      }
    };
  }

  void _handleText(String text) {
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        _messages.add(WatchPartyEvent.fromJson(decoded));
      }
    } on Object catch (error) {
      debugPrint('[WatchParty] Failed to decode sync message: $error');
    }
  }

  Future<void> send(WatchPartyEvent event) async {
    final RTCDataChannel? channel = _channel;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    try {
      await channel.send(RTCDataChannelMessage(jsonEncode(event.toJson())));
    } on Object catch (error) {
      debugPrint('[WatchParty] Failed to send sync message: $error');
    }
  }

  Future<void> dispose() async {
    try {
      await _channel?.close();
    } on Object {
      // The channel may already be torn down by a connection failure.
    }
    try {
      await _pc?.close();
    } on Object {
      // Ignore late close errors during teardown.
    }
    _channel = null;
    _pc = null;
    await _messages.close();
    await _channelOpen.close();
    await _connection.close();
  }
}
