import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../domain/player_models.dart';
import 'player_engine.dart';

class VideoPlayerEngine extends PlayerEngine {
  VideoPlayerEngine({double? initialAspectRatio})
    : _initialAspectRatio = initialAspectRatio,
      _state = ValueNotifier<PlayerEngineState>(
        PlayerEngineState(
          aspectRatio: _usableAspectRatio(initialAspectRatio) ?? 16 / 9,
        ),
      );

  final double? _initialAspectRatio;
  final ValueNotifier<PlayerEngineState> _state;
  VideoPlayerController? _controller;
  VoidCallback? _controllerListener;
  double _volume = 1;
  double _playbackSpeed = 1;

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return VideoPlayer(controller);
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    await _disposeControllerOnly();

    _volume = _state.value.volume;
    _playbackSpeed = _state.value.playbackSpeed;
    _state.value = _state.value.copyWith(
      isBuffering: true,
      isInitialized: false,
      clearError: true,
    );

    final Uri uri = Uri.parse(source.url);
    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      uri,
      formatHint: _formatHint(source),
      httpHeaders: source.headers,
      videoPlayerOptions: VideoPlayerOptions(
        webOptions: const VideoPlayerWebOptions(allowContextMenu: false),
      ),
    );
    _controller = controller;
    _controllerListener = () => _syncState();
    controller.addListener(_controllerListener!);

    try {
      await controller.initialize();
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(_playbackSpeed);
      final Duration initialPosition = startAt ?? Duration.zero;
      if (initialPosition > Duration.zero) {
        await controller.seekTo(initialPosition);
      }
      if (autoplay) {
        await controller.play();
      }
      _syncState();
    } on Object catch (error) {
      _state.value = _state.value.copyWith(
        isBuffering: false,
        hasError: true,
        errorDescription: _friendlyOpenError(error, source),
      );
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    await controller.play();
    _syncState();
  }

  @override
  Future<void> pause() async {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    await controller.pause();
    _syncState();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    _state.value = _state.value.copyWith(position: position);
    await controller.seekTo(position);
    _syncState();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    final VideoPlayerController? controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      await controller.setPlaybackSpeed(speed);
    }
    _syncState();
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    final VideoPlayerController? controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      await controller.setVolume(_volume);
    }
    _syncState();
  }

  @override
  Future<void> dispose() async {
    await _disposeControllerOnly();
    _state.value = const PlayerEngineState();
    _state.dispose();
  }

  void _syncState() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) return;
    final VideoPlayerValue value = controller.value;
    final Size videoSize = value.size;
    final double aspectRatio = _effectiveAspectRatio(value.aspectRatio);
    final List<PlayerBufferedRange> buffered = value.buffered
        .map(
          (DurationRange range) =>
              PlayerBufferedRange(start: range.start, end: range.end),
        )
        .toList(growable: false);

    _state.value = PlayerEngineState(
      position: value.position,
      duration: value.duration,
      volume: _volume,
      playbackSpeed: _playbackSpeed,
      aspectRatio: aspectRatio,
      videoSize: videoSize,
      buffered: buffered,
      isInitialized: value.isInitialized,
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
      hasError: value.hasError,
      errorDescription: value.errorDescription,
    );
  }

  Future<void> _disposeControllerOnly() async {
    final VideoPlayerController? controller = _controller;
    final VoidCallback? listener = _controllerListener;
    _controller = null;
    _controllerListener = null;
    if (controller == null) return;
    if (listener != null) {
      controller.removeListener(listener);
    }
    await controller.dispose();
  }

  VideoFormat? _formatHint(PlayerSource source) {
    if (source.streamType == StreamType.hls ||
        source.url.toLowerCase().contains('.m3u8')) {
      return VideoFormat.hls;
    }
    if (source.streamType == StreamType.dash ||
        source.url.toLowerCase().contains('.mpd')) {
      return VideoFormat.dash;
    }
    if (source.streamType == StreamType.mp4) {
      return VideoFormat.other;
    }
    return null;
  }

  double _effectiveAspectRatio(double reportedAspectRatio) {
    return _usableAspectRatio(reportedAspectRatio) ??
        _usableAspectRatio(_state.value.aspectRatio) ??
        _usableAspectRatio(_initialAspectRatio) ??
        16 / 9;
  }

  static double? _usableAspectRatio(double? value) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    if (value < 1.2 || value > 2.4) return null;
    return value;
  }

  String _friendlyOpenError(Object error, PlayerSource source) {
    if (!kIsWeb) return error.toString();
    final List<String> details = <String>[error.toString()];
    if (source.headers.isNotEmpty) {
      details.add(
        'This stream provided custom headers, but browsers do not let HTML video set per-request stream headers.',
      );
    }
    details.add(
      'Web playback requires CORS-enabled media URLs and browser-supported formats.',
    );
    if (source.streamType == StreamType.hls ||
        source.url.toLowerCase().contains('.m3u8')) {
      details.add(
        'HLS support depends on the browser unless a separate HLS/MSE web player is added.',
      );
    }
    return details.join('\n');
  }
}
