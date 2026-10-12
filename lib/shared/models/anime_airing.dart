import 'media_item.dart';

const anilistAiringKnownKey = 'anilist_airing_known';
const shikimoriAiringKnownKey = 'shikimori_airing_known';
const shikimoriEpisodesAiredKey = 'shikimori_episodes_aired';
const shikimoriNextEpisodeAtKey = 'shikimori_next_episode_at';

/// An episode/time pair belongs to one snapshot. Never combine a cached
/// episode number with a newer timestamp or extrapolate a weekly schedule.
class AnimeAiringSchedule {
  const AnimeAiringSchedule({this.nextEpisode, this.airingAt});

  final int? nextEpisode;
  final DateTime? airingAt;

  factory AnimeAiringSchedule.fromMedia(
    MediaItem media, {
    int? legacyNextEpisode,
    DateTime? legacyAiringAt,
  }) {
    final ids = media.externalIds;
    final episode = int.tryParse(ids[anilistNextAiringEpisodeKey] ?? '');
    final seconds = int.tryParse(ids[anilistNextAiringAtKey] ?? '');
    final cached = AnimeAiringSchedule(
      nextEpisode: episode != null && episode > 0 ? episode : null,
      airingAt: seconds != null && seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
          : null,
    );
    // New snapshots explicitly distinguish "no next airing" from a provider
    // that did not return this field. This also clears a finished title.
    if (ids[anilistAiringKnownKey] == 'true') return cached;
    final legacy = AnimeAiringSchedule(
      nextEpisode: legacyNextEpisode,
      airingAt: legacyAiringAt,
    );
    if (cached.nextEpisode == null) return legacy;
    if (legacy.nextEpisode == null) return cached;
    if (cached.airingAt != null &&
        (legacy.airingAt == null ||
            cached.airingAt!.isAfter(legacy.airingAt!))) {
      return cached;
    }
    return legacy;
  }

  static AnimeAiringSchedule forLibrary(
    MediaItem media, {
    int? nextEpisode,
    DateTime? airingAt,
    DateTime? now,
  }) {
    if (media.type != MediaType.anime) return const AnimeAiringSchedule();
    final at = now ?? DateTime.now();
    final anilist = AnimeAiringSchedule.fromMedia(
      media,
      legacyNextEpisode: nextEpisode,
      legacyAiringAt: airingAt,
    );
    if (anilist.isUpcoming(at)) return anilist;
    final aired = int.tryParse(
      media.externalIds[shikimoriEpisodesAiredKey] ?? '',
    );
    final shikiAt = DateTime.tryParse(
      media.externalIds[shikimoriNextEpisodeAtKey] ?? '',
    );
    if (aired != null && aired >= 0 && shikiAt != null && shikiAt.isAfter(at)) {
      return AnimeAiringSchedule(nextEpisode: aired + 1, airingAt: shikiAt);
    }
    return anilist;
  }

  bool isUpcoming(DateTime now) =>
      nextEpisode != null &&
      nextEpisode! > 0 &&
      airingAt != null &&
      airingAt!.isAfter(now);

  int? airedEpisodes(DateTime now) {
    final episode = nextEpisode;
    if (episode == null || episode <= 0) return null;
    // An expired next-airing row proves that ONE further episode aired. It
    // does not prove any subsequent episodes aired during an API outage.
    return airingAt != null && !airingAt!.isAfter(now) ? episode : episode - 1;
  }
}

Map<String, String> mergeAiringMetadata(
  Map<String, String> cached,
  Map<String, String> incoming,
) {
  final result = {...cached};
  if (incoming[anilistAiringKnownKey] == 'true') {
    result.remove(anilistNextAiringEpisodeKey);
    result.remove(anilistNextAiringAtKey);
  }
  if (incoming[shikimoriAiringKnownKey] == 'true') {
    result.remove(shikimoriEpisodesAiredKey);
    result.remove(shikimoriNextEpisodeAtKey);
  }
  return result..addAll(incoming);
}

int? animeEpisodesBehind(
  MediaItem media, {
  required int progress,
  int? nextEpisode,
  DateTime? airingAt,
  DateTime? now,
}) {
  if (media.type != MediaType.anime) return null;
  final at = now ?? DateTime.now();
  final schedule = AnimeAiringSchedule.forLibrary(
    media,
    nextEpisode: nextEpisode,
    airingAt: airingAt,
    now: at,
  );
  var aired = schedule.airedEpisodes(at);
  final shikiAired = int.tryParse(
    media.externalIds[shikimoriEpisodesAiredKey] ?? '',
  );
  if (!schedule.isUpcoming(at) &&
      shikiAired != null &&
      shikiAired >= 0 &&
      (aired == null || shikiAired > aired)) {
    aired = shikiAired;
  }
  if (aired == null) return null;
  final behind = aired - (progress < 0 ? 0 : progress);
  return behind > 0 ? behind : null;
}
