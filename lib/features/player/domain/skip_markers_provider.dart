import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/metadata/data/anilist_anime_client.dart';
import '../../../features/metadata/data/anira_client.dart';
import '../../../features/metadata/domain/anira_models.dart';
import '../application/playback_controller.dart';
import '../application/player_settings.dart';
import '../data/aniskip_client.dart';
import '../domain/player_models.dart';

final _aniSkipForPlayerProvider = Provider<AniSkipClient>(
  (Ref ref) => AniSkipClient(),
);

final _aniListForSkipProvider = Provider<AniListAnimeClient>(
  (Ref ref) => AniListAnimeClient(),
);

final _aniraForPlayerProvider = Provider<AniraClient>(
  (Ref ref) => AniraClient(),
);

/// Fetches OP/ED timeskips for the current playback item.
///
/// Addon-provided markers take priority per field. Remote databases
/// (AniSkip → Anira) fill in whichever fields the addon left empty.
final skipMarkersProvider = FutureProvider.autoDispose<SkipMarkers>((
  Ref ref,
) async {
  final _SkipMarkerRequest request = ref.watch(
    playbackControllerProvider.select(_SkipMarkerRequest.fromState),
  );
  final MediaPlaybackItem? item = request.item;
  if (item == null) return const SkipMarkers();

  final SkipMarkers addonMarkers = item.skipMarkers;
  final PlayerSettings settings =
      ref.watch(playerSettingsProvider).value ?? const PlayerSettings();
  final bool useAniSkip = settings.useAniSkip;
  final SkipMarkersSource source = settings.skipMarkersSource;

  // When addon is the primary source and already has both markers, skip remote.
  if (source == SkipMarkersSource.addon &&
      addonMarkers.hasOpening &&
      addonMarkers.hasEnding) {
    return addonMarkers;
  }

  if (!useAniSkip) return addonMarkers;

  final int? malId = await _resolveMalId(ref, item);
  if (malId == null) return addonMarkers;

  final int episode = item.episodeNumber.round();

  // Try AniSkip first.
  final SkipMarkers aniSkipMarkers = await ref
      .watch(_aniSkipForPlayerProvider)
      .getSkipMarkers(
        malId: malId,
        episode: episode,
        episodeLength: request.episodeLength,
      );

  // Try Anira for any fields still missing after AniSkip.
  SkipMarkers remoteMarkers = aniSkipMarkers;
  if (!remoteMarkers.hasOpening || !remoteMarkers.hasEnding) {
    final AniraClient anira = ref.watch(_aniraForPlayerProvider);
    final AniraEpisodeTimeskips? timeskips = await anira.getEpisodeTimeskips(
      malId.toString(),
      episode,
    );
    if (timeskips != null) {
      Duration? sec(double? v) =>
          v != null ? Duration(milliseconds: (v * 1000).round()) : null;
      final SkipMarkers aniraMarkers = SkipMarkers(
        openingStart: sec(timeskips.openingStart),
        openingEnd: sec(timeskips.openingEnd),
        endingStart: sec(timeskips.endingStart),
        endingEnd: sec(timeskips.endingEnd),
      );
      remoteMarkers = remoteMarkers.withFallback(aniraMarkers);
    }
  }

  // Primary source wins per field; the other fills any gaps.
  if (source == SkipMarkersSource.mirushin) {
    return remoteMarkers.withFallback(addonMarkers);
  }
  return addonMarkers.withFallback(remoteMarkers);
});

Future<int?> _resolveMalId(Ref ref, MediaPlaybackItem item) async {
  final int? directMalId = int.tryParse(item.externalIds['mal'] ?? '');
  if (directMalId != null) return directMalId;

  final int? anilistId = _anilistIdFromItem(item);
  if (anilistId == null) return null;

  try {
    final AniListAnimeDetails? details = await ref
        .watch(_aniListForSkipProvider)
        .getById(anilistId);
    return details?.malId;
  } on Object {
    return null;
  }
}

int? _anilistIdFromItem(MediaPlaybackItem item) {
  final int? fromExternal = int.tryParse(item.externalIds['anilist'] ?? '');
  if (fromExternal != null) return fromExternal;

  final List<String> parts = item.id.split(':');
  if (parts.length >= 2 && parts.first == 'anilist') {
    return int.tryParse(parts.last);
  }
  return null;
}

class _SkipMarkerRequest {
  const _SkipMarkerRequest({
    required this.item,
    required this.mediaId,
    required this.currentEpisodeId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.malId,
    required this.anilistId,
    required this.episodeLength,
  });

  final MediaPlaybackItem? item;
  final String mediaId;
  final String currentEpisodeId;
  final int seasonNumber;
  final double episodeNumber;
  final String malId;
  final String anilistId;
  final Duration episodeLength;

  factory _SkipMarkerRequest.fromState(PlaybackState state) {
    final MediaPlaybackItem? item = state.item;
    final bool hasDuration = state.engine?.value.isInitialized == true;
    return _SkipMarkerRequest(
      item: item,
      mediaId: item?.id ?? '',
      currentEpisodeId: item?.currentEpisodeId ?? '',
      seasonNumber: item?.seasonNumber ?? 0,
      episodeNumber: item?.episodeNumber ?? 0,
      malId: item?.externalIds['mal'] ?? '',
      anilistId: item?.externalIds['anilist'] ?? '',
      episodeLength: hasDuration ? state.engine!.value.duration : Duration.zero,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _SkipMarkerRequest &&
        mediaId == other.mediaId &&
        currentEpisodeId == other.currentEpisodeId &&
        seasonNumber == other.seasonNumber &&
        episodeNumber == other.episodeNumber &&
        malId == other.malId &&
        anilistId == other.anilistId &&
        episodeLength.inSeconds == other.episodeLength.inSeconds;
  }

  @override
  int get hashCode => Object.hash(
    mediaId,
    currentEpisodeId,
    seasonNumber,
    episodeNumber,
    malId,
    anilistId,
    episodeLength.inSeconds,
  );
}
