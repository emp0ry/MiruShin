import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../domain/player_models.dart';

enum PlayerEngineUiCommand { showControls, toggleFullscreen, exitFullscreen }

class PlayerSource {
  const PlayerSource({
    required this.url,
    this.headers = const <String, String>{},
    this.streamType = StreamType.unknown,
  });

  final String url;
  final Map<String, String> headers;
  final StreamType streamType;
}

class PlayerBufferedRange {
  const PlayerBufferedRange({required this.start, required this.end});

  final Duration start;
  final Duration end;
}

class PlayerEngineState {
  const PlayerEngineState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1,
    this.playbackSpeed = 1,
    this.aspectRatio = 16 / 9,
    this.videoSize = Size.zero,
    this.buffered = const <PlayerBufferedRange>[],
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.hasVideoSurface = false,
    this.hasError = false,
    this.errorDescription,
  });

  final Duration position;
  final Duration duration;
  final double volume;
  final double playbackSpeed;
  final double aspectRatio;
  final Size videoSize;
  final List<PlayerBufferedRange> buffered;
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasVideoSurface;
  final bool hasError;
  final String? errorDescription;

  PlayerEngineState copyWith({
    Duration? position,
    Duration? duration,
    double? volume,
    double? playbackSpeed,
    double? aspectRatio,
    Size? videoSize,
    List<PlayerBufferedRange>? buffered,
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? hasVideoSurface,
    bool? hasError,
    String? errorDescription,
    bool clearError = false,
  }) {
    return PlayerEngineState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      videoSize: videoSize ?? this.videoSize,
      buffered: buffered ?? this.buffered,
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      hasVideoSurface: hasVideoSurface ?? this.hasVideoSurface,
      hasError: clearError ? false : hasError ?? this.hasError,
      errorDescription: clearError
          ? null
          : errorDescription ?? this.errorDescription,
    );
  }
}

abstract class PlayerEngine implements Listenable {
  ValueListenable<PlayerEngineState> get state;

  PlayerEngineState get value => state.value;

  Stream<PlayerEngineUiCommand> get uiCommands =>
      const Stream<PlayerEngineUiCommand>.empty();

  /// URL that native desktop PiP should use when taking over playback.
  ///
  /// Backends that proxy or transform the source can expose their effective
  /// playback URL here. The default keeps older engines on their original URL.
  String? get nativePlaybackUrl => null;

  Map<String, String> get nativePlaybackHeaders => const <String, String>{};

  Widget buildVideoSurface(BuildContext context);

  Future<void> open(PlayerSource source, {Duration? startAt, bool autoplay});
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}
