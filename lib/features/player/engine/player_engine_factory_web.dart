import '../domain/playback_attempt_plan.dart';
import '../domain/player_models.dart';
import 'player_engine.dart';
import 'video_player_engine.dart';

PlayerBackend resolvePlayerEngineBackend(PlayerBackend backend) => backend;

bool isPlayerEngineBackendAvailable(
  PlayerBackend backend, {
  StreamType streamType = StreamType.unknown,
}) {
  return backend == PlayerBackend.auto;
}

bool isPlayerEngineRouteAvailable(
  PlayerBackend backend,
  PlaybackRoute route, {
  StreamType streamType = StreamType.unknown,
}) {
  return backend == PlayerBackend.auto && route == PlaybackRoute.direct;
}

bool get usesBrowserPlayerEngine => true;

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  PlayerBackend backend = PlayerBackend.auto,
  bool youtubeEmbed = false,
  String trailerBackLabel = 'Back',
}) {
  // Web keeps the browser video backend. The native MPV/FVP engines are FFI
  // based and are intentionally not selected in web builds.
  return VideoPlayerEngine(initialAspectRatio: initialAspectRatio);
}
