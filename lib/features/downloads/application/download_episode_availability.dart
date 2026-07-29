import '../../../shared/models/media_item.dart';
import '../../addons/domain/sora_models.dart';

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
