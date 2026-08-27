import 'package:path/path.dart' as p;

import '../../../shared/models/media_item.dart';
import '../../player/domain/player_models.dart';
import '../domain/download_models.dart';
import 'download_episode_display.dart';

/// Builds a [MediaPlaybackItem] that plays a downloaded episode entirely from
/// local files through the existing player. The `sora_addon_id` /
/// `sora_episode_href` external ids match the online watch flow so offline
/// playback shares the same saved progress.
MediaPlaybackItem buildOfflinePlaybackItem({
  required DownloadedEpisode episode,
  required String rootPath,
  List<DownloadedEpisode> moduleEpisodes = const <DownloadedEpisode>[],
  PlaybackStartPolicy startPolicy = PlaybackStartPolicy.resumeSaved,
}) {
  final String videoPath = p.join(
    rootPath,
    episode.relDir,
    episode.videoFileName,
  );
  final String fileUrl = Uri.file(videoPath).toString();
  // Keep the original container type even when an offline DASH download is
  // represented by local HLS metadata. The player uses this distinction to
  // select the backend that can safely consume those fragmented-MP4 tracks.
  final StreamType streamType = switch (episode.kind) {
    DownloadKind.mp4 => StreamType.mp4,
    DownloadKind.hls => StreamType.hls,
    DownloadKind.dash => StreamType.dash,
  };

  final List<SubtitleTrack> subtitles = <SubtitleTrack>[
    for (final DownloadedSubtitle s in episode.subtitles)
      SubtitleTrack(
        id: s.fileName,
        label: s.label.isNotEmpty ? s.label : s.language,
        url: Uri.file(p.join(rootPath, episode.relDir, s.fileName)).toString(),
        language: s.language,
        format: _subtitleFormat(s.fileName),
      ),
  ];

  final MediaServer server = MediaServer(
    id: 'offline',
    name: episode.addonName.isNotEmpty ? episode.addonName : 'Downloaded',
    sourceName: episode.addonId,
    url: fileUrl,
    streamType: streamType,
    subtitles: subtitles,
  );

  final MediaItem media = downloadedMediaWithLocalArtwork(
    episode,
    rootPath: rootPath,
  );
  final String episodeTitle = downloadedEpisodeDisplayTitle(episode);

  return MediaPlaybackItem(
    id: media.id,
    title: media.title,
    mediaType: media.type,
    originalTitle: media.originalTitle,
    subtitle: episodeTitle.isNotEmpty
        ? episodeTitle
        : (episode.displayNumber.isNotEmpty
              ? 'Episode ${episode.displayNumber}'
              : ''),
    posterUrl: media.posterUrl,
    backdropUrl: media.backdropUrl,
    externalIds: <String, String>{
      ...media.externalIds,
      'sora_addon_id': episode.addonId,
      'sora_episode_href': episode.episodeHref,
      'mirushin_offline_download_id': episode.id,
      'mirushin_offline_media_path': p.join(
        episode.relDir,
        episode.videoFileName,
      ),
      'mirushin_offline_quality': episode.qualityLabel,
    },
    servers: <MediaServer>[server],
    seasons: _buildSeasons(moduleEpisodes, rootPath: rootPath),
    currentEpisodeId: '${episode.seasonNumber}_${episode.episodeNumber}',
    skipMarkers: _skipMarkers(episode),
    seasonNumber: episode.seasonNumber,
    episodeNumber: episode.episodeNumber,
    episodeCount: media.episodeCount,
    startPolicy: startPolicy,
  );
}

/// The next downloaded+completed episode in the same module after [current],
/// for offline auto-next / in-player episode jumps. Returns null at the end.
DownloadedEpisode? nextDownloadedEpisode(
  DownloadedEpisode current,
  List<DownloadedEpisode> moduleEpisodes,
) {
  final List<DownloadedEpisode> sorted = _sortedCompleted(moduleEpisodes);
  final int index = _currentDownloadIndex(current, sorted);
  if (index < 0 || index + 1 >= sorted.length) return null;
  return sorted[index + 1];
}

DownloadedEpisode? downloadedEpisodeByHref(
  String href,
  List<DownloadedEpisode> moduleEpisodes,
) {
  final String normalizedHref = normalizeDownloadedEpisodeHref(href);
  for (final DownloadedEpisode e in moduleEpisodes) {
    if (e.isComplete &&
        (e.episodeHref == href ||
            normalizeDownloadedEpisodeHref(e.episodeHref) == normalizedHref)) {
      return e;
    }
  }
  return null;
}

int _currentDownloadIndex(
  DownloadedEpisode current,
  List<DownloadedEpisode> episodes,
) {
  int index = episodes.indexWhere((DownloadedEpisode e) => e.id == current.id);
  if (index >= 0) return index;
  final String href = normalizeDownloadedEpisodeHref(current.episodeHref);
  if (href.isNotEmpty) {
    index = episodes.indexWhere(
      (DownloadedEpisode e) =>
          normalizeDownloadedEpisodeHref(e.episodeHref) == href,
    );
    if (index >= 0) return index;
  }
  return episodes.indexWhere(
    (DownloadedEpisode e) =>
        e.addonId == current.addonId &&
        e.seasonNumber == current.seasonNumber &&
        e.episodeNumber == current.episodeNumber,
  );
}

String normalizeDownloadedEpisodeHref(String value) {
  final String trimmed = value.trim();
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }
  final String path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return uri
      .replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
        path: path,
        fragment: '',
      )
      .toString();
}

class OfflinePlayerContinuation {
  const OfflinePlayerContinuation({
    required this.episode,
    required this.startInFullscreen,
    required this.startPolicy,
  });

  final DownloadedEpisode episode;
  final bool startInFullscreen;
  final PlaybackStartPolicy startPolicy;
}

OfflinePlayerContinuation? offlinePlayerContinuationForResult({
  required Object? result,
  required DownloadedEpisode current,
  required List<DownloadedEpisode> moduleEpisodes,
}) {
  if (result is PlayerEpisodeSelectionResult) {
    final DownloadedEpisode? selected = downloadedEpisodeByHref(
      result.episodeHref,
      moduleEpisodes,
    );
    return selected == null
        ? null
        : OfflinePlayerContinuation(
            episode: selected,
            startInFullscreen: result.startInFullscreen,
            startPolicy: PlaybackStartPolicy.resumeSaved,
          );
  }
  if (result is PlayerNextEpisodeResult) {
    final DownloadedEpisode? next = nextDownloadedEpisode(
      current,
      moduleEpisodes,
    );
    return next == null
        ? null
        : OfflinePlayerContinuation(
            episode: next,
            startInFullscreen: result.startInFullscreen,
            startPolicy: result.startPolicy,
          );
  }
  return null;
}

/// Picks the downloaded episode the offline page should label as "Continue".
///
/// A fresh full download that starts at episode 1 has no continuation yet, but
/// if earlier episodes are not available locally we continue from the first
/// playable gap episode.
DownloadedEpisode? offlineContinueEpisode(
  List<DownloadedEpisode> episodes, {
  required bool Function(DownloadedEpisode episode) isWatched,
}) {
  final List<DownloadedEpisode> sorted = _sortedCompleted(episodes)
      .where((DownloadedEpisode e) => e.episodeNumber >= 1)
      .toList(growable: false);
  if (sorted.isEmpty) return null;

  bool hasWatchedDownload = false;
  for (final DownloadedEpisode e in sorted) {
    if (isWatched(e)) {
      hasWatchedDownload = true;
      continue;
    }
    final bool startsAfterFirstEpisode =
        e.seasonNumber > 1 || e.episodeNumber.round() > 1;
    return hasWatchedDownload || startsAfterFirstEpisode ? e : null;
  }
  return null;
}

List<DownloadedEpisode> _sortedCompleted(List<DownloadedEpisode> episodes) {
  final List<DownloadedEpisode> list =
      episodes
          .where((DownloadedEpisode e) => e.isComplete)
          .toList(growable: false)
        ..sort((DownloadedEpisode a, DownloadedEpisode b) {
          final int s = a.seasonNumber.compareTo(b.seasonNumber);
          if (s != 0) return s;
          return a.episodeNumber.compareTo(b.episodeNumber);
        });
  return list;
}

List<Season> _buildSeasons(
  List<DownloadedEpisode> moduleEpisodes, {
  required String rootPath,
}) {
  if (moduleEpisodes.isEmpty) return const <Season>[];
  final Map<int, List<DownloadedEpisode>> bySeason =
      <int, List<DownloadedEpisode>>{};
  for (final DownloadedEpisode e in _sortedCompleted(moduleEpisodes)) {
    bySeason.putIfAbsent(e.seasonNumber, () => <DownloadedEpisode>[]).add(e);
  }
  final List<int> seasons = bySeason.keys.toList()..sort();
  final bool multi = seasons.length > 1;
  return <Season>[
    for (final int season in seasons)
      Season(
        number: season,
        title: multi ? 'Season $season' : 'Episodes',
        episodes: <Episode>[
          for (final DownloadedEpisode e in bySeason[season]!)
            _playerEpisode(e, rootPath: rootPath),
        ],
      ),
  ];
}

Episode _playerEpisode(DownloadedEpisode e, {required String rootPath}) {
  final String title = downloadedEpisodeDisplayTitle(e);
  return Episode(
    id: e.episodeHref,
    number: e.episodeNumber.round(),
    title: title.isNotEmpty ? title : 'Episode ${e.displayNumber}',
    thumbnailUrl: downloadedEpisodeImageUrl(e, rootPath: rootPath),
  );
}

SkipMarkers _skipMarkers(DownloadedEpisode e) {
  Duration? opStart;
  Duration? opEnd;
  if (e.openingStart != null &&
      e.openingEnd != null &&
      e.openingStart! >= 0 &&
      e.openingEnd! > e.openingStart!) {
    opStart = Duration(seconds: e.openingStart!);
    opEnd = Duration(seconds: e.openingEnd!);
  }
  Duration? edStart;
  Duration? edEnd;
  if (e.endingStart != null &&
      e.endingEnd != null &&
      e.endingStart! >= 0 &&
      e.endingEnd! > e.endingStart!) {
    edStart = Duration(seconds: e.endingStart!);
    edEnd = Duration(seconds: e.endingEnd!);
  }
  return SkipMarkers(
    openingStart: opStart,
    openingEnd: opEnd,
    endingStart: edStart,
    endingEnd: edEnd,
  );
}

SubtitleFormat _subtitleFormat(String fileName) {
  final String lower = fileName.toLowerCase();
  if (lower.endsWith('.vtt')) return SubtitleFormat.vtt;
  if (lower.endsWith('.srt')) return SubtitleFormat.srt;
  if (lower.endsWith('.ass') || lower.endsWith('.ssa')) {
    return SubtitleFormat.ass;
  }
  return SubtitleFormat.unknown;
}
