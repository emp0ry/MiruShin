import '../domain/player_models.dart';
import 'fvp_player_engine.dart';
import 'media_kit_player_engine.dart';
import 'player_engine.dart';

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  bool previewMode = false,
  PlayerBackend backend = PlayerBackend.auto,
}) {
  switch (backend) {
    case PlayerBackend.auto:
    case PlayerBackend.mpv:
      return MediaKitPlayerEngine(
        initialAspectRatio: initialAspectRatio,
        previewMode: previewMode,
      );
    case PlayerBackend.fvp:
      return FvpPlayerEngine(
        initialAspectRatio: initialAspectRatio,
        previewMode: previewMode,
      );
  }
}
