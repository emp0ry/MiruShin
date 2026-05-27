import 'fvp_player_engine.dart';
import 'player_engine.dart';

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  bool previewMode = false,
}) {
  return FvpPlayerEngine(
    initialAspectRatio: initialAspectRatio,
    previewMode: previewMode,
  );
}
