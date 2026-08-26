import 'dart:io' show Platform;

import '../domain/playback_attempt_plan.dart';
import '../domain/player_models.dart';
import 'fvp_player_engine.dart';
import 'media_kit_player_engine.dart';
import 'player_engine.dart';
import 'youtube_embed_player_engine.dart';

PlayerBackend resolvePlayerEngineBackend(PlayerBackend backend) {
  if (Platform.isLinux) return PlayerBackend.fvp;
  return backend == PlayerBackend.auto ? PlayerBackend.mpv : backend;
}

bool isPlayerEngineBackendAvailable(
  PlayerBackend backend, {
  StreamType streamType = StreamType.unknown,
}) {
  return switch (backend) {
    PlayerBackend.auto => true,
    // media_kit/libmpv terminates the Windows process while opening some DASH
    // manifests. A Dart try/catch cannot recover from a native process abort,
    // so Auto treats MPV as unavailable only for that unsafe combination.
    PlayerBackend.mpv =>
      !Platform.isLinux &&
          !(Platform.isWindows && streamType == StreamType.dash),
    PlayerBackend.fvp => true,
  };
}

bool isPlayerEngineRouteAvailable(
  PlayerBackend backend,
  PlaybackRoute route, {
  StreamType streamType = StreamType.unknown,
  bool dashUsesHlsContainer = false,
}) {
  if (!isPlayerEngineBackendAvailable(backend, streamType: streamType)) {
    return false;
  }
  // The Windows FVP distribution omits FFmpeg's libxml2-backed MPD demuxer.
  // Its local-proxy route converts static DASH metadata to fMP4 HLS; a direct
  // MPD route cannot work and must not appear as a fake fallback attempt.
  if (Platform.isWindows &&
      backend == PlayerBackend.fvp &&
      streamType == StreamType.dash &&
      !dashUsesHlsContainer &&
      route == PlaybackRoute.direct) {
    return false;
  }
  return true;
}

bool get usesBrowserPlayerEngine => false;

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  PlayerBackend backend = PlayerBackend.auto,
  bool youtubeEmbed = false,
  String trailerBackLabel = 'Back',
}) {
  if (youtubeEmbed) {
    return YoutubeEmbedPlayerEngine(
      initialAspectRatio: initialAspectRatio,
      renderControlsInHtml: Platform.isWindows || Platform.isLinux,
      trailerBackLabel: trailerBackLabel,
    );
  }
  switch (resolvePlayerEngineBackend(backend)) {
    case PlayerBackend.auto:
    case PlayerBackend.mpv:
      return MediaKitPlayerEngine(initialAspectRatio: initialAspectRatio);
    case PlayerBackend.fvp:
      return FvpPlayerEngine(initialAspectRatio: initialAspectRatio);
  }
}
