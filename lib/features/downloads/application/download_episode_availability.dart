import '../../../shared/models/media_item.dart';
import '../../addons/domain/sora_models.dart';

const String downloadAvailableEpisodeLimitKey =
    'mirushin_download_available_episode_limit';

int? anilistAiredEpisodeLimit(MediaItem item, {DateTime? now}) {
  if (item.type != MediaType.anime ||
      !item.externalIds.containsKey('anilist')) {
    return null;
  }

  final int? nextEpisode = int.tryParse(
    item.externalIds[anilistNextAiringEpisodeKey] ?? '',
  );
  if (nextEpisode == null || nextEpisode <= 0) return null;

  final int? airingAtSeconds = int.tryParse(
    item.externalIds[anilistNextAiringAtKey] ?? '',
  );
  if (airingAtSeconds != null && airingAtSeconds > 0) {
    final DateTime airingAt = DateTime.fromMillisecondsSinceEpoch(
      airingAtSeconds * 1000,
    );
    if (!airingAt.isAfter(now ?? DateTime.now())) {
      return nextEpisode;
    }
  }
  return nextEpisode - 1;
}

/// Returns the number of numbered episode rows that belong on the offline
/// page for one season.
///
/// TMDB exposes real seasons, so an individual season count takes precedence
/// over the title-wide total. AniList entries already represent one anime
/// season; their `seasons` list contains related franchise entries and must
/// not be treated as season metadata.
int offlineSeasonEpisodeTotal(
  MediaItem item,
  int season, {
  required int highestDownloadedEpisode,
  int sourceAvailableEpisodeLimit = 0,
  DateTime? now,
}) {
  int plannedTotal = 0;
  if (_usesRealSeasonMetadata(item)) {
    for (final MediaSeason metadata in item.seasons) {
      if (metadata.seasonNumber == season && metadata.episodeCount > 0) {
        plannedTotal = metadata.episodeCount;
        break;
      }
    }
    if (plannedTotal == 0 &&
        item.seasons.isEmpty &&
        season <= 1 &&
        (item.episodeCount ?? 0) > 0) {
      plannedTotal = item.episodeCount!;
    }
  } else if ((item.episodeCount ?? 0) > 0) {
    plannedTotal = item.episodeCount!;
  }

  int total = plannedTotal > 0 ? plannedTotal : highestDownloadedEpisode;
  final int? anilistLimit = anilistAiredEpisodeLimit(item, now: now);
  if (anilistLimit != null) {
    total = _capEpisodeTotal(
      total,
      anilistLimit,
      highestDownloadedEpisode: highestDownloadedEpisode,
    );
  } else if (_isOngoing(item) && sourceAvailableEpisodeLimit > 0) {
    if (total == 0) total = sourceAvailableEpisodeLimit;
    total = _capEpisodeTotal(
      total,
      sourceAvailableEpisodeLimit,
      highestDownloadedEpisode: highestDownloadedEpisode,
    );
  }
  return total;
}

int downloadedAvailableEpisodeLimit(MediaItem item) {
  return int.tryParse(
        item.externalIds[downloadAvailableEpisodeLimitKey] ?? '',
      ) ??
      0;
}

bool _usesRealSeasonMetadata(MediaItem item) {
  if (item.id.startsWith('tmdb:')) return true;
  return item.sourceProvider.trim().toLowerCase() == 'tmdb';
}

bool _isOngoing(MediaItem item) {
  final String status = item.statusLabel.trim().toLowerCase().replaceAll(
    '_',
    ' ',
  );
  return status.contains('releasing') ||
      status.contains('airing') ||
      status.contains('ongoing') ||
      status.contains('returning') ||
      status.contains('in production') ||
      status.contains('continuing');
}

int _capEpisodeTotal(
  int total,
  int limit, {
  required int highestDownloadedEpisode,
}) {
  final int safeLimit = limit < highestDownloadedEpisode
      ? highestDownloadedEpisode
      : limit;
  if (total == 0 || total > safeLimit) return safeLimit;
  return total;
}

int airedDownloadEpisodeTotal(
  MediaItem item,
  int plannedTotal, {
  DateTime? now,
}) {
  final int? limit = anilistAiredEpisodeLimit(item, now: now);
  if (limit == null || plannedTotal <= limit) return plannedTotal;
  return limit;
}

List<SoraEpisode> airedDownloadEpisodes(
  List<SoraEpisode> episodes,
  MediaItem item, {
  DateTime? now,
}) {
  final int? limit = anilistAiredEpisodeLimit(item, now: now);
  if (limit == null) return episodes;
  return episodes
      .where(
        (SoraEpisode episode) => episode.number <= 0 || episode.number <= limit,
      )
      .toList(growable: false);
}
