// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/subtitle_parser.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../library/application/local_library_provider.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../../watch/domain/normalized_models.dart';
import '../data/discord_rpc_service.dart';
import '../data/media_session_service.dart';
import '../domain/player_models.dart';
import '../engine/local_hls_proxy.dart';
import '../engine/player_engine.dart';
import '../engine/player_engine_factory.dart';
import 'player_settings.dart';

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

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
    this.seekPreviewPosition,
    this.seekPreviewBufferedEnd,
    this.seekPreviewEngine,
    this.seekPreviewReady = false,
    this.temporarySpeedActive = false,
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
  final Duration? seekPreviewPosition;
  final Duration? seekPreviewBufferedEnd;
  final PlayerEngine? seekPreviewEngine;
  final bool seekPreviewReady;
  final bool temporarySpeedActive;

  PlaybackState copyWith({
    MediaPlaybackItem? item,
    PlayerEngine? engine,
    MediaServer? server,
    StreamQuality? quality,
    VoiceOverTrack? voiceover,
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
    Duration? seekPreviewPosition,
    Duration? seekPreviewBufferedEnd,
    PlayerEngine? seekPreviewEngine,
    bool? seekPreviewReady,
    bool clearSeekPreviewPosition = false,
    bool clearSeekPreviewBufferedEnd = false,
    bool clearSeekPreviewEngine = false,
    bool? temporarySpeedActive,
  }) {
    return PlaybackState(
      item: item ?? this.item,
      engine: engine ?? this.engine,
      server: server ?? this.server,
      quality: quality ?? this.quality,
      voiceover: voiceover ?? this.voiceover,
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
      seekPreviewPosition: clearSeekPreviewPosition
          ? null
          : seekPreviewPosition ?? this.seekPreviewPosition,
      seekPreviewBufferedEnd:
          clearSeekPreviewPosition || clearSeekPreviewBufferedEnd
          ? null
          : seekPreviewBufferedEnd ?? this.seekPreviewBufferedEnd,
      seekPreviewEngine: clearSeekPreviewEngine
          ? null
          : seekPreviewEngine ?? this.seekPreviewEngine,
      seekPreviewReady: clearSeekPreviewEngine
          ? false
          : seekPreviewReady ?? this.seekPreviewReady,
      temporarySpeedActive: temporarySpeedActive ?? this.temporarySpeedActive,
    );
  }
}

class _SeekPreviewSource {
  const _SeekPreviewSource({required this.source, required this.key});

  final PlayerSource source;
  final String key;
}

class PlaybackController extends Notifier<PlaybackState> {
  // Disabled for release: FVP/MDK can abort on macOS when creating a second
  // Flutter texture for a low-quality preview stream next to the main player.
  static const bool _seekPreviewStreamEnabled = false;
  static const Duration _interactiveSeekDelay = Duration(milliseconds: 180);
  static const Duration _seekPreviewDebounce = Duration(milliseconds: 220);
  static const Duration _seekPreviewMinStep = Duration(seconds: 3);
  static const Duration _seekPreviewOpenTimeout = Duration(milliseconds: 1800);
  static const Duration _seekPreviewFrameHold = Duration(milliseconds: 180);
  static const Duration _seekPreviewWarmupDelay = Duration(milliseconds: 650);
  static const Duration _seekPreviewWarmupFrameHold = Duration(
    milliseconds: 700,
  );
  static const Duration _seekPreviewWarmupInterval = Duration(seconds: 25);
  static const Duration _seekPreviewSettleTimeout = Duration(milliseconds: 900);
  static const Duration _seekPreviewTargetTolerance = Duration(
    milliseconds: 1500,
  );
  static const Duration _seekSettleTick = Duration(milliseconds: 80);
  static const Duration _seekSettleMinHold = Duration(milliseconds: 700);
  static const Duration _seekSettleTimeout = Duration(milliseconds: 5000);
  static const Duration _seekSettleTolerance = Duration(milliseconds: 1200);
  static const Duration _engineOpenTimeout = Duration(seconds: 45);
  static const double _temporaryPlaybackSpeedBoost = 1.0;
  // Fraction of an episode that counts as "watched". Matches the common anime
  // convention where the last ~15% is the ED/credits + next-episode preview, so
  // progress is committed before the stream actually reaches the end.
  static const double _watchedFraction = 0.85;

  Timer? _progressTimer;
  Timer? _undoTimer;
  // Latched when the user seeks to (or plays past) the very end of a reliable
  // stream. Some backends snap the reported position back to 0:00 at
  // end-of-stream, which would otherwise hide completion from both the progress
  // saver (episode never marked watched) and the auto-next trigger.
  bool _reachedNearEnd = false;
  // Latched once the current episode crosses the watched threshold (85%). The
  // engine listener fires on every position tick, so this guarantees the
  // watched mark + AniList sync run exactly once and can't be cleared by a
  // later periodic save.
  bool _autoProgressMarked = false;
  Timer? _interactiveSeekTimer;
  Timer? _seekPreviewTimer;
  Timer? _seekPreviewWarmupTimer;
  Timer? _seekSettleTimer;
  int _retryCount = 0;
  int _playbackGeneration = 0;
  final Set<String> _autoFallbackTriedServers = <String>{};
  final Set<String> _autoFallbackTriedQualities = <String>{};
  int _seekPreviewGeneration = 0;
  int _manualSeekEpoch = 0;
  Duration _resumeGuardPosition = Duration.zero;
  DateTime? _resumeGuardUntil;
  PlayerEngine? _queuedSeekEngine;
  Duration? _queuedSeekTarget;
  bool _seekInFlight = false;
  PlayerEngine? _seekPreviewEngine;
  String? _seekPreviewSourceKey;
  Duration? _pendingSeekPreviewTarget;
  Duration? _lastSeekPreviewTarget;
  bool _seekPreviewInFlight = false;
  bool _seekPreviewScrubbing = false;
  DateTime _nextSeekPreviewWarmupAt = DateTime.fromMillisecondsSinceEpoch(0);
  PlayerEngine? _settlingSeekEngine;
  Duration? _settlingSeekTarget;
  DateTime? _settlingSeekUntil;
  DateTime? _settlingSeekEarliestClear;
  int _temporarySpeedHolds = 0;
  final Set<String> _syncedToAnilist = <String>{};

  void Function()? _nextEpisodeHandler;

  @override
  PlaybackState build() {
    MediaSessionService.init(
      onPlay: () {
        final PlayerEngine? e = state.engine;
        if (e != null && !e.state.value.isPlaying) {
          unawaited(e.play());
          state = state.copyWith();
          _updateMediaSession();
        }
      },
      onPause: () {
        final PlayerEngine? e = state.engine;
        if (e != null && e.state.value.isPlaying) {
          unawaited(e.pause());
          state = state.copyWith();
          _updateMediaSession();
        }
      },
      onTogglePlay: () => unawaited(togglePlay()),
      onNext: () => _nextEpisodeHandler?.call(),
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
    });
    ref.onDispose(() {
      _playbackGeneration++;
      _progressTimer?.cancel();
      _undoTimer?.cancel();
      _interactiveSeekTimer?.cancel();
      _seekPreviewTimer?.cancel();
      _seekPreviewWarmupTimer?.cancel();
      _seekSettleTimer?.cancel();
      unawaited(DiscordRpcService.dispose());
      unawaited(_disposeSeekPreviewEngine(clearState: false));
      final PlayerEngine? engine = state.engine;
      if (engine != null) {
        unawaited(engine.dispose());
      }
    });
    return const PlaybackState();
  }

  void setNextEpisodeHandler(void Function()? handler) {
    _nextEpisodeHandler = handler;
  }

  void _updateMediaSession() {
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    if (item == null || engine == null || !engine.state.value.isInitialized) {
      unawaited(MediaSessionService.clearNowPlaying());
      unawaited(DiscordRpcService.clearActivity());
      return;
    }
    final PlayerEngineState es = engine.state.value;
    final String sub = item.subtitle.isNotEmpty
        ? item.subtitle
        : (item.episodeNumber > 0
              ? 'Episode ${item.episodeNumber.toInt()}'
              : '');
    unawaited(
      MediaSessionService.updateNowPlaying(
        title: item.title,
        subtitle: sub,
        artworkUrl: item.posterUrl,
        position: es.position,
        duration: es.duration,
        isPlaying: es.isPlaying,
        playbackRate: es.playbackSpeed,
        hasNext: _nextEpisodeHandler != null,
      ),
    );
    unawaited(_updateDiscordRpc(item, es));
  }

  Future<void> _updateDiscordRpc(
    MediaPlaybackItem item,
    PlayerEngineState engineState,
  ) async {
    final SettingsState settings = ref.read(settingsProvider);
    final PlayerSettings playerSettings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await DiscordRpcService.configure(
      appEnabled: settings.discordRpcEnabled,
      playerEnabled: playerSettings.discordRpcEnabled,
    );
    final String rpcTitle = _discordTitle(item);
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
        isPlaying: engineState.isPlaying,
      ),
    );
  }

  String _discordTitle(MediaPlaybackItem item) {
    for (final String value in <String>[
      item.externalIds['mirushin_metadata_title'] ?? '',
      item.title,
      item.originalTitle,
    ]) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return item.title;
  }

  String _discordViewUrl(MediaPlaybackItem item) {
    final String? aniListId = item.externalIds['anilist'];
    if (aniListId != null && aniListId.isNotEmpty) {
      return 'https://anilist.co/anime/$aniListId';
    }

    final String? tmdbId = item.externalIds['tmdb'];
    if (tmdbId != null && tmdbId.isNotEmpty) {
      final String path = item.mediaType == MediaType.movie ? 'movie' : 'tv';
      return 'https://www.themoviedb.org/$path/$tmdbId';
    }

    final String query = Uri.encodeComponent(_discordTitle(item));
    final String searchPath = item.mediaType == MediaType.movie
        ? 'movie'
        : 'tv';
    return 'https://www.themoviedb.org/search/$searchPath?query=$query';
  }

  Future<void> load(MediaPlaybackItem item) async {
    print(
      '[DEBUG] load: S${item.seasonNumber}E${item.episodeNumber} ignoreProgress=${item.ignoreProgress}',
    );
    _progressTimer?.cancel();
    _undoTimer?.cancel();
    _reachedNearEnd = false;
    _autoProgressMarked = false;
    _clearInteractiveSeek();
    if (state.autoNextVisible ||
        state.lastSkippedFrom != null ||
        state.seekPreviewPosition != null ||
        state.seekPreviewEngine != null) {
      state = state.copyWith(
        autoNextVisible: false,
        clearLastSkippedFrom: true,
        clearSeekPreviewPosition: true,
        clearSeekPreviewEngine: true,
      );
    }
    if (item.servers.isEmpty) {
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
    final StreamQuality quality = _initialQuality(server);
    final EpisodeProgress? prog = item.ignoreProgress
        ? null
        : await _loadProgressForItem(item);
    final Duration startPos = _safeResumePosition(item, prog);
    await _open(
      item: item,
      server: server,
      quality: quality,
      position: startPos,
      autoplay: true,
    );
  }

  Future<EpisodeProgress?> _loadProgressForItem(MediaPlaybackItem item) async {
    EpisodeProgress? best;

    final List<String> ids = _progressMediaIds(item);
    print(
      '[DEBUG] _loadProgressForItem: ids=$ids S${item.seasonNumber}E${item.episodeNumber}',
    );

    for (final String mediaId in ids) {
      final EpisodeProgress? progress = await ref
          .read(localLibraryProvider.notifier)
          .loadEpisodeProgress(mediaId, item.seasonNumber, item.episodeNumber);

      print(
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

    print(
      '[DEBUG] _loadProgressForItem: best=${best == null ? 'null' : 'pos=${best.positionSeconds}s'}',
    );
    return best;
  }

  Duration _safeResumePosition(
    MediaPlaybackItem item,
    EpisodeProgress? progress,
  ) {
    final int savedSeconds = progress?.positionSeconds ?? 0;
    // A finished episode is reset to 0:00 on save, so it restarts fresh. But an
    // episode marked watched early (at 85%) keeps its real position — reopen in
    // the final stretch instead of jumping back to the beginning.
    if (progress?.completed == true && savedSeconds <= 0) {
      print('[DEBUG] _safeResumePosition: completed=true -> 0');
      return Duration.zero;
    }
    final Duration saved = savedSeconds > 0
        ? Duration(seconds: savedSeconds)
        : Duration.zero;
    final Duration start = saved > item.startPosition
        ? saved
        : item.startPosition;

    print(
      '[DEBUG] _safeResumePosition: savedSeconds=$savedSeconds item.startPosition=${item.startPosition} -> start=$start',
    );

    final int? durationSeconds = progress?.durationSeconds;
    if (durationSeconds != null && durationSeconds > 0) {
      final Duration duration = Duration(seconds: durationSeconds);
      if (start >= duration - const Duration(seconds: 20)) {
        print('[DEBUG] _safeResumePosition: near end -> 0');
        return Duration.zero;
      }
    }

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
    SubtitleTrack? subtitle,
    double? preserveAspectRatio,
    bool isAutoFallback = false,
    PlayerBackend? backendOverride,
    bool allowSourceFallback = true,
    bool disableProxy = false,
  }) async {
    if (!isAutoFallback) {
      _autoFallbackTriedServers.clear();
      _autoFallbackTriedQualities.clear();
    }
    _progressTimer?.cancel();
    _undoTimer?.cancel();
    final int generation = ++_playbackGeneration;
    _clearInteractiveSeek();
    unawaited(_disposeSeekPreviewEngine());
    _resumeGuardPosition = position;
    _resumeGuardUntil = position > const Duration(seconds: 3)
        ? DateTime.now().add(const Duration(seconds: 15))
        : null;
    final PlayerEngine? previous = state.engine;
    state = state.copyWith(
      item: item,
      server: server,
      quality: quality,
      voiceover: voiceover,
      subtitle: subtitle,
      clearSubtitle: subtitle == null,
      subtitleCues: subtitle == null ? const <SubtitleCue>[] : null,
      loading: true,
      controlsVisible: true,
      autoNextVisible: false,
      clearError: true,
      clearLastSkippedFrom: true,
      clearSeekPreviewPosition: true,
      clearSeekPreviewEngine: true,
      temporarySpeedActive: false,
    );
    if (subtitle == null) unawaited(_autoSelectSubtitle(server));

    final String url = quality.isAuto || quality.url.isEmpty
        ? server.url
        : quality.url;
    final StreamType streamType = _streamTypeForUrl(url, server.streamType);
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final bool youtubeEmbed = _isYoutubeTrailerServer(server);
    final PlayerBackend backend = youtubeEmbed
        ? PlayerBackend.auto
        : backendOverride ?? settings.playerBackend;
    final PlayerBackend engineBackend = resolvePlayerEngineBackend(backend);
    final PlayerEngine engine = createPlayerEngine(
      initialAspectRatio: _safeAspectRatio(preserveAspectRatio),
      backend: engineBackend,
      youtubeEmbed: youtubeEmbed,
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
            ),
            startAt: position,
            autoplay: false,
          )
          .timeout(_engineOpenTimeout);
      if (generation != _playbackGeneration) {
        await engine.dispose();
        return;
      }
      await engine.setPlaybackSpeed(_effectivePlaybackSpeed(settings));
      await engine.setVolume(settings.volume);
      if (autoplay) await engine.play();
      if (generation != _playbackGeneration) {
        await engine.pause();
        await engine.dispose();
        return;
      }
      await previous?.dispose();
      state = state.copyWith(engine: engine, loading: false, clearError: true);
      _retryCount = 0;
      _updateMediaSession();
      _startProgressSaver();
      _watchPlaybackProgress(engine, generation);
      _reinforceInitialSeek(engine, position, generation, _manualSeekEpoch);
      _guardFreshStart(engine, position, generation, _manualSeekEpoch);
      _watchEngineErrors(
        engine,
        generation,
        engineBackend,
        proxyDisabled: disableProxy,
        allowSourceFallback: allowSourceFallback,
      );
      if (_seekPreviewStreamEnabled) {
        _scheduleSeekPreviewWarmup(position);
      }
    } on Object catch (error) {
      final Duration fallbackPosition = _fallbackPositionFor(
        engine,
        requestedPosition: position,
      );
      final bool fallbackAutoplay = autoplay || engine.state.value.isPlaying;
      final double? fallbackAspectRatio = _safeAspectRatio(
        engine.state.value.aspectRatio,
      );
      await engine.dispose();
      if (generation != _playbackGeneration) return;
      if (youtubeEmbed) {
        debugPrint('YouTube trailer WebView open failed: $error');
        state = state.copyWith(
          engine: previous,
          loading: false,
          error: PlayerError(
            title: 'Trailer failed',
            message: error.toString(),
            canRetry: true,
          ),
        );
        return;
      }
      if (_tryDirectAfterProxyFallback(
        failedBackend: engineBackend,
        proxyDisabled: disableProxy,
        position: fallbackPosition,
        autoplay: fallbackAutoplay,
        preserveAspectRatio: fallbackAspectRatio ?? preserveAspectRatio,
      )) {
        return;
      }
      if (_tryAutoBackendFallback(
        failedBackend: engineBackend,
        position: fallbackPosition,
        autoplay: fallbackAutoplay,
        preserveAspectRatio: fallbackAspectRatio ?? preserveAspectRatio,
      )) {
        return;
      }
      if (_tryAutoFallbackQuality(
        position: fallbackPosition,
        autoplay: fallbackAutoplay,
        preserveAspectRatio: fallbackAspectRatio ?? preserveAspectRatio,
        backendOverride: engineBackend,
      )) {
        return;
      }
      if (allowSourceFallback &&
          _tryAutoFallbackServer(requestedPosition: fallbackPosition)) {
        return;
      }
      state = state.copyWith(
        engine: previous,
        loading: false,
        error: PlayerError(title: 'Stream failed', message: error.toString()),
      );
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
    for (final Duration delay in const <Duration>[
      Duration(milliseconds: 1800),
      Duration(milliseconds: 2500),
      Duration(milliseconds: 4000),
    ]) {
      await Future<void>.delayed(delay);
      if (generation != _playbackGeneration ||
          manualSeekEpoch != _manualSeekEpoch ||
          state.engine != engine) {
        return;
      }

      if (_initialSeekAccepted(engine, position)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (generation != _playbackGeneration ||
          manualSeekEpoch != _manualSeekEpoch ||
          state.engine != engine ||
          _initialSeekAccepted(engine, position)) {
        return;
      }

      final PlayerEngineState value = engine.state.value;
      if (!value.isInitialized) continue;

      try {
        await engine.seekTo(position);
      } on Object {
        // Some native backends reject an early startup seek. Later loop ticks
        // can retry if the stream is still behind the saved resume point.
      }
      state = state.copyWith();
    }
  }

  bool _initialSeekAccepted(PlayerEngine engine, Duration position) {
    final PlayerEngineState value = engine.state.value;
    if (!value.isInitialized) return false;
    return value.position + const Duration(seconds: 3) >= position;
  }

  void _guardFreshStart(
    PlayerEngine engine,
    Duration requestedPosition,
    int generation,
    int manualSeekEpoch,
  ) {
    if (requestedPosition > const Duration(seconds: 1)) return;
    unawaited(
      _guardFreshStartFromInheritedPosition(
        engine,
        generation,
        manualSeekEpoch,
      ),
    );
  }

  Future<void> _guardFreshStartFromInheritedPosition(
    PlayerEngine engine,
    int generation,
    int manualSeekEpoch,
  ) async {
    for (final Duration delay in const <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1600),
    ]) {
      await Future<void>.delayed(delay);
      if (generation != _playbackGeneration ||
          manualSeekEpoch != _manualSeekEpoch ||
          state.engine != engine) {
        return;
      }

      final PlayerEngineState value = engine.state.value;
      if (!value.isInitialized) continue;

      final Duration position = value.position;
      if (position > const Duration(seconds: 5) &&
          position < const Duration(seconds: 30)) {
        try {
          await engine.seekTo(Duration.zero);
          state = state.copyWith();
        } on Object {
          // Startup guard should never break playback if the backend rejects
          // a defensive seek-to-zero.
        }
        return;
      }
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

  bool _tryDirectAfterProxyFallback({
    required PlayerBackend failedBackend,
    required bool proxyDisabled,
    required Duration position,
    required bool autoplay,
    double? preserveAspectRatio,
  }) {
    if (proxyDisabled) return false;

    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? quality = state.quality;
    if (item == null || server == null || quality == null) return false;
    if (_isYoutubeTrailerServer(server)) return false;

    final String url = _effectiveQualityUrl(server, quality);
    final Uri? uri = Uri.tryParse(url);
    final String scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme != 'http' && scheme != 'https') return false;

    debugPrint(
      'Playback proxy fallback: ${failedBackend.name.toUpperCase()} proxy failed; '
      'trying ${failedBackend.name.toUpperCase()} direct for ${server.name}.',
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
        isAutoFallback: true,
        backendOverride: failedBackend,
        allowSourceFallback: false,
        disableProxy: true,
      ),
    );
    return true;
  }

  bool _tryAutoBackendFallback({
    required PlayerBackend failedBackend,
    required Duration position,
    required bool autoplay,
    double? preserveAspectRatio,
  }) {
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if (settings.playerBackend != PlayerBackend.auto ||
        failedBackend != PlayerBackend.mpv) {
      return false;
    }

    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? quality = state.quality;
    if (item == null || server == null || quality == null) return false;
    if (_isYoutubeTrailerServer(server)) return false;

    debugPrint(
      'Playback auto backend fallback: MPV failed; trying FVP for ${server.name}.',
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
        isAutoFallback: true,
        backendOverride: PlayerBackend.fvp,
        allowSourceFallback: false,
      ),
    );
    return true;
  }

  bool _tryAutoFallbackQuality({
    required Duration position,
    required bool autoplay,
    double? preserveAspectRatio,
    PlayerBackend? backendOverride,
  }) {
    final MediaPlaybackItem? item = state.item;
    final MediaServer? server = state.server;
    final StreamQuality? current = state.quality;
    if (item == null || server == null || current == null) return false;
    if (_isYoutubeTrailerServer(server)) return false;
    if (server.qualities.length <= 1) return false;

    final String currentUrl = _effectiveQualityUrl(server, current);
    _autoFallbackTriedQualities.add(_qualityFallbackKey(server, current));

    final List<StreamQuality> explicitCandidates = <StreamQuality>[];
    final List<StreamQuality> autoCandidates = <StreamQuality>[];
    for (final StreamQuality quality in server.qualities) {
      final String url = _effectiveQualityUrl(server, quality);
      if (url.isEmpty || url == currentUrl) continue;
      if (_autoFallbackTriedQualities.contains(
        _qualityFallbackKey(server, quality),
      )) {
        continue;
      }
      if (quality.isAuto) {
        autoCandidates.add(quality);
      } else {
        explicitCandidates.add(quality);
      }
    }

    final List<StreamQuality> candidates = <StreamQuality>[
      ...explicitCandidates,
      ...autoCandidates,
    ];
    if (candidates.isEmpty) return false;

    final StreamQuality next = candidates.first;
    debugPrint(
      'Playback quality fallback: ${current.label} failed; trying ${next.label} for ${server.name}.',
    );
    unawaited(
      _open(
        item: item,
        server: server,
        quality: next,
        position: position,
        autoplay: autoplay,
        voiceover: state.voiceover,
        subtitle: state.subtitle,
        preserveAspectRatio: preserveAspectRatio,
        isAutoFallback: true,
        backendOverride: backendOverride,
        allowSourceFallback: false,
      ),
    );
    return true;
  }

  String _effectiveQualityUrl(MediaServer server, StreamQuality quality) {
    if (quality.isAuto || quality.url.trim().isEmpty) {
      return server.url.trim();
    }
    return quality.url.trim();
  }

  String _qualityFallbackKey(MediaServer server, StreamQuality quality) {
    return '${server.id}|${quality.id}|${_effectiveQualityUrl(server, quality)}';
  }

  bool _tryAutoFallbackServer({Duration requestedPosition = Duration.zero}) {
    final MediaPlaybackItem? item = state.item;
    final MediaServer? current = state.server;
    if (item == null || current == null) return false;
    if (_isYoutubeTrailerServer(current)) return false;
    _autoFallbackTriedServers.add(current.id);
    final Iterable<MediaServer> untried = item.servers.where(
      (MediaServer s) => !_autoFallbackTriedServers.contains(s.id),
    );
    if (untried.isEmpty) return false;
    final MediaServer next = untried.first;
    unawaited(
      _open(
        item: item,
        server: next,
        quality: _initialQuality(next),
        position: _fallbackPositionFor(
          state.engine,
          requestedPosition: requestedPosition,
        ),
        autoplay: true,
        subtitle: state.subtitle,
        isAutoFallback: true,
      ),
    );
    return true;
  }

  void _watchEngineErrors(
    PlayerEngine engine,
    int generation,
    PlayerBackend engineBackend, {
    required bool proxyDisabled,
    required bool allowSourceFallback,
  }) {
    late void Function() listener;
    listener = () {
      if (generation != _playbackGeneration ||
          !identical(state.engine, engine)) {
        engine.removeListener(listener);
        return;
      }
      if (engine.state.value.hasError && state.error == null) {
        engine.removeListener(listener);
        if (_tryDirectAfterProxyFallback(
          failedBackend: engineBackend,
          proxyDisabled: proxyDisabled,
          position: _fallbackPositionFor(engine),
          autoplay: engine.state.value.isPlaying,
          preserveAspectRatio: engine.state.value.aspectRatio,
        )) {
          return;
        }
        if (_tryAutoBackendFallback(
          failedBackend: engineBackend,
          position: _fallbackPositionFor(engine),
          autoplay: engine.state.value.isPlaying,
          preserveAspectRatio: engine.state.value.aspectRatio,
        )) {
          return;
        }
        if (_tryAutoFallbackQuality(
          position: _fallbackPositionFor(engine),
          autoplay: engine.state.value.isPlaying,
          preserveAspectRatio: engine.state.value.aspectRatio,
          backendOverride: engineBackend,
        )) {
          return;
        }
        if (allowSourceFallback &&
            _tryAutoFallbackServer(
              requestedPosition: _fallbackPositionFor(engine),
            )) {
          return;
        }
        state = state.copyWith(
          error: PlayerError(
            title: 'Playback error',
            message:
                engine.state.value.errorDescription ??
                'The stream failed to load.',
            canRetry: true,
          ),
        );
      }
    };
    engine.addListener(listener);
  }

  Future<void> stop() async {
    unawaited(MediaSessionService.clearNowPlaying());
    unawaited(DiscordRpcService.clearActivity());
    _playbackGeneration++;
    _temporarySpeedHolds = 0;
    _progressTimer?.cancel();
    _undoTimer?.cancel();
    _clearInteractiveSeek();
    await _disposeSeekPreviewEngine(clearState: false);

    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    state = const PlaybackState();
    if (engine == null) return;

    if (item != null && !item.ignoreProgress) {
      await _saveProgress(item, engine);
    }
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

  StreamQuality _initialQuality(MediaServer server) {
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if (server.qualities.isEmpty) return StreamQuality.auto;
    if (server.id == 'youtube-trailer') {
      return server.qualities.firstWhere(
        (StreamQuality q) => q.isAuto,
        orElse: () => server.qualities.first,
      );
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

  Future<void> pause() async {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isPlaying) return;
    await engine.pause();
    state = state.copyWith();
    _updateMediaSession();
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
    // Mirror the FVP/MPV path: watched at 85% (keep the real position), but only
    // snap the resume point to 0:00 once essentially finished.
    final bool reachedWatchedFraction =
        durationSeconds > 0 &&
        positionSeconds >= durationSeconds * _watchedFraction;
    final bool isNearEnd =
        durationSeconds > 0 && positionSeconds >= durationSeconds - 20;
    final bool resetToStart = completed || isNearEnd;
    final int savePosition = resetToStart ? 0 : positionSeconds;
    final bool saveCompleted = completed || isNearEnd || reachedWatchedFraction;

    // Latch the watched mark so a later FVP save can't clear it. Only latch
    // end-of-stream when genuinely finished — at 85% there is still ~15% left,
    // and _reachedNearEnd would otherwise pop the auto-next overlay on restore.
    if (saveCompleted) _autoProgressMarked = true;
    if (resetToStart) _reachedNearEnd = true;

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
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    if (_queuedSeekEngine == engine && _queuedSeekTarget != null) {
      unawaited(_flushInteractiveSeek());
    }
    engine.state.value.isPlaying ? await engine.pause() : await engine.play();
    state = state.copyWith();
    _updateMediaSession();
  }

  Future<void> seekBy(Duration offset, {Duration? flushDelay}) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration duration = engine.state.value.duration;
    final Duration target = _clampSeekPosition(
      _seekBaseFor(engine) + offset,
      duration,
    );
    _noteManualSeekTarget(target, duration);
    _queueInteractiveSeek(
      engine,
      target,
      delay: flushDelay ?? _interactiveSeekDelay,
    );
  }

  Future<void> seekTo(Duration position) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration duration = engine.state.value.duration;
    final Duration target = _clampSeekPosition(position, duration);
    _noteManualSeekTarget(target, duration);
    _queueInteractiveSeek(engine, target, delay: Duration.zero);
  }

  // Treat a seek to the last few seconds of a reliable stream as completion:
  // mark the episode watched right away (the backend may snap position back to
  // 0:00 at end-of-stream, hiding it from the periodic saver) and surface the
  // auto-next overlay. Seeking back well before the end clears the latch so a
  // re-watch doesn't instantly re-trigger completion.
  void _noteManualSeekTarget(Duration target, Duration duration) {
    if (duration < const Duration(minutes: 2)) return;
    if (target >= duration - const Duration(seconds: 3)) {
      if (_reachedNearEnd) return;
      _reachedNearEnd = true;
      _markCurrentCompleted(showNext: true);
    } else if (target < duration - const Duration(seconds: 30)) {
      _reachedNearEnd = false;
    }
  }

  /// Persist the current episode as watched immediately, bypassing the periodic
  /// saver. Used before auto-advancing and on seek-to-end so the episode is
  /// never left unwatched when the next one starts.
  Future<void> markCurrentEpisodeWatched() async {
    _reachedNearEnd = true;
    await _markCurrentCompleted(showNext: false);
  }

  Future<void> _markCurrentCompleted({required bool showNext}) async {
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    if (item == null || engine == null || item.ignoreProgress) return;
    await _saveProgress(item, engine);
    if (!showNext) return;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    if ((settings.autoplayNext || settings.showNextEpisodeButton) &&
        !state.autoNextVisible) {
      state = state.copyWith(autoNextVisible: true);
    }
  }

  void previewSeekTo(Duration position) {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration clamped = _clampSeekPosition(
      position,
      engine.state.value.duration,
    );
    _cancelSeekSettle(clearPreview: false);
    _setSeekPreview(engine, clamped);
    if (_seekPreviewStreamEnabled) {
      _queueSeekPreviewFrame(clamped);
    }
  }

  /// Start a slider preview session without touching the active playback engine.
  void beginSeekPreview() {
    _seekPreviewGeneration++;
    _seekPreviewScrubbing = true;
    _seekPreviewTimer?.cancel();
    _seekPreviewWarmupTimer?.cancel();
    _seekPreviewTimer = null;
    _seekPreviewWarmupTimer = null;
    _pendingSeekPreviewTarget = null;
    _lastSeekPreviewTarget = null;
  }

  /// End slider interaction while keeping real playback seek separate.
  void endSeekPreview() {
    _seekPreviewScrubbing = false;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreviewTarget = null;
    if (!_seekPreviewStreamEnabled) return;

    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;

    final Duration target = _clampSeekPosition(
      state.seekPreviewPosition ?? engine.state.value.position,
      engine.state.value.duration,
    );
    _scheduleSeekPreviewWarmup(target);
  }

  void _queueSeekPreviewFrame(Duration target) {
    if (!_seekPreviewStreamEnabled) return;
    _pendingSeekPreviewTarget = target;
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;

    if (!_shouldSeekPreviewFrame(target)) return;

    _seekPreviewTimer = Timer(
      _seekPreviewDebounce,
      () => unawaited(_flushSeekPreviewFrame()),
    );
  }

  bool _shouldSeekPreviewFrame(Duration target) {
    if (!_seekPreviewStreamEnabled) return false;
    final _SeekPreviewSource? source = _seekPreviewSourceForCurrentState();
    if (source == null) return false;
    if (_seekPreviewEngine == null || _seekPreviewSourceKey != source.key) {
      return true;
    }

    final Duration? lastTarget = _lastSeekPreviewTarget;
    if (lastTarget == null) return true;

    final int deltaMs = (target.inMilliseconds - lastTarget.inMilliseconds)
        .abs();
    return deltaMs >= _seekPreviewMinStep.inMilliseconds;
  }

  Future<void> _flushSeekPreviewFrame() async {
    if (!_seekPreviewStreamEnabled) return;
    if (_seekPreviewInFlight) {
      final Duration? pending = _pendingSeekPreviewTarget;
      if (pending != null && _shouldSeekPreviewFrame(pending)) {
        _seekPreviewTimer?.cancel();
        _seekPreviewTimer = Timer(
          _seekPreviewDebounce,
          () => unawaited(_flushSeekPreviewFrame()),
        );
      }
      return;
    }

    final Duration? target = _pendingSeekPreviewTarget;
    if (target == null || !_shouldSeekPreviewFrame(target)) {
      _pendingSeekPreviewTarget = null;
      return;
    }

    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreviewTarget = null;
    _seekPreviewInFlight = true;
    final int generation = _seekPreviewGeneration;

    try {
      final PlayerEngine? previewEngine = await _ensureSeekPreviewEngine(
        target,
        generation,
      );
      if (previewEngine == null ||
          generation != _seekPreviewGeneration ||
          _seekPreviewEngine != previewEngine) {
        return;
      }

      await previewEngine.setVolume(0);
      await _primeSeekPreviewFrame(previewEngine, target, generation);
      if (!_isActiveSeekPreview(previewEngine, generation)) return;
      _lastSeekPreviewTarget = target;
      if (state.seekPreviewEngine == previewEngine) {
        state = state.copyWith(
          seekPreviewEngine: previewEngine,
          seekPreviewReady: true,
        );
      }
    } on Object {
      // Slider previews should never interrupt real playback if the preview
      // decoder rejects a target or a provider URL.
    } finally {
      _seekPreviewInFlight = false;
      final Duration? nextTarget = _pendingSeekPreviewTarget;
      if (nextTarget != null && _shouldSeekPreviewFrame(nextTarget)) {
        _queueSeekPreviewFrame(nextTarget);
      } else if (!_seekPreviewScrubbing) {
        final PlayerEngine? engine = state.engine;
        if (engine != null && engine.state.value.isInitialized) {
          _scheduleSeekPreviewWarmup(engine.state.value.position);
        }
      }
    }
  }

  void _scheduleSeekPreviewWarmup(
    Duration position, {
    Duration delay = _seekPreviewWarmupDelay,
  }) {
    _seekPreviewWarmupTimer?.cancel();
    _seekPreviewWarmupTimer = null;
    if (!_seekPreviewStreamEnabled) return;
    if (_seekPreviewScrubbing) return;

    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;

    final Duration target = _clampSeekPosition(
      position,
      engine.state.value.duration,
    );
    _seekPreviewWarmupTimer = Timer(
      delay,
      () => unawaited(_warmSeekPreviewEngine(target)),
    );
  }

  void _maybeScheduleSeekPreviewWarmup(PlayerEngine engine) {
    if (!_seekPreviewStreamEnabled) return;
    if (_seekPreviewScrubbing || _seekPreviewInFlight) return;
    if (!engine.state.value.isPlaying) return;

    final DateTime now = DateTime.now();
    if (now.isBefore(_nextSeekPreviewWarmupAt)) return;

    _nextSeekPreviewWarmupAt = now.add(_seekPreviewWarmupInterval);
    _scheduleSeekPreviewWarmup(
      engine.state.value.position,
      delay: Duration.zero,
    );
  }

  Future<void> _warmSeekPreviewEngine(Duration position) async {
    if (!_seekPreviewStreamEnabled) return;
    if (_seekPreviewScrubbing || _seekPreviewInFlight) return;

    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;

    final Duration target = _clampSeekPosition(
      position,
      engine.state.value.duration,
    );
    _seekPreviewInFlight = true;
    final int generation = _seekPreviewGeneration;

    try {
      final PlayerEngine? previewEngine = await _ensureSeekPreviewEngine(
        target,
        generation,
      );
      if (previewEngine == null ||
          generation != _seekPreviewGeneration ||
          _seekPreviewEngine != previewEngine) {
        return;
      }

      await previewEngine.setVolume(0);
      await _primeSeekPreviewFrame(
        previewEngine,
        target,
        generation,
        hold: _seekPreviewWarmupFrameHold,
      );
      if (!_isActiveSeekPreview(previewEngine, generation)) return;
      _lastSeekPreviewTarget = target;
      if (state.seekPreviewEngine == previewEngine) {
        state = state.copyWith(
          seekPreviewEngine: previewEngine,
          seekPreviewReady: true,
        );
      }
    } on Object {
      // Background preview warmup is opportunistic; the main player must never
      // care if a low-quality variant rejects a seek.
    } finally {
      _seekPreviewInFlight = false;
      final Duration? nextTarget = _pendingSeekPreviewTarget;
      if (nextTarget != null && _shouldSeekPreviewFrame(nextTarget)) {
        _queueSeekPreviewFrame(nextTarget);
      }
    }
  }

  Future<PlayerEngine?> _ensureSeekPreviewEngine(
    Duration target,
    int generation,
  ) async {
    if (!_seekPreviewStreamEnabled) return null;
    final _SeekPreviewSource? previewSource =
        _seekPreviewSourceForCurrentState();
    if (previewSource == null) return null;

    final PlayerEngine? current = _seekPreviewEngine;
    if (current != null && _seekPreviewSourceKey == previewSource.key) {
      return current;
    }

    _lastSeekPreviewTarget = null;
    if (current != null) {
      unawaited(current.dispose());
    }

    final PlayerEngine? mainEngine = state.engine;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final PlayerEngine previewEngine = createPlayerEngine(
      initialAspectRatio: _safeAspectRatio(mainEngine?.state.value.aspectRatio),
      previewMode: true,
      backend: resolvePlayerEngineBackend(settings.playerBackend),
    );
    _seekPreviewEngine = previewEngine;
    _seekPreviewSourceKey = previewSource.key;
    state = state.copyWith(
      seekPreviewEngine: previewEngine,
      seekPreviewReady: false,
    );

    try {
      await previewEngine.setVolume(0);
      await previewEngine.open(
        previewSource.source,
        startAt: target,
        autoplay: true,
      );
      await previewEngine.setVolume(0);
      await _waitForSeekPreviewContent(
        previewEngine,
        generation,
        timeout: _seekPreviewOpenTimeout,
      );
    } on Object {
      if (_seekPreviewEngine == previewEngine) {
        _seekPreviewEngine = null;
        _seekPreviewSourceKey = null;
        if (state.seekPreviewEngine == previewEngine) {
          state = state.copyWith(clearSeekPreviewEngine: true);
        }
      }
      await previewEngine.dispose();
      return null;
    }

    if (generation != _seekPreviewGeneration ||
        _seekPreviewEngine != previewEngine) {
      if (_seekPreviewEngine == previewEngine) {
        _seekPreviewEngine = null;
        _seekPreviewSourceKey = null;
        if (state.seekPreviewEngine == previewEngine) {
          state = state.copyWith(clearSeekPreviewEngine: true);
        }
      }
      await previewEngine.dispose();
      return null;
    }

    return previewEngine;
  }

  Future<void> _primeSeekPreviewFrame(
    PlayerEngine previewEngine,
    Duration target,
    int generation, {
    Duration hold = _seekPreviewFrameHold,
  }) async {
    try {
      await previewEngine.setVolume(0);
      await previewEngine.play();
      await _waitForSeekPreviewContent(
        previewEngine,
        generation,
        timeout: _seekPreviewOpenTimeout,
      );
      if (!_isActiveSeekPreview(previewEngine, generation)) return;

      await previewEngine.seekTo(target);
      await previewEngine.setVolume(0);
      await previewEngine.play();
      await _waitForSeekPreviewTarget(previewEngine, target, generation);
      if (!_isActiveSeekPreview(previewEngine, generation)) return;

      await Future<void>.delayed(hold);
    } finally {
      if (_seekPreviewEngine == previewEngine) {
        try {
          await previewEngine.pause();
          await previewEngine.setVolume(0);
        } on Object {
          // A disposed or rejected preview decoder should not bubble into playback.
        }
      }
    }
  }

  Future<void> _waitForSeekPreviewContent(
    PlayerEngine previewEngine,
    int generation, {
    required Duration timeout,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (_isActiveSeekPreview(previewEngine, generation) &&
        DateTime.now().isBefore(deadline)) {
      final PlayerEngineState value = previewEngine.state.value;
      if (value.hasError) return;
      if (_hasSeekPreviewFrameContext(value)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  Future<void> _waitForSeekPreviewTarget(
    PlayerEngine previewEngine,
    Duration target,
    int generation,
  ) async {
    final DateTime deadline = DateTime.now().add(_seekPreviewSettleTimeout);
    while (_isActiveSeekPreview(previewEngine, generation) &&
        DateTime.now().isBefore(deadline)) {
      final PlayerEngineState value = previewEngine.state.value;
      if (value.hasError) return;
      final int deltaMs =
          (value.position.inMilliseconds - target.inMilliseconds).abs();
      final bool nearTarget =
          deltaMs <= _seekPreviewTargetTolerance.inMilliseconds;
      final bool hasFrameContext = _hasSeekPreviewFrameContext(value);
      if (nearTarget && hasFrameContext) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  bool _hasSeekPreviewFrameContext(PlayerEngineState value) {
    return value.hasVideoSurface ||
        (value.videoSize.width > 0 && value.videoSize.height > 0) ||
        value.duration > Duration.zero ||
        value.buffered.isNotEmpty;
  }

  bool _isActiveSeekPreview(PlayerEngine previewEngine, int generation) {
    return generation == _seekPreviewGeneration &&
        _seekPreviewEngine == previewEngine;
  }

  _SeekPreviewSource? _seekPreviewSourceForCurrentState() {
    final MediaServer? server = state.server;
    if (server == null) return null;

    final StreamQuality? lowQuality = _lowestSeekPreviewQuality(server);
    final StreamQuality? activeQuality = state.quality;

    final String url =
        _usableQualityUrl(lowQuality) ??
        _usableQualityUrl(activeQuality) ??
        server.url.trim();
    if (url.isEmpty) return null;

    final Map<String, String> headers;
    if (lowQuality != null) {
      headers = lowQuality.headers.isNotEmpty
          ? lowQuality.headers
          : server.headers;
    } else if (activeQuality != null && activeQuality.headers.isNotEmpty) {
      headers = activeQuality.headers;
    } else {
      headers = server.headers;
    }
    final StreamType streamType = _streamTypeForUrl(url, server.streamType);
    final PlayerSource source = PlayerSource(
      url: url,
      headers: headers,
      streamType: streamType,
    );
    return _SeekPreviewSource(source: source, key: _sourceKeyFor(source));
  }

  String? _usableQualityUrl(StreamQuality? quality) {
    if (quality == null || quality.isAuto) return null;
    final String url = quality.url.trim();
    return url.isEmpty ? null : url;
  }

  StreamQuality? _lowestSeekPreviewQuality(MediaServer server) {
    final List<StreamQuality> explicitQualities = server.qualities
        .where((StreamQuality q) => !q.isAuto && q.url.trim().isNotEmpty)
        .toList(growable: false);
    if (explicitQualities.isEmpty) return null;

    final List<StreamQuality> hlsQualities = explicitQualities
        .where(
          (StreamQuality q) =>
              _streamTypeForUrl(q.url, server.streamType) == StreamType.hls,
        )
        .toList(growable: false);
    final List<StreamQuality> candidates = hlsQualities.isNotEmpty
        ? hlsQualities
        : explicitQualities;
    final List<StreamQuality> ranked = candidates
        .where(_hasPreviewQualitySignal)
        .toList(growable: true);
    if (ranked.isEmpty) {
      return candidates.last;
    }

    ranked.sort((StreamQuality a, StreamQuality b) {
      final int heightCompare = (_previewQualityHeight(a) ?? (1 << 30))
          .compareTo(_previewQualityHeight(b) ?? (1 << 30));
      if (heightCompare != 0) return heightCompare;

      final int bitrateCompare = (a.bitrate ?? 1 << 30).compareTo(
        b.bitrate ?? 1 << 30,
      );
      if (bitrateCompare != 0) return bitrateCompare;

      return a.label.compareTo(b.label);
    });
    return ranked.first;
  }

  bool _hasPreviewQualitySignal(StreamQuality quality) {
    return _previewQualityHeight(quality) != null ||
        (quality.bitrate != null && quality.bitrate! > 0);
  }

  int? _previewQualityHeight(StreamQuality quality) {
    final int? height = quality.height;
    if (height != null && height > 0) return height;

    final String label = '${quality.label} ${quality.id}'.toLowerCase();
    if (label.contains('4k')) return 2160;
    if (label.contains('2k')) return 1440;

    final RegExpMatch? match = RegExp(
      r'(2160|1440|1080|720|576|540|480|360|240|144)\s*p?\b',
    ).firstMatch(label);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    if (label.contains('low') || label.contains('sd')) return 480;
    if (label.contains('hd')) return 720;
    return null;
  }

  StreamType _streamTypeForUrl(String url, StreamType fallback) {
    if (LocalHlsProxy.isInlineDashUrl(url)) return StreamType.dash;
    final String lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return StreamType.hls;
    if (lower.contains('.mpd')) return StreamType.dash;
    if (lower.contains('.mp4')) return StreamType.mp4;
    return fallback;
  }

  String _sourceKeyFor(PlayerSource source) {
    final List<MapEntry<String, String>> headers = source.headers.entries
        .toList(growable: false);
    headers.sort(
      (MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key),
    );

    final StringBuffer buffer = StringBuffer()
      ..writeln(source.streamType.name)
      ..writeln(source.url);
    for (final MapEntry<String, String> header in headers) {
      buffer.writeln('${header.key}: ${header.value}');
    }
    return buffer.toString();
  }

  Future<void> _disposeSeekPreviewEngine({bool clearState = true}) async {
    _seekPreviewGeneration++;
    _seekPreviewTimer?.cancel();
    _seekPreviewWarmupTimer?.cancel();
    _seekPreviewTimer = null;
    _seekPreviewWarmupTimer = null;
    _pendingSeekPreviewTarget = null;
    _lastSeekPreviewTarget = null;
    _seekPreviewInFlight = false;
    _seekPreviewScrubbing = false;
    _seekPreviewSourceKey = null;

    final PlayerEngine? previewEngine = _seekPreviewEngine;
    _seekPreviewEngine = null;
    if (clearState && state.seekPreviewEngine == previewEngine) {
      state = state.copyWith(clearSeekPreviewEngine: true);
    }
    if (previewEngine != null) {
      await previewEngine.dispose();
    }
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

  void _queueInteractiveSeek(
    PlayerEngine engine,
    Duration target, {
    required Duration delay,
  }) {
    _manualSeekEpoch++;
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
    if (_seekInFlight) return;
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

    try {
      await engine.seekTo(target);
    } on Object {
      // Keep rapid seek gestures from surfacing as uncaught async errors if
      // the native player rejects a stale target during stream transitions.
    } finally {
      _seekInFlight = false;
      if (_queuedSeekTarget != null) {
        unawaited(_flushInteractiveSeek());
      } else if (state.engine == engine) {
        _queuedSeekEngine = null;
        _beginSeekSettle(engine, target);
      } else if (_queuedSeekEngine == engine) {
        _clearInteractiveSeek();
      }
    }
  }

  void _beginSeekSettle(PlayerEngine engine, Duration target) {
    _cancelSeekSettle(clearPreview: false);
    if (state.engine != engine) return;
    _settlingSeekEngine = engine;
    _settlingSeekTarget = target;
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

  void _settleSeekPreview() {
    final PlayerEngine? engine = _settlingSeekEngine;
    final Duration? target = _settlingSeekTarget;
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
    final bool settled = _isSeekSettled(position, target);
    final bool timedOut = now.isAfter(until);
    final bool heldLongEnough =
        earliestClear == null || !now.isBefore(earliestClear);
    final bool liveTargetBuffered = _bufferedEndFor(engine, target) != null;
    final bool hasRememberedBuffer = state.seekPreviewBufferedEnd != null;
    final bool nativeStillBuffering =
        engine.state.value.isBuffering && !liveTargetBuffered;
    final bool canClearRememberedBuffer =
        !hasRememberedBuffer || !nativeStillBuffering;

    if (!timedOut &&
        (!settled || !heldLongEnough || !canClearRememberedBuffer)) {
      return;
    }

    final bool shouldClear = state.seekPreviewPosition == target;
    _cancelSeekSettle(clearPreview: false);
    if (shouldClear && state.engine == engine) {
      state = state.copyWith(clearSeekPreviewPosition: true);
    }
  }

  bool _isSeekSettled(Duration position, Duration target) {
    final int diffMs = (position.inMilliseconds - target.inMilliseconds).abs();
    return diffMs <= _seekSettleTolerance.inMilliseconds;
  }

  void _cancelSeekSettle({required bool clearPreview}) {
    _seekSettleTimer?.cancel();
    _seekSettleTimer = null;
    _settlingSeekEngine = null;
    _settlingSeekTarget = null;
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
    await ref.read(playerSettingsProvider.notifier).setSpeed(speed);
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await state.engine?.setPlaybackSpeed(_effectivePlaybackSpeed(settings));
    state = state.copyWith();
    _updateMediaSession();
  }

  Future<void> beginTemporarySpeed() async {
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    _temporarySpeedHolds += 1;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await engine.setPlaybackSpeed(_effectivePlaybackSpeed(settings));
    state = state.copyWith(temporarySpeedActive: true);
    _updateMediaSession();
  }

  Future<void> endTemporarySpeed() async {
    if (_temporarySpeedHolds <= 0) return;
    _temporarySpeedHolds -= 1;
    if (_temporarySpeedHolds > 0) return;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await state.engine?.setPlaybackSpeed(settings.playbackSpeed);
    state = state.copyWith(temporarySpeedActive: false);
    _updateMediaSession();
  }

  double _effectivePlaybackSpeed(PlayerSettings settings) {
    if (_temporarySpeedHolds <= 0) return settings.playbackSpeed;
    return settings.playbackSpeed + _temporaryPlaybackSpeedBoost;
  }

  Future<void> setVolume(double volume) async {
    final double clamped = volume.clamp(0.0, 1.0).toDouble();
    await state.engine?.setVolume(clamped);
    await ref.read(playerSettingsProvider.notifier).setVolume(clamped);
    state = state.copyWith();
  }

  Future<void> switchServer(MediaServer server) async {
    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? current = state.engine;
    if (item == null) return;
    await _open(
      item: item,
      server: server,
      quality: _initialQuality(server),
      position: _currentPositionFor(current),
      autoplay: current?.state.value.isPlaying ?? true,
    );
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
      autoplay: current?.state.value.isPlaying ?? true,
      voiceover: state.voiceover,
      subtitle: state.subtitle,
      preserveAspectRatio: current?.state.value.aspectRatio,
    );
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
      autoplay: current?.state.value.isPlaying ?? true,
      voiceover: state.voiceover,
      subtitle: state.subtitle,
      preserveAspectRatio: current?.state.value.aspectRatio,
      backendOverride: backend,
    );
  }

  Future<void> switchVoiceover(VoiceOverTrack voiceover) async {
    final MediaPlaybackItem? item = state.item;
    final MediaServer? currentServer = state.server;
    final PlayerEngine? current = state.engine;
    final String? voiceUrl = voiceover.url?.trim();
    if (item == null ||
        currentServer == null ||
        voiceUrl == null ||
        voiceUrl.isEmpty) {
      state = state.copyWith(voiceover: voiceover);
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
      autoplay: current?.state.value.isPlaying ?? true,
      voiceover: voiceover,
      subtitle: state.subtitle,
    );
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
    if (!settings.subtitlesEnabled ||
        settings.preferredSubtitleLanguage.isEmpty) {
      return;
    }
    final List<SubtitleTrack> tracks = server.subtitles;
    if (tracks.isEmpty) return;

    SubtitleTrack? best;
    for (final SubtitleTrack t in tracks) {
      if (t.language == settings.preferredSubtitleLanguage ||
          t.label == settings.preferredSubtitleLanguage) {
        best = t;
        break;
      }
    }
    best ??= tracks.first;

    final List<SubtitleCue> cues = await _loadSubtitleCues(best);
    if (state.subtitle == null) {
      state = state.copyWith(subtitle: best, subtitleCues: cues);
    } else {
      return;
    }
  }

  Future<List<SubtitleCue>> _loadSubtitleCues(SubtitleTrack track) async {
    try {
      final Response<String> response = await Dio().get<String>(
        track.url,
        options: track.headers.isNotEmpty
            ? Options(headers: track.headers)
            : null,
      );
      return const SubtitleParser().parse(response.data ?? '');
    } on Object {
      return const <SubtitleCue>[];
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

  Future<void> skipTo(Duration target) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    final Duration from = _currentPositionFor(engine);
    final Duration duration = engine.state.value.duration;
    final Duration clampedTarget = _clampSeekPosition(target, duration);
    _manualSeekEpoch++;
    _clearInteractiveSeek();
    // Skip jumps (notably the auto ED-skip, which lands on the episode end) must
    // feed completion detection like slider/gesture seeks do — otherwise jumping
    // past the end leaves the episode unwatched and never triggers auto-next.
    _noteManualSeekTarget(clampedTarget, duration);
    _setSeekPreview(engine, clampedTarget);
    try {
      await engine.seekTo(clampedTarget);
    } on Object {
      // Native backends may reject stale skip targets during stream changes.
    }
    if (state.engine == engine) {
      _beginSeekSettle(engine, clampedTarget);
    }
    state = state.copyWith(lastSkippedFrom: from);
    _undoTimer?.cancel();
    _undoTimer = Timer(
      const Duration(seconds: 5),
      () => state = state.copyWith(clearLastSkippedFrom: true),
    );
  }

  Future<void> undoSkip() async {
    final Duration? from = state.lastSkippedFrom;
    if (from == null) return;
    final PlayerEngine? engine = state.engine;
    if (engine == null) return;
    final Duration target = _clampSeekPosition(
      from,
      engine.state.value.duration,
    );
    _manualSeekEpoch++;
    _clearInteractiveSeek();
    _setSeekPreview(engine, target);
    try {
      await engine.seekTo(target);
    } on Object {
      // Ignore stale undo seeks while the player is being replaced.
    }
    if (state.engine == engine) {
      _beginSeekSettle(engine, target);
    }
    state = state.copyWith(clearLastSkippedFrom: true);
  }

  void setControlsVisible(bool visible) =>
      state = state.copyWith(controlsVisible: visible);
  void setLocked(bool locked) => state = state.copyWith(locked: locked);

  void _startProgressSaver() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final MediaPlaybackItem? item = state.item;
      final PlayerEngine? engine = state.engine;
      if (item == null || engine == null || !engine.state.value.isInitialized) {
        return;
      }
      if (!item.ignoreProgress) {
        await _saveProgress(item, engine);
      }
      _updateMediaSession();
      if (_seekPreviewStreamEnabled) {
        _maybeScheduleSeekPreviewWarmup(engine);
      }
      if (item.ignoreProgress) {
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
      _evaluatePlaybackProgress(engine);
    };
    engine.addListener(listener);
  }

  void _evaluatePlaybackProgress(PlayerEngine engine) {
    final MediaPlaybackItem? item = state.item;
    if (item == null || item.ignoreProgress) return;
    final PlayerEngineState es = engine.state.value;
    if (!es.isInitialized) return;

    final Duration dur = es.duration;
    final Duration pos = es.position;
    // Require a stable, realistic duration before trusting a fraction/near-end
    // check: fragile HLS/DASH streams briefly expose a few-second duration while
    // the full manifest is still being parsed.
    final bool reliableDuration = dur >= const Duration(minutes: 2);

    // (1) Auto-progress: mark the episode watched the instant playback crosses
    // 85%, independent of ever reaching the very end. This is what makes the
    // watched mark + AniList sync fire mid-playback instead of only on exit.
    if (reliableDuration &&
        !_autoProgressMarked &&
        pos.inMilliseconds >= dur.inMilliseconds * _watchedFraction) {
      _autoProgressMarked = true;
      print(
        '[DEBUG] auto-progress: 85% reached at ${pos.inSeconds}s/${dur.inSeconds}s -> marking watched',
      );
      unawaited(_saveProgress(item, engine));
    }

    // (2) End-of-stream latch: the moment the backend reports completion (or the
    // position crosses into the final seconds) persist the episode as watched so
    // a seek-to-end or a 0:00 position-snap can never hide completion.
    final bool ended =
        es.isCompleted ||
        (reliableDuration && pos >= dur - const Duration(seconds: 2));
    if (ended && !_reachedNearEnd) {
      _reachedNearEnd = true;
      print(
        '[DEBUG] auto-next: end latched (isCompleted=${es.isCompleted} pos=${pos.inSeconds}s/${dur.inSeconds}s)',
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
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    final bool showNextOverlay =
        settings.autoplayNext || settings.showNextEpisodeButton;
    final bool showAfterEnd =
        settings.showNextEpisodeButton && !settings.autoplayNext;
    if (showNextOverlay && !state.autoNextVisible) {
      final Duration dur = engine.state.value.duration;
      final Duration pos = engine.state.value.position;
      final bool ended = engine.state.value.isCompleted || _reachedNearEnd;
      // The backend reaching end-of-stream is the most reliable trigger:
      // some streams snap the reported position back to 0:00 on completion,
      // so a pure position-vs-duration check would never fire auto-next.
      bool shouldShow = ended;
      // Require at least 2 minutes of reported duration before showing
      // auto-next. Some HLS/DASH streams report a very small initial duration
      // before the full manifest is parsed, which would otherwise trigger the
      // next-episode overlay within the first few seconds.
      if (!shouldShow && dur >= const Duration(minutes: 2)) {
        if (showAfterEnd) {
          shouldShow = pos + const Duration(seconds: 1) >= dur;
        } else {
          shouldShow = pos >= dur - const Duration(seconds: 10);
        }
      }
      if (shouldShow) {
        print(
          '[DEBUG] auto-next: overlay shown (ended=$ended pos=${pos.inSeconds}s/${dur.inSeconds}s)',
        );
        state = state.copyWith(autoNextVisible: true);
      }
    } else if (!showNextOverlay && state.autoNextVisible) {
      state = state.copyWith(autoNextVisible: false);
    }
  }

  void dismissAutoNext() => state = state.copyWith(autoNextVisible: false);

  Future<void> _saveProgress(
    MediaPlaybackItem item,
    PlayerEngine engine,
  ) async {
    if (item.ignoreProgress) return;
    if (!engine.state.value.isInitialized) return;

    final Duration position = engine.state.value.position;
    // Treat a latched seek-to-end the same as a backend-reported completion so
    // the episode is still marked watched even when the position snapped to 0.
    final bool engineCompleted =
        engine.state.value.isCompleted || _reachedNearEnd;
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

    final int? durationSeconds = engine.state.value.duration.inSeconds > 0
        ? engine.state.value.duration.inSeconds
        : null;

    // Never treat very short reported durations as completion. Fragile HLS
    // streams can briefly expose a 4-10 second media duration while the real
    // playlist is still being parsed. Saving that as completed breaks resume
    // and can trigger auto-next incorrectly.
    final bool hasReliableCompletionDuration =
        durationSeconds != null && durationSeconds >= 120;

    // The episode counts as watched once playback crosses 85% (the common
    // anime convention) or the backend reports end-of-stream. Latched in
    // [_autoProgressMarked] so a later periodic save can never clear it back to
    // unwatched while the final 15% (ED/credits) is still playing.
    final bool reachedWatchedFraction =
        hasReliableCompletionDuration &&
        position.inSeconds >= durationSeconds * _watchedFraction;
    final bool watched =
        engineCompleted || reachedWatchedFraction || _autoProgressMarked;

    // Only snap the resume point back to 0:00 once the stream is essentially
    // finished. When we mark "watched" early (at 85%) the real position is kept
    // so reopening resumes in the final stretch instead of restarting.
    final bool resetToStart =
        engineCompleted ||
        (hasReliableCompletionDuration &&
            position.inSeconds >= durationSeconds - 20);
    final int savePosition = resetToStart ? 0 : position.inSeconds;
    final int? savedDurationSeconds = hasReliableCompletionDuration
        ? durationSeconds
        : null;

    for (final String mediaId in _progressMediaIds(item)) {
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

    final bool syncEnabled =
        (ref.read(playerSettingsProvider).value ?? const PlayerSettings())
            .autoAnilistSync;
    if (syncEnabled && watched) {
      unawaited(_trySyncAniList(item, item.episodeNumber.round()));
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
