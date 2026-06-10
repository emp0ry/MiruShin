import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'player_engine.dart';

const mdk.SeekFlag _vodSeekFlag = mdk.SeekFlag(
  mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache,
);

class FvpDirectEngine extends PlayerEngine {
  FvpDirectEngine();

  final ValueNotifier<PlayerEngineState> _state =
      ValueNotifier<PlayerEngineState>(const PlayerEngineState());
  final mdk.Player _player = mdk.Player();
  Timer? _stateTimer;
  StreamSubscription<mdk.MediaEvent>? _eventSubscription;
  StreamSubscription<dynamic>? _stateSubscription;
  StreamSubscription<dynamic>? _mediaStatusSubscription;
  String? _lastError;
  bool _disposed = false;
  bool _prepared = false;
  List<PlayerBufferedRange> _lastBufferedRanges = const <PlayerBufferedRange>[];

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: _player.textureId,
      builder: (BuildContext context, int? textureId, Widget? child) {
        if (textureId == null) return const SizedBox.shrink();
        return Texture(textureId: textureId);
      },
    );
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    if (_disposed) return;

    // fvp exposes a direct MDK backend, but the public direct Player API does
    // not provide the same stable httpHeaders argument that video_player has.
    // Keep header-heavy sources on VideoPlayerEngine until a tested MDK header
    // mapping is added, otherwise those Sora streams can fail before playback.
    if (source.headers.isNotEmpty) {
      throw UnsupportedError(
        'FVP Direct currently does not support per-source HTTP headers safely.',
      );
    }

    _lastError = null;
    _prepared = false;
    _lastBufferedRanges = const <PlayerBufferedRange>[];
    _state.value = const PlayerEngineState(isBuffering: true);

    _installCallbacks();
    _configurePlayerForNetworkStreams();

    try {
      _player.media = source.url;
      await _player.updateTexture();
      final int preparedPosition = await _player.prepare(
        position: (startAt ?? Duration.zero).inMilliseconds,
      );
      if (preparedPosition < 0) {
        throw StateError(
          'FVP Direct failed to prepare stream ($preparedPosition).',
        );
      }
      _prepared = true;
      _startStateTimer();
      _syncState();
      if (autoplay) {
        await play();
      }
    } on Object catch (error) {
      _lastError = error.toString();
      _syncState(forceError: true);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed || !_prepared) return;
    _player.state = mdk.PlaybackState.playing;
    _state.value = _state.value.copyWith(isPlaying: true);
    _syncState();
  }

  @override
  Future<void> pause() async {
    if (_disposed || !_prepared) return;
    _player.state = mdk.PlaybackState.paused;
    _state.value = _state.value.copyWith(isPlaying: false, isBuffering: false);
    _syncState();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_disposed || !_prepared) return;
    try {
      final int targetMs = position.inMilliseconds.clamp(0, 1 << 62).toInt();
      final PlayerEngineState current = _state.value;
      final Duration target = Duration(milliseconds: targetMs);
      _state.value = _state.value.copyWith(
        position: target,
        isBuffering:
            _isPositionBuffered(current.buffered, target, current.duration)
            ? false
            : current.isBuffering,
      );
      final int result = await _player.seek(
        position: targetMs,
        flags: _vodSeekFlag,
      );
      if (result < 0) {
        _lastError = 'FVP Direct seek failed ($result).';
      }
    } on Object catch (error) {
      _lastError = error.toString();
    }
    _syncState(forceError: _lastError != null);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    if (_disposed) return;
    _player.playbackRate = speed;
    _syncState();
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    _player.volume = volume.clamp(0.0, 1.0).toDouble();
    _syncState();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stateTimer?.cancel();
    _stateTimer = null;
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _mediaStatusSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription = null;
    _mediaStatusSubscription = null;
    _player.dispose();
    _state.value = const PlayerEngineState();
  }

  void _installCallbacks() {
    _eventSubscription ??= _player.onEvent.listen((mdk.MediaEvent event) {
      if (event.error != 0) {
        _lastError = '${event.category}: ${event.detail} (${event.error})';
      }
      _syncState(forceError: event.error != 0);
    });
    _stateSubscription ??= _player.onStateChanged.listen((_) => _syncState());
    _mediaStatusSubscription ??= _player.onMediaStatus.listen(
      (_) => _syncState(),
    );
  }

  void _configurePlayerForNetworkStreams() {
    // MDK supports a real demuxer cache and buffered ranges. These properties
    // are safe no-ops on unsupported builds, so failures are intentionally
    // ignored to keep the engine usable across all platforms.
    try {
      _player.setProperty('demux.buffer.protocols', 'file,http,https');
      _player.setProperty('demux.buffer.ranges', '8');
      _player.setBufferRange(min: 8000, max: 45000);
    } catch (_) {
      // Ignore unsupported backend options.
    }

    try {
      _player.setProperty('avformat.strict', 'experimental');
      _player.setProperty('avformat.safe', '0');
      _player.setProperty('avformat.extension_picky', '0');
      _player.setProperty('avformat.allowed_segment_extensions', 'ALL');
    } catch (_) {
      // Not all MDK builds expose avformat properties — safe to ignore.
    }

    try {
      _player.setProperty('avio.reconnect', '1');
      _player.setProperty('avio.reconnect_streamed', '1');
      _player.setProperty('avio.reconnect_delay_max', '5');
    } catch (_) {
      // Older MDK builds may not expose all avio properties — safe to ignore.
    }
  }

  void _startStateTimer() {
    _stateTimer?.cancel();
    _stateTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _syncState(),
    );
  }

  void _syncState({bool forceError = false}) {
    if (_disposed) return;

    final mdk.PlaybackState playbackState = _player.state;
    final mdk.MediaStatus status = _player.mediaStatus;
    final mdk.MediaInfo info = _player.mediaInfo;
    final Size size = _videoSize(info);
    final double aspectRatio = size.width > 0 && size.height > 0
        ? size.width / size.height
        : 16 / 9;

    final bool isPlaying =
        playbackState == mdk.PlaybackState.playing ||
        playbackState == mdk.PlaybackState.running;
    final bool nativeBuffering =
        status.test(mdk.MediaStatus.loading) ||
        status.test(mdk.MediaStatus.buffering) ||
        status.test(mdk.MediaStatus.stalled);
    final bool initialized =
        _prepared &&
        (status.test(mdk.MediaStatus.prepared) ||
            status.test(mdk.MediaStatus.loaded) ||
            playbackState == mdk.PlaybackState.paused ||
            playbackState == mdk.PlaybackState.playing ||
            playbackState == mdk.PlaybackState.running);

    final List<PlayerBufferedRange> nativeBufferedRanges = _bufferedRanges();
    if (nativeBufferedRanges.isNotEmpty) {
      _lastBufferedRanges = nativeBufferedRanges;
    }
    final bool transientBufferReset =
        nativeBufferedRanges.isEmpty &&
        (status.test(mdk.MediaStatus.seeking) || nativeBuffering);
    final List<PlayerBufferedRange> bufferedRanges = transientBufferReset
        ? _lastBufferedRanges
        : nativeBufferedRanges;
    final Duration position = Duration(
      milliseconds: _safePositive(_player.position),
    );
    final Duration duration = Duration(
      milliseconds: _safePositive(info.duration),
    );
    final bool seekIsBuffered = _isPositionBuffered(
      bufferedRanges,
      position,
      duration,
    );

    _state.value = PlayerEngineState(
      position: position,
      duration: duration,
      volume: _player.volume,
      playbackSpeed: _player.playbackRate,
      aspectRatio: aspectRatio,
      videoSize: size,
      buffered: bufferedRanges,
      isInitialized: initialized,
      isPlaying: isPlaying,
      isBuffering:
          !initialized ||
          (status.test(mdk.MediaStatus.seeking) && !seekIsBuffered) ||
          (isPlaying && nativeBuffering),
      isCompleted: status.test(mdk.MediaStatus.end) && initialized,
      hasVideoSurface: _player.textureId.value != null,
      hasError: forceError || _lastError != null,
      errorDescription: _lastError,
    );
  }

  bool _isPositionBuffered(
    List<PlayerBufferedRange> ranges,
    Duration position,
    Duration duration,
  ) {
    final int totalMs = duration.inMilliseconds;
    if (totalMs <= 0 || ranges.isEmpty) return false;
    final int positionMs = position.inMilliseconds.clamp(0, totalMs).toInt();
    final int toleranceMs = const Duration(milliseconds: 1200).inMilliseconds;
    for (final PlayerBufferedRange range in ranges) {
      final int startMs = range.start.inMilliseconds.clamp(0, totalMs).toInt();
      final int endMs = range.end.inMilliseconds.clamp(0, totalMs).toInt();
      if (endMs <= startMs) continue;
      if (positionMs >= startMs - toleranceMs &&
          positionMs <= endMs + toleranceMs) {
        return true;
      }
    }
    return false;
  }

  List<PlayerBufferedRange> _bufferedRanges() {
    final List<PlayerBufferedRange> bufferedRanges = <PlayerBufferedRange>[];
    try {
      bufferedRanges.addAll(
        _player.bufferedTimeRanges().map(
          (range) => PlayerBufferedRange(start: range.start, end: range.end),
        ),
      );
    } catch (_) {
      // Fall back to buffered duration below.
    }

    final int bufferedMs = _player.buffered();
    if (bufferedMs > 0) {
      final Duration start = Duration(
        milliseconds: _safePositive(_player.position),
      );
      bufferedRanges.add(
        PlayerBufferedRange(
          start: start,
          end: start + Duration(milliseconds: bufferedMs),
        ),
      );
    }
    return bufferedRanges;
  }

  Size _videoSize(mdk.MediaInfo info) {
    final List<mdk.VideoStreamInfo>? videos = info.video;
    if (videos == null || videos.isEmpty) return Size.zero;
    final mdk.VideoStreamInfo first = videos.first;
    final int width = first.codec.width;
    final int height = first.codec.height;
    if (width <= 0 || height <= 0) return Size.zero;
    return Size(width.toDouble(), height.toDouble());
  }

  int _safePositive(int value) => value < 0 ? 0 : value;
}
