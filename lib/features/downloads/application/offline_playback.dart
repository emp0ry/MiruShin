import 'package:path/path.dart' as p;

import '../../../shared/models/media_item.dart';
import '../../player/domain/player_models.dart';
import 'download_episode_display.dart';
import '../domain/download_models.dart';

/// Builds a [MediaPlaybackItem] that plays a downloaded episode entirely from
/// local files through the existing player. The `sora_addon_id` /
/// `sora_episode_href` external ids match the online watch flow so offline
/// playback shares the same saved progress.
MediaPlaybackItem buildOfflinePlaybackItem({
  required DownloadedEpisode episode,
  required String rootPath,
  List<DownloadedEpisode> moduleEpisodes = const <DownloadedEpisode>[],
}) {
  final String videoPath = p.join(
    rootPath,
    episode.relDir,
    episode.videoFileName,
  );
  final String fileUrl = Uri.file(videoPath).toString();
  final StreamType streamType = episode.kind == DownloadKind.hls
      ? StreamType.hls
      : StreamType.mp4;

  final List<SubtitleTrack> subtitles = <SubtitleTrack>[
    for (final DownloadedSubtitle s in episode.subtitles)
      SubtitleTrack(
        id: s.fileName,
        label: s.label.isNotEmpty ? s.label : s.language,
        url: p.join(rootPath, episode.relDir, s.fileName),
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

  final MediaItem media = episode.media;
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
    },
    servers: <MediaServer>[server],
    seasons: _buildSeasons(moduleEpisodes),
    currentEpisodeId: '${episode.seasonNumber}_${episode.episodeNumber}',
    skipMarkers: _skipMarkers(episode),
    seasonNumber: episode.seasonNumber,
    episodeNumber: episode.episodeNumber,
    episodeCount: media.episodeCount,
  );
}

/// The next downloaded+completed episode in the same module after [current],
/// for offline auto-next / in-player episode jumps. Returns null at the end.
DownloadedEpisode? nextDownloadedEpisode(
  DownloadedEpisode current,
  List<DownloadedEpisode> moduleEpisodes,
) {
  final List<DownloadedEpisode> sorted = _sortedCompleted(moduleEpisodes);
  final int index = sorted.indexWhere(
    (DownloadedEpisode e) => e.id == current.id,
  );
  if (index < 0 || index + 1 >= sorted.length) return null;
  return sorted[index + 1];
}

DownloadedEpisode? downloadedEpisodeByHref(
  String href,
  List<DownloadedEpisode> moduleEpisodes,
) {
  for (final DownloadedEpisode e in moduleEpisodes) {
    if (e.episodeHref == href && e.isComplete) return e;
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

List<Season> _buildSeasons(List<DownloadedEpisode> moduleEpisodes) {
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
            _playerEpisode(e),
        ],
      ),
  ];
}

Episode _playerEpisode(DownloadedEpisode e) {
  final String title = downloadedEpisodeDisplayTitle(e);
  return Episode(
    id: e.episodeHref,
    number: e.episodeNumber.round(),
    title: title.isNotEmpty ? title : 'Episode ${e.displayNumber}',
    thumbnailUrl: downloadedEpisodeImageUrl(e),
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
