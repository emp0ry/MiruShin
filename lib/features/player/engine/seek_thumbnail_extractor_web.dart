import '../domain/player_models.dart';
import 'seek_thumbnail.dart';

bool get seekThumbnailExtractionSupported => false;

PlayerBackend seekThumbnailExtractionBackend(PlayerBackend _) {
  return PlayerBackend.auto;
}

SeekThumbnailExtractor createSeekThumbnailExtractor(PlayerBackend backend) {
  return const _UnsupportedSeekThumbnailExtractor();
}

class _UnsupportedSeekThumbnailExtractor implements SeekThumbnailExtractor {
  const _UnsupportedSeekThumbnailExtractor();

  @override
  Future<SeekThumbnail?> extract({
    required source,
    required position,
    required duration,
    required sourceKey,
  }) async {
    return null;
  }

  @override
  Future<void> dispose() async {}
}
