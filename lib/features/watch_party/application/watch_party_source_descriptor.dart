import '../../downloads/domain/download_identity.dart';
import '../../player/application/playback_controller.dart';
import '../../player/domain/player_models.dart';
import '../domain/watch_party_models.dart';

SourceDescriptor? watchPartySourceDescriptorFor(PlaybackState playback) {
  final MediaPlaybackItem? item = playback.item;
  if (item == null) return null;
  final String addonId = item.externalIds['sora_addon_id']?.trim() ?? '';
  final String href = item.externalIds['sora_episode_href']?.trim() ?? '';
  if (addonId.isEmpty || href.isEmpty) return null;

  final bool offline = playback.server?.id == 'offline';
  final String? serverId =
      _nonEmpty(item.externalIds[offlineOriginServerIdKey]) ??
      (offline ? null : _nonEmpty(playback.server?.id));
  final String? voiceoverId =
      _nonEmpty(item.externalIds[offlineOriginVoiceoverIdKey]) ??
      (offline ? null : _nonEmpty(playback.voiceover?.id));
  final String? qualityId =
      _nonEmpty(item.externalIds[offlineOriginQualityIdKey]) ??
      (offline ? null : _nonEmpty(playback.quality?.id));

  return SourceDescriptor(
    mediaId: item.id,
    title: item.title,
    originalTitle: item.originalTitle,
    posterUrl: _safeVisualUrl(
      item.posterUrl,
      fallback: item.externalIds[offlineOriginPosterUrlKey],
    ),
    backdropUrl: _safeVisualUrl(
      item.backdropUrl,
      fallback: item.externalIds[offlineOriginBackdropUrlKey],
    ),
    mediaType: item.mediaType,
    externalIds: <String, String>{
      for (final MapEntry<String, String> entry in item.externalIds.entries)
        if (!entry.key.startsWith('mirushin_offline_') &&
            !_isLocalFileUrl(entry.value))
          entry.key: entry.value,
    },
    soraAddonId: addonId,
    soraEpisodeHref: href,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    serverId: serverId,
    voiceoverId: voiceoverId,
    qualityId: qualityId,
    episodeCount: item.episodeCount,
  );
}

String _safeVisualUrl(String current, {String? fallback}) {
  if (!_isLocalFileUrl(current)) return current;
  final String cleanFallback = fallback?.trim() ?? '';
  return _isLocalFileUrl(cleanFallback) ? '' : cleanFallback;
}

bool _isLocalFileUrl(String value) {
  return Uri.tryParse(value.trim())?.scheme.toLowerCase() == 'file';
}

String? _nonEmpty(String? value) {
  final String clean = value?.trim() ?? '';
  return clean.isEmpty ? null : clean;
}
