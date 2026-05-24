// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
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
import '../engine/player_engine.dart';
import '../engine/fvp_player_engine.dart';
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
    bool clearSeekPreviewPosition = false,
    bool clearSeekPreviewBufferedEnd = false,
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
    );
  }
}

class PlaybackController extends Notifier<PlaybackState> {
  static const Duration _interactiveSeekDelay = Duration(milliseconds: 180);
  static const Duration _seekSettleTick = Duration(milliseconds: 80);
  static const Duration _seekSettleMinHold = Duration(milliseconds: 700);
  static const Duration _seekSettleTimeout = Duration(milliseconds: 5000);
  static const Duration _seekSettleTolerance = Duration(milliseconds: 1200);
  static const double _temporaryPlaybackSpeedBoost = 1.0;

  Timer? _progressTimer;
  Timer? _undoTimer;
  Timer? _interactiveSeekTimer;
  Timer? _seekSettleTimer;
  int _retryCount = 0;
  int _playbackGeneration = 0;
  int _manualSeekEpoch = 0;
  Duration _resumeGuardPosition = Duration.zero;
  DateTime? _resumeGuardUntil;
  PlayerEngine? _queuedSeekEngine;
  Duration? _queuedSeekTarget;
  bool _seekInFlight = false;
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
      _seekSettleTimer?.cancel();
      unawaited(DiscordRpcService.dispose());
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
    unawaited(MediaSessionService.updateNowPlaying(
      title: item.title,
      subtitle: sub,
      artworkUrl: item.posterUrl,
      position: es.position,
      duration: es.duration,
      isPlaying: es.isPlaying,
      playbackRate: es.playbackSpeed,
      hasNext: _nextEpisodeHandler != null,
    ));
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
    if (progress?.completed == true) {
      print('[DEBUG] _safeResumePosition: completed=true → 0');
      return Duration.zero;
    }
    final int savedSeconds = progress?.positionSeconds ?? 0;
    final Duration saved = savedSeconds > 0
        ? Duration(seconds: savedSeconds)
        : Duration.zero;
    final Duration start = saved > item.startPosition
        ? saved
        : item.startPosition;

    print(
      '[DEBUG] _safeResumePosition: savedSeconds=$savedSeconds item.startPosition=${item.startPosition} → start=$start',
    );

    final int? durationSeconds = progress?.durationSeconds;
    if (durationSeconds != null && durationSeconds > 0) {
      final Duration duration = Duration(seconds: durationSeconds);
      if (start >= duration - const Duration(seconds: 20)) {
        print('[DEBUG] _safeResumePosition: near end → 0');
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
  }) async {
    final int generation = ++_playbackGeneration;
    _clearInteractiveSeek();
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
      clearError: true,
    );
    if (subtitle == null) unawaited(_autoSelectSubtitle(server));

    final String url = quality.isAuto || quality.url.isEmpty
        ? server.url
        : quality.url;
    final PlayerEngine engine = FvpPlayerEngine(
      initialAspectRatio: _safeAspectRatio(preserveAspectRatio),
    );

    try {
      await engine.open(
        PlayerSource(
          url: url,
          headers: quality.headers.isNotEmpty
              ? quality.headers
              : server.headers,
          streamType: server.streamType,
        ),
        startAt: position,
        autoplay: false,
      );
      if (generation != _playbackGeneration) {
        await engine.dispose();
        return;
      }
      final PlayerSettings settings =
          ref.read(playerSettingsProvider).value ?? const PlayerSettings();
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
      _reinforceInitialSeek(engine, position, generation, _manualSeekEpoch);
      _watchEngineErrors(engine, generation);
    } on Object catch (error) {
      await engine.dispose();
      if (generation != _playbackGeneration) return;
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

  void _reinforceInitialSeek(
    PlayerEngine engine,
    Duration position,
    int generation,
    int manualSeekEpoch,
  ) {
    if (position <= const Duration(seconds: 3)) return;

    for (final Duration delay in const <Duration>[
      Duration(milliseconds: 500),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2500),
      Duration(milliseconds: 4500),
    ]) {
      Future<void>.delayed(delay, () async {
        if (generation != _playbackGeneration ||
            manualSeekEpoch != _manualSeekEpoch ||
            state.engine != engine) {
          return;
        }

        final PlayerEngineState value = engine.state.value;
        if (!value.isInitialized) {
          return;
        }

        if (value.position + const Duration(seconds: 2) >= position) {
          return;
        }

        await engine.seekTo(position);
        state = state.copyWith();
      });
    }
  }

  void _watchEngineErrors(PlayerEngine engine, int generation) {
    late void Function() listener;
    listener = () {
      if (generation != _playbackGeneration || state.engine != engine) {
        engine.removeListener(listener);
        return;
      }
      if (engine.state.value.hasError && state.error == null) {
        engine.removeListener(listener);
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

    final MediaPlaybackItem? item = state.item;
    final PlayerEngine? engine = state.engine;
    state = const PlaybackState();
    if (engine == null) return;

    if (item != null) {
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

    final int positionSeconds = positionMs ~/ 1000;
    final int durationSeconds = durationMs ~/ 1000;
    final bool isNearEnd =
        durationSeconds > 0 && positionSeconds >= durationSeconds - 20;
    final int savePosition = (completed || isNearEnd) ? 0 : positionSeconds;
    final bool saveCompleted = completed || isNearEnd;

    for (final String mediaId in _progressMediaIds(item)) {
      await ref.read(localLibraryProvider.notifier).saveEpisodeProgress(
        mediaId: mediaId,
        season: item.seasonNumber,
        episode: item.episodeNumber,
        positionSeconds: savePosition,
        durationSeconds: durationSeconds > 0 ? durationSeconds : null,
        completed: saveCompleted,
      );
    }

    if (saveCompleted && durationSeconds > 0) {
      final double fraction =
          (positionSeconds / durationSeconds).clamp(0.0, 1.0);
      if (fraction >= 0.85) {
        final bool syncEnabled =
            (ref.read(playerSettingsProvider).value ?? const PlayerSettings())
                .autoAnilistSync;
        if (syncEnabled) {
          unawaited(_trySyncAniList(item, item.episodeNumber.round()));
        }
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

  Future<void> seekBy(Duration offset) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    final Duration duration = engine.state.value.duration;
    final Duration target = _clampSeekPosition(
      _seekBaseFor(engine) + offset,
      duration,
    );
    _queueInteractiveSeek(engine, target, delay: _interactiveSeekDelay);
  }

  Future<void> seekTo(Duration position) async {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    _queueInteractiveSeek(
      engine,
      _clampSeekPosition(position, engine.state.value.duration),
      delay: Duration.zero,
    );
  }

  void previewSeekTo(Duration position) {
    final PlayerEngine? engine = state.engine;
    if (engine == null || !engine.state.value.isInitialized) return;
    _cancelSeekSettle(clearPreview: false);
    _setSeekPreview(
      engine,
      _clampSeekPosition(position, engine.state.value.duration),
    );
  }

  Duration _seekBaseFor(PlayerEngine engine) {
    if (_queuedSeekEngine == engine && _queuedSeekTarget != null) {
      return _queuedSeekTarget!;
    }
    if (state.engine == engine && state.seekPreviewPosition != null) {
      return state.seekPreviewPosition!;
    }
    return engine.state.value.position;
  }

  Duration _currentPositionFor(PlayerEngine? engine) {
    if (engine == null) return Duration.zero;
    if (_queuedSeekEngine == engine && _queuedSeekTarget != null) {
      return _queuedSeekTarget!;
    }
    if (state.engine == engine && state.seekPreviewPosition != null) {
      return state.seekPreviewPosition!;
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
    state = state.copyWith();
    _updateMediaSession();
  }

  Future<void> endTemporarySpeed() async {
    if (_temporarySpeedHolds <= 0) return;
    _temporarySpeedHolds -= 1;
    if (_temporarySpeedHolds > 0) return;
    final PlayerSettings settings =
        ref.read(playerSettingsProvider).value ?? const PlayerSettings();
    await state.engine?.setPlaybackSpeed(settings.playbackSpeed);
    state = state.copyWith();
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
      final Response<String> response = await Dio().get<String>(track.url);
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
    final Duration clampedTarget = _clampSeekPosition(
      target,
      engine.state.value.duration,
    );
    _manualSeekEpoch++;
    _clearInteractiveSeek();
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
      await _saveProgress(item, engine);
      _updateMediaSession();
      final PlayerSettings settings =
          ref.read(playerSettingsProvider).value ?? const PlayerSettings();
      final bool showNextOverlay =
          settings.autoplayNext || settings.showNextEpisodeButton;
      final bool showAfterEnd =
          settings.showNextEpisodeButton && !settings.autoplayNext;
      if (showNextOverlay && !state.autoNextVisible) {
        final Duration dur = engine.state.value.duration;
        final Duration pos = engine.state.value.position;
        // Require at least 2 minutes of reported duration before showing
        // auto-next. Some HLS/DASH streams report a very small initial
        // duration before the full manifest is parsed, which would otherwise
        // trigger the next-episode overlay within the first few seconds.
        if (dur >= const Duration(minutes: 2)) {
          if (showAfterEnd) {
            const Duration endThreshold = Duration(seconds: 1);
            if (pos + endThreshold >= dur) {
              state = state.copyWith(autoNextVisible: true);
            }
          } else if (pos >= dur - const Duration(seconds: 10)) {
            state = state.copyWith(autoNextVisible: true);
          }
        }
      } else if (!showNextOverlay && state.autoNextVisible) {
        state = state.copyWith(autoNextVisible: false);
      }
    });
  }

  void dismissAutoNext() => state = state.copyWith(autoNextVisible: false);

  Future<void> _saveProgress(
    MediaPlaybackItem item,
    PlayerEngine engine,
  ) async {
    if (!engine.state.value.isInitialized) return;

    final Duration position = engine.state.value.position;
    final DateTime? guardUntil = _resumeGuardUntil;
    if (guardUntil != null && DateTime.now().isBefore(guardUntil)) {
      if (position + const Duration(seconds: 2) < _resumeGuardPosition) {
        return;
      }
      _resumeGuardUntil = null;
    }

    if (position <= const Duration(seconds: 1)) {
      return;
    }

    final int? durationSeconds = engine.state.value.duration.inSeconds > 0
        ? engine.state.value.duration.inSeconds
        : null;

    // Save position=0 with completed=true when near the end.
    // This resets the resume point to 0:00 (start fresh next time) while
    // keeping isWatched=true via the completed flag.
    final bool isNearEnd =
        durationSeconds != null &&
        durationSeconds > 0 &&
        position.inSeconds >= durationSeconds - 20;
    final int savePosition = isNearEnd ? 0 : position.inSeconds;

    for (final String mediaId in _progressMediaIds(item)) {
      await ref
          .read(localLibraryProvider.notifier)
          .saveEpisodeProgress(
            mediaId: mediaId,
            season: item.seasonNumber,
            episode: item.episodeNumber,
            positionSeconds: savePosition,
            durationSeconds: durationSeconds,
            completed: isNearEnd,
          );
    }

    if (durationSeconds != null && durationSeconds > 0) {
      final double fraction = (position.inSeconds / durationSeconds).clamp(
        0.0,
        1.0,
      );
      final bool syncEnabled =
          (ref.read(playerSettingsProvider).value ?? const PlayerSettings())
              .autoAnilistSync;
      if (fraction >= 0.85 && syncEnabled) {
        unawaited(_trySyncAniList(item, item.episodeNumber.round()));
      }
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
        (totalEpisodes != null && totalEpisodes > 0 && episodeNumber >= totalEpisodes)
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
          .updateEntryProgress(
            anilistId,
            episodeNumber,
            status: targetStatus,
          );
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
