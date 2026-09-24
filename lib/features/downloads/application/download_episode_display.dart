import 'package:path/path.dart' as p;

import '../../../shared/models/media_item.dart';
import '../../metadata/domain/anime_episode_metadata.dart';
import '../domain/download_models.dart';

String downloadedEpisodeQualityLabel(DownloadedEpisode episode) {
  final String downloadedQuality = episode.qualityLabel.trim();
  if (downloadedQuality.isNotEmpty) return downloadedQuality;
  return episode.streamPreference.qualityLabel.trim();
}

String downloadedEpisodeVoiceoverLabel(DownloadedEpisode episode) {
  final DownloadStreamPreference preference = episode.streamPreference;
  final String label = preference.voiceoverLabel.trim();
  if (label.isNotEmpty) return label;
  final String id = preference.voiceoverId.trim();
  if (id.isNotEmpty) return id;
  // Some modules model each dub as a separate server instead of exposing an
  // explicit voiceover track. In that case the server is the best audio label
  // available for the downloaded stream.
  final String server = preference.serverTitle.trim();
  return server.isNotEmpty ? server : preference.serverId.trim();
}

/// Best persisted estimate of the completed download's media size.
///
/// Progressive downloads normally know [DownloadedEpisode.totalBytes], while
/// segmented HLS/DASH downloads only know how many bytes they actually wrote.
/// Using the larger value covers both without changing in-progress semantics.
int downloadedEpisodeSizeBytes(DownloadedEpisode episode) {
  if (episode.totalBytes > episode.receivedBytes) return episode.totalBytes;
  return episode.receivedBytes;
}

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
  return downloadLocalFileUrl(p.join(root, episode.relDir, file));
}

/// Converts an absolute local path to a file URL using the path's syntax,
/// rather than the OS currently running the conversion. This matters when a
/// Windows download is restored or tested on another platform: on POSIX,
/// `Uri.file(r'C:\downloads\video.mp4')` otherwise treats the drive path as a
/// relative URI and produces no `file:` scheme.
String downloadLocalFileUrl(String path) {
  final String value = path.trim();
  if (value.isEmpty) return '';
  final bool windows =
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');
  return Uri.file(value, windows: windows).toString();
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
