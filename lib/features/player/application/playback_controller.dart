import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/deep_links/mirushin_deep_link.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../core/platform/tv_platform.dart';
import '../../../shared/models/anilist_models.dart';
import '../../addons/data/anime_titles_service.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../library/application/local_library_provider.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/application/settings_state.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/application/tracker_sync_coordinator.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../../watch/application/stream_selection_preferences.dart';
import '../../watch/domain/normalized_models.dart';
import '../data/discord_rpc_service.dart';
import '../data/media_session_service.dart';
import '../data/subtitle_loader.dart';
import '../domain/offline_stall_recovery.dart';
import '../domain/playback_attempt_plan.dart';
import '../domain/playback_end_decision.dart';
import '../domain/player_models.dart';
import '../domain/player_volume_policy.dart';
import '../domain/seek_settle.dart';
import '../engine/local_hls_proxy.dart';
import '../engine/player_engine.dart';
import '../engine/player_engine_factory.dart';
import '../engine/seek_thumbnail.dart';
import '../engine/seek_thumbnail_extractor.dart';
import '../engine/seek_thumbnail_source.dart';
import 'player_settings.dart';
import 'resume_stability.dart';

/// Hook the watch-party host uses to broadcast its global playback changes to
/// guests. Implemented by the watch-party controller and registered via
/// [PlaybackController.setPlaybackSyncSink]. Kept in the player layer so the
/// player never depends on the watch-party feature (no import cycle).
abstract interface class PlaybackSyncSink {
  void onHostPlay(Duration position, double speed);
  void onHostPause(Duration position, double speed);
  void onHostSeek(Duration position, double speed, bool playing);
  void onHostSpeed(
    double speed,
    Duration position,
    bool playing, {
    bool temporary = false,
  });
  void onHostSourceChanged({required bool userInitiated});
}

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

Future<void> _ignorePlaybackTeardownErrors(Future<void> future) async {
  try {
    await future;
  } on Object {
    // Native/player resources can already be gone while the app is exiting.
  }
}

class PlaybackState {
  const PlaybackState({
    this.item,
    this.engine,
    this.server,
    this.quality,
    this.voiceover,
    this.subtitle,
    this.subtitleCues = const <SubtitleCue>[],
    this.loading = false,
    this.controlsVisible = true,
    this.locked = false,
    this.error,
    this.lastSkippedFrom,
    this.autoNextVisible = false,
    this.confirmedEnded = false,
    this.seekPreviewPosition,
    this.seekPreviewBufferedEnd,
    this.seekPreviewThumbnail,
    this.seekPreviewLoading = false,
    this.seekPreviewImageSurface = false,
    this.temporarySpeedActive = false,
    this.desiredPlaying = false,
    this.playPauseOperationInFlight = false,
    this.resumeStabilizing = false,
  });

  final MediaPlaybackItem? item;
  final PlayerEngine? engine;
  final MediaServer? server;
  final StreamQuality? quality;
  final VoiceOverTrack? voiceover;
  final SubtitleTrack? subtitle;
  final List<SubtitleCue> subtitleCues;
  final bool loading;
  final bool controlsVisible;
  final bool locked;
  final PlayerError? error;
  final Duration? lastSkippedFrom;
  final bool autoNextVisible;
  final bool confirmedEnded;
  final Duration? seekPreviewPosition;
  final Duration? seekPreviewBufferedEnd;
  final SeekThumbnail? seekPreviewThumbnail;
  final bool seekPreviewLoading;
  final bool seekPreviewImageSurface;
  final bool temporarySpeedActive;
  final bool desiredPlaying;
  final bool playPauseOperationInFlight;
  final bool resumeStabilizing;

  PlaybackState copyWith({
    MediaPlaybackItem? item,
    PlayerEngine? engine,
    bool clearEngine = false,
    MediaServer? server,
    StreamQuality? quality,
    VoiceOverTrack? voiceover,
    bool clearVoiceover = false,
    SubtitleTrack? subtitle,
    bool clearSubtitle = false,
    List<SubtitleCue>? subtitleCues,
    bool? loading,
    bool? controlsVisible,
    bool? locked,
    PlayerError? error,
    bool clearError = false,
    Duration? lastSkippedFrom,
    bool clearLastSkippedFrom = false,
    bool? autoNextVisible,
    bool? confirmedEnded,
    Duration? seekPreviewPosition,
    Duration? seekPreviewBufferedEnd,
    SeekThumbnail? seekPreviewThumbnail,
    bool? seekPreviewLoading,
    bool? seekPreviewImageSurface,
    bool clearSeekPreviewPosition = false,
    bool clearSeekPreviewBufferedEnd = false,
    bool clearSeekPreviewThumbnail = false,
    bool? temporarySpeedActive,
    bool? desiredPlaying,
    bool? playPauseOperationInFlight,
    bool? resumeStabilizing,
  }) {
    return PlaybackState(
      item: item ?? this.item,
      engine: clearEngine ? null : engine ?? this.engine,
      server: server ?? this.server,
      quality: quality ?? this.quality,
      voiceover: clearVoiceover ? null : voiceover ?? this.voiceover,
      subtitle: clearSubtitle ? null : subtitle ?? this.subtitle,
      subtitleCues: subtitleCues ?? this.subtitleCues,
      loading: loading ?? this.loading,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      locked: locked ?? this.locked,
      error: clearError ? null : error ?? this.error,
      lastSkippedFrom: clearLastSkippedFrom
          ? null
          : lastSkippedFrom ?? this.lastSkippedFrom,
      autoNextVisible: autoNextVisible ?? this.autoNextVisible,
      confirmedEnded: confirmedEnded ?? this.confirmedEnded,
      seekPreviewPosition: clearSeekPreviewPosition
          ? null
          : seekPreviewPosition ?? this.seekPreviewPosition,
      seekPreviewBufferedEnd:
          clearSeekPreviewPosition || clearSeekPreviewBufferedEnd
          ? null
          : seekPreviewBufferedEnd ?? this.seekPreviewBufferedEnd,
      seekPreviewThumbnail:
          clearSeekPreviewPosition || clearSeekPreviewThumbnail
          ? null
          : seekPreviewThumbnail ?? this.seekPreviewThumbnail,
      seekPreviewLoading: clearSeekPreviewPosition || clearSeekPreviewThumbnail
          ? false
          : seekPreviewLoading ?? this.seekPreviewLoading,
      seekPreviewImageSurface: clearSeekPreviewPosition
          ? false
          : seekPreviewImageSurface ?? this.seekPreviewImageSurface,
      temporarySpeedActive: temporarySpeedActive ?? this.temporarySpeedActive,
      desiredPlaying: desiredPlaying ?? this.desiredPlaying,
      playPauseOperationInFlight:
          playPauseOperationInFlight ?? this.playPauseOperationInFlight,
      resumeStabilizing: resumeStabilizing ?? this.resumeStabilizing,
    );
  }
}

class PlaybackController extends Notifier<PlaybackState> {
  static const Duration _interactiveSeekDelay = Duration(milliseconds: 180);
  static const Duration _offlineSeekPreviewDebounce = Duration(
    milliseconds: 30,
  );
  static const Duration _onlineSeekPreviewDebounce = Duration(
    milliseconds: 100,
  );
  static const Duration _progressiveSeekPreviewYield = Duration(
    milliseconds: 40,
  );
  static const Duration _seekSettleTick = Duration(milliseconds: 80);
  static const Duration _seekSettleMinHold = Duration(milliseconds: 700);
  static const Duration _seekSettleTimeout = Duration(seconds: 12);
  static const Duration _seekSettleTolerance = Duration(milliseconds: 1200);
  static const Duration _seekSettleForwardTolerance = Duration(
    milliseconds: 2500,
  );
  static const Duration _manualSeekEofQuarantine = Duration(milliseconds: 700);
  static const Duration _engineSeekTimeout = Duration(seconds: 30);
  static const Duration _resumeSeekRetryInterval = Duration(milliseconds: 650);
  static const Duration _resumeSeekRetryTimeout = Duration(seconds: 75);
  static const Duration _resumeStabilityTick = Duration(milliseconds: 260);
  static const Duration _resumeRecoverySettleTimeout = Duration(
    milliseconds: 3200,
  );
  static const Duration _offlineStallTick = Duration(milliseconds: 500);
  static const Duration _offlineStallKickDelay = Duration(milliseconds: 90);
  static const Duration _engineOpenTimeout = Duration(seconds: 45);
  static const List<Duration> _startupSpeedReapplyDelays = <Duration>[
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];
  static const double _temporaryPlaybackSpeedBoost = 1.0;
  // Fraction of an episode that counts as "watched". Matches the common anime
  // convention where the last ~15% is the ED/credits + next-episode preview, so
  // progress is committed before the stream actually reaches the end.
  static const double _watchedFraction = 0.85;
  // Grace period between an episode finishing and the manual next-episode button
  // overlay appearing, so it eases in instead of popping up the instant the
  // stream ends. Auto-play mode advances immediately (no overlay), so this only
  // affects the button overlay.
  static const Duration _autoNextOverlayDelay = Duration(seconds: 2);

  bool get _usesSystemVolumeOnly => usesSystemVolumeOnly(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
    isAndroidTv: TvPlatform.isAndroidTv,
  );

  Timer? _progressTimer;
  Timer? _offlineStallTimer;
  Timer? _undoTimer;
  // Pending appearance of the delayed next-episode button overlay (button mode).
  Timer? _autoNextOverlayTimer;
  // Latched when the user seeks to (or plays past) the very end of a reliable
  // stream. Some backends snap the reported position back to 0:00 at
  // end-of-stream, which would otherwise hide completion from both the progress
  // saver (episode never marked watched) and the auto-next trigger.
  bool _reachedNearEnd = false;
  // Highest playback position actually observed for the current episode. Used to
  // validate a backend completion signal: real playback reaches ~the duration
  // before completing, so a "completed" report while this high-water mark is
  // still far from the end is a spurious EOF (bad/reloaded stream) and must be
  // ignored. Survives an end-of-stream snap-back to 0:00.
  Duration _maxObservedPosition = Duration.zero;
  final PlaybackDurationEvidence _durationEvidence = PlaybackDurationEvidence();
  bool _prematureEofRecoveryActive = false;
  int _prematureEofRecoveryAttempts = 0;
  Duration? _prematureEofRecoveryNeedsProgressFrom;
  // Latched once the current episode crosses the watched threshold (85%). The
  // engine listener fires on every position tick, so this guarantees the
  // watched mark + AniList sync run exactly once and can't be cleared by a
  // later periodic save.
  bool _autoProgressMarked = false;
  // Latched once the auto-next overlay has been dismissed for the current
  // episode (countdown expired, cancelled, or advanced). Without it the
  // end-of-stream evaluators would re-show the overlay on the very next tick,
  // looping the countdown endlessly. Reset when a new episode loads.
  bool _autoNextDismissed = false;
  Timer? _interactiveSeekTimer;
  Timer? _seekPreviewTimer;
  Timer? _seekSettleTimer;
  Timer? _manualSeekEofQuarantineTimer;
  int _retryCount = 0;
  int _playbackGeneration = 0;
  int _seekPreviewGeneration = 0;
  int _manualSeekEpoch = 0;
  int? _manualSeekEofEpoch;
  Duration? _manualSeekEofTarget;
  int _engineStateEventEpoch = 0;
  int? _manualSeekSettledAfterEngineEvent;
  DateTime? _manualSeekEofQuarantineUntil;
  int? _manualSeekRejectedBackendEofEpoch;
  bool _manualSeekOperationActive = false;
  String? _lastManualSeekEofLogKey;
  Duration _resumeGuardPosition = Duration.zero;
  DateTime? _resumeGuardUntil;
  PlayerEngine? _queuedSeekEngine;
  Duration? _queuedSeekTarget;
  bool _seekInFlight = false;
  Duration? _pendingSeekPreviewTarget;
  bool _seekPreviewInFlight = false;
  bool _playPauseOperationActive = false;
  bool? _pendingDesiredPlaying;
  Completer<void>? _playPauseDrainCompleter;
  int _playPauseIntentEpoch = 0;
  int _resumeStabilizeEpoch = 0;
  int _offlineStallWatchEpoch = 0;
  bool _offlineStallRecoveryActive = false;
  Duration _offlineStallObservedPosition = Duration.zero;
  DateTime? _offlineStallObservedAt;
  Duration _lastStablePausePosition = Duration.zero;
  PlayerEngine? _engineForDispose;
  Future<void>? _finalProgressSaveBarrier;
  final SeekThumbnailRequestTracker _seekThumbnailRequests =
      SeekThumbnailRequestTracker();
  final SeekThumbnailService _seekThumbnailService = SeekThumbnailService(
    extractorFactory: createSeekThumbnailExtractor,
    // A typical episode needs roughly 240 entries at five-to-six-second
    // coverage. Keep enough room for long movies without making the cache
    // unbounded for unusually long streams.
    maxCacheEntries: 2400,
    maxCacheBytes: 96 * 1024 * 1024,
  );
  SeekThumbnailPlan? _seekThumbnailPlan;
  PlayerBackend _seekThumbnailBackend = PlayerBackend.auto;
  int _progressiveSeekPreviewGeneration = 0;
  int? _progressiveSeekPreviewActiveRequest;
  String? _progressiveSeekPreviewSession;
  PlayerEngine? _settlingSeekEngine;
  Duration? _settlingSeekTarget;
  Duration? _settlingSeekFrom;
  DateTime? _settlingSeekUntil;
  DateTime? _settlingSeekEarliestClear;
  int _temporarySpeedHolds = 0;
  final Set<String> _syncedToAnilist = <String>{};

  // Cache of Russian (Shikimori) titles resolved on demand for the now-playing
  // surfaces, keyed by AniList id. Lets the media session / Discord show the
  // localized title without blocking playback while Shikimori is fetched.
  final Map<String, String> _russianTitleCache = <String, String>{};
  String? _russianTitleResolving;

  void Function()? _nextEpisodeHandler;
  void Function()? _prepareNextEpisodeHandler;

  // Watch-party sync. Guests are locked by default, but the host can grant a
  // small set of remote-control permissions. applyRemote* raises
  // [_applyingRemote] so host-driven events neither re-broadcast nor get gated.
  PlaybackSyncSink? _syncSink;
  bool _guestLocked = false;
  bool _guestCanControlPlayback = false;
  bool _guestCanSeek = false;
  bool _guestCanChangeSpeed = false;
  bool _guestCanChangeStream = false;
  bool _applyingRemote = false;
  double? _remoteTemporaryPlaybackSpeed;

  void setPlaybackSyncSink(PlaybackSyncSink? sink) {
    _syncSink = sink;
    if (sink == null) _clearRemoteTemporarySpeed();
  }

  void setGuestLocked(bool locked) {
    _guestLocked = locked;
    if (locked) {
      _autoNextOverlayTimer?.cancel();
      _autoNextOverlayTimer = null;
      if (state.autoNextVisible) {
        state = state.copyWith(autoNextVisible: false);
      }
    }
    if (!locked) {
      _guestCanControlPlayback = false;
      _guestCanSeek = false;
      _guestCanChangeSpeed = false;
      _guestCanChangeStream = false;
    }
  }

  void setCurrentItemProgressIgnored(bool ignored) {
    final MediaPlaybackItem? item = state.item;
    if (item == null || item.ignoreProgress == ignored) return;
    state = state.copyWith(item: item.withIgnoreProgress(ignored));
    final PlayerEngine? engine = state.engine;
    if (!ignored && engine != null) {
      _evaluatePlaybackProgress(engine);
    }
  }

  void setGuestPermissions({
    required bool canControlPlayback,
    required bool canSeek,
    required bool canChangeSpeed,
    required bool canChangeStream,
  }) {
    _guestCanControlPlayback = canControlPlayback;
    _guestCanSeek = canSeek;
    _guestCanChangeSpeed = canChangeSpeed;
    _guestCanChangeStream = canChangeStream;
  }

  bool get _guestControlLocked => _guestLocked && !_applyingRemote;
  bool get _suppressPlaybackControl =>
      _guestControlLocked && !_guestCanControlPlayback;
  bool get _suppressSeekControl => _guestControlLocked && !_guestCanSeek;
  bool get _suppressSpeedControl =>
      _guestControlLocked && !_guestCanChangeSpeed;
  bool get _suppressStreamControl =>
      _guestControlLocked && !_guestCanChangeStream;
  bool get _suppressGuestGlobalControl => _guestControlLocked;
  bool get allowsEpisodeNavigation => !_suppressGuestGlobalControl;

  /// Current engine position, for the host heartbeat and guest drift checks.
  Duration get currentEnginePosition => _currentPositionFor(state.engine);
  bool get isEnginePlaying =>
      state.desiredPlaying || (state.engine?.state.value.isPlaying ?? false);
  double get currentPlaybackSpeed {
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final double? remoteTemporarySpeed = _remoteTemporaryPlaybackSpeed;
    if (_temporarySpeedHolds <= 0 &&
        remoteTemporarySpeed != null &&
        state.temporarySpeedActive) {
      return remoteTemporarySpeed;
    }
    return _effectivePlaybackSpeed(settings);
  }

  void _broadcastPlayState() {
    final PlaybackSyncSink? sink = _syncSink;
    if (sink == null || _applyingRemote) return;
    final Duration pos = currentEnginePosition;
    final double speed = currentPlaybackSpeed;
    if (isEnginePlaying) {
      sink.onHostPlay(pos, speed);
    } else {
      sink.onHostPause(pos, speed);
    }
  }

  void _broadcastSeek(Duration target) {
    if (_syncSink == null || _applyingRemote) return;
    _syncSink!.onHostSeek(target, currentPlaybackSpeed, isEnginePlaying);
  }

  void _broadcastSpeed(double speed, {bool temporary = false}) {
    if (_syncSink == null || _applyingRemote) return;
    _syncSink!.onHostSpeed(
      speed,
      currentEnginePosition,
      isEnginePlaying,
      temporary: temporary,
    );
  }

  void _broadcastSourceChanged({required bool userInitiated}) {
    if (_syncSink == null || _applyingRemote) return;
    _syncSink!.onHostSourceChanged(userInitiated: userInitiated);
  }

  /// Apply a host play/pause without re-broadcasting (guest side).
  Future<void> applyRemotePlay() async {
    _applyingRemote = true;
    try {
      await _setDesiredPlaying(true);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> applyRemotePause() async {
    _applyingRemote = true;
    try {
      await _setDesiredPlaying(false);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> applyRemoteSeek(Duration position) async {
    _applyingRemote = true;
    try {
      await seekTo(position);
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> applyRemoteSpeed(double speed, {bool temporary = false}) async {
    _applyingRemote = true;
    try {
      if (temporary) {
        _remoteTemporaryPlaybackSpeed = speed;
        await state.engine?.setPlaybackSpeed(speed);
        state = state.copyWith(temporarySpeedActive: true);
        _updateMediaSession();
      } else {
        _remoteTemporaryPlaybackSpeed = null;
        await setSpeed(speed);
      }
    } finally {
      _applyingRemote = false;
    }
  }

  void _clearRemoteTemporarySpeed() {
    if (_remoteTemporaryPlaybackSpeed == null) return;
    _remoteTemporaryPlaybackSpeed = null;
    if (_temporarySpeedHolds > 0) return;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    unawaited(state.engine?.setPlaybackSpeed(settings.playbackSpeed));
    state = state.copyWith(temporarySpeedActive: false);
    _updateMediaSession();
  }

  Future<String> _localizedText(String key) async {
    try {
      final SettingsState settings = ref.read(settingsProvider);
      final Locale locale =
          settings.appLocale ?? PlatformDispatcher.instance.locale;
      return (await AppLocalizations.load(locale)).t(key);
    } on Object {
      return key;
    }
  }

  @override
  PlaybackState build() {
    MediaSessionService.init(
      onPlay: () {
        final PlayerEngine? e = state.engine;
        if (e != null && !state.desiredPlaying) {
          unawaited(_setDesiredPlaying(true));
        }
      },
      onPause: () {
        final PlayerEngine? e = state.engine;
        if (e != null && (state.desiredPlaying || e.state.value.isPlaying)) {
          unawaited(pause());
        }
      },
      onTogglePlay: () => unawaited(togglePlay()),
      onNext: () {
        if (!_suppressGuestGlobalControl) _nextEpisodeHandler?.call();
      },
      onSeekTo: (Duration pos) => unawaited(seekTo(pos)),
    );
    ref.listen<SettingsState>(settingsProvider, (previous, next) {
      _updateMediaSession();
    });
    ref.listen<AsyncValue<PlayerSettings>>(playerSettingsProvider, (
      previous,
      next,
    ) {
      _updateMediaSession();
      final PlayerSettings? previousSettings = previous?.value;
      final PlayerSettings? nextSettings = next.value;
      if (nextSettings == null) return;
      if (previousSettings?.seekPreviewsEnabled !=
          nextSettings.seekPreviewsEnabled) {
        if (nextSettings.seekPreviewsEnabled) {
          _enableSeekPreviewsForCurrentPlayback();
        } else {
          _disableSeekPreviews();
        }
        return;
      }
      final SeekPreviewMode? previousMode = previousSettings?.seekPreviewMode;
      final SeekPreviewMode nextMode = nextSettings.seekPreviewMode;
      if (previousMode != nextMode) {
        if (nextSettings.seekPreviewsEnabled &&
            nextMode == SeekPreviewMode.progressive) {
          _maybeStartProgressiveSeekPreviews();
        } else {
          _cancelProgressiveSeekPreviews(cancelActiveRequest: true);
        }
      }
    });
    ref.onDispose(() {
      _playbackGeneration++;
      _playPauseIntentEpoch++;
      _resumeStabilizeEpoch++;
      _progressTimer?.cancel();
      _stopOfflineStallWatch();
      _undoTimer?.cancel();
      _autoNextOverlayTimer?.cancel();
      _interactiveSeekTimer?.cancel();
      _seekPreviewTimer?.cancel();
      _seekSettleTimer?.cancel();
      _manualSeekEofQuarantineTimer?.cancel();
      unawaited(_ignorePlaybackTeardownErrors(DiscordRpcService.dispose()));
      unawaited(_ignorePlaybackTeardownErrors(_seekThumbnailService.dispose()));
      final PlayerEngine? engine = _engineForDispose;
      if (engine != null) {
        unawaited(_ignorePlaybackTeardownErrors(engine.dispose()));
      }
    });
    return const PlaybackState();
  }

  void setNextEpisodeHandler(void Function()? handler) {
    _nextEpisodeHandler = handler;
  }

  void setPrepareNextEpisodeHandler(void Function()? handler) {
    _prepareNextEpisodeHandler = handler;
  }

  int get playbackGeneration => _playbackGeneration;

  @visibleForTesting
  void debugSetPlaybackState(PlaybackState value) {
    _engineForDispose = value.engine;
    state = value;
  }

  @visibleForTesting
  void debugSetMaxObservedPosition(Duration value) {
    _maxObservedPosition = value;
  }

  @visibleForTesting
  void debugEvaluatePlaybackProgress(PlayerEngine engine) {
    _engineStateEventEpoch++;
    _evaluatePlaybackProgress(engine);
  }

  @visibleForTesting
  bool debugManualSeekOwnsBackendEof(PlayerEngine engine) {
    return _manualSeekOwnsBackendEof(engine);
  }

  @visibleForTesting
  Duration debugSafeResumePosition(
    MediaPlaybackItem item,
    EpisodeProgress? progress,
  ) {
    return _safeResumePosition(item, progress);
  }

  void _updateMediaSession() {
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    if (item == null || engine == null || !engine.state.value.isInitialized) {
      unawaited(MediaSessionService.clearNowPlaying());
      unawaited(
        _ignorePlaybackTeardownErrors(DiscordRpcService.clearActivity()),
      );
      return;
    }
    final PlayerEngineState es = engine.state.value;
    final bool externallyPlaying = state.desiredPlaying || es.isPlaying;
    final String sub = item.subtitle.isNotEmpty
        ? item.subtitle
        : (item.episodeNumber > 0
              ? 'Episode ${item.episodeNumber.toInt()}'
              : '');
    unawaited(
      MediaSessionService.updateNowPlaying(
        title: _nowPlayingTitle(item),
        subtitle: sub,
        artworkUrl: item.posterUrl,
        position: es.position,
        duration: es.duration,
        isPlaying: externallyPlaying,
        playbackRate: es.playbackSpeed,
        hasNext: _nextEpisodeHandler != null,
      ),
    );
    unawaited(_updateDiscordRpc(item, es, isPlaying: externallyPlaying));
  }

  Future<void> _updateDiscordRpc(
    MediaPlaybackItem item,
    PlayerEngineState engineState, {
    required bool isPlaying,
  }) async {
    final SettingsState settings = ref.read(settingsProvider);
    final PlayerSettings playerSettings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await DiscordRpcService.configure(
      appEnabled: settings.discordRpcEnabled,
      playerEnabled: playerSettings.discordRpcEnabled,
    );
    final String rpcTitle = _nowPlayingTitle(item);
    await DiscordRpcService.updatePresence(
      DiscordRpcPresence(
        title: rpcTitle,
        mediaType: item.mediaType,
        position: engineState.position,
        duration: engineState.duration,
        subtitle: item.subtitle,
        posterUrl: item.posterUrl,
        mediaUrl: _discordViewUrl(item),
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        episodeCount: item.episodeCount,
        isPlaying: isPlaying,
      ),
    );
  }

  /// The series/movie title shown on the now-playing surfaces (Control Center,
  /// Android/Windows media session, Discord). Always the AniList/TMDB metadata
  /// title. The addon's source title is never used.
  ///
  /// AniList anime follow the AniList title-language setting
  /// (ROMAJI/ENGLISH/NATIVE/RUSSIAN) using the per-language titles carried in
  /// externalIds (`anilist_title_{romaji,english,native}`); RUSSIAN comes from
  /// Shikimori, fetched lazily and cached (see [_maybeResolveRussianTitle]).
  /// TMDB items already store [mirushin_metadata_title] localized to the chosen
  /// metadata language, so it is used directly.
  String _nowPlayingTitle(MediaPlaybackItem item) {
    final Map<String, String> ids = item.externalIds;
    final String english = (ids['anilist_title_english'] ?? '').trim();
    final String romaji = (ids['anilist_title_romaji'] ?? '').trim();
    final String native = (ids['anilist_title_native'] ?? '').trim();
    final String meta = (ids['mirushin_metadata_title'] ?? '').trim();
    final String original =
        (ids['mirushin_metadata_original_title'] ?? '').trim().isNotEmpty
        ? (ids['mirushin_metadata_original_title'] ?? '').trim()
        : item.originalTitle.trim();

    final bool isAnime =
        english.isNotEmpty || romaji.isNotEmpty || native.isNotEmpty;

    String chosen;
    if (isAnime) {
      // AniList content uses its own title-language preference, not the TMDB
      // metadata locale. AniList has no Russian, so it comes from Shikimori.
      final String titleLanguage = ref.read(
        aniListEffectiveTitleLanguageProvider,
      );
      chosen = switch (titleLanguage) {
        'ROMAJI' => romaji,
        'NATIVE' => native,
        'RUSSIAN' => _russianTitleFor(item),
        _ => english,
      };
    } else {
      // TMDB's metadata title is already localized to the chosen language
      // (with TMDB's own fallback baked in).
      chosen = meta;
    }

    // `meta` is the app's own already-localized display title (for AniList it
    // honours the title-language setting, including the Russian injection), so
    // it must rank above the raw per-language candidates.
    for (final String candidate in <String>[
      chosen,
      meta,
      english,
      romaji,
      native,
      original,
    ]) {
      if (candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    // Use the addon source title only as a last resort.
    return item.title;
  }

  /// Returns the cached Russian title for [item] and, if not yet available,
  /// kicks off a best-effort Shikimori lookup that refreshes the now-playing
  /// surfaces once it resolves. Returns '' until then so the fallback chain runs.
  String _russianTitleFor(MediaPlaybackItem item) {
    final String anilistId = (item.externalIds['anilist'] ?? '').trim();
    if (anilistId.isEmpty) return '';
    final String? cached = _russianTitleCache[anilistId];
    if (cached != null) return cached;
    unawaited(_maybeResolveRussianTitle(item, anilistId));
    return '';
  }

  Future<void> _maybeResolveRussianTitle(
    MediaPlaybackItem item,
    String anilistId,
  ) async {
    if (_russianTitleCache.containsKey(anilistId)) return;
    if (_russianTitleResolving == anilistId) return;
    _russianTitleResolving = anilistId;
    try {
      final AnimeTitles titles = await AnimeTitlesService.resolve(
        anilistId: anilistId,
        malId: (item.externalIds['mal'] ?? '').trim().isEmpty
            ? null
            : item.externalIds['mal'],
        titleCandidates: <String>[
          item.externalIds['anilist_title_romaji'] ?? '',
          item.externalIds['anilist_title_english'] ?? '',
          item.title,
        ].where((String s) => s.trim().isNotEmpty),
      );
      _russianTitleCache[anilistId] = titles.russian.trim();
    } on Object {
      // Best-effort: cache empty so we don't retry the same id every tick.
      _russianTitleCache[anilistId] = '';
    } finally {
      _russianTitleResolving = null;
    }
    // Refresh the surfaces now that the localized title (or its absence) is known.
    if (state.item?.externalIds['anilist'] == anilistId) {
      _updateMediaSession();
    }
  }

  String _discordViewUrl(MediaPlaybackItem item) {
    final MiruShinMediaDeepLink? link = mirushinMediaLink(
      internalId: item.id,
      mediaType: item.mediaType,
      externalIds: item.externalIds,
    );
    return link?.shareUri.toString() ?? '';
  }

  Future<void> load(MediaPlaybackItem item) async {
    debugPrint(
      '[DEBUG] load: S${item.seasonNumber}E${item.episodeNumber} ignoreProgress=${item.ignoreProgress}',
    );
    await _waitForFinalProgressSaveBarrier();
    // Invalidate listeners and EOF recovery immediately when a new item starts
    // loading. Resolution/progress lookup can await before _open creates the
    // replacement engine, so waiting until _open would leave a stale recovery
    // free to mutate the outgoing session during that gap.
    _playbackGeneration++;
    _stopOfflineStallWatch();
    _progressTimer?.cancel();
    _undoTimer?.cancel();
    _autoNextOverlayTimer?.cancel();
    _reachedNearEnd = false;
    _maxObservedPosition = Duration.zero;
    _durationEvidence.reset();
    _prematureEofRecoveryActive = false;
    _prematureEofRecoveryAttempts = 0;
    _prematureEofRecoveryNeedsProgressFrom = null;
    _resetManualSeekEofWindow();
    _autoProgressMarked = false;
    _autoNextDismissed = false;
    _playPauseIntentEpoch++;
    _resumeStabilizeEpoch++;
    _pendingDesiredPlaying = null;
    _lastStablePausePosition = Duration.zero;
    _clearInteractiveSeek();
    if (state.autoNextVisible ||
        state.confirmedEnded ||
        state.lastSkippedFrom != null ||
        state.seekPreviewPosition != null ||
        state.seekPreviewThumbnail != null) {
      state = state.copyWith(
        autoNextVisible: false,
        confirmedEnded: false,
        clearLastSkippedFrom: true,
        clearSeekPreviewPosition: true,
        clearSeekPreviewThumbnail: true,
        desiredPlaying: false,
        playPauseOperationInFlight: false,
        resumeStabilizing: false,
      );
    }
    if (item.servers.isEmpty) {
      _engineForDispose = null;
      state = PlaybackState(
        item: item,
        error: const PlayerError(
          title: 'No stream',
          message: 'No playable server was provided.',
        ),
      );
      return;
    }
    final MediaServer server = item.servers.first;
    final StreamQuality quality = _initialQuality(
      server,
      explicitId: item.initialQualityId,
    );
    final VoiceOverTrack? voiceover = _voiceoverById(
      server.voiceovers,
      item.initialVoiceoverId,
    );
    final EpisodeProgress? prog =
        item.ignoreProgress ||
            item.startPolicy == PlaybackStartPolicy.forceBeginning
        ? null
        : await _loadProgressForItem(item);
    final Duration startPos = _safeResumePosition(item, prog);
    await _open(
      item: item,
      server: server,
      quality: quality,
      position: startPos,
      autoplay: true,
      voiceover: voiceover,
      clearVoiceover: voiceover == null,
    );
    // A host load is a global source/episode change. Guest loads caused by
    // synchronization are marked non-user-initiated and ignored by the party
    // controller, so they cannot loop back as stream-change requests.
    _broadcastSourceChanged(userInitiated: false);
  }

  Future<void> _waitForFinalProgressSaveBarrier() async {
    final Future<void>? pending = _finalProgressSaveBarrier;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // The barrier is best-effort; failed persistence should not block opening.
    }
  }

  Future<EpisodeProgress?> _loadProgressForItem(MediaPlaybackItem item) async {
    EpisodeProgress? best;

    final List<String> ids = _progressMediaIds(item);
    debugPrint(
      '[DEBUG] _loadProgressForItem: ids=$ids S${item.seasonNumber}E${item.episodeNumber}',
    );

    for (final String mediaId in ids) {
      final EpisodeProgress? progress = await ref
          .read(localLibraryProvider.notifier)
          .loadEpisodeProgress(mediaId, item.seasonNumber, item.episodeNumber);

      debugPrint(
        '[DEBUG]   mediaId=$mediaId => ${progress == null ? 'null' : 'pos=${progress.positionSeconds}s completed=${progress.completed}'}',
      );

      if (progress == null ||
          (progress.positionSeconds <= 0 && !progress.completed)) {
        continue;
      }

      if (best == null || progress.updatedAt.isAfter(best.updatedAt)) {
        best = progress;
      }
    }

    debugPrint(
      '[DEBUG] _loadProgressForItem: best=${best == null ? 'null' : 'pos=${best.positionSeconds}s'}',
    );
    return best;
  }

  Duration _safeResumePosition(
    MediaPlaybackItem item,
    EpisodeProgress? progress,
  ) {
    switch (item.startPolicy) {
      case PlaybackStartPolicy.forceBeginning:
        debugPrint('[DEBUG] _safeResumePosition: forceBeginning -> 0');
        return Duration.zero;
      case PlaybackStartPolicy.explicitPosition:
        debugPrint(
          '[DEBUG] _safeResumePosition: explicitPosition '
          '-> ${item.startPosition}',
        );
        return item.startPosition;
      case PlaybackStartPolicy.resumeSaved:
        break;
    }
    final int savedSeconds = progress?.positionSeconds ?? 0;
    // A finished episode is reset to 0:00 on save, so it restarts fresh. But an
    // episode marked watched early at 85% keeps its real position. Reopen in the
    // final stretch instead of jumping back to the beginning.
    if (progress?.completed == true && savedSeconds <= 0) {
      debugPrint('[DEBUG] _safeResumePosition: completed=true -> 0');
      return Duration.zero;
    }
    final Duration saved = savedSeconds > 0
        ? Duration(seconds: savedSeconds)
        : Duration.zero;
    final Duration start = saved > item.startPosition
        ? saved
        : item.startPosition;

    debugPrint(
      '[DEBUG] _safeResumePosition: savedSeconds=$savedSeconds item.startPosition=${item.startPosition} -> start=$start',
    );

    return start;
  }

  // Keys that are actual unique identifiers (not metadata like type or URLs).
  static const Set<String> _identifierKeys = <String>{
    'anilist',
    'mal',
    'tmdb',
    'imdb',
    'kitsu',
    'anidb',
  };

  List<String> _progressMediaIds(MediaPlaybackItem item) {
    final LinkedHashSet<String> ids = LinkedHashSet<String>();

    void add(String value) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        ids.add(trimmed);
      }
    }

    final String? soraMediaId = soraEpisodeProgressMediaId(
      addonId: item.externalIds['sora_addon_id'] ?? '',
      episodeHref: item.externalIds['sora_episode_href'] ?? '',
    );
    if (soraMediaId != null) {
      add(soraMediaId);
      return ids.toList(growable: false);
    }

    add(item.id);

    item.externalIds.forEach((String key, String value) {
      final String cleanKey = key.trim().toLowerCase();
      final String cleanValue = value.trim();
      if (_identifierKeys.contains(cleanKey) && cleanValue.isNotEmpty) {
        add('external:$cleanKey:$cleanValue');
      }
    });

    final String titleKey = item.originalTitle.isNotEmpty
        ? item.originalTitle
        : item.title;
    add('title:$titleKey|season:${item.seasonNumber}');

    return ids.toList(growable: false);
  }

  Future<void> _open({
    required MediaPlaybackItem item,
    required MediaServer server,
    required StreamQuality quality,
    required Duration position,
    required bool autoplay,
    VoiceOverTrack? voiceover,
    bool clearVoiceover = false,
    SubtitleTrack? subtitle,
    double? preserveAspectRatio,
    PlayerBackend? backendOverride,
    List<PlaybackAttempt>? attemptPlan,
    int attemptIndex = 0,
    List<String> attemptFailures = const <String>[],
    bool respectDesiredPlaying = false,
  }) async {
    _stopOfflineStallWatch();
    _playPauseIntentEpoch++;
    _resumeStabilizeEpoch++;
    _progressTimer?.cancel();
    _undoTimer?.cancel();
    _autoNextOverlayTimer?.cancel();
    _reachedNearEnd = false;
    _durationEvidence.reset();
    _prematureEofRecoveryActive = false;
    _prematureEofRecoveryAttempts = 0;
    _prematureEofRecoveryNeedsProgressFrom = null;
    _resetManualSeekEofWindow();
    final int generation = ++_playbackGeneration;
    _clearInteractiveSeek();
    _cancelSeekThumbnailRequests();
    _resumeGuardPosition = position;
    _resumeGuardUntil = position > const Duration(seconds: 3)
        ? DateTime.now().add(_resumeSeekRetryTimeout)
        : null;
    final PlayerEngine? previous = state.engine;
    if (identical(_engineForDispose, previous)) {
      _engineForDispose = null;
    }
    state = state.copyWith(
      item: item,
      clearEngine: true,
      server: server,
      quality: quality,
      voiceover: voiceover,
      clearVoiceover: clearVoiceover,
      subtitle: subtitle,
      clearSubtitle: subtitle == null,
      subtitleCues: subtitle == null ? const <SubtitleCue>[] : null,
      loading: true,
      controlsVisible: true,
      autoNextVisible: false,
      confirmedEnded: false,
      clearError: true,
      clearLastSkippedFrom: true,
      clearSeekPreviewPosition: true,
      clearSeekPreviewThumbnail: true,
      temporarySpeedActive: false,
      desiredPlaying: autoplay,
      playPauseOperationInFlight: false,
      resumeStabilizing: false,
    );
    // Never keep two native video outputs alive during a source/backend swap.
    // Both MediaKit and FVP own native textures whose asynchronous teardown can
    // otherwise overlap the next backend and terminate the process.
    if (previous != null) {
      await _ignorePlaybackTeardownErrors(previous.dispose());
      if (generation != _playbackGeneration) return;
    }
    if (subtitle == null) unawaited(_autoSelectSubtitle(server));

    final String url = quality.isAuto || quality.url.isEmpty
        ? server.url
        : quality.url;
    final StreamType streamType = _streamTypeForUrl(url, server.streamType);
    // Await the persisted settings rather than reading `.value`, which is null
    // on the first playback after launch while the async provider is still
    // loading. Reading `.value` there fell back to the defaults, so a saved
    // speed (e.g. 2x) was shown in the UI but the engine opened at 1x until the
    // user re-selected it. Awaiting guarantees the saved speed/volume/backend.
    final PlayerSettings settings = await ref.read(
      playerSettingsProvider.future,
    );
    final bool youtubeEmbed = _isYoutubeTrailerServer(server);
    final List<PlaybackAttempt> attempts = youtubeEmbed
        ? const <PlaybackAttempt>[]
        : attemptPlan ??
              _buildPlaybackAttemptPlan(
                preference: backendOverride ?? settings.playerBackend,
                url: url,
                streamType: streamType,
              );
    if (!youtubeEmbed &&
        (attempts.isEmpty ||
            attemptIndex < 0 ||
            attemptIndex >= attempts.length)) {
      state = state.copyWith(
        loading: false,
        error: const PlayerError(
          title: 'Stream failed',
          message: 'No compatible playback backend is available.',
        ),
      );
      return;
    }
    final PlaybackAttempt? attempt = youtubeEmbed
        ? null
        : attempts[attemptIndex];
    final PlayerBackend backend = attempt?.backend ?? PlayerBackend.auto;
    final PlayerBackend engineBackend = resolvePlayerEngineBackend(backend);
    final bool disableProxy = attempt?.disableProxy ?? false;
    final SeekThumbnailPlan thumbnailPlan = buildSeekThumbnailPlan(
      item: item,
      server: server,
      activeQuality: quality,
      preferDirectNetwork: disableProxy,
    );
    final PlayerBackend thumbnailBackend = seekThumbnailExtractionBackend(
      engineBackend,
    );
    if (settings.seekPreviewsEnabled) {
      await _seekThumbnailService.activate(thumbnailPlan, thumbnailBackend);
    }
    if (generation != _playbackGeneration) return;
    _seekThumbnailPlan = thumbnailPlan;
    _seekThumbnailBackend = thumbnailBackend;
    if (attempt != null) {
      debugPrint(
        'Playback attempt ${attemptIndex + 1}/${attempts.length}: '
        '${attempt.label} for ${server.name}.',
      );
    }
    final String trailerBackLabel = youtubeEmbed
        ? await _localizedText('Back')
        : 'Back';
    final PlayerEngine engine = createPlayerEngine(
      initialAspectRatio: _safeAspectRatio(preserveAspectRatio),
      backend: engineBackend,
      youtubeEmbed: youtubeEmbed,
      trailerBackLabel: trailerBackLabel,
    );

    try {
      await engine
          .open(
            PlayerSource(
              url: url,
              headers: quality.headers.isNotEmpty
                  ? quality.headers
                  : server.headers,
              streamType: streamType,
              disableProxy: disableProxy,
              allowDirectFallback: youtubeEmbed,
            ),
            startAt: position,
            autoplay: false,
          )
          .timeout(_engineOpenTimeout);
      if (generation != _playbackGeneration) {
        await engine.dispose();
        return;
      }
      final double targetPlaybackSpeed = _effectivePlaybackSpeed(settings);
      await engine.setPlaybackSpeed(targetPlaybackSpeed);
      await engine.setVolume(
        effectivePlayerOutputVolume(
          configuredVolume: settings.volume,
          systemVolumeOnly: _usesSystemVolumeOnly,
        ),
      );
      final bool effectiveAutoplay =
          autoplay && (!respectDesiredPlaying || state.desiredPlaying);
      if (effectiveAutoplay) await engine.play();
      if (generation != _playbackGeneration) {
        await engine.pause();
        await engine.dispose();
        return;
      }
      _engineForDispose = engine;
      state = state.copyWith(
        engine: engine,
        loading: false,
        clearError: true,
        desiredPlaying: effectiveAutoplay,
        playPauseOperationInFlight: false,
        resumeStabilizing: false,
      );
      _retryCount = 0;
      _updateMediaSession();
      _startProgressSaver();
      _watchPlaybackProgress(engine, generation);
      _reinforcePlaybackSpeed(engine, generation);
      if (!engine.managesInitialPosition) {
        _reinforceInitialSeek(engine, position, generation, _manualSeekEpoch);
      }
      _watchEngineErrors(
        engine,
        generation,
        attempts,
        attemptIndex,
        attemptFailures,
      );
      _startOfflineStallWatch(item, server, engine, generation);
      if (_seekPreviewsEnabled()) {
        unawaited(
          _warmSeekThumbnailIndex(thumbnailPlan, thumbnailBackend, generation),
        );
      }
    } on Object catch (error) {
      final Duration fallbackPosition = _fallbackPositionFor(
        engine,
        requestedPosition: position,
      );
      final bool fallbackAutoplay =
          (autoplay && (!respectDesiredPlaying || state.desiredPlaying)) ||
          engine.state.value.isPlaying;
      final double? fallbackAspectRatio = _safeAspectRatio(
        engine.state.value.aspectRatio,
      );
      await engine.dispose();
      if (generation != _playbackGeneration) return;
      if (youtubeEmbed) {
        debugPrint('YouTube trailer WebView open failed: $error');
        state = state.copyWith(
          clearEngine: true,
          loading: false,
          error: PlayerError(
            title: 'Trailer failed',
            message: error.toString(),
            canRetry: true,
          ),
        );
        return;
      }
      final List<String> failures = _appendPlaybackFailure(
        attemptFailures,
        attempts[attemptIndex],
        error,
      );
      if (_tryNextPlaybackAttempt(
        attempts: attempts,
        failedAttemptIndex: attemptIndex,
        failures: failures,
        position: fallbackPosition,
        autoplay: fallbackAutoplay,
        preserveAspectRatio: fallbackAspectRatio ?? preserveAspectRatio,
      )) {
        return;
      }
      state = state.copyWith(
        clearEngine: true,
        loading: false,
        error: PlayerError(
          title: 'Stream failed',
          message: _playbackFailureMessage(failures),
        ),
      );
      _engineForDispose = null;
    }
  }

  Future<void> _warmSeekThumbnailIndex(
    SeekThumbnailPlan plan,
    PlayerBackend backend,
    int generation,
  ) async {
    if (!_seekPreviewsEnabled()) return;
    // Local downloads can be indexed immediately. Online warmup yields to the
    // main player so its initial manifest/segment requests are never competing
    // with preview traffic during startup.
    if (!plan.isOffline) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    if (generation != _playbackGeneration ||
        _seekThumbnailPlan?.sessionKey != plan.sessionKey ||
        state.engine == null ||
        !state.engine!.state.value.isInitialized ||
        !_seekPreviewsEnabled()) {
      return;
    }
    await _seekThumbnailService.warm(plan, backend);
    if (generation == _playbackGeneration && _seekPreviewsEnabled()) {
      _maybeStartProgressiveSeekPreviews();
    }
  }

  bool _seekPreviewsEnabled({PlayerSettings? settings}) {
    return (settings ??
            ref.read(playerSettingsProvider).value ??
            const PlayerSettings())
        .seekPreviewsEnabled;
  }

  void _enableSeekPreviewsForCurrentPlayback() {
    final SeekThumbnailPlan? plan = _seekThumbnailPlan;
    final PlayerEngine? engine = state.engine;
    if (plan == null ||
        engine == null ||
        !engine.state.value.isInitialized ||
        !_seekPreviewsEnabled()) {
      return;
    }
    unawaited(
      _warmSeekThumbnailIndex(plan, _seekThumbnailBackend, _playbackGeneration),
    );
  }

  void _disableSeekPreviews() {
    _cancelSeekThumbnailRequests();
    if (state.seekPreviewThumbnail != null ||
        state.seekPreviewLoading ||
        state.seekPreviewImageSurface) {
      state = state.copyWith(
        clearSeekPreviewThumbnail: true,
        seekPreviewImageSurface: false,
      );
    }
  }

  void _maybeStartProgressiveSeekPreviews() {
    final PlayerEngine? engine = state.engine;
    final SeekThumbnailPlan? plan = _seekThumbnailPlan;
    if (!seekThumbnailExtractionSupported ||
        engine == null ||
        !engine.state.value.isInitialized ||
        plan == null) {
      return;
    }
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if (!_progressiveSeekPreviewsEnabled(plan, settings: settings)) {
      _cancelProgressiveSeekPreviews(cancelActiveRequest: true);
      return;
    }
    final Duration duration = engine.state.value.duration;
    if (duration <= Duration.zero) return;

    final String session = '${plan.sessionKey}|${duration.inMilliseconds}';
    if (_progressiveSeekPreviewSession == session) return;
    _cancelProgressiveSeekPreviews(cancelActiveRequest: true);
    _progressiveSeekPreviewSession = session;
    final int generation = ++_progressiveSeekPreviewGeneration;
    unawaited(
      _refineSeekPreviewsAcrossTimeline(
        engine: engine,
        plan: plan,
        duration: duration,
        generation: generation,
      ),
    );
  }

  Future<void> _refineSeekPreviewsAcrossTimeline({
    required PlayerEngine engine,
    required SeekThumbnailPlan plan,
    required Duration duration,
    required int generation,
  }) async {
    for (final Duration target in progressiveSeekThumbnailPositions(duration)) {
      if (!_isProgressiveSeekPreviewCurrent(generation, engine, plan)) return;
      if (_seekThumbnailService.cachedFor(plan, target, duration: duration) !=
          null) {
        continue;
      }
      _progressiveSeekPreviewActiveRequest = generation;
      SeekThumbnail? thumbnail;
      try {
        thumbnail = await _seekThumbnailService.request(
          plan: plan,
          backend: _seekThumbnailBackend,
          position: target,
          duration: duration,
        );
      } on Object {
        // Background refinement is opportunistic. An interactive request can
        // retry the same bucket and remains independent from playback.
      } finally {
        if (_progressiveSeekPreviewActiveRequest == generation) {
          _progressiveSeekPreviewActiveRequest = null;
        }
      }
      if (!_isProgressiveSeekPreviewCurrent(generation, engine, plan)) return;
      if (thumbnail != null) {
        _refreshVisibleProgressiveSeekPreview(plan, duration);
      }
      await Future<void>.delayed(_progressiveSeekPreviewYield);
    }
  }

  bool _isProgressiveSeekPreviewCurrent(
    int generation,
    PlayerEngine engine,
    SeekThumbnailPlan plan,
  ) {
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    return generation == _progressiveSeekPreviewGeneration &&
        identical(state.engine, engine) &&
        _seekThumbnailPlan?.sessionKey == plan.sessionKey &&
        _progressiveSeekPreviewsEnabled(plan, settings: settings);
  }

  bool _progressiveSeekPreviewsEnabled(
    SeekThumbnailPlan plan, {
    PlayerSettings? settings,
  }) {
    final PlayerSettings effectiveSettings =
        settings ??
        ref.read(playerSettingsProvider).value ??
        const PlayerSettings();
    return shouldProgressivelyGenerateSeekThumbnails(
      enabled: effectiveSettings.seekPreviewsEnabled,
      mode: effectiveSettings.seekPreviewMode,
      plan: plan,
    );
  }

  void _refreshVisibleProgressiveSeekPreview(
    SeekThumbnailPlan plan,
    Duration duration,
  ) {
    final Duration? visiblePosition = state.seekPreviewPosition;
    if (visiblePosition == null || !_progressiveSeekPreviewsEnabled(plan)) {
      return;
    }
    final SeekThumbnail? nearest = _seekThumbnailService.nearestCachedFor(
      plan,
      visiblePosition,
      duration: duration,
      maxDistance: duration,
      preferLaterOnTie: true,
    );
    if (nearest == null) return;
    state = state.copyWith(
      seekPreviewThumbnail: nearest,
      seekPreviewLoading: false,
      seekPreviewImageSurface: true,
    );
  }

  void _cancelProgressiveSeekPreviews({required bool cancelActiveRequest}) {
    _progressiveSeekPreviewGeneration++;
    _progressiveSeekPreviewSession = null;
    if (cancelActiveRequest && _progressiveSeekPreviewActiveRequest != null) {
      _seekThumbnailService.cancelPending();
    }
  }

  double? _safeAspectRatio(double? value) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    // Keep only realistic video aspect ratios. This is mainly used during
    // quality switching so a low-quality variant with bad metadata does not
    // squeeze a normal 16:9 stream into a narrower frame.
    if (value < 1.2 || value > 2.4) return null;
    return value;
  }

  bool _isYoutubeTrailerServer(MediaServer server) {
    return server.id == 'youtube-trailer';
  }

  void _reinforceInitialSeek(
    PlayerEngine engine,
    Duration position,
    int generation,
    int manualSeekEpoch,
  ) {
    if (position <= const Duration(seconds: 3)) return;
    unawaited(
      _reinforceInitialSeekUntilAccepted(
        engine,
        position,
        generation,
        manualSeekEpoch,
      ),
    );
  }

  Future<void> _reinforceInitialSeekUntilAccepted(
    PlayerEngine engine,
    Duration position,
    int generation,
    int manualSeekEpoch,
  ) async {
    final DateTime deadline = DateTime.now().add(_resumeSeekRetryTimeout);
    bool attemptedSeek = false;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_resumeSeekRetryInterval);
      if (generation != _playbackGeneration ||
          manualSeekEpoch != _manualSeekEpoch ||
          state.engine != engine) {
        return;
      }

      if (_initialSeekAccepted(engine, position)) {
        _clearResumeGuard();
        return;
      }

      final PlayerEngineState value = engine.state.value;
      if (!value.isInitialized) continue;
      // One seek has already selected the target fragment. Reissuing the same
      // request while that fragment is buffering causes native seek/download
      // storms on long-segment DASH-to-HLS streams.
      if (attemptedSeek && value.isBuffering) continue;

      try {
        await _seekEngineTo(engine, position, reason: 'Resume seek');
        attemptedSeek = true;
      } on Object {
        // Some native backends reject an early startup seek. Later loop ticks
        // can retry if the stream is still behind the saved resume point.
      }
      state = state.copyWith();
    }

    if (state.engine == engine &&
        generation == _playbackGeneration &&
        manualSeekEpoch == _manualSeekEpoch &&
        !_initialSeekAccepted(engine, position) &&
        kDebugMode) {
      debugPrint(
        'Resume seek was not accepted after '
        '${_resumeSeekRetryTimeout.inSeconds}s '
        '(target=${position.inSeconds}s, '
        'position=${engine.state.value.position.inSeconds}s, '
        'attempted=$attemptedSeek).',
      );
    }
  }

  bool _initialSeekAccepted(PlayerEngine engine, Duration position) {
    final PlayerEngineState value = engine.state.value;
    if (!value.isInitialized) return false;
    return value.position + const Duration(seconds: 3) >= position;
  }

  void _clearResumeGuard() {
    _resumeGuardPosition = Duration.zero;
    _resumeGuardUntil = null;
  }

  void _reinforcePlaybackSpeed(PlayerEngine engine, int generation) {
    unawaited(_reinforcePlaybackSpeedAfterStartup(engine, generation));
  }

  Future<void> _reinforcePlaybackSpeedAfterStartup(
    PlayerEngine engine,
    int generation,
  ) async {
    for (final Duration delay in _startupSpeedReapplyDelays) {
      await Future<void>.delayed(delay);
      if (generation != _playbackGeneration || state.engine != engine) {
        return;
      }

      final double speed = engine.state.value.playbackSpeed
          .clamp(0.25, 3.0)
          .toDouble();
      if (speed == 1.0) continue;

      try {
        await engine.setPlaybackSpeed(speed);
      } on Object {
        return;
      }
      state = state.copyWith();
      _updateMediaSession();
    }
  }

  Duration _fallbackPositionFor(
    PlayerEngine? engine, {
    Duration requestedPosition = Duration.zero,
  }) {
    Duration position = _currentPositionFor(engine);
    if (position <= const Duration(seconds: 3) &&
        requestedPosition > position) {
      position = requestedPosition;
    }

    final DateTime? guardUntil = _resumeGuardUntil;
    if (guardUntil != null &&
        DateTime.now().isBefore(guardUntil) &&
        _resumeGuardPosition > position) {
      return _resumeGuardPosition;
    }

    return position;
  }

  List<PlaybackAttempt> _buildPlaybackAttemptPlan({
    required PlayerBackend preference,
    required String url,
    required StreamType streamType,
  }) {
    final Uri? uri = Uri.tryParse(url);
    final String scheme = uri?.scheme.toLowerCase() ?? '';
    final bool inlineDash = LocalHlsProxy.isInlineDashUrl(url);
    final bool network = scheme == 'http' || scheme == 'https';
    final bool localSegmentedMedia =
        scheme == 'file' && url.toLowerCase().contains('.m3u8');
    // Local media has no remote headers, TLS, or CDN requests for the proxy to
    // repair. Direct file access also avoids pauses at segment boundaries.
    final bool proxyEligible =
        !usesBrowserPlayerEngine && (network || inlineDash);
    final bool directEligible = !inlineDash;

    return buildPlaybackAttemptPlan(
      preference: preference,
      // Some stored segmented media retain non-zero or discontinuous source
      // timestamps. libmpv can then expose only the first segment as the
      // duration and reject every seek outside it. FVP resolves the rewritten
      // local playlist as a complete timeline, so use it for all stored HLS.
      // Network streams keep the normal MPV -> FVP attempt order.
      mpvAvailable:
          !localSegmentedMedia &&
          isPlayerEngineBackendAvailable(
            PlayerBackend.mpv,
            streamType: streamType,
          ),
      fvpAvailable: isPlayerEngineBackendAvailable(
        PlayerBackend.fvp,
        streamType: streamType,
      ),
      proxyEligible: proxyEligible,
      // An inline DASH value contains the manifest itself, not a directly
      // playable URL, so only its local-proxy route is valid.
      directEligible: directEligible,
      mpvProxyEligible:
          proxyEligible &&
          isPlayerEngineRouteAvailable(
            PlayerBackend.mpv,
            PlaybackRoute.localProxy,
            streamType: streamType,
            dashUsesHlsContainer: localSegmentedMedia,
          ),
      mpvDirectEligible:
          directEligible &&
          isPlayerEngineRouteAvailable(
            PlayerBackend.mpv,
            PlaybackRoute.direct,
            streamType: streamType,
            dashUsesHlsContainer: localSegmentedMedia,
          ),
      fvpProxyEligible:
          proxyEligible &&
          isPlayerEngineRouteAvailable(
            PlayerBackend.fvp,
            PlaybackRoute.localProxy,
            streamType: streamType,
            dashUsesHlsContainer: localSegmentedMedia,
          ),
      fvpDirectEligible:
          directEligible &&
          isPlayerEngineRouteAvailable(
            PlayerBackend.fvp,
            PlaybackRoute.direct,
            streamType: streamType,
            dashUsesHlsContainer: localSegmentedMedia,
          ),
      usesBrowserBackend: usesBrowserPlayerEngine,
    );
  }

  bool _tryNextPlaybackAttempt({
    required List<PlaybackAttempt> attempts,
    required int failedAttemptIndex,
    required List<String> failures,
    required Duration position,
    required bool autoplay,
    double? preserveAspectRatio,
  }) {
    final int nextIndex = failedAttemptIndex + 1;
    if (nextIndex >= attempts.length) return false;

    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? quality = state.quality;
    if (item == null || server == null || quality == null) return false;

    debugPrint(
      'Playback fallback: ${attempts[failedAttemptIndex].label} failed; '
      'trying ${attempts[nextIndex].label} for ${server.name}.',
    );
    unawaited(
      _open(
        item: item,
        server: server,
        quality: quality,
        position: position,
        autoplay: autoplay,
        voiceover: state.voiceover,
        subtitle: state.subtitle,
        preserveAspectRatio: preserveAspectRatio,
        attemptPlan: attempts,
        attemptIndex: nextIndex,
        attemptFailures: failures,
      ),
    );
    return true;
  }

  List<String> _appendPlaybackFailure(
    List<String> failures,
    PlaybackAttempt attempt,
    Object error,
  ) {
    String description = error
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (description.length > 320) {
      description = '${description.substring(0, 317)}...';
    }
    final String failure = '${attempt.label}: $description';
    debugPrint('Playback attempt failed: $failure');
    return <String>[...failures, failure];
  }

  String _playbackFailureMessage(List<String> failures) {
    if (failures.isEmpty) return 'All compatible playback attempts failed.';
    return 'All compatible playback attempts failed.\n${failures.join('\n')}';
  }

  void _watchEngineErrors(
    PlayerEngine engine,
    int generation,
    List<PlaybackAttempt> attempts,
    int attemptIndex,
    List<String> attemptFailures,
  ) {
    late void Function() listener;
    listener = () {
      if (generation != _playbackGeneration ||
          !identical(state.engine, engine)) {
        engine.removeListener(listener);
        return;
      }
      if (engine.state.value.hasError && state.error == null) {
        engine.removeListener(listener);
        final String? errorDescription = engine.state.value.errorDescription;
        if (attempts.isEmpty) {
          state = state.copyWith(
            error: PlayerError(
              title: 'Trailer failed',
              message: errorDescription ?? 'The trailer failed to load.',
              canRetry: true,
            ),
          );
          return;
        }

        final List<String> failures = _appendPlaybackFailure(
          attemptFailures,
          attempts[attemptIndex],
          errorDescription ?? 'The stream failed to load.',
        );
        if (_tryNextPlaybackAttempt(
          attempts: attempts,
          failedAttemptIndex: attemptIndex,
          failures: failures,
          position: _fallbackPositionFor(engine),
          autoplay: state.desiredPlaying || engine.state.value.isPlaying,
          preserveAspectRatio: engine.state.value.aspectRatio,
        )) {
          return;
        }

        _playbackGeneration++;
        if (identical(_engineForDispose, engine)) {
          _engineForDispose = null;
        }
        state = state.copyWith(
          clearEngine: true,
          loading: false,
          error: PlayerError(
            title: 'Playback error',
            message: _playbackFailureMessage(failures),
            canRetry: true,
          ),
        );
        unawaited(_ignorePlaybackTeardownErrors(engine.dispose()));
      }
    };
    engine.addListener(listener);
  }

  bool _isOfflineLocalServer(MediaServer server) {
    if (server.id != 'offline') return false;
    return Uri.tryParse(server.url)?.scheme.toLowerCase() == 'file';
  }

  void _startOfflineStallWatch(
    MediaPlaybackItem item,
    MediaServer server,
    PlayerEngine engine,
    int generation,
  ) {
    _stopOfflineStallWatch();
    if (!_isOfflineLocalServer(server)) return;

    final int watchEpoch = _offlineStallWatchEpoch;
    _offlineStallObservedPosition = engine.state.value.position;
    _offlineStallObservedAt = DateTime.now();
    _offlineStallTimer = Timer.periodic(_offlineStallTick, (_) {
      if (watchEpoch != _offlineStallWatchEpoch ||
          generation != _playbackGeneration ||
          state.engine != engine ||
          state.item != item ||
          state.server != server) {
        _stopOfflineStallWatch();
        return;
      }
      _checkOfflinePlaybackStall(item, server, engine, generation, watchEpoch);
    });
  }

  void _stopOfflineStallWatch() {
    _offlineStallWatchEpoch++;
    _offlineStallTimer?.cancel();
    _offlineStallTimer = null;
    _offlineStallRecoveryActive = false;
    _offlineStallObservedPosition = Duration.zero;
    _offlineStallObservedAt = null;
  }

  void _checkOfflinePlaybackStall(
    MediaPlaybackItem item,
    MediaServer server,
    PlayerEngine engine,
    int generation,
    int watchEpoch,
  ) {
    final DateTime now = DateTime.now();
    final PlayerEngineState value = engine.state.value;
    final DateTime observedAt = _offlineStallObservedAt ?? now;
    // Completion is decided before the stall state machine sees an inactive
    // backend. A raw completed flag at 1194/1246 is premature EOF and remains
    // recoverable; only a confirmed real end suppresses stall recovery.
    _evaluatePlaybackProgress(engine);
    final bool confirmedEnded = state.confirmedEnded;
    final bool interactionInProgress =
        _offlineStallRecoveryActive ||
        _prematureEofRecoveryActive ||
        (value.isCompleted && !confirmedEnded) ||
        state.loading ||
        state.playPauseOperationInFlight ||
        state.resumeStabilizing ||
        _seekInFlight ||
        _queuedSeekEngine == engine ||
        _settlingSeekEngine == engine;
    final OfflinePlaybackStallDecision decision = offlinePlaybackStallDecision(
      desiredPlaying: state.desiredPlaying,
      isInitialized: value.isInitialized,
      isCompleted: confirmedEnded,
      hasError: value.hasError,
      interactionInProgress: interactionInProgress,
      isNearEnd: confirmedEnded,
      position: value.position,
      observedPosition: _offlineStallObservedPosition,
      stalledFor: now.difference(observedAt),
    );

    switch (decision) {
      case OfflinePlaybackStallDecision.inactive:
      case OfflinePlaybackStallDecision.progressed:
        _offlineStallObservedPosition = value.position;
        _offlineStallObservedAt = now;
        return;
      case OfflinePlaybackStallDecision.waiting:
        _offlineStallObservedAt ??= now;
        return;
      case OfflinePlaybackStallDecision.recover:
        _offlineStallObservedPosition = value.position;
        _offlineStallObservedAt = now;
        unawaited(
          _kickOfflinePlayback(
            item,
            server,
            engine,
            generation,
            watchEpoch,
            value.position,
          ),
        );
        return;
    }
  }

  bool _isActiveOfflineStallRecovery(
    MediaPlaybackItem item,
    MediaServer server,
    PlayerEngine engine,
    int generation,
    int watchEpoch,
  ) {
    return watchEpoch == _offlineStallWatchEpoch &&
        generation == _playbackGeneration &&
        state.item == item &&
        state.server == server &&
        state.engine == engine &&
        state.desiredPlaying;
  }

  Future<void> _kickOfflinePlayback(
    MediaPlaybackItem item,
    MediaServer server,
    PlayerEngine engine,
    int generation,
    int watchEpoch,
    Duration stalledPosition,
  ) async {
    if (_offlineStallRecoveryActive ||
        !_isActiveOfflineStallRecovery(
          item,
          server,
          engine,
          generation,
          watchEpoch,
        )) {
      return;
    }
    _offlineStallRecoveryActive = true;
    final int manualSeekEpoch = _manualSeekEpoch;
    try {
      debugPrint(
        'Offline playback stalled at ${stalledPosition.inMilliseconds}ms; '
        'kicking the local player.',
      );
      await engine.pause();
      await Future<void>.delayed(_offlineStallKickDelay);
      if (!_isActiveOfflineStallRecovery(
        item,
        server,
        engine,
        generation,
        watchEpoch,
      )) {
        return;
      }
      await engine.play();
      if (!_isActiveOfflineStallRecovery(
        item,
        server,
        engine,
        generation,
        watchEpoch,
      )) {
        return;
      }
      if (manualSeekEpoch == _manualSeekEpoch) {
        state = state.copyWith(resumeStabilizing: true);
        _startResumeStabilityWatch(engine, stalledPosition);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Offline playback kick failed: $error');
      }
    } finally {
      if (watchEpoch == _offlineStallWatchEpoch) {
        _offlineStallRecoveryActive = false;
      }
    }
  }

  Future<void> stop() async {
    unawaited(MediaSessionService.clearNowPlaying());
    unawaited(_ignorePlaybackTeardownErrors(DiscordRpcService.clearActivity()));
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    Future<void>? finalProgressSave;
    if (item != null && engine != null && !item.ignoreProgress) {
      late final Future<void> barrier;
      barrier = _saveProgress(item, engine)
          .catchError((Object _) {
            // Exiting should still release the native player if persistence is busy.
          })
          .whenComplete(() {
            if (identical(_finalProgressSaveBarrier, barrier)) {
              _finalProgressSaveBarrier = null;
            }
          });
      _finalProgressSaveBarrier = barrier;
      finalProgressSave = barrier;
    }
    _playbackGeneration++;
    _playPauseIntentEpoch++;
    _resumeStabilizeEpoch++;
    _pendingDesiredPlaying = null;
    _temporarySpeedHolds = 0;
    _progressTimer?.cancel();
    _stopOfflineStallWatch();
    _undoTimer?.cancel();
    _autoNextOverlayTimer?.cancel();
    _clearInteractiveSeek();
    _cancelSeekThumbnailRequests();
    _prematureEofRecoveryActive = false;
    _prematureEofRecoveryAttempts = 0;
    _prematureEofRecoveryNeedsProgressFrom = null;
    _resetManualSeekEofWindow();
    _engineForDispose = null;
    state = const PlaybackState();
    try {
      await _seekThumbnailService.reset();
      _seekThumbnailPlan = null;
      _seekThumbnailBackend = PlayerBackend.auto;
    } catch (_) {
      // Preview teardown must not prevent the main player from being released.
    }

    if (engine == null) return;

    await finalProgressSave;
    _resumeGuardPosition = Duration.zero;
    _resumeGuardUntil = null;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      if (engine.state.value.isInitialized) {
        await engine.pause();
      }
    } catch (_) {
      // The native player may already be torn down by the platform route pop.
    }
    try {
      await engine.dispose();
    } catch (_) {
      // Some native backends reject late disposal during app/window teardown.
    }
  }

  StreamQuality _initialQuality(MediaServer server, {String? explicitId}) {
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if (server.qualities.isEmpty) return StreamQuality.auto;
    if (server.id == 'youtube-trailer') {
      return server.qualities.firstWhere(
        (StreamQuality q) => q.isAuto,
        orElse: () => server.qualities.first,
      );
    }
    // A quality the user picked explicitly for this playback (e.g. from the
    // stream sheet) wins over the saved global preference.
    if (explicitId != null && explicitId.trim().isNotEmpty) {
      for (final StreamQuality quality in server.qualities) {
        if (quality.id == explicitId || quality.label == explicitId) {
          return quality;
        }
      }
    }
    for (final StreamQuality quality in server.qualities) {
      if (quality.id == settings.preferredQuality ||
          quality.label == settings.preferredQuality) {
        return quality;
      }
    }
    return server.qualities.firstWhere(
      (StreamQuality q) => q.isAuto,
      orElse: () => server.qualities.first,
    );
  }

  VoiceOverTrack? _voiceoverById(List<VoiceOverTrack> voiceovers, String? id) {
    final String cleanId = id?.trim() ?? '';
    if (cleanId.isEmpty) return null;
    for (final VoiceOverTrack voiceover in voiceovers) {
      if (voiceover.id.trim() == cleanId) return voiceover;
    }
    return null;
  }

  Future<void> pause() async {
    if (_suppressPlaybackControl) return;
    await _setDesiredPlaying(false);
  }

  Future<void> _setDesiredPlaying(bool desiredPlaying) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null) {
      state = state.copyWith(
        desiredPlaying: desiredPlaying,
        playPauseOperationInFlight: false,
        resumeStabilizing: false,
      );
      return;
    }

    final bool alreadyDesired = state.desiredPlaying == desiredPlaying;
    final bool nativeMatches = desiredPlaying
        ? engine.state.value.isPlaying || state.resumeStabilizing
        : !engine.state.value.isPlaying && !state.resumeStabilizing;
    if (alreadyDesired && nativeMatches && !_playPauseOperationActive) {
      return;
    }

    _pendingDesiredPlaying = desiredPlaying;
    state = state.copyWith(
      desiredPlaying: desiredPlaying,
      playPauseOperationInFlight: true,
      resumeStabilizing: desiredPlaying ? state.resumeStabilizing : false,
    );

    final Completer<void> completer = _playPauseDrainCompleter ??=
        Completer<void>();
    if (!_playPauseOperationActive) {
      unawaited(_drainPlayPauseIntents());
    }
    return completer.future;
  }

  Future<void> _drainPlayPauseIntents() async {
    if (_playPauseOperationActive) return;
    _playPauseOperationActive = true;
    Object? failure;
    StackTrace? failureStack;

    try {
      while (_pendingDesiredPlaying != null) {
        final bool desiredPlaying = _pendingDesiredPlaying!;
        _pendingDesiredPlaying = null;
        final int epoch = ++_playPauseIntentEpoch;
        await _applyDesiredPlaying(desiredPlaying, epoch);
      }
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
      if (kDebugMode) {
        debugPrint('Play/pause intent failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _playPauseOperationActive = false;
      state = state.copyWith(playPauseOperationInFlight: false);
      final Completer<void>? completer = _playPauseDrainCompleter;
      _playPauseDrainCompleter = null;
      if (completer != null && !completer.isCompleted) {
        if (failure == null) {
          completer.complete();
        } else {
          completer.completeError(failure, failureStack);
        }
      }
      if (_pendingDesiredPlaying != null) {
        unawaited(_drainPlayPauseIntents());
      }
    }
  }

  Future<void> _applyDesiredPlaying(bool desiredPlaying, int epoch) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    if (desiredPlaying) {
      await _applyPlayIntent(engine, epoch);
    } else {
      await _applyPauseIntent(engine, epoch);
    }
  }

  Future<void> _applyPauseIntent(PlayerEngine engine, int epoch) async {
    _resumeStabilizeEpoch++;
    final Duration pausePosition = _currentPositionFor(engine);
    _lastStablePausePosition = pausePosition;
    state = state.copyWith(desiredPlaying: false, resumeStabilizing: false);

    if (state.engine != engine || epoch != _playPauseIntentEpoch) return;
    if (engine.state.value.isPlaying || engine.state.value.isBuffering) {
      await engine.pause();
    }
    if (state.engine != engine || epoch != _playPauseIntentEpoch) return;

    _lastStablePausePosition = _currentPositionFor(engine);
    state = state.copyWith(desiredPlaying: false, resumeStabilizing: false);
    _updateMediaSession();
    _broadcastPlayState();
  }

  Future<void> _applyPlayIntent(PlayerEngine engine, int epoch) async {
    final Duration resumePosition = _resumePositionFor(engine);
    state = state.copyWith(desiredPlaying: true, resumeStabilizing: true);

    final PlayerEngineState before = engine.state.value;
    if (resumePositionNeedsCorrection(
      position: before.position,
      resumeFrom: resumePosition,
    )) {
      try {
        await _seekEngineTo(
          engine,
          resumePosition,
          reason: 'Resume correction seek',
        );
      } on Object catch (error) {
        if (kDebugMode) {
          debugPrint('Resume correction seek ignored: $error');
        }
      }
    }

    if (state.engine != engine ||
        epoch != _playPauseIntentEpoch ||
        !state.desiredPlaying) {
      return;
    }
    if (!engine.state.value.isPlaying) {
      await engine.play();
    }
    if (state.engine != engine ||
        epoch != _playPauseIntentEpoch ||
        !state.desiredPlaying) {
      return;
    }

    state = state.copyWith(desiredPlaying: true, resumeStabilizing: true);
    _updateMediaSession();
    _broadcastPlayState();
    _startResumeStabilityWatch(engine, resumePosition);
  }

  Duration _resumePositionFor(PlayerEngine engine) {
    final Duration current = _currentPositionFor(engine);
    final Duration paused = _lastStablePausePosition;
    if (paused <= Duration.zero) return current;
    if (resumePositionNeedsCorrection(position: current, resumeFrom: paused)) {
      return paused;
    }
    return current > paused ? current : paused;
  }

  void _startResumeStabilityWatch(
    PlayerEngine engine,
    Duration resumePosition,
  ) {
    final int token = ++_resumeStabilizeEpoch;
    unawaited(_verifyResumeStability(engine, resumePosition, token));
  }

  bool _isActiveResumeWatch(PlayerEngine engine, int token) {
    return token == _resumeStabilizeEpoch &&
        state.engine == engine &&
        state.desiredPlaying;
  }

  Future<void> _verifyResumeStability(
    PlayerEngine engine,
    Duration resumePosition,
    int token,
  ) async {
    final bool stable = await _waitForResumeStability(
      engine,
      resumePosition,
      token,
    );
    if (stable) return;
    if (!_isActiveResumeWatch(engine, token)) return;

    try {
      await _seekEngineTo(
        engine,
        resumePosition,
        reason: 'Resume recovery seek',
      );
      if (_isActiveResumeWatch(engine, token) &&
          !engine.state.value.isPlaying) {
        await engine.play();
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Resume recovery seek ignored: $error');
      }
    }

    final bool recovered = await _waitForResumeStability(
      engine,
      resumePosition,
      token,
      recoveryTimeout: _resumeRecoverySettleTimeout,
    );
    if (recovered) return;
    if (!_isActiveResumeWatch(engine, token)) return;

    await _reopenForResumeRecovery(engine, resumePosition, token);
  }

  Future<bool> _waitForResumeStability(
    PlayerEngine engine,
    Duration resumePosition,
    int token, {
    Duration? recoveryTimeout,
  }) async {
    final DateTime startedAt = DateTime.now();
    while (_isActiveResumeWatch(engine, token)) {
      await Future<void>.delayed(_resumeStabilityTick);
      if (!_isActiveResumeWatch(engine, token)) return false;

      final PlayerEngineState value = engine.state.value;
      final Duration elapsed = DateTime.now().difference(startedAt);
      final Duration bufferedAhead = bufferedAheadForPosition(
        value.buffered,
        value.position,
      );
      final ResumeStabilityDecision decision = resumeStabilityDecision(
        desiredPlaying: state.desiredPlaying,
        isInitialized: value.isInitialized,
        isBuffering: value.isBuffering,
        hasError: value.hasError,
        position: value.position,
        resumeFrom: resumePosition,
        bufferedAhead: bufferedAhead,
        elapsed: elapsed,
        normalTimeout: recoveryTimeout ?? const Duration(milliseconds: 2600),
        bufferedTimeout: recoveryTimeout ?? const Duration(milliseconds: 5200),
      );

      switch (decision) {
        case ResumeStabilityDecision.stable:
          if (_isActiveResumeWatch(engine, token)) {
            state = state.copyWith(resumeStabilizing: false);
            _updateMediaSession();
          }
          return true;
        case ResumeStabilityDecision.waiting:
          continue;
        case ResumeStabilityDecision.recover:
        case ResumeStabilityDecision.canceled:
          return false;
      }
    }
    return false;
  }

  Future<void> _reopenForResumeRecovery(
    PlayerEngine engine,
    Duration resumePosition,
    int token,
  ) async {
    if (!_isActiveResumeWatch(engine, token)) return;
    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? quality = state.quality;
    if (item == null || server == null || quality == null) {
      state = state.copyWith(resumeStabilizing: false);
      return;
    }

    final Duration position = _clampSeekPosition(
      resumePosition,
      engine.state.value.duration,
    );
    final double? aspectRatio = _safeAspectRatio(
      engine.state.value.aspectRatio,
    );
    await _open(
      item: item,
      server: server,
      quality: quality,
      position: position,
      autoplay: true,
      voiceover: state.voiceover,
      subtitle: state.subtitle,
      preserveAspectRatio: aspectRatio,
      respectDesiredPlaying: true,
    );
  }

  // Save progress from the native player (position is known, engine is paused).
  // Bypasses the FVP engine position entirely.
  Future<void> saveNativeProgress({
    required int positionMs,
    required int durationMs,
    bool completed = false,
  }) async {
    final MediaPlaybackItem? item = state.item;
    if (item == null) return;
    if (item.ignoreProgress) return;

    final int positionSeconds = positionMs ~/ 1000;
    final int durationSeconds = durationMs ~/ 1000;
    final PlaybackEndEvaluation end = evaluateNativePlaybackEnd(
      positionMs: positionMs,
      durationMs: durationMs,
      backendCompleted: completed,
    );
    final bool resetToStart = end.confirmedEnded;
    final int savePosition = resetToStart ? 0 : positionSeconds;
    final bool saveCompleted =
        end.confirmedEnded || end.watchedThresholdReached;

    // Latch the watched mark so a later FVP save can't clear it. Only latch
    // end-of-stream only when genuinely finished. At 85% there is still about 15% left,
    // and _reachedNearEnd would otherwise pop the auto-next overlay on restore.
    if (saveCompleted) _autoProgressMarked = true;
    if (resetToStart) {
      _reachedNearEnd = true;
      state = state.copyWith(confirmedEnded: true);
    }

    for (final String mediaId in _progressMediaIds(item)) {
      await ref
          .read(localLibraryProvider.notifier)
          .saveEpisodeProgress(
            mediaId: mediaId,
            season: item.seasonNumber,
            episode: item.episodeNumber,
            positionSeconds: savePosition,
            durationSeconds: durationSeconds > 0 ? durationSeconds : null,
            completed: saveCompleted,
          );
    }

    unawaited(
      ref
          .read(localLibraryProvider.notifier)
          .updateWatchProgress(
            mediaId: item.id,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            positionFraction: saveCompleted
                ? 1.0
                : (durationSeconds > 0
                      ? positionSeconds / durationSeconds
                      : null),
          ),
    );

    if (saveCompleted) {
      final bool syncEnabled =
          (ref.read(playerSettingsProvider).value ?? const PlayerSettings())
              .autoAnilistSync;
      if (syncEnabled) {
        unawaited(_trySyncAniList(item, item.episodeNumber.round()));
      }
    }
  }

  Future<void> togglePlay() async {
    if (_suppressPlaybackControl) return;
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    if (_queuedSeekEngine == engine && _queuedSeekTarget != null) {
      unawaited(_flushInteractiveSeek());
    }
    final bool effectivePlaying =
        state.playPauseOperationInFlight || state.resumeStabilizing
        ? state.desiredPlaying
        : engine.state.value.isPlaying;
    await _setDesiredPlaying(!effectivePlaying);
  }

  Future<void> seekBy(Duration offset, {Duration? flushDelay}) async {
    if (_suppressSeekControl) return;
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration duration = engine.state.value.duration;
    final Duration target = _clampSeekPosition(
      _seekBaseFor(engine) + offset,
      duration,
    );
    _clearResumeGuard();
    _notePausedResumeTarget(engine, target);
    _queueInteractiveSeek(
      engine,
      target,
      delay: flushDelay ?? _interactiveSeekDelay,
    );
    _broadcastSeek(target);
  }

  Future<void> seekTo(Duration position) async {
    if (_suppressSeekControl) return;
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration duration = engine.state.value.duration;
    final Duration target = _clampSeekPosition(position, duration);
    _clearResumeGuard();
    _notePausedResumeTarget(engine, target);
    _queueInteractiveSeek(engine, target, delay: Duration.zero);
    _broadcastSeek(target);
  }

  void _notePausedResumeTarget(PlayerEngine engine, Duration target) {
    if (state.desiredPlaying || engine.state.value.isPlaying) return;
    _lastStablePausePosition = target;
  }

  // A user-selected target is intent, not end-of-stream evidence. Completion
  // remains disarmed until the native seek settles and a later engine event
  // reports a credible strict end.
  void _noteManualSeekTarget(Duration target, Duration duration) {
    _durationEvidence.observe(duration);
    _invalidateConfirmedEnd('manual seek target accepted');
    // A backward seek starts a new completion-evidence window. Progress from
    // before the seek must not validate a stale completed callback afterward.
    if (_maxObservedPosition > target) _maxObservedPosition = target;
  }

  /// Persist the current episode as watched immediately, bypassing the periodic
  /// saver. Used before auto-advancing and on seek-to-end so the episode is
  /// never left unwatched when the next one starts.
  Future<void> markCurrentEpisodeWatched() async {
    if (!state.confirmedEnded || !_reachedNearEnd) return;
    await _markCurrentCompleted(showNext: false);
  }

  Future<void> _markCurrentCompleted({required bool showNext}) async {
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    if (item == null || engine == null || item.ignoreProgress) return;
    await _saveProgress(item, engine);
    if (!showNext || _suppressGuestGlobalControl) return;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if ((settings.autoplayNext || settings.showNextEpisodeButton) &&
        state.confirmedEnded &&
        !state.autoNextVisible) {
      state = state.copyWith(autoNextVisible: true);
    }
  }

  void previewSeekTo(Duration position) {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration duration = engine.state.value.duration;
    final Duration clamped = _clampSeekPosition(position, duration);
    _cancelSeekSettle(clearPreview: false);
    _setSeekPreview(engine, clamped);

    final SeekThumbnailPlan? plan = _seekThumbnailPlan;
    final bool imageSurface =
        _seekPreviewsEnabled() &&
        seekThumbnailExtractionSupported &&
        plan != null &&
        plan.candidates.isNotEmpty;
    final bool progressiveTimeline =
        imageSurface && _progressiveSeekPreviewsEnabled(plan);
    final SeekThumbnail? cached = imageSurface
        ? _seekThumbnailService.cachedFor(plan, clamped, duration: duration)
        : null;
    final SeekThumbnail? visibleThumbnail = progressiveTimeline
        ? cached ??
              _seekThumbnailService.nearestCachedFor(
                plan,
                clamped,
                duration: duration,
                maxDistance: duration,
                preferLaterOnTie: true,
              ) ??
              state.seekPreviewThumbnail
        : cached ??
              (imageSurface
                  ? state.seekPreviewThumbnail ??
                        _seekThumbnailService.nearestCachedFor(
                          plan,
                          clamped,
                          duration: duration,
                        )
                  : null);
    state = state.copyWith(
      seekPreviewThumbnail: visibleThumbnail,
      clearSeekPreviewThumbnail: !imageSurface,
      seekPreviewLoading: progressiveTimeline && visibleThumbnail == null,
      seekPreviewImageSurface: imageSurface,
    );
    if (cached != null) {
      _seekPreviewTimer?.cancel();
      _pendingSeekPreviewTarget = null;
      return;
    }
    if (progressiveTimeline) {
      _maybeStartProgressiveSeekPreviews();
    } else if (imageSurface) {
      _queueSeekPreviewFrame(clamped);
    }
  }

  /// Starts a hover/drag preview session without mutating the main engine.
  void beginSeekPreview() {
    _seekPreviewGeneration++;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreviewTarget = null;
    _seekThumbnailRequests.invalidate();
    final SeekThumbnailPlan? plan = _seekThumbnailPlan;
    if (plan == null || !_progressiveSeekPreviewsEnabled(plan)) {
      _seekThumbnailService.cancelPending();
    }
  }

  /// Ends slider interaction. The committed seek remains a separate operation.
  void endSeekPreview() {
    _seekPreviewGeneration++;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreviewTarget = null;
    _seekThumbnailRequests.invalidate();
    final SeekThumbnailPlan? plan = _seekThumbnailPlan;
    if (plan == null || !_progressiveSeekPreviewsEnabled(plan)) {
      _seekThumbnailService.cancelPending();
    }
    if (state.seekPreviewLoading) {
      state = state.copyWith(seekPreviewLoading: false);
    }
    _maybeStartProgressiveSeekPreviews();
  }

  /// Ends a desktop hover preview without committing a seek.
  void cancelSeekPreview() {
    endSeekPreview();
    if (state.seekPreviewPosition != null ||
        state.seekPreviewThumbnail != null ||
        state.seekPreviewImageSurface) {
      state = state.copyWith(
        clearSeekPreviewPosition: true,
        clearSeekPreviewThumbnail: true,
        seekPreviewImageSurface: false,
      );
    }
  }

  void _queueSeekPreviewFrame(Duration target) {
    _pendingSeekPreviewTarget = target;
    if (_seekPreviewInFlight) _seekThumbnailService.cancelPending();
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = Timer(
      (_seekThumbnailPlan?.isOffline ?? false)
          ? _offlineSeekPreviewDebounce
          : _onlineSeekPreviewDebounce,
      () => unawaited(_flushSeekPreviewFrame()),
    );
  }

  Future<void> _flushSeekPreviewFrame() async {
    if (_seekPreviewInFlight) return;
    final Duration? target = _pendingSeekPreviewTarget;
    final PlayerEngine? engine = state.engine;
    final SeekThumbnailPlan? plan = _seekThumbnailPlan;
    if (target == null ||
        engine == null ||
        !engine.state.value.isInitialized ||
        plan == null ||
        plan.candidates.isEmpty ||
        !_seekPreviewsEnabled() ||
        !seekThumbnailExtractionSupported) {
      _pendingSeekPreviewTarget = null;
      return;
    }

    final Duration duration = engine.state.value.duration;
    final Duration bucket = quantizeSeekThumbnailPosition(
      target,
      duration: duration,
    );
    final SeekThumbnail? cached = _seekThumbnailService.cachedFor(
      plan,
      target,
      duration: duration,
    );
    if (cached != null) {
      _pendingSeekPreviewTarget = null;
      state = state.copyWith(
        seekPreviewThumbnail: cached,
        seekPreviewLoading: false,
        seekPreviewImageSurface: true,
      );
      return;
    }

    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreviewTarget = null;
    _seekPreviewInFlight = true;
    final int generation = _seekPreviewGeneration;
    final int request = _seekThumbnailRequests.begin(plan.sessionKey, bucket);
    state = state.copyWith(
      seekPreviewLoading: true,
      seekPreviewImageSurface: true,
    );
    if (kDebugMode) {
      debugPrint(
        'SeekPreview: extracting @ ${bucket.inSeconds}s '
        'from candidate 1/${plan.candidates.length}.',
      );
    }

    try {
      final SeekThumbnail? thumbnail = await _seekThumbnailService.request(
        plan: plan,
        backend: _seekThumbnailBackend,
        position: target,
        duration: duration,
      );
      final Duration? visiblePosition = state.seekPreviewPosition;
      final bool currentBucket =
          visiblePosition != null &&
          quantizeSeekThumbnailPosition(visiblePosition, duration: duration) ==
              bucket;
      if (generation != _seekPreviewGeneration ||
          state.engine != engine ||
          _seekThumbnailPlan?.sessionKey != plan.sessionKey ||
          !_seekPreviewsEnabled() ||
          !_seekThumbnailRequests.accepts(request, plan.sessionKey, bucket) ||
          !currentBucket) {
        if (kDebugMode) debugPrint('SeekPreview: request superseded.');
        return;
      }
      state = state.copyWith(
        seekPreviewThumbnail: thumbnail,
        seekPreviewLoading: false,
        seekPreviewImageSurface:
            thumbnail != null || state.seekPreviewThumbnail != null,
      );
    } on Object {
      if (generation == _seekPreviewGeneration && state.engine == engine) {
        state = state.copyWith(
          seekPreviewLoading: false,
          seekPreviewImageSurface: state.seekPreviewThumbnail != null,
        );
      }
    } finally {
      _seekPreviewInFlight = false;
      final Duration? pending = _pendingSeekPreviewTarget;
      if (!_seekPreviewsEnabled()) {
        _pendingSeekPreviewTarget = null;
      } else if (pending != null) {
        _queueSeekPreviewFrame(pending);
      } else {
        _maybeStartProgressiveSeekPreviews();
      }
    }
  }

  void _cancelSeekThumbnailRequests() {
    _cancelProgressiveSeekPreviews(cancelActiveRequest: false);
    _seekPreviewGeneration++;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreviewTarget = null;
    _seekThumbnailRequests.invalidate();
    _seekThumbnailService.cancelPending();
  }

  StreamType _streamTypeForUrl(String url, StreamType fallback) {
    return seekPreviewStreamTypeForUrl(url, fallback);
  }

  Duration _seekBaseFor(PlayerEngine engine) {
    if (_queuedSeekEngine == engine && _queuedSeekTarget != null) {
      return _queuedSeekTarget!;
    }
    if (_settlingSeekEngine == engine && _settlingSeekTarget != null) {
      return _settlingSeekTarget!;
    }
    return engine.state.value.position;
  }

  Duration _currentPositionFor(PlayerEngine? engine) {
    if (engine == null) return Duration.zero;
    if (_queuedSeekEngine == engine && _queuedSeekTarget != null) {
      return _queuedSeekTarget!;
    }
    if (_settlingSeekEngine == engine && _settlingSeekTarget != null) {
      return _settlingSeekTarget!;
    }
    return engine.state.value.position;
  }

  Duration _clampSeekPosition(Duration position, Duration duration) {
    if (position < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && position > duration) return duration;
    return position;
  }

  Future<bool> _seekEngineTo(
    PlayerEngine engine,
    Duration target, {
    String reason = 'seek',
  }) async {
    try {
      await engine.seekTo(target).timeout(_engineSeekTimeout);
      return true;
    } on TimeoutException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '$reason timed out after ${_engineSeekTimeout.inSeconds}s '
          '(target=${target.inMilliseconds}ms): $error',
        );
      }
      return false;
    }
  }

  void _queueInteractiveSeek(
    PlayerEngine engine,
    Duration target, {
    required Duration delay,
  }) {
    _beginManualSeekEofWindow(engine, target);
    _cancelSeekSettle(clearPreview: false);
    _queuedSeekEngine = engine;
    _queuedSeekTarget = target;
    _interactiveSeekTimer?.cancel();
    _setSeekPreview(engine, target);

    if (delay <= Duration.zero) {
      unawaited(_flushInteractiveSeek());
      return;
    }

    _interactiveSeekTimer = Timer(
      delay,
      () => unawaited(_flushInteractiveSeek()),
    );
  }

  Future<void> _flushInteractiveSeek() async {
    if (_seekInFlight || _prematureEofRecoveryActive) return;
    final PlayerEngine? engine = _queuedSeekEngine;
    final Duration? target = _queuedSeekTarget;
    if (engine == null || target == null || state.engine != engine) {
      _clearInteractiveSeek();
      return;
    }

    _interactiveSeekTimer?.cancel();
    _interactiveSeekTimer = null;
    _queuedSeekTarget = null;
    _seekInFlight = true;
    final int manualSeekEpoch = _manualSeekEpoch;
    final Duration from = engine.state.value.position;
    bool seekCompleted = false;

    try {
      seekCompleted = await _seekEngineTo(
        engine,
        target,
        reason: 'Interactive seek',
      );
    } on Object {
      // Keep rapid seek gestures from surfacing as uncaught async errors if
      // the native player rejects a stale target during stream transitions.
    } finally {
      _seekInFlight = false;
      if (manualSeekEpoch == _manualSeekEpoch) {
        _manualSeekOperationActive = false;
      }
      if (_queuedSeekTarget != null) {
        unawaited(_flushInteractiveSeek());
      } else if (state.engine == engine) {
        _queuedSeekEngine = null;
        if (seekCompleted) {
          _noteManualSeekTarget(target, engine.state.value.duration);
          _beginSeekSettle(engine, target, from: from);
          if (engine.state.value.isCompleted) {
            _evaluatePlaybackProgress(engine);
          }
        } else {
          _cancelSeekSettle(clearPreview: true);
          _resetManualSeekEofWindow();
        }
      } else if (_queuedSeekEngine == engine) {
        _clearInteractiveSeek();
      }
    }
  }

  void _beginSeekSettle(
    PlayerEngine engine,
    Duration target, {
    required Duration from,
  }) {
    _cancelSeekSettle(clearPreview: false);
    if (state.engine != engine) return;
    _settlingSeekEngine = engine;
    _settlingSeekTarget = target;
    _settlingSeekFrom = from;
    final DateTime now = DateTime.now();
    _settlingSeekUntil = now.add(_seekSettleTimeout);
    _settlingSeekEarliestClear = now.add(_seekSettleMinHold);
    _setSeekPreview(engine, target, preserveBufferedEnd: true);
    _settleSeekPreview();
    _seekSettleTimer = Timer.periodic(
      _seekSettleTick,
      (_) => _settleSeekPreview(),
    );
  }

  void _beginManualSeekEofWindow(PlayerEngine engine, Duration target) {
    if (!identical(state.engine, engine)) return;
    _resetManualSeekEofWindow();
    _manualSeekEpoch++;
    _manualSeekEofEpoch = _manualSeekEpoch;
    _manualSeekEofTarget = target;
    _manualSeekSettledAfterEngineEvent = null;
    _manualSeekOperationActive = true;
    _manualSeekRejectedBackendEofEpoch = null;
    _lastManualSeekEofLogKey = null;
    _prematureEofRecoveryAttempts = 0;
    _prematureEofRecoveryNeedsProgressFrom = null;

    _invalidateConfirmedEnd('manual seek started');
    if (_maxObservedPosition > target) {
      _maxObservedPosition = target;
    }
  }

  bool _manualSeekOwnsBackendEof(PlayerEngine engine) {
    final DateTime? quarantineUntil = _manualSeekEofQuarantineUntil;
    final bool quarantineActive =
        quarantineUntil != null && DateTime.now().isBefore(quarantineUntil);
    return identical(state.engine, engine) &&
        _manualSeekEofEpoch == _manualSeekEpoch &&
        (_manualSeekOperationActive ||
            _seekInFlight ||
            (_queuedSeekEngine == engine && _queuedSeekTarget != null) ||
            _settlingSeekEngine == engine ||
            quarantineActive);
  }

  void _resetManualSeekEofWindow({bool clearRejectedBackendEof = true}) {
    _manualSeekEofQuarantineTimer?.cancel();
    _manualSeekEofQuarantineTimer = null;
    _manualSeekEofEpoch = null;
    _manualSeekEofTarget = null;
    _manualSeekSettledAfterEngineEvent = null;
    _manualSeekEofQuarantineUntil = null;
    _manualSeekOperationActive = false;
    _lastManualSeekEofLogKey = null;
    if (clearRejectedBackendEof) {
      _manualSeekRejectedBackendEofEpoch = null;
    }
  }

  void _settleSeekPreview() {
    final PlayerEngine? engine = _settlingSeekEngine;
    final Duration? target = _settlingSeekTarget;
    final Duration? from = _settlingSeekFrom;
    final DateTime? until = _settlingSeekUntil;
    final DateTime? earliestClear = _settlingSeekEarliestClear;
    if (engine == null || target == null || until == null) {
      _cancelSeekSettle(clearPreview: false);
      return;
    }
    if (state.engine != engine) {
      _cancelSeekSettle(clearPreview: true);
      return;
    }
    if (_seekInFlight || _queuedSeekTarget != null) {
      return;
    }

    final DateTime now = DateTime.now();
    final Duration position = engine.state.value.position;
    final bool settled = _isSeekSettled(position, target, from: from);
    final bool timedOut = now.isAfter(until);
    final bool heldLongEnough =
        earliestClear == null || !now.isBefore(earliestClear);
    final bool liveTargetBuffered = _bufferedEndFor(engine, target) != null;
    final bool hasRememberedBuffer = state.seekPreviewBufferedEnd != null;
    final bool nativeStillBuffering =
        engine.state.value.isBuffering && !liveTargetBuffered;
    final bool canClearRememberedBuffer =
        !hasRememberedBuffer || !nativeStillBuffering;

    if (timedOut && !settled) {
      if (kDebugMode) {
        debugPrint(
          'Seek did not settle at ${target.inMilliseconds}ms after '
          '${_seekSettleTimeout.inSeconds}s; '
          'actual=${position.inMilliseconds}ms.',
        );
      }
      _cancelSeekSettle(clearPreview: true);
      if (engine.state.value.isCompleted) {
        _armManualSeekEofQuarantine(engine, delay: Duration.zero);
      } else {
        _resetManualSeekEofWindow();
      }
      return;
    }

    if (!timedOut &&
        (!settled || !heldLongEnough || !canClearRememberedBuffer)) {
      return;
    }

    if (!engine.state.value.isCompleted) {
      _resetManualSeekEofWindow();
      debugPrint(
        'SeekEOF: epoch=$_manualSeekEpoch state=settled '
        'backendEnd=false action=quarantine-ended',
      );
    } else {
      // A target near duration is not proof of EOF. Only a later engine event
      // or the bounded quarantine deadline may confirm completion after this
      // seek has actually settled.
      _armManualSeekEofQuarantine(engine);
    }

    final bool shouldClear = state.seekPreviewPosition == target;
    _cancelSeekSettle(clearPreview: false);
    if (shouldClear && state.engine == engine) {
      state = state.copyWith(clearSeekPreviewPosition: true);
    }
    if (!engine.state.value.isCompleted && state.engine == engine) {
      _evaluatePlaybackProgress(engine);
    }
  }

  void _armManualSeekEofQuarantine(
    PlayerEngine engine, {
    Duration delay = _manualSeekEofQuarantine,
  }) {
    if (!identical(state.engine, engine) ||
        _manualSeekEofEpoch != _manualSeekEpoch) {
      return;
    }
    final int generation = _playbackGeneration;
    final int manualSeekEpoch = _manualSeekEpoch;
    _manualSeekOperationActive = false;
    _manualSeekSettledAfterEngineEvent = _engineStateEventEpoch;
    _manualSeekEofQuarantineUntil = DateTime.now().add(delay);
    _manualSeekEofQuarantineTimer?.cancel();
    debugPrint(
      'SeekEOF: epoch=$manualSeekEpoch state=settled '
      'target=${_manualSeekEofTarget?.inSeconds}s '
      'backendEnd=${engine.state.value.isCompleted} '
      'action=quarantine-start',
    );
    _manualSeekEofQuarantineTimer = Timer(delay, () {
      if (generation != _playbackGeneration ||
          manualSeekEpoch != _manualSeekEpoch ||
          !identical(state.engine, engine)) {
        return;
      }
      _evaluatePlaybackProgress(engine);
    });
  }

  void _expireManualSeekEofQuarantineIfDue(
    PlayerEngine engine,
    PlaybackEndEvaluation evaluation,
  ) {
    final DateTime? until = _manualSeekEofQuarantineUntil;
    if (_manualSeekEofEpoch != _manualSeekEpoch ||
        until == null ||
        DateTime.now().isBefore(until)) {
      return;
    }
    final int manualSeekEpoch = _manualSeekEpoch;
    final Duration? target = _manualSeekEofTarget;
    final bool rejectedStaleBackendEof =
        engine.state.value.isCompleted && !evaluation.confirmedEnded;
    _resetManualSeekEofWindow(clearRejectedBackendEof: false);
    _manualSeekRejectedBackendEofEpoch = rejectedStaleBackendEof
        ? manualSeekEpoch
        : null;
    debugPrint(
      'SeekEOF: epoch=$manualSeekEpoch state=settled '
      'target=${target?.inSeconds}s action=quarantine-ended '
      'decision=${evaluation.decision.name}',
    );
  }

  bool _isSeekSettled(
    Duration position,
    Duration target, {
    required Duration? from,
  }) {
    return seekHasSettled(
      position: position,
      target: target,
      from: from,
      tolerance: _seekSettleTolerance,
      forwardTolerance: _seekSettleForwardTolerance,
    );
  }

  void _cancelSeekSettle({required bool clearPreview}) {
    _seekSettleTimer?.cancel();
    _seekSettleTimer = null;
    _settlingSeekEngine = null;
    _settlingSeekTarget = null;
    _settlingSeekFrom = null;
    _settlingSeekUntil = null;
    _settlingSeekEarliestClear = null;
    if (clearPreview && state.seekPreviewPosition != null) {
      state = state.copyWith(clearSeekPreviewPosition: true);
    }
  }

  void _clearInteractiveSeek() {
    _interactiveSeekTimer?.cancel();
    _interactiveSeekTimer = null;
    _cancelSeekSettle(clearPreview: false);
    _queuedSeekEngine = null;
    _queuedSeekTarget = null;
    _seekInFlight = false;
    _resetManualSeekEofWindow();
    if (state.seekPreviewPosition != null) {
      state = state.copyWith(clearSeekPreviewPosition: true);
    }
  }

  void _setSeekPreview(
    PlayerEngine engine,
    Duration target, {
    bool preserveBufferedEnd = false,
  }) {
    final Duration? preservedEnd =
        preserveBufferedEnd && state.seekPreviewPosition == target
        ? state.seekPreviewBufferedEnd
        : null;
    final Duration? bufferedEnd =
        preservedEnd ?? _bufferedEndFor(engine, target);
    state = state.copyWith(
      seekPreviewPosition: target,
      seekPreviewBufferedEnd: bufferedEnd,
      clearSeekPreviewBufferedEnd: bufferedEnd == null,
    );
  }

  Duration? _bufferedEndFor(PlayerEngine engine, Duration position) {
    final Duration duration = engine.state.value.duration;
    final int totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return null;

    final int positionMs = position.inMilliseconds.clamp(0, totalMs).toInt();
    final int toleranceMs = const Duration(milliseconds: 1200).inMilliseconds;
    int? bufferedEndMs;
    for (final PlayerBufferedRange range in engine.state.value.buffered) {
      final int startMs = range.start.inMilliseconds.clamp(0, totalMs).toInt();
      final int endMs = range.end.inMilliseconds.clamp(0, totalMs).toInt();
      if (endMs <= startMs) continue;
      final bool containsTarget =
          positionMs >= startMs - toleranceMs &&
          positionMs <= endMs + toleranceMs;
      if (containsTarget && (bufferedEndMs == null || endMs > bufferedEndMs)) {
        bufferedEndMs = endMs;
      }
    }
    return bufferedEndMs == null ? null : Duration(milliseconds: bufferedEndMs);
  }

  Future<void> setSpeed(double speed) async {
    if (_suppressSpeedControl) return;
    _remoteTemporaryPlaybackSpeed = null;
    await ref.read(playerSettingsProvider.notifier).setSpeed(speed);
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await state.engine?.setPlaybackSpeed(_effectivePlaybackSpeed(settings));
    state = state.copyWith(temporarySpeedActive: _temporarySpeedHolds > 0);
    _updateMediaSession();
    _broadcastSpeed(speed);
  }

  Future<bool> beginTemporarySpeed() async {
    if (_suppressSpeedControl) return false;
    final PlayerEngine? engine = state.engine;
    if (engine == null) return false;
    _remoteTemporaryPlaybackSpeed = null;
    _temporarySpeedHolds += 1;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final double temporarySpeed = _effectivePlaybackSpeed(settings);
    await engine.setPlaybackSpeed(temporarySpeed);
    state = state.copyWith(temporarySpeedActive: true);
    _updateMediaSession();
    _broadcastSpeed(temporarySpeed, temporary: true);
    return true;
  }

  Future<void> endTemporarySpeed() async {
    if (_temporarySpeedHolds <= 0) return;
    _temporarySpeedHolds -= 1;
    if (_temporarySpeedHolds > 0) return;
    _remoteTemporaryPlaybackSpeed = null;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await state.engine?.setPlaybackSpeed(settings.playbackSpeed);
    state = state.copyWith(temporarySpeedActive: false);
    _updateMediaSession();
    _broadcastSpeed(settings.playbackSpeed);
  }

  double _effectivePlaybackSpeed(PlayerSettings settings) {
    if (_temporarySpeedHolds <= 0) return settings.playbackSpeed;
    return settings.playbackSpeed + _temporaryPlaybackSpeedBoost;
  }

  Future<void> setVolume(double volume) async {
    final double effective = effectivePlayerOutputVolume(
      configuredVolume: volume,
      systemVolumeOnly: _usesSystemVolumeOnly,
    );
    await state.engine?.setVolume(effective);
    await ref.read(playerSettingsProvider.notifier).setVolume(effective);
    state = state.copyWith();
  }

  Future<void> toggleMute() async {
    final PlayerSettings settings = await ref.read(
      playerSettingsProvider.future,
    );
    final double current = (state.engine?.value.volume ?? settings.volume)
        .clamp(0.0, 1.0)
        .toDouble();
    await setVolume(current > 0 ? 0 : settings.lastAudibleVolume);
  }

  bool _autoplayForSourceChange(PlayerEngine? current) {
    return state.desiredPlaying || (current?.state.value.isPlaying ?? true);
  }

  void _persistCurrentStreamSelection() {
    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    if (item == null || server == null) return;
    final StreamQuality? quality = state.quality;
    unawaited(
      ref
          .read(streamSelectionPreferenceStoreProvider)
          .save(
            mediaType: item.mediaType,
            mediaId: item.id,
            preference: StreamSelectionPreference(
              serverId: server.id,
              serverTitle: server.name,
              qualityId: quality?.id ?? '',
              qualityLabel: quality?.label ?? '',
            ),
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> switchServer(MediaServer server) async {
    if (_suppressStreamControl) return;
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? current = state.engine;
    if (item == null) return;
    await _open(
      item: item,
      server: server,
      quality: _initialQuality(server),
      position: _currentPositionFor(current),
      autoplay: _autoplayForSourceChange(current),
      clearVoiceover: true,
    );
    _persistCurrentStreamSelection();
    _broadcastSourceChanged(userInitiated: true);
  }

  Future<void> switchQuality(StreamQuality quality) async {
    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final PlayerEngine? current = state.engine;
    if (item == null || server == null) return;
    await _open(
      item: item,
      server: server,
      quality: quality,
      position: _currentPositionFor(current),
      autoplay: _autoplayForSourceChange(current),
      voiceover: state.voiceover,
      subtitle: state.subtitle,
      preserveAspectRatio: current?.state.value.aspectRatio,
    );
    _persistCurrentStreamSelection();
  }

  Future<void> reloadWithBackend(PlayerBackend backend) async {
    await ref.read(playerSettingsProvider.notifier).setPlayerBackend(backend);

    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? quality = state.quality;
    final PlayerEngine? current = state.engine;
    if (item == null || server == null || quality == null) {
      return;
    }

    await _open(
      item: item,
      server: server,
      quality: quality,
      position: _currentPositionFor(current),
      autoplay: _autoplayForSourceChange(current),
      voiceover: state.voiceover,
      subtitle: state.subtitle,
      preserveAspectRatio: current?.state.value.aspectRatio,
      backendOverride: backend,
    );
  }

  Future<void> switchVoiceover(VoiceOverTrack voiceover) async {
    if (_suppressStreamControl) return;
    final MediaPlaybackItem? item = state.item;
    final MediaServer? currentServer = state.server;
    final PlayerEngine? current = state.engine;
    final String? voiceUrl = voiceover.url?.trim();
    if (item == null ||
        currentServer == null ||
        voiceUrl == null ||
        voiceUrl.isEmpty) {
      state = state.copyWith(voiceover: voiceover);
      _broadcastSourceChanged(userInitiated: true);
      return;
    }

    final MediaServer voiceServer = MediaServer(
      id: currentServer.id,
      name: currentServer.name,
      sourceName: currentServer.sourceName,
      url: voiceUrl,
      headers: voiceover.headers.isNotEmpty
          ? voiceover.headers
          : currentServer.headers,
      streamType: voiceover.streamType == StreamType.unknown
          ? currentServer.streamType
          : voiceover.streamType,
      qualities: voiceover.qualities.isNotEmpty
          ? voiceover.qualities
          : currentServer.qualities,
      voiceovers: currentServer.voiceovers,
      subtitles: voiceover.subtitles.isNotEmpty
          ? voiceover.subtitles
          : currentServer.subtitles,
    );
    await _open(
      item: item,
      server: voiceServer,
      quality: _initialQuality(voiceServer),
      position: _currentPositionFor(current),
      autoplay: _autoplayForSourceChange(current),
      voiceover: voiceover,
      subtitle: state.subtitle,
    );
    _broadcastSourceChanged(userInitiated: true);
  }

  Future<void> selectSubtitle(
    SubtitleTrack? subtitle,
    List<SubtitleCue> cues,
  ) async {
    state = state.copyWith(
      subtitle: subtitle,
      clearSubtitle: subtitle == null,
      subtitleCues: subtitle == null ? <SubtitleCue>[] : cues,
    );
  }

  Future<void> _autoSelectSubtitle(MediaServer server) async {
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if (!settings.subtitlesEnabled) return;
    final List<SubtitleTrack> tracks = server.subtitles;
    if (tracks.isEmpty) return;
    final String preferred = settings.preferredSubtitleLanguage.trim();
    final bool hasLocalTracks = tracks.any(isLocalSubtitleTrack);
    if (preferred.isEmpty && !hasLocalTracks) return;

    SubtitleTrack? best;
    if (preferred.isNotEmpty) {
      for (final SubtitleTrack t in tracks) {
        if (t.language == preferred || t.label == preferred) {
          best = t;
          break;
        }
      }
    }
    best ??= tracks.first;

    final List<SubtitleCue> cues = await loadSubtitleCues(best);
    if (state.subtitle == null) {
      state = state.copyWith(subtitle: best, subtitleCues: cues);
    } else {
      return;
    }
  }

  Future<void> retry() async {
    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? quality = state.quality;
    if (item == null || server == null || quality == null) return;
    _retryCount += 1;
    await Future<void>.delayed(
      Duration(milliseconds: 300 * _retryCount.clamp(1, 5)),
    );
    await _open(
      item: item,
      server: server,
      quality: quality,
      position: _currentPositionFor(state.engine),
      autoplay: true,
      subtitle: state.subtitle,
    );
  }

  Future<bool> skipTo(Duration target) async {
    if (_suppressSeekControl) return false;
    final PlayerEngine? engine = state.engine;
    if (engine == null) return false;
    final Duration from = _currentPositionFor(engine);
    final Duration duration = engine.state.value.duration;
    final Duration clampedTarget = _clampSeekPosition(target, duration);
    _clearResumeGuard();
    _clearInteractiveSeek();
    _beginManualSeekEofWindow(engine, clampedTarget);
    final int manualSeekEpoch = _manualSeekEpoch;
    // Skip jumps (notably the auto ED-skip, which lands on the episode end) must
    // feed completion detection like slider and gesture seeks do. Otherwise, jumping
    // past the end leaves the episode unwatched and never triggers auto-next.
    _setSeekPreview(engine, clampedTarget);
    bool seekCompleted = false;
    try {
      seekCompleted = await _seekEngineTo(
        engine,
        clampedTarget,
        reason: 'Skip seek',
      );
    } on Object catch (error) {
      // Native backends may reject stale skip targets during stream changes.
      if (kDebugMode) debugPrint('Skip seek failed: $error');
    }
    if (manualSeekEpoch == _manualSeekEpoch) {
      _manualSeekOperationActive = false;
    }
    if (!seekCompleted || state.engine != engine) {
      if (state.engine == engine && manualSeekEpoch == _manualSeekEpoch) {
        _resetManualSeekEofWindow();
      }
      if (state.engine == engine &&
          state.seekPreviewPosition == clampedTarget) {
        state = state.copyWith(clearSeekPreviewPosition: true);
      }
      return false;
    }
    _noteManualSeekTarget(clampedTarget, duration);
    _notePausedResumeTarget(engine, clampedTarget);
    _beginSeekSettle(engine, clampedTarget, from: from);
    if (engine.state.value.isCompleted) {
      _evaluatePlaybackProgress(engine);
    }
    state = state.copyWith(lastSkippedFrom: from);
    _undoTimer?.cancel();
    _undoTimer = Timer(
      const Duration(seconds: 5),
      () => state = state.copyWith(clearLastSkippedFrom: true),
    );
    _broadcastSeek(clampedTarget);
    return true;
  }

  Future<void> undoSkip() async {
    if (_suppressSeekControl) return;
    final Duration? from = state.lastSkippedFrom;
    if (from == null) return;
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    final Duration fromPosition = _currentPositionFor(engine);
    final Duration target = _clampSeekPosition(
      from,
      engine.state.value.duration,
    );
    _clearResumeGuard();
    _clearInteractiveSeek();
    _beginManualSeekEofWindow(engine, target);
    _notePausedResumeTarget(engine, target);
    _setSeekPreview(engine, target);
    bool seekCompleted = false;
    try {
      seekCompleted = await _seekEngineTo(engine, target, reason: 'Undo seek');
    } on Object catch (error) {
      // Ignore stale undo seeks while the player is being replaced.
      if (kDebugMode) debugPrint('Undo seek failed: $error');
    }
    if (!seekCompleted || state.engine != engine) {
      if (state.engine == engine && state.seekPreviewPosition == target) {
        state = state.copyWith(clearSeekPreviewPosition: true);
      }
      return;
    }
    _beginSeekSettle(engine, target, from: fromPosition);
    state = state.copyWith(clearLastSkippedFrom: true);
    _broadcastSeek(target);
  }

  void setControlsVisible(bool visible) =>
      state = state.copyWith(controlsVisible: visible);
  void hideControls({bool clearTransientChrome = false}) {
    if (clearTransientChrome) {
      _cancelSeekSettle(clearPreview: true);
    }
    state = state.copyWith(
      controlsVisible: false,
      clearSeekPreviewPosition: clearTransientChrome,
    );
  }

  void setLocked(bool locked) => state = state.copyWith(locked: locked);

  void _startProgressSaver() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final MediaPlaybackItem? item = state.item;
      final PlayerEngine? engine = state.engine;
      if (item == null || engine == null || !engine.state.value.isInitialized) {
        return;
      }
      // Keep the high-water mark fresh even if the engine listener stopped
      // emitting, so completion is validated correctly on this fallback path.
      _trackMaxObservedPosition(engine);
      if (!item.ignoreProgress) {
        await _saveProgress(item, engine);
      }
      _updateMediaSession();
      if (item.ignoreProgress || _suppressGuestGlobalControl) {
        return;
      }
      // Fallback path. The engine listener (_watchPlaybackProgress) is the
      // primary, near-instant trigger; this keeps the overlay correct if a
      // backend stops emitting state changes after reaching the end.
      _evaluateAutoNextOverlay(engine);
    });
  }

  // Drives 85% auto-progress and end-of-stream auto-next directly off engine
  // state changes (~every 120ms) instead of the 5-second periodic saver, so a
  // seek to the end, a paused-on-completion backend, or one that snaps the final
  // position back to 0:00 can't make completion slip through the poll gap.
  void _watchPlaybackProgress(PlayerEngine engine, int generation) {
    late void Function() listener;
    listener = () {
      if (generation != _playbackGeneration ||
          !identical(state.engine, engine)) {
        engine.removeListener(listener);
        return;
      }
      _engineStateEventEpoch++;
      _evaluatePlaybackProgress(engine);
      _maybeStartProgressiveSeekPreviews();
    };
    engine.addListener(listener);
    _evaluatePlaybackProgress(engine);
    _maybeStartProgressiveSeekPreviews();
  }

  // Records the furthest point playback has genuinely reached. A lower reading
  // never lowers the mark, so an end-of-stream snap-back to 0:00 is ignored; a
  // glitchy overshoot past the reported duration is dropped too. The mark is the
  // evidence used by the shared completion oracle to tell a real end from a
  // premature EOF.
  void _trackMaxObservedPosition(PlayerEngine engine) {
    final PlayerEngineState es = engine.state.value;
    if (!es.isInitialized) return;
    final bool durationGrew = _durationEvidence.observe(es.duration);
    if (durationGrew) {
      _invalidateConfirmedEnd('authoritative duration grew');
    }
    if (_manualSeekRejectedBackendEofEpoch == _manualSeekEpoch &&
        !es.isCompleted) {
      _manualSeekRejectedBackendEofEpoch = null;
    }
    final Duration pos = es.position;
    final Duration dur = es.duration;
    if (pos > _maxObservedPosition &&
        !(dur > Duration.zero && pos > dur + const Duration(seconds: 5))) {
      _maxObservedPosition = pos;
    }
    final Duration? recoveryPosition = _prematureEofRecoveryNeedsProgressFrom;
    if (recoveryPosition != null &&
        _maxObservedPosition >= recoveryPosition + const Duration(seconds: 1)) {
      _prematureEofRecoveryAttempts = 0;
      _prematureEofRecoveryNeedsProgressFrom = null;
    }
  }

  PlaybackMediaKind _mediaKindForCurrentSource() {
    final MediaServer? server = state.server;
    if (server == null) return PlaybackMediaKind.direct;
    final StreamQuality? quality = state.quality;
    final String url = quality == null || quality.isAuto || quality.url.isEmpty
        ? server.url
        : quality.url;
    final StreamType type = _streamTypeForUrl(url, server.streamType);
    return type == StreamType.hls || type == StreamType.dash
        ? PlaybackMediaKind.segmented
        : PlaybackMediaKind.direct;
  }

  PlaybackEndEvaluation _playbackEndEvaluation(PlayerEngine engine) {
    final PlayerEngineState es = engine.state.value;
    final MediaServer? server = state.server;
    final PlaybackMediaKind mediaKind = _mediaKindForCurrentSource();
    final bool isOffline = server != null && _isOfflineLocalServer(server);
    return evaluatePlaybackEnd(
      backendCompleted: es.isCompleted,
      durationIsAuthoritative: _durationEvidence.isAuthoritative(
        isOffline: isOffline,
        mediaKind: mediaKind,
      ),
      mediaKind: mediaKind,
      position: es.position,
      maxObservedPosition: _maxObservedPosition,
      duration: _durationEvidence.maximum,
      watchedFraction: _watchedFraction,
    );
  }

  String _playbackEndSourceLabel() {
    final MediaServer? server = state.server;
    final bool offline = server != null && _isOfflineLocalServer(server);
    final StreamQuality? quality = state.quality;
    final String url = server == null
        ? ''
        : quality == null || quality.isAuto || quality.url.isEmpty
        ? server.url
        : quality.url;
    final StreamType type = server == null
        ? StreamType.unknown
        : _streamTypeForUrl(url, server.streamType);
    final String kind = switch (type) {
      StreamType.hls => 'hls',
      StreamType.dash => 'dash',
      _ => 'direct',
    };
    return '${offline ? 'offline' : 'online'}-$kind';
  }

  void _logPlaybackEnd(PlayerEngine engine, PlaybackEndEvaluation evaluation) {
    final int? durationSeconds = evaluation.authoritativeDuration?.inSeconds;
    final int? remainingSeconds = durationSeconds == null
        ? null
        : (durationSeconds - evaluation.observedPosition.inSeconds)
              .clamp(0, durationSeconds)
              .toInt();
    debugPrint(
      'PlaybackEnd: source=${_playbackEndSourceLabel()} '
      'backendCompleted=${engine.state.value.isCompleted} '
      'position=${engine.state.value.position.inSeconds}s '
      'maxObserved=${_maxObservedPosition.inSeconds}s '
      'duration=${durationSeconds == null ? 'unknown' : '${durationSeconds}s'} '
      'remaining=${remainingSeconds == null ? 'unknown' : '${remainingSeconds}s'} '
      'decision=${evaluation.decision.name}',
    );
  }

  void _invalidateConfirmedEnd(String reason) {
    final bool hadEndState =
        _reachedNearEnd || state.confirmedEnded || state.autoNextVisible;
    _reachedNearEnd = false;
    _autoNextOverlayTimer?.cancel();
    _autoNextOverlayTimer = null;
    if (state.confirmedEnded || state.autoNextVisible) {
      state = state.copyWith(confirmedEnded: false, autoNextVisible: false);
    }
    if (hadEndState) {
      debugPrint('[DEBUG] auto-next: confirmed end invalidated ($reason)');
    }
  }

  void _handlePrematureBackendEof(
    PlayerEngine engine,
    PlaybackEndEvaluation evaluation,
  ) {
    _invalidateConfirmedEnd(evaluation.decision.name);
    if (_manualSeekOwnsBackendEof(engine)) {
      _handleManualSeekBackendEof(engine, evaluation);
      return;
    }
    if (_manualSeekRejectedBackendEofEpoch == _manualSeekEpoch) {
      // The bounded manual-seek quarantine already classified this still-
      // latched END as stale. Do not turn it into a target rollback or source
      // reopen. A cleared backend END, a newer seek, or strict final-position
      // evidence re-arms the normal completion path.
      return;
    }
    if (_prematureEofRecoveryActive || _prematureEofRecoveryAttempts >= 1) {
      return;
    }
    unawaited(_recoverPrematureBackendEof(engine, evaluation));
  }

  void _handleManualSeekBackendEof(
    PlayerEngine engine,
    PlaybackEndEvaluation evaluation,
  ) {
    // Native END may remain asserted while a seek is pending or settling. It is
    // deliberately non-actionable: the requested target stays authoritative,
    // and no fallback seek, source reopen, or origin rollback is permitted.
    final String phase = _manualSeekOperationActive || _seekInFlight
        ? 'inFlight'
        : _settlingSeekEngine == engine
        ? 'settling'
        : 'quarantine';
    final String logKey =
        '$_manualSeekEpoch|$phase|${evaluation.decision.name}';
    if (kDebugMode && logKey != _lastManualSeekEofLogKey) {
      _lastManualSeekEofLogKey = logKey;
      debugPrint(
        'SeekEOF: epoch=$_manualSeekEpoch state=$phase '
        'target=${_manualSeekEofTarget?.inSeconds}s '
        'backendEnd=${engine.state.value.isCompleted} action=suppress '
        'decision=${evaluation.decision.name}',
      );
    }
    if (state.confirmedEnded || state.autoNextVisible) {
      state = state.copyWith(confirmedEnded: false, autoNextVisible: false);
    }
  }

  bool _manualSeekHasPostSettleEndEvidence(PlayerEngine engine) {
    final int? settledAfter = _manualSeekSettledAfterEngineEvent;
    return identical(state.engine, engine) &&
        _manualSeekEofEpoch == _manualSeekEpoch &&
        settledAfter != null &&
        _engineStateEventEpoch > settledAfter;
  }

  bool _isCurrentEofRecovery(
    PlayerEngine engine,
    int generation,
    int manualSeekEpoch,
  ) {
    return generation == _playbackGeneration &&
        manualSeekEpoch == _manualSeekEpoch &&
        identical(state.engine, engine);
  }

  Future<void> _recoverPrematureBackendEof(
    PlayerEngine engine,
    PlaybackEndEvaluation evaluation,
  ) async {
    if (_prematureEofRecoveryActive || !identical(state.engine, engine)) {
      return;
    }
    _prematureEofRecoveryActive = true;
    final int generation = _playbackGeneration;
    final int manualSeekEpoch = _manualSeekEpoch;
    _prematureEofRecoveryAttempts = 1;
    // Re-assert the last authoritative position exactly. Recovery must never
    // move playback behind the user's latest target (the old target-minus-
    // several-seconds fallback looked like a seek rollback in real playback).
    final Duration resumeAt = evaluation.observedPosition;
    bool recoveryOperationFailed = false;
    _logPlaybackEnd(engine, evaluation);
    try {
      await engine.pause();
      if (!_isCurrentEofRecovery(engine, generation, manualSeekEpoch)) return;
      await engine.seekTo(resumeAt);
      if (!_isCurrentEofRecovery(engine, generation, manualSeekEpoch)) return;
      await engine.play();
      if (_isCurrentEofRecovery(engine, generation, manualSeekEpoch)) {
        state = state.copyWith(
          desiredPlaying: true,
          clearError: true,
          confirmedEnded: false,
          autoNextVisible: false,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    } on Object catch (error) {
      recoveryOperationFailed = true;
      if (kDebugMode) {
        debugPrint(
          'PlaybackRecovery: reason=premature-eof attempt=1/1 '
          'resume=${resumeAt.inSeconds}s success=false '
          'error=${error.runtimeType}',
        );
      }
    } finally {
      if (generation == _playbackGeneration &&
          identical(state.engine, engine)) {
        _prematureEofRecoveryActive = false;
        final bool stillCurrentSeek = manualSeekEpoch == _manualSeekEpoch;
        final PlayerEngineState value = engine.state.value;
        if (stillCurrentSeek && !recoveryOperationFailed && !value.hasError) {
          debugPrint(
            'PlaybackRecovery: reason=premature-eof attempt=1/1 '
            'resume=${resumeAt.inSeconds}s success=${!value.isCompleted}',
          );
        }
        if (stillCurrentSeek && !value.isCompleted && !value.hasError) {
          _prematureEofRecoveryNeedsProgressFrom = evaluation.observedPosition;
        }
        if (_queuedSeekTarget != null) {
          unawaited(_flushInteractiveSeek());
        } else if (!stillCurrentSeek && value.isCompleted) {
          _evaluatePlaybackProgress(engine);
        }
      }
    }
  }

  PlaybackEndEvaluation evaluateNativePlaybackEnd({
    required int positionMs,
    required int durationMs,
    required bool backendCompleted,
  }) {
    final Duration position = Duration(milliseconds: positionMs);
    final Duration duration = Duration(milliseconds: durationMs);
    if (position > _maxObservedPosition) {
      _maxObservedPosition = position;
    }
    return evaluatePlaybackEnd(
      backendCompleted: backendCompleted,
      durationIsAuthoritative: duration >= const Duration(seconds: 30),
      mediaKind: _mediaKindForCurrentSource(),
      position: position,
      maxObservedPosition: _maxObservedPosition,
      duration: duration,
      watchedFraction: _watchedFraction,
    );
  }

  void _evaluatePlaybackProgress(PlayerEngine engine) {
    final MediaPlaybackItem? item = state.item;
    if (item == null || item.ignoreProgress) return;
    final PlayerEngineState es = engine.state.value;
    if (!es.isInitialized) return;

    _trackMaxObservedPosition(engine);
    final PlaybackEndEvaluation end = _playbackEndEvaluation(engine);
    _expireManualSeekEofQuarantineIfDue(engine, end);
    // (1) Auto-progress: mark the episode watched the instant playback crosses
    // 85%, independent of ever reaching the very end. This is what makes the
    // watched mark + AniList sync fire mid-playback instead of only on exit.
    if (end.watchedThresholdReached && !_autoProgressMarked) {
      _autoProgressMarked = true;
      debugPrint(
        '[DEBUG] auto-progress: 85% reached at '
        '${end.observedPosition.inSeconds}s/'
        '${end.authoritativeDuration?.inSeconds}s -> marking watched',
      );
      if (!_suppressGuestGlobalControl) {
        try {
          _prepareNextEpisodeHandler?.call();
        } on Object catch (error) {
          debugPrint(
            'OnlineNext: preparation callback failed: ${error.runtimeType}',
          );
        }
      }
      unawaited(_saveProgress(item, engine));
    }

    // (2) End-of-stream latch: the moment the backend reports completion (or the
    // position crosses into the final seconds) persist the episode as watched so
    // a seek-to-end or a 0:00 position-snap can never hide completion. The
    // completion signal is validated against real progress so a premature EOF on
    // a bad/reloaded stream can't latch the end minutes early.
    if (_manualSeekOwnsBackendEof(engine)) {
      if (end.confirmedEnded && _manualSeekHasPostSettleEndEvidence(engine)) {
        // This is a later backend event after the accepted seek settled. The
        // native engine or strict position oracle has re-armed completion, so
        // end evaluation may now proceed normally.
        _resetManualSeekEofWindow();
      } else if (es.isCompleted || end.confirmedEnded) {
        _handleManualSeekBackendEof(engine, end);
        return;
      }
    }
    if ((end.decision == PlaybackEndDecision.prematureBackendEof ||
            end.decision == PlaybackEndDecision.durationUnreliable) &&
        es.isCompleted) {
      _handlePrematureBackendEof(engine, end);
      return;
    }
    if (end.confirmedEnded && !_reachedNearEnd) {
      _reachedNearEnd = true;
      _prematureEofRecoveryAttempts = 0;
      state = state.copyWith(confirmedEnded: true);
      _logPlaybackEnd(engine, end);
      debugPrint(
        '[DEBUG] auto-next: end latched (isCompleted=${es.isCompleted} '
        'pos=${es.position.inSeconds}s max=${_maxObservedPosition.inSeconds}s '
        'dur=${end.authoritativeDuration?.inSeconds}s)',
      );
      unawaited(_saveProgress(item, engine));
    }

    // (3) Surface the auto-next overlay using the configured thresholds.
    _evaluateAutoNextOverlay(engine);
  }

  // Shows / hides the auto-next overlay based on the current settings and how
  // close playback is to the end. Shared by the engine listener and the
  // periodic saver so both paths stay in lockstep.
  void _evaluateAutoNextOverlay(PlayerEngine engine) {
    final MediaPlaybackItem? item = state.item;
    if (item == null || item.ignoreProgress) return;
    if (_suppressGuestGlobalControl) {
      _autoNextOverlayTimer?.cancel();
      _autoNextOverlayTimer = null;
      if (state.autoNextVisible) {
        state = state.copyWith(autoNextVisible: false);
      }
      return;
    }
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final bool showNextOverlay =
        settings.autoplayNext || settings.showNextEpisodeButton;
    if (showNextOverlay && !state.autoNextVisible && !_autoNextDismissed) {
      final bool shouldShow = state.confirmedEnded && _reachedNearEnd;
      if (shouldShow) {
        debugPrint('AutoNext: confirmedEnd=true overlay=eligible');
        debugPrint(
          '[DEBUG] auto-next: trigger reached (confirmed=true '
          'autoplay=${settings.autoplayNext})',
        );
        if (settings.autoplayNext) {
          // Auto-play advances on its own 5s timer (no visible overlay), so
          // Surface the state immediately because there is nothing to ease in.
          _showAutoNextOverlay();
        } else {
          // Button mode: let the ending breathe, then ease the overlay in.
          _scheduleAutoNextOverlay();
        }
      } else {
        // The end condition no longer holds (e.g. the user sought back before
        // the delayed overlay appeared). Drop the pending appearance.
        _autoNextOverlayTimer?.cancel();
        _autoNextOverlayTimer = null;
      }
    } else if (!showNextOverlay) {
      _autoNextOverlayTimer?.cancel();
      _autoNextOverlayTimer = null;
      if (state.autoNextVisible) {
        state = state.copyWith(autoNextVisible: false);
      }
    }
  }

  // Surfaces the auto-next overlay now, unless it was already dismissed for this
  // episode. Clears any pending delayed appearance.
  void _showAutoNextOverlay() {
    _autoNextOverlayTimer?.cancel();
    _autoNextOverlayTimer = null;
    if (_suppressGuestGlobalControl ||
        _autoNextDismissed ||
        state.autoNextVisible ||
        !state.confirmedEnded) {
      return;
    }
    debugPrint('[DEBUG] auto-next: overlay shown');
    state = state.copyWith(autoNextVisible: true);
  }

  // Surfaces the auto-next overlay after [_autoNextOverlayDelay]. Idempotent:
  // repeated calls while the timer is pending (every engine tick) are no-ops.
  void _scheduleAutoNextOverlay() {
    if (_suppressGuestGlobalControl ||
        _autoNextOverlayTimer != null ||
        _autoNextDismissed ||
        state.autoNextVisible ||
        !state.confirmedEnded) {
      return;
    }
    final int generation = _playbackGeneration;
    _autoNextOverlayTimer = Timer(_autoNextOverlayDelay, () {
      _autoNextOverlayTimer = null;
      if (generation != _playbackGeneration || !state.confirmedEnded) return;
      _showAutoNextOverlay();
    });
  }

  void dismissAutoNext() {
    _autoNextDismissed = true;
    _autoNextOverlayTimer?.cancel();
    _autoNextOverlayTimer = null;
    state = state.copyWith(autoNextVisible: false);
  }

  Future<void> _saveProgress(
    MediaPlaybackItem item,
    PlayerEngine engine,
  ) async {
    if (item.ignoreProgress || !ref.mounted) return;

    final PlayerEngineState engineState = engine.state.value;
    _trackMaxObservedPosition(engine);
    final bool hasPendingSeekTarget =
        (_queuedSeekEngine == engine && _queuedSeekTarget != null) ||
        (_settlingSeekEngine == engine && _settlingSeekTarget != null);
    Duration position = _currentPositionFor(engine);
    if (!hasPendingSeekTarget &&
        position <= const Duration(seconds: 1) &&
        _maxObservedPosition > position) {
      position = _maxObservedPosition;
    }
    if (!engineState.isInitialized &&
        position <= const Duration(seconds: 1) &&
        !_reachedNearEnd &&
        !_autoProgressMarked) {
      return;
    }

    final PlaybackEndEvaluation end = _playbackEndEvaluation(engine);
    // A watched mark at 85% is intentionally not completion. Resume resets to
    // zero only after the strict end decision was latched for this generation.
    final bool engineCompleted = end.confirmedEnded && _reachedNearEnd;
    final DateTime? guardUntil = _resumeGuardUntil;
    if (!engineCompleted &&
        guardUntil != null &&
        DateTime.now().isBefore(guardUntil)) {
      if (position + const Duration(seconds: 2) < _resumeGuardPosition) {
        return;
      }
      _resumeGuardUntil = null;
    }

    // When the backend signals end-of-stream the reported position can snap
    // back to 0:00, so don't bail out on the early-position guard in that case.
    if (!engineCompleted && position <= const Duration(seconds: 1)) {
      return;
    }

    final int? durationSeconds = end.authoritativeDuration?.inSeconds;

    // The episode counts as watched once playback crosses 85% (the common
    // anime convention) or the backend reports end-of-stream. Latched in
    // [_autoProgressMarked] so a later periodic save can never clear it back to
    // unwatched while the final 15% (ED/credits) is still playing.
    final bool reachedWatchedFraction = end.watchedThresholdReached;
    final bool watched =
        engineCompleted || reachedWatchedFraction || _autoProgressMarked;

    // Only snap the resume point back to 0:00 once the stream is essentially
    // finished. When we mark "watched" early (at 85%) the real position is kept
    // so reopening resumes in the final stretch instead of restarting.
    final bool resetToStart = engineCompleted;
    final int savePosition = resetToStart ? 0 : position.inSeconds;
    final int? savedDurationSeconds = durationSeconds;

    for (final String mediaId in _progressMediaIds(item)) {
      if (!ref.mounted) return;
      await ref
          .read(localLibraryProvider.notifier)
          .saveEpisodeProgress(
            mediaId: mediaId,
            season: item.seasonNumber,
            episode: item.episodeNumber,
            positionSeconds: savePosition,
            durationSeconds: savedDurationSeconds,
            completed: watched,
          );
    }

    if (!ref.mounted) return;
    unawaited(
      ref
          .read(localLibraryProvider.notifier)
          .updateWatchProgress(
            mediaId: item.id,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            positionFraction: watched
                ? 1.0
                : (durationSeconds != null && durationSeconds > 0
                      ? position.inSeconds / durationSeconds
                      : null),
          ),
    );

    if (!ref.mounted) return;
    final bool syncEnabled =
        (ref.read(playerSettingsProvider).value ?? const PlayerSettings())
            .autoAnilistSync;
    if (syncEnabled && watched) {
      unawaited(_trySyncAniList(item, item.episodeNumber.round()));
      // Fan out the same progress to any connected secondary trackers (MAL /
      // Shikimori). The coordinator no-ops when those services are signed out
      // or the item lacks a MAL id, so this is safe regardless of catalog mode.
      // Also drain any edits queued while offline (cheap when the queue is
      // empty) so syncing recovers even when AniList stays the primary source.
      final TrackerSyncCoordinator coordinator = ref.read(
        trackerSyncCoordinatorProvider,
      );
      unawaited(coordinator.flushPending());
      unawaited(
        coordinator.pushEpisodeProgress(
          externalIds: item.externalIds,
          episode: item.episodeNumber.round(),
          total: item.episodeCount,
        ),
      );
    }
  }

  Future<void> _trySyncAniList(
    MediaPlaybackItem item,
    int episodeNumber,
  ) async {
    if (ref.read(catalogModeProvider) != CatalogMode.anilist) return;
    final String? anilistIdStr = _anilistIdOf(item);
    if (anilistIdStr == null) return;
    final int? anilistId = int.tryParse(anilistIdStr);
    if (anilistId == null || anilistId <= 0) return;

    final String syncKey = '$anilistId:$episodeNumber';
    if (_syncedToAnilist.contains(syncKey)) return;

    // Don't overwrite a higher AniList progress when the user re-watches an
    // older episode. Also capture total episode count for completion detection.
    final List<AniListAnimeListFolder> folders =
        ref.read(anilistAnimeListProvider).value ?? <AniListAnimeListFolder>[];
    int? totalEpisodes;
    for (final AniListAnimeListFolder folder in folders) {
      for (final AniListAnimeListEntry entry in folder.entries) {
        final int? entryId = int.tryParse(
          entry.mediaItem.externalIds['anilist'] ?? '',
        );
        if (entryId == anilistId) {
          totalEpisodes = entry.mediaItem.episodeCount;
          if (entry.progress >= episodeNumber) return;
          break;
        }
      }
    }

    // Mark completed when the user finishes the final episode.
    final AniListListStatus targetStatus =
        (totalEpisodes != null &&
            totalEpisodes > 0 &&
            episodeNumber >= totalEpisodes)
        ? AniListListStatus.completed
        : AniListListStatus.current;

    _syncedToAnilist.add(syncKey);

    final SettingsState settings = ref.read(settingsProvider);
    final String token = settings.anilistAccessToken.trim();
    if (token.isEmpty) return;

    try {
      final AniListApiClient client = AniListApiClient(accessToken: token);
      await client.updateProgress(
        mediaId: anilistId,
        progress: episodeNumber,
        status: targetStatus,
      );
      try {
        final AniListAnimeListEntry? updatedEntry = await client
            .fetchMediaListEntry(
              userId: settings.anilistViewerId,
              mediaId: anilistId,
            );
        if (updatedEntry == null) {
          ref
              .read(anilistAnimeListProvider.notifier)
              .updateEntryProgress(
                anilistId,
                episodeNumber,
                status: targetStatus,
              );
          invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
        } else {
          ref
              .read(anilistAnimeListProvider.notifier)
              .replaceEntry(mediaId: anilistId, entry: updatedEntry);
          invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
        }
      } catch (_) {
        ref
            .read(anilistAnimeListProvider.notifier)
            .updateEntryProgress(
              anilistId,
              episodeNumber,
              status: targetStatus,
            );
        invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
      }
    } catch (_) {
      await ref
          .read(anilistEditQueueProvider)
          .queueProgress(
            mediaId: anilistId,
            progress: episodeNumber,
            status: targetStatus,
          );
      ref
          .read(anilistAnimeListProvider.notifier)
          .updateEntryProgress(anilistId, episodeNumber, status: targetStatus);
      invalidateAniListAnimePreviewLibraryProvider(ref.invalidate);
    }
  }

  String? _anilistIdOf(MediaPlaybackItem item) {
    final String? fromExternal = item.externalIds['anilist'];
    if (fromExternal != null && fromExternal.isNotEmpty) return fromExternal;
    if (item.id.startsWith('anilist:')) return item.id.substring(8);
    return null;
  }
}
