import '../domain/player_models.dart';
import 'player_engine.dart';
import 'video_player_engine.dart';

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  bool previewMode = false,
  PlayerBackend backend = PlayerBackend.auto,
}) {
  // Web keeps the browser video backend. The native MPV/FVP engines are FFI
  // based and are intentionally not selected in web builds.
  return VideoPlayerEngine(
    initialAspectRatio: initialAspectRatio,
    previewMode: previewMode,
  );
}
