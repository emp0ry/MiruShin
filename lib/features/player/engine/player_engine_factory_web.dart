import 'player_engine.dart';
import 'video_player_engine.dart';

PlayerEngine createPlayerEngine({double? initialAspectRatio}) {
  return VideoPlayerEngine(initialAspectRatio: initialAspectRatio);
}
