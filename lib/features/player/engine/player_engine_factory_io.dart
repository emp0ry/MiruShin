import 'dart:io' show Platform;

import '../domain/player_models.dart';
import 'fvp_player_engine.dart';
import 'media_kit_player_engine.dart';
import 'player_engine.dart';
import 'youtube_embed_player_engine.dart';
import 'youtube_trailer_fallback_player_engine.dart';

PlayerBackend resolvePlayerEngineBackend(PlayerBackend backend) {
  if (Platform.isLinux) return PlayerBackend.fvp;
  return backend == PlayerBackend.auto ? PlayerBackend.mpv : backend;
}

PlayerEngine createPlayerEngine({
  double? initialAspectRatio,
  bool previewMode = false,
  PlayerBackend backend = PlayerBackend.auto,
  bool youtubeEmbed = false,
}) {
  if (youtubeEmbed) {
    if (!_supportsYoutubeEmbedPlayer) {
      return YoutubeTrailerFallbackPlayerEngine(
        initialAspectRatio: initialAspectRatio,
      );
    }
    return YoutubeEmbedPlayerEngine(initialAspectRatio: initialAspectRatio);
  }
  switch (resolvePlayerEngineBackend(backend)) {
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

bool get _supportsYoutubeEmbedPlayer =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
