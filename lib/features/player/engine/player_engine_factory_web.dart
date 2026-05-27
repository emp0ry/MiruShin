import 'player_engine.dart';
import 'video_player_engine.dart';

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  bool previewMode = false,
}) {
  return VideoPlayerEngine(
    initialAspectRatio: initialAspectRatio,
    previewMode: previewMode,
  );
}
