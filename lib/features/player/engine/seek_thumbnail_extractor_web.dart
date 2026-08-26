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
  void cancelPending() {}

  @override
  Future<void> warm(SeekThumbnailSource source) async {}

  @override
  Future<SeekThumbnailExtractionResult> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
  }) async {
    return const SeekThumbnailExtractionResult.failure(
      SeekThumbnailFailure(
        scope: SeekThumbnailFailureScope.permanentSource,
        reason: SeekThumbnailFailureReason.unavailable,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
