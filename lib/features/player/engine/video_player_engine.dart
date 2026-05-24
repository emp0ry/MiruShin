import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'player_engine.dart';

/// Deprecated compatibility stub.
///
/// MiruShin's player branch is now FVP-direct. Do not use VideoPlayerEngine for
/// runtime playback. The file remains only so older imports fail gracefully
/// instead of pulling `package:video_player` back into the player layer.
@Deprecated('Use FvpPlayerEngine instead.')
class VideoPlayerEngine extends PlayerEngine {
  VideoPlayerEngine()
    : _state = ValueNotifier<PlayerEngineState>(
        const PlayerEngineState(
          hasError: true,
          errorDescription: 'VideoPlayerEngine has been removed. Use FVP.',
        ),
      );

  final ValueNotifier<PlayerEngineState> _state;

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    throw UnsupportedError('VideoPlayerEngine has been removed. Use FVP.');
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    _state.dispose();
  }
}
