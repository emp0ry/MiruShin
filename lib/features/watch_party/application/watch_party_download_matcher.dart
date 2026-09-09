import '../../downloads/domain/download_identity.dart';
import '../../downloads/domain/download_models.dart';
import '../../tracking/domain/tracking_sync_models.dart';
import '../domain/watch_party_models.dart';

class WatchPartyDownloadMatch {
  const WatchPartyDownloadMatch({
    required this.episode,
    required this.isLegacyFallback,
  });

  final DownloadedEpisode episode;
  final bool isLegacyFallback;
}

WatchPartyDownloadMatch? selectWatchPartyDownload({
  required SourceDescriptor descriptor,
  required Iterable<DownloadedEpisode> downloads,
  required bool Function(DownloadedEpisode episode) isPlayable,
}) {
  final List<DownloadedEpisode> exact = <DownloadedEpisode>[];
  final List<DownloadedEpisode> legacy = <DownloadedEpisode>[];
  final String descriptorHref = normalizeDownloadedEpisodeHref(
    descriptor.soraEpisodeHref,
  );

  for (final DownloadedEpisode episode in downloads) {
    if (!episode.isComplete || !isPlayable(episode)) continue;
    if (!_sameMedia(episode, descriptor) ||
        episode.addonId != descriptor.soraAddonId ||
        episode.seasonNumber != descriptor.seasonNumber ||
        episode.episodeNumber != descriptor.episodeNumber) {
      continue;
    }

    final bool precise = hasPreciseDownloadStreamIdentity(
      episode.streamPreference,
    );
    if (precise) {
      if (normalizeDownloadedEpisodeHref(episode.episodeHref) ==
              descriptorHref &&
          downloadPreferenceMatchesStream(
            episode.streamPreference,
            serverId: descriptor.serverId,
            voiceoverId: descriptor.voiceoverId,
          )) {
        exact.add(episode);
      }
    } else {
      // Very old records did not persist server/voiceover. They remain usable
      // only as the last-resort episode-level fallback requested by the user.
      legacy.add(episode);
    }
  }

  int newestFirst(DownloadedEpisode left, DownloadedEpisode right) =>
      right.updatedAt.compareTo(left.updatedAt);
  exact.sort(newestFirst);
  legacy.sort(newestFirst);
  if (exact.isNotEmpty) {
    return WatchPartyDownloadMatch(
      episode: exact.first,
      isLegacyFallback: false,
    );
  }
  if (legacy.isNotEmpty) {
    return WatchPartyDownloadMatch(
      episode: legacy.first,
      isLegacyFallback: true,
    );
  }
  return null;
}

bool _sameMedia(DownloadedEpisode episode, SourceDescriptor descriptor) {
  if (episode.mediaId == descriptor.mediaId) return true;
  final MediaIdentity downloadedIdentity = MediaIdentity.fromExternalIds(
    episode.media.externalIds,
    mediaId: episode.mediaId,
  );
  final MediaIdentity hostIdentity = MediaIdentity.fromExternalIds(
    descriptor.externalIds,
    mediaId: descriptor.mediaId,
  );
  return downloadedIdentity.hasProviderId &&
      hostIdentity.hasProviderId &&
      downloadedIdentity.matches(hostIdentity);
}
