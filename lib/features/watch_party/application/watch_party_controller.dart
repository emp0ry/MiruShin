import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../player/application/playback_controller.dart';
import '../../player/domain/player_models.dart';
import '../data/signaling_service.dart';
import '../data/webrtc_sync_service.dart';
import '../domain/watch_party_models.dart';
import 'watch_party_guest_resolver.dart';

final watchPartyProvider =
    NotifierProvider<WatchPartyController, WatchPartyRoomState>(
      WatchPartyController.new,
    );

/// Orchestrates the whole watch party: the Worker pairing handshake, the P2P
/// WebRTC connection, and the bridge between [PlaybackController] and the peer.
/// The host broadcasts global playback changes (it implements [PlaybackSyncSink]);
/// the guest applies them with timestamp-based drift correction.
class WatchPartyController extends Notifier<WatchPartyRoomState>
    implements PlaybackSyncSink {
  // Drift beyond this triggers a corrective seek on the guest.
  static const Duration _maxDrift = Duration(seconds: 1);
  static const Duration _initialSignalingPoll = Duration(seconds: 1);
  static const Duration _maxSignalingPoll = Duration(seconds: 8);
  static const Duration _pairingTimeout = Duration(seconds: 60);
  static const Duration _heartbeat = Duration(seconds: 1);
  static const int _maxHostAnswerFetches = 2;

  SignalingService? _signaling;
  WebRtcSyncService? _webrtc;
  WatchPartyGuestResolver? _resolver;

  StreamSubscription<bool>? _channelSub;
  StreamSubscription<WatchPartyEvent>? _messageSub;
  StreamSubscription<RTCPeerConnectionState>? _connectionSub;

  Timer? _pollTimer;
  Timer? _pairingTimeoutTimer;
  Timer? _heartbeatTimer;
  Timer? _finalizeTimer;

  String? _code;
  Duration _nextSignalingPoll = _initialSignalingPoll;
  int _hostAnswerFetches = 0;
  bool _remoteAnswerSet = false;
  bool _signalingDone = false;
  // Latest source descriptor the guest applied, to avoid redundant reloads.
  SourceDescriptor? _lastAppliedSource;

  @override
  WatchPartyRoomState build() {
    ref.onDispose(_teardown);
    return WatchPartyRoomState.idle;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Host: create a room and wait for a guest to pair.
  Future<void> createRoom() async {
    if (state.isActive) await leave();
    _resetSignalingState();
    state = const WatchPartyRoomState(
      role: WatchPartyRole.host,
      status: WatchPartyConnectionStatus.signaling,
    );

    final SignalingService signaling = SignalingService();
    final WebRtcSyncService webrtc = WebRtcSyncService();
    _signaling = signaling;
    _webrtc = webrtc;
    _bindWebrtc(webrtc, role: 'host');

    try {
      final Map<String, dynamic> offer = await webrtc.createOffer();
      final String code = await signaling.createRoom(offer);
      _code = code;
      state = state.copyWith(roomCode: code);
      _startHostPolling();
    } on Object catch (error) {
      _fail('Could not create room: $error', deleteRoom: true);
    }
  }

  /// Guest: join an existing room by [code].
  Future<void> joinRoom(String rawCode) async {
    final String code = rawCode.trim().toUpperCase();
    if (code.length != 6) {
      state = const WatchPartyRoomState(
        role: WatchPartyRole.guest,
        status: WatchPartyConnectionStatus.error,
        lastError: 'Enter a valid 6-character room code.',
      );
      return;
    }
    if (state.isActive) await leave();
    _resetSignalingState();
    state = WatchPartyRoomState(
      role: WatchPartyRole.guest,
      status: WatchPartyConnectionStatus.signaling,
      roomCode: code,
    );

    final SignalingService signaling = SignalingService();
    final WebRtcSyncService webrtc = WebRtcSyncService();
    _signaling = signaling;
    _webrtc = webrtc;
    _resolver = WatchPartyGuestResolver(ref);
    _code = code;
    _bindWebrtc(webrtc, role: 'guest');
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    playback.setGuestLocked(true);
    playback.setGuestPermissions(
      canControlPlayback: state.permissions.canControlPlayback,
      canSeek: state.permissions.canSeek,
      canChangeSpeed: state.permissions.canChangeSpeed,
    );

    try {
      final Map<String, dynamic>? offer = await signaling.fetchOffer(code);
      if (offer == null) {
        _fail('Room not found or expired.');
        return;
      }
      final Map<String, dynamic> answer = await webrtc.createAnswer(offer);
      await signaling.postAnswer(code, answer);
      state = state.copyWith(status: WatchPartyConnectionStatus.connecting);
      _startPairingDeadline(
        'Could not connect within 60 seconds. Ask the host for a fresh code.',
        deleteRoom: false,
      );
    } on Object catch (error) {
      _fail('Could not join room: $error');
    }
  }

  /// Leave the party and release everything.
  Future<void> leave() async {
    await _teardown();
    state = WatchPartyRoomState.idle;
  }

  void setGuestPlaybackControlAllowed(bool allowed) {
    _updatePermissions(state.permissions.copyWith(canControlPlayback: allowed));
  }

  void setGuestSeekAllowed(bool allowed) {
    _updatePermissions(state.permissions.copyWith(canSeek: allowed));
  }

  void setGuestSpeedAllowed(bool allowed) {
    _updatePermissions(state.permissions.copyWith(canChangeSpeed: allowed));
  }

  // ---------------------------------------------------------------------------
  // PlaybackSyncSink (host -> guests)
  // ---------------------------------------------------------------------------

  @override
  void onHostPlay(Duration position, double speed) {
    if (!state.isConnected) return;
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.play,
        position: position,
        speed: speed,
        isPlaying: true,
      ),
    );
  }

  @override
  void onHostPause(Duration position, double speed) {
    if (!state.isConnected) return;
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.pause,
        position: position,
        speed: speed,
        isPlaying: false,
      ),
    );
  }

  @override
  void onHostSeek(Duration position, double speed, bool playing) {
    if (!state.isConnected) return;
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.seek,
        position: position,
        speed: speed,
        isPlaying: playing,
      ),
    );
  }

  @override
  void onHostSpeed(
    double speed,
    Duration position,
    bool playing, {
    bool temporary = false,
  }) {
    if (!state.isConnected) return;
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.speed,
        position: position,
        speed: speed,
        isPlaying: playing,
        temporarySpeedActive: temporary,
      ),
    );
  }

  @override
  void onHostSourceChanged() {
    if (!state.isHost || !state.isConnected) return;
    final SourceDescriptor? descriptor = _currentDescriptor();
    if (descriptor == null) return;
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.sourceChanged,
        position: playback.currentEnginePosition,
        speed: playback.currentPlaybackSpeed,
        isPlaying: playback.isEnginePlaying,
        temporarySpeedActive: ref
            .read(playbackControllerProvider)
            .temporarySpeedActive,
        source: descriptor,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WebRTC wiring
  // ---------------------------------------------------------------------------

  void _bindWebrtc(WebRtcSyncService webrtc, {required String role}) {
    _channelSub = webrtc.channelOpen.listen((bool open) {
      if (open) {
        _onChannelOpen();
      }
    });
    _messageSub = webrtc.messages.listen(_onMessage);
    _connectionSub = webrtc.connectionState.listen(_onConnectionState);
  }

  void _onChannelOpen() {
    if (state.status == WatchPartyConnectionStatus.connected) {
      // A reconnect recovered — ask for a fresh snapshot to realign.
      state = state.copyWith(status: WatchPartyConnectionStatus.connected);
      if (state.isGuest) {
        _send(WatchPartyEvent(type: WatchPartyEventType.helloRequest));
      }
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _signalingDone = true;
    state = state.copyWith(
      status: WatchPartyConnectionStatus.connected,
      peerConnected: true,
      clearError: true,
    );

    ref.read(playbackControllerProvider.notifier).setPlaybackSyncSink(this);

    if (state.isHost) {
      _startHeartbeat();
    } else {
      _send(WatchPartyEvent(type: WatchPartyEventType.helloRequest));
    }

    // Pairing is complete. From here all sync is P2P. The Worker room is left
    // to expire by TTL so the app does not spend another request deleting it.
  }

  void _onConnectionState(RTCPeerConnectionState s) {
    if (state.status == WatchPartyConnectionStatus.error ||
        state.status == WatchPartyConnectionStatus.idle) {
      return;
    }
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (state.isConnected) {
          state = state.copyWith(
            status: WatchPartyConnectionStatus.reconnecting,
          );
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _fail('Connection lost.', deleteRoom: state.isHost && !_signalingDone);
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (state.isActive &&
            state.status != WatchPartyConnectionStatus.closed) {
          state = state.copyWith(status: WatchPartyConnectionStatus.closed);
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        if (state.status == WatchPartyConnectionStatus.reconnecting) {
          state = state.copyWith(status: WatchPartyConnectionStatus.connected);
          if (state.isGuest) {
            _send(WatchPartyEvent(type: WatchPartyEventType.helloRequest));
          }
        }
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming messages
  // ---------------------------------------------------------------------------

  void _onMessage(WatchPartyEvent event) {
    if (state.isHost) {
      if (event.type == WatchPartyEventType.helloRequest) {
        _sendPermissions();
        onHostSourceChanged();
        _send(_snapshotEvent());
      } else if (event.type == WatchPartyEventType.play ||
          event.type == WatchPartyEventType.pause) {
        if (state.permissions.canControlPlayback) {
          unawaited(_applyGuestPlayPause(event));
        }
      } else if (event.type == WatchPartyEventType.seek) {
        if (state.permissions.canSeek) {
          unawaited(_applyGuestSeek(event));
        }
      } else if (event.type == WatchPartyEventType.speed) {
        if (state.permissions.canChangeSpeed) {
          unawaited(
            ref
                .read(playbackControllerProvider.notifier)
                .applyRemoteSpeed(
                  event.speed,
                  temporary: event.temporarySpeedActive,
                ),
          );
        }
      }
      return;
    }
    if (event.permissions != null) {
      _applyPermissions(event.permissions!);
    }
    // Guest side: apply the host's global state.
    switch (event.type) {
      case WatchPartyEventType.play:
        unawaited(_applyPlayPause(event));
      case WatchPartyEventType.pause:
        unawaited(_applyPlayPause(event));
      case WatchPartyEventType.seek:
        unawaited(_applySeek(event));
      case WatchPartyEventType.speed:
        unawaited(
          ref
              .read(playbackControllerProvider.notifier)
              .applyRemoteSpeed(
                event.speed,
                temporary: event.temporarySpeedActive,
              ),
        );
      case WatchPartyEventType.positionSync:
        unawaited(_applyPositionSync(event));
      case WatchPartyEventType.sourceChanged:
      case WatchPartyEventType.episodeChanged:
      case WatchPartyEventType.stateSnapshot:
        unawaited(_applySource(event));
      case WatchPartyEventType.helloRequest:
      case WatchPartyEventType.permissionsChanged:
        break;
    }
  }

  void _updatePermissions(WatchPartyPermissions permissions) {
    if (!state.isHost) return;
    state = state.copyWith(permissions: permissions);
    _sendPermissions();
  }

  void _sendPermissions() {
    if (!state.isConnected) return;
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.permissionsChanged,
        permissions: state.permissions,
      ),
    );
  }

  void _applyPermissions(WatchPartyPermissions permissions) {
    state = state.copyWith(permissions: permissions);
    ref
        .read(playbackControllerProvider.notifier)
        .setGuestPermissions(
          canControlPlayback: permissions.canControlPlayback,
          canSeek: permissions.canSeek,
          canChangeSpeed: permissions.canChangeSpeed,
        );
  }

  Future<void> _applyPlayPause(WatchPartyEvent event) async {
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    if (event.isPlaying) {
      await playback.applyRemoteSeek(_expectedPosition(event));
      await playback.applyRemotePlay();
    } else {
      await playback.applyRemotePause();
      await playback.applyRemoteSeek(event.position);
    }
  }

  Future<void> _applyGuestPlayPause(WatchPartyEvent event) async {
    if (state.permissions.canSeek) {
      await _applyPlayPause(event);
      return;
    }
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    if (event.isPlaying) {
      await playback.applyRemotePlay();
    } else {
      await playback.applyRemotePause();
    }
  }

  Future<void> _applySeek(WatchPartyEvent event) async {
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    await playback.applyRemoteSeek(_expectedPosition(event));
    if (event.isPlaying) {
      await playback.applyRemotePlay();
    } else {
      await playback.applyRemotePause();
    }
  }

  Future<void> _applyGuestSeek(WatchPartyEvent event) async {
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    await playback.applyRemoteSeek(_expectedPosition(event));
    if (!state.permissions.canControlPlayback) return;
    if (event.isPlaying) {
      await playback.applyRemotePlay();
    } else {
      await playback.applyRemotePause();
    }
  }

  Future<void> _applyPositionSync(WatchPartyEvent event) async {
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    // Keep speed in lockstep. This also catches the very first heartbeat after a
    // guest joins, so the speed shows correctly even if the initial snapshot
    // applied before the engine was ready.
    final bool localTemporary = ref
        .read(playbackControllerProvider)
        .temporarySpeedActive;
    if ((playback.currentPlaybackSpeed - event.speed).abs() > 0.01 ||
        localTemporary != event.temporarySpeedActive) {
      await playback.applyRemoteSpeed(
        event.speed,
        temporary: event.temporarySpeedActive,
      );
    }
    // Keep play/pause in lockstep.
    if (event.isPlaying && !playback.isEnginePlaying) {
      await playback.applyRemotePlay();
    } else if (!event.isPlaying && playback.isEnginePlaying) {
      await playback.applyRemotePause();
    }
    final Duration expected = _expectedPosition(event);
    final Duration drift = (playback.currentEnginePosition - expected).abs();
    if (drift > _maxDrift) {
      await playback.applyRemoteSeek(expected);
    }
  }

  Future<void> _applySource(WatchPartyEvent event) async {
    final SourceDescriptor? descriptor = event.source;
    final WatchPartyGuestResolver? resolver = _resolver;
    if (descriptor == null || resolver == null) return;
    if (descriptor.sameSelectionAs(_lastAppliedSource) &&
        event.type != WatchPartyEventType.stateSnapshot) {
      return;
    }
    _lastAppliedSource = descriptor;
    try {
      await resolver.apply(
        descriptor,
        position: _expectedPosition(event),
        speed: event.speed,
        temporarySpeedActive: event.temporarySpeedActive,
        playing: event.isPlaying,
      );
    } on Object catch (error) {
      // Non-fatal: the party stays connected, the host keeps playing.
      state = state.copyWith(
        lastError: 'Could not load the host\'s source: $error',
      );
    }
  }

  /// expected = position + ((now - sentAt) / 1000) * speed, when playing.
  Duration _expectedPosition(WatchPartyEvent event) {
    if (!event.isPlaying) return event.position;
    final int elapsedMs = DateTime.now().millisecondsSinceEpoch - event.sentAt;
    if (elapsedMs <= 0) return event.position;
    final int advancedMs = (elapsedMs * event.speed).round();
    return event.position + Duration(milliseconds: advancedMs);
  }

  // ---------------------------------------------------------------------------
  // Host snapshot / heartbeat
  // ---------------------------------------------------------------------------

  WatchPartyEvent _snapshotEvent() {
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    return WatchPartyEvent(
      type: WatchPartyEventType.stateSnapshot,
      position: playback.currentEnginePosition,
      speed: playback.currentPlaybackSpeed,
      isPlaying: playback.isEnginePlaying,
      temporarySpeedActive: ref
          .read(playbackControllerProvider)
          .temporarySpeedActive,
      source: _currentDescriptor(),
      permissions: state.permissions,
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeat, (_) {
      if (!state.isHost || !state.isConnected) return;
      final PlaybackController playback = ref.read(
        playbackControllerProvider.notifier,
      );
      if (ref.read(playbackControllerProvider).engine == null) return;
      _send(
        WatchPartyEvent(
          type: WatchPartyEventType.positionSync,
          position: playback.currentEnginePosition,
          speed: playback.currentPlaybackSpeed,
          isPlaying: playback.isEnginePlaying,
          temporarySpeedActive: ref
              .read(playbackControllerProvider)
              .temporarySpeedActive,
        ),
      );
    });
  }

  SourceDescriptor? _currentDescriptor() {
    final MediaPlaybackItem? item = ref.read(playbackControllerProvider).item;
    if (item == null) return null;
    final String addonId = item.externalIds['sora_addon_id'] ?? '';
    final String href = item.externalIds['sora_episode_href'] ?? '';
    if (addonId.isEmpty || href.isEmpty) return null;
    final PlaybackState playback = ref.read(playbackControllerProvider);
    return SourceDescriptor(
      mediaId: item.id,
      title: item.title,
      originalTitle: item.originalTitle,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      mediaType: item.mediaType,
      externalIds: item.externalIds,
      soraAddonId: addonId,
      soraEpisodeHref: href,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      serverId: playback.server?.id,
      voiceoverId: playback.voiceover?.id,
      qualityId: playback.quality?.id,
      episodeCount: item.episodeCount,
    );
  }

  // ---------------------------------------------------------------------------
  // Signaling polling
  // ---------------------------------------------------------------------------

  void _startHostPolling() {
    _pollTimer?.cancel();
    _startPairingDeadline(
      'Nobody joined within 60 seconds. Create a new room to try again.',
      deleteRoom: true,
    );
    _scheduleHostPoll();
  }

  void _scheduleHostPoll() {
    _pollTimer?.cancel();
    if (_signalingDone || !state.isActive) return;
    _pollTimer = Timer(_nextSignalingPoll, () async {
      await _pollHostOnce();
      _scheduleNextPoll(_scheduleHostPoll);
    });
  }

  void _scheduleNextPoll(VoidCallback schedule) {
    if (_signalingDone ||
        !state.isActive ||
        _remoteAnswerSet ||
        state.status == WatchPartyConnectionStatus.error ||
        state.status == WatchPartyConnectionStatus.closed) {
      return;
    }
    _nextSignalingPoll = _nextSignalingPoll * 2;
    if (_nextSignalingPoll > _maxSignalingPoll) {
      _nextSignalingPoll = _maxSignalingPoll;
    }
    schedule();
  }

  Future<void> _pollHostOnce() async {
    final String? code = _code;
    if (_signalingDone ||
        code == null ||
        _remoteAnswerSet ||
        _hostAnswerFetches >= _maxHostAnswerFetches) {
      return;
    }
    final SignalingService? signaling = _signaling;
    final WebRtcSyncService? webrtc = _webrtc;
    if (signaling == null || webrtc == null) return;
    try {
      _hostAnswerFetches++;
      final Map<String, dynamic>? answer = await signaling.fetchAnswer(
        code,
        wait: true,
      );
      if (answer == null) {
        if (_hostAnswerFetches >= _maxHostAnswerFetches) {
          _fail(
            'Nobody joined within 60 seconds. Create a new room to try again.',
            deleteRoom: false,
          );
        }
        return;
      }
      _remoteAnswerSet = true;
      await webrtc.setRemoteAnswer(answer);
      _pollTimer?.cancel();
      _pollTimer = null;
      _nextSignalingPoll = _initialSignalingPoll;
      state = state.copyWith(status: WatchPartyConnectionStatus.connecting);
    } on Object catch (error) {
      debugPrint('[WatchParty] host poll error: $error');
    }
  }

  void _startPairingDeadline(String message, {required bool deleteRoom}) {
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = Timer(_pairingTimeout, () {
      if (_signalingDone || state.isConnected) return;
      _fail(message, deleteRoom: deleteRoom);
    });
  }

  // ---------------------------------------------------------------------------
  // Teardown
  // ---------------------------------------------------------------------------

  void _send(WatchPartyEvent event) {
    unawaited(_webrtc?.send(event));
  }

  void _fail(String message, {bool deleteRoom = false}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _signalingDone = true;

    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    playback.setPlaybackSyncSink(null);
    playback.setGuestLocked(false);

    final String? code = _code;
    // Rooms have a short KV TTL. Avoid delete calls in failure paths so a bad
    // pairing attempt stays bounded to a tiny number of Worker requests.
    if (deleteRoom && code != null) {
      debugPrint('[WatchParty] room $code will expire automatically.');
    }
    unawaited(_disposePeerAfterFailure());

    state = state.copyWith(
      status: WatchPartyConnectionStatus.error,
      peerConnected: false,
      lastError: message,
    );
  }

  void _resetSignalingState() {
    _code = null;
    _nextSignalingPoll = _initialSignalingPoll;
    _hostAnswerFetches = 0;
    _remoteAnswerSet = false;
    _signalingDone = false;
    _lastAppliedSource = null;
  }

  Future<void> _disposePeerAfterFailure() async {
    final StreamSubscription<bool>? channelSub = _channelSub;
    final StreamSubscription<WatchPartyEvent>? messageSub = _messageSub;
    final StreamSubscription<RTCPeerConnectionState>? connectionSub =
        _connectionSub;
    final WebRtcSyncService? webrtc = _webrtc;

    _channelSub = null;
    _messageSub = null;
    _connectionSub = null;
    _webrtc = null;
    _resolver = null;

    await channelSub?.cancel();
    await messageSub?.cancel();
    await connectionSub?.cancel();
    await webrtc?.dispose();
  }

  Future<void> _teardown() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    await _channelSub?.cancel();
    await _messageSub?.cancel();
    await _connectionSub?.cancel();
    _channelSub = null;
    _messageSub = null;
    _connectionSub = null;

    // Release playback hooks.
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    playback.setPlaybackSyncSink(null);
    playback.setGuestLocked(false);

    // Let the room expire by TTL; no cleanup request is needed.
    await _webrtc?.dispose();
    _webrtc = null;
    _signaling = null;
    _resolver = null;
    _resetSignalingState();
  }
}
