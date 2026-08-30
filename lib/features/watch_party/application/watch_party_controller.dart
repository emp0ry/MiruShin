import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/application/playback_controller.dart';
import '../../player/domain/player_models.dart';
import '../data/default_watch_party_transport.dart';
import '../data/self_hosted_relay_transport.dart';
import '../data/signaling_service.dart';
import '../data/watch_party_transport.dart';
import '../data/webrtc_sync_service.dart';
import '../domain/watch_party_models.dart';
import '../domain/watch_party_qr.dart';
import 'watch_party_connection_settings.dart';
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
    with WidgetsBindingObserver
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

  WatchPartyTransport? _transport;
  StreamSubscription<WatchPartyIncomingMessage>? _messageSub;
  StreamSubscription<WatchPartyTransportUpdate>? _connectionSub;
  StreamSubscription<List<WatchPartyParticipant>>? _participantsSub;

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
  SourceDescriptor? _pendingGuestStreamRequest;

  @override
  WatchPartyRoomState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(_teardown);
    return WatchPartyRoomState.idle;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeRelay());
    }
  }

  Future<void> _resumeRelay() async {
    if (state.connectionMode != WatchPartyConnectionMode.selfHostedRelay) {
      return;
    }
    await _transport?.resume();
    if (!state.isConnected) return;
    if (state.isGuest) {
      _send(WatchPartyEvent(type: WatchPartyEventType.helloRequest));
    } else if (state.isHost) {
      _send(_snapshotEvent());
    }
  }

  // Public API

  /// Host: create a room and wait for a guest to pair.
  Future<void> createRoom() async {
    final WatchPartyConnectionSettings settings = await ref.read(
      watchPartyConnectionSettingsProvider.future,
    );
    if (settings.mode == WatchPartyConnectionMode.selfHostedRelay) {
      await _createRelayRoom(settings);
      return;
    }
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
    _resolver = WatchPartyGuestResolver(ref);
    _setCurrentPartyProgressIgnored(false);
    _bindWebrtc(webrtc, role: WatchPartyRole.host);

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
    _bindWebrtc(webrtc, role: WatchPartyRole.guest);
    _lockGuestPlayback();

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

  Future<void> joinInvite(WatchPartyInvite invite) async {
    if (!invite.isRelay) {
      await joinRoom(invite.roomId);
      return;
    }
    final Uri? relay = invite.relayUrl;
    final String? joinToken = invite.joinToken;
    if (relay == null || joinToken == null) {
      _fail('Invalid relay invite.');
      return;
    }
    if (state.isActive) await leave();
    _resetSignalingState();
    state = WatchPartyRoomState(
      role: WatchPartyRole.guest,
      status: WatchPartyConnectionStatus.connecting,
      roomCode: invite.roomId,
      connectionMode: WatchPartyConnectionMode.selfHostedRelay,
      relayUrl: relay.toString(),
      inviteUrl: invite.encode(),
      hostConnected: true,
    );
    _resolver = WatchPartyGuestResolver(ref);
    _lockGuestPlayback();
    try {
      final SelfHostedRelayTransport transport =
          await SelfHostedRelayTransport.join(
            relay: relay,
            roomId: invite.roomId,
            joinToken: joinToken,
          );
      _bindTransport(transport);
      state = state.copyWith(participants: transport.currentParticipants);
      _onChannelOpen();
    } on Object catch (error) {
      _fail('Could not join room: $error');
    }
  }

  Future<void> _createRelayRoom(WatchPartyConnectionSettings settings) async {
    final String? rawRelay = settings.relayUrl;
    if (rawRelay == null) {
      _fail('Configure and test a self-hosted relay in Settings first.');
      return;
    }
    if (state.isActive) await leave();
    _resetSignalingState();
    final Uri relay;
    try {
      relay = WatchPartyRelayUrl.parse(rawRelay);
    } on FormatException catch (error) {
      _fail(error.message);
      return;
    }
    state = WatchPartyRoomState(
      role: WatchPartyRole.host,
      status: WatchPartyConnectionStatus.signaling,
      connectionMode: WatchPartyConnectionMode.selfHostedRelay,
      relayUrl: relay.toString(),
    );
    _resolver = WatchPartyGuestResolver(ref);
    _setCurrentPartyProgressIgnored(false);
    try {
      final SelfHostedRelayHostConnection connection =
          await SelfHostedRelayTransport.createHost(relay);
      final WatchPartyInvite invite = WatchPartyInvite(
        roomId: connection.credentials.roomId,
        mode: WatchPartyConnectionMode.selfHostedRelay,
        relayUrl: relay,
        joinToken: connection.credentials.joinToken,
      );
      _code = connection.credentials.roomId;
      state = state.copyWith(
        roomCode: connection.credentials.roomId,
        status: WatchPartyConnectionStatus.connecting,
        inviteUrl: invite.encode(),
        participants: connection.transport.currentParticipants,
      );
      _bindTransport(connection.transport);
      _onChannelOpen();
    } on Object catch (error) {
      _fail('Could not create room: $error');
    }
  }

  void _lockGuestPlayback() {
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    playback.setGuestLocked(true);
    _setCurrentPartyProgressIgnored(false);
    playback.setGuestPermissions(
      canControlPlayback: state.permissions.canControlPlayback,
      canSeek: state.permissions.canSeek,
      canChangeSpeed: state.permissions.canChangeSpeed,
      canChangeStream: state.permissions.canChangeStream,
    );
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

  void setGuestStreamChangeAllowed(bool allowed) {
    _updatePermissions(state.permissions.copyWith(canChangeStream: allowed));
  }

  // PlaybackSyncSink (host -> guests)

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
  void onHostSourceChanged({required bool userInitiated}) {
    if (!state.isConnected) return;
    if (state.isGuest &&
        (!userInitiated || !state.permissions.canChangeStream)) {
      return;
    }
    final SourceDescriptor? descriptor = _currentDescriptor();
    if (descriptor == null) return;
    if (state.isGuest) {
      _pendingGuestStreamRequest = descriptor;
    }
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    _send(
      WatchPartyEvent(
        type: state.isHost
            ? WatchPartyEventType.sourceChanged
            : WatchPartyEventType.streamChangeRequested,
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

  // WebRTC wiring

  void _bindWebrtc(WebRtcSyncService webrtc, {required WatchPartyRole role}) {
    _bindTransport(DefaultWatchPartyTransport(webrtc, role: role));
  }

  void _bindTransport(WatchPartyTransport transport) {
    _transport = transport;
    _messageSub = transport.messages.listen(_onMessage);
    _connectionSub = transport.updates.listen(_onTransportUpdate);
    _participantsSub = transport.participants.listen((
      List<WatchPartyParticipant> participants,
    ) {
      state = state.copyWith(participants: participants);
    });
  }

  void _onChannelOpen() {
    if (state.status == WatchPartyConnectionStatus.connected) {
      // Request a fresh snapshot after reconnecting so playback can realign.
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

  void _onTransportUpdate(WatchPartyTransportUpdate update) {
    if (state.status == WatchPartyConnectionStatus.error ||
        state.status == WatchPartyConnectionStatus.idle) {
      return;
    }
    if (update.status == WatchPartyConnectionStatus.error) {
      _fail(update.error ?? 'Connection lost.');
      return;
    }
    if (update.status == WatchPartyConnectionStatus.connected) {
      final bool reconnecting =
          state.status == WatchPartyConnectionStatus.reconnecting;
      state = state.copyWith(
        status: WatchPartyConnectionStatus.connected,
        peerConnected: true,
        hostConnected: update.hostConnected,
        clearError: true,
      );
      if (reconnecting && state.isGuest) {
        _send(WatchPartyEvent(type: WatchPartyEventType.helloRequest));
      }
      return;
    }
    state = state.copyWith(
      status: update.status,
      peerConnected: update.status == WatchPartyConnectionStatus.connected,
      hostConnected: update.hostConnected,
      lastError: update.error,
    );
  }

  // Incoming messages

  void _onMessage(WatchPartyIncomingMessage incoming) {
    final WatchPartyEvent event = incoming.event;
    if (state.isHost) {
      if (event.type == WatchPartyEventType.helloRequest) {
        _sendPermissions(targetParticipantId: incoming.senderParticipantId);
        _send(
          _snapshotEvent(),
          targetParticipantId: incoming.senderParticipantId,
        );
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
      } else if (event.type == WatchPartyEventType.streamChangeRequested) {
        unawaited(_handleGuestStreamChange(event));
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
      case WatchPartyEventType.streamChangeRequested:
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

  void _sendPermissions({String? targetParticipantId}) {
    if (!state.isConnected) return;
    _send(
      WatchPartyEvent(
        type: WatchPartyEventType.permissionsChanged,
        permissions: state.permissions,
      ),
      targetParticipantId: targetParticipantId,
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
          canChangeStream: permissions.canChangeStream,
        );
  }

  Future<void> _handleGuestStreamChange(WatchPartyEvent event) async {
    final SourceDescriptor? requested = event.source;
    final SourceDescriptor? current = _currentDescriptor();
    if (!state.permissions.canChangeStream ||
        requested == null ||
        current == null ||
        !requested.sameEpisodeAs(current)) {
      // Reassert the authoritative host selection so a request made just as
      // permission was revoked cannot leave the guest on a private fork.
      onHostSourceChanged(userInitiated: false);
      return;
    }

    final WatchPartyGuestResolver? resolver = _resolver;
    if (resolver == null) {
      onHostSourceChanged(userInitiated: false);
      return;
    }
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    final Duration position = playback.currentEnginePosition;
    final double speed = playback.currentPlaybackSpeed;
    final bool playing = playback.isEnginePlaying;
    final bool temporarySpeedActive = ref
        .read(playbackControllerProvider)
        .temporarySpeedActive;
    final bool relayMode =
        state.connectionMode == WatchPartyConnectionMode.selfHostedRelay;
    final bool alreadySelected = relayMode
        ? requested.sameSelectionAs(current)
        : requested.sameStreamAs(current);
    try {
      await resolver.apply(
        requested,
        position: position,
        speed: speed,
        temporarySpeedActive: temporarySpeedActive,
        playing: playing,
        syncQuality: relayMode,
        forceReload: !alreadySelected,
      );
      // A real reload broadcasts from PlaybackController.load(). An unchanged
      // request still needs an acknowledgement to clear the guest's pending
      // request and reassert the host's authoritative selection.
      if (alreadySelected) onHostSourceChanged(userInitiated: false);
    } on Object catch (error) {
      state = state.copyWith(lastError: 'Could not change stream: $error');
      onHostSourceChanged(userInitiated: false);
    }
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
    final bool hasPendingGuestStreamRequest =
        _pendingGuestStreamRequest != null;
    final bool relayMode =
        state.connectionMode == WatchPartyConnectionMode.selfHostedRelay;
    final bool syncInitialQuality = _lastAppliedSource == null || relayMode;
    if (!hasPendingGuestStreamRequest &&
        (relayMode
            ? descriptor.sameSelectionAs(_lastAppliedSource)
            : descriptor.sameStreamAs(_lastAppliedSource)) &&
        event.type != WatchPartyEventType.stateSnapshot) {
      return;
    }
    _pendingGuestStreamRequest = null;
    _lastAppliedSource = descriptor;
    try {
      await resolver.apply(
        descriptor,
        position: _expectedPosition(event),
        speed: event.speed,
        temporarySpeedActive: event.temporarySpeedActive,
        playing: event.isPlaying,
        syncQuality: syncInitialQuality,
        forceReload: hasPendingGuestStreamRequest,
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
    return event.expectedPositionAt(DateTime.now().millisecondsSinceEpoch);
  }

  void _setCurrentPartyProgressIgnored(bool ignored) {
    if (_currentDescriptor() == null) return;
    ref
        .read(playbackControllerProvider.notifier)
        .setCurrentItemProgressIgnored(ignored);
  }

  // Host snapshot / heartbeat

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
    final Duration interval =
        state.connectionMode == WatchPartyConnectionMode.selfHostedRelay
        ? const Duration(seconds: 10)
        : _heartbeat;
    _heartbeatTimer = Timer.periodic(interval, (_) {
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

  // Signaling polling

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

  // Teardown

  void _send(WatchPartyEvent event, {String? targetParticipantId}) {
    unawaited(
      _transport?.send(event, targetParticipantId: targetParticipantId),
    );
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
    if (state.isGuest) _setCurrentPartyProgressIgnored(false);

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
    _pendingGuestStreamRequest = null;
  }

  Future<void> _disposePeerAfterFailure() async {
    final StreamSubscription<WatchPartyIncomingMessage>? messageSub =
        _messageSub;
    final StreamSubscription<WatchPartyTransportUpdate>? connectionSub =
        _connectionSub;
    final StreamSubscription<List<WatchPartyParticipant>>? participantsSub =
        _participantsSub;
    final WatchPartyTransport? transport = _transport;

    _messageSub = null;
    _connectionSub = null;
    _participantsSub = null;
    _transport = null;
    _webrtc = null;
    _resolver = null;

    await messageSub?.cancel();
    await connectionSub?.cancel();
    await participantsSub?.cancel();
    await transport?.disconnect();
  }

  Future<void> _teardown() async {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _pollTimer = null;
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    await _messageSub?.cancel();
    await _connectionSub?.cancel();
    await _participantsSub?.cancel();
    _messageSub = null;
    _connectionSub = null;
    _participantsSub = null;

    // Release playback hooks.
    final PlaybackController playback = ref.read(
      playbackControllerProvider.notifier,
    );
    playback.setPlaybackSyncSink(null);
    playback.setGuestLocked(false);
    if (state.isGuest) _setCurrentPartyProgressIgnored(false);

    // Let the room expire by TTL; no cleanup request is needed.
    await _transport?.disconnect(closeRoom: state.isHost);
    _transport = null;
    _webrtc = null;
    _signaling = null;
    _resolver = null;
    _resetSignalingState();
  }
}
