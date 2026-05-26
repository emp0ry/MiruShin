import 'fvp_player_engine.dart';
import 'player_engine.dart';

PlayerEngine createPlayerEngine({double? initialAspectRatio}) {
  return FvpPlayerEngine(initialAspectRatio: initialAspectRatio);
}
