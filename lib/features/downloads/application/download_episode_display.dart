import '../../../shared/models/media_item.dart';
import '../../metadata/domain/anime_episode_metadata.dart';
import '../domain/download_models.dart';

String downloadedEpisodeDisplayTitle(DownloadedEpisode episode) {
  final String title = bestPlayerEpisodeTitle(
    moduleTitle: episode.episodeTitle,
    tvdbTitle: _episodeDataString(episode, 'tvdbTitle'),
    metadataTitle: _episodeDataString(episode, 'metadataTitle'),
    number: episode.episodeNumber,
  );
  final String cleaned = _cleanEpisodePrefix(title);
  return isGenericEpisodeTitle(cleaned, episode.episodeNumber) ? '' : cleaned;
}

String downloadedEpisodeImageUrl(
  DownloadedEpisode episode, {
  MediaItem? media,
}) {
  for (final String image in <String>[
    _episodeDataString(episode, 'metadataImage'),
    episode.episodeImage,
    media?.posterUrl ?? episode.media.posterUrl,
  ]) {
    final String trimmed = image.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _episodeDataString(DownloadedEpisode episode, String key) {
  final Object? value = episode.episodeData[key];
  return value is String ? value.trim() : '';
}

String _cleanEpisodePrefix(String title) {
  return title
      .trim()
      .replaceFirst(
        RegExp(r'^\s*(episode|ep)\s*\d+\s*[-:–—]?\s*', caseSensitive: false),
        '',
      )
      .trim();
}
