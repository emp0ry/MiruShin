import 'package:path/path.dart' as p;

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
  String? rootPath,
}) {
  for (final String image in <String>[
    _downloadFileUrl(rootPath, episode, episode.episodeImageFileName),
    _downloadFileUrl(rootPath, episode, episode.mediaPosterFileName),
    _downloadFileUrl(rootPath, episode, episode.mediaBackdropFileName),
    _episodeDataString(episode, 'metadataImage'),
    episode.episodeImage,
    media?.posterUrl ?? episode.media.posterUrl,
  ]) {
    final String trimmed = image.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

MediaItem downloadedMediaWithLocalArtwork(
  DownloadedEpisode episode, {
  String? rootPath,
}) {
  final MediaItem media = episode.media;
  final String posterUrl = _downloadFileUrl(
    rootPath,
    episode,
    episode.mediaPosterFileName,
  ).trim();
  final String backdropUrl = _downloadFileUrl(
    rootPath,
    episode,
    episode.mediaBackdropFileName,
  ).trim();
  if (posterUrl.isEmpty && backdropUrl.isEmpty) return media;
  return media.copyWith(
    posterUrl: posterUrl.isNotEmpty ? posterUrl : media.posterUrl,
    backdropUrl: backdropUrl.isNotEmpty ? backdropUrl : media.backdropUrl,
  );
}

String _episodeDataString(DownloadedEpisode episode, String key) {
  final Object? value = episode.episodeData[key];
  return value is String ? value.trim() : '';
}

String _downloadFileUrl(
  String? rootPath,
  DownloadedEpisode episode,
  String fileName,
) {
  final String root = rootPath?.trim() ?? '';
  final String file = fileName.trim();
  if (root.isEmpty || file.isEmpty) return '';
  return Uri.file(p.join(root, episode.relDir, file)).toString();
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
