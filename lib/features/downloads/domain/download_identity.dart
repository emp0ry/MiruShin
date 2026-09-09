import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'download_models.dart';

const String offlineOriginServerIdKey = 'mirushin_offline_origin_server_id';
const String offlineOriginVoiceoverIdKey =
    'mirushin_offline_origin_voiceover_id';
const String offlineOriginQualityIdKey = 'mirushin_offline_origin_quality_id';
const String offlineOriginPosterUrlKey = 'mirushin_offline_origin_poster_url';
const String offlineOriginBackdropUrlKey =
    'mirushin_offline_origin_backdrop_url';

String cleanDownloadStreamId(String? value) => value?.trim() ?? '';

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

bool hasPreciseDownloadStreamIdentity(DownloadStreamPreference preference) {
  return cleanDownloadStreamId(preference.serverId).isNotEmpty;
}

String downloadStreamVariantKey(DownloadStreamPreference preference) {
  final String serverId = cleanDownloadStreamId(preference.serverId);
  final String voiceoverId = cleanDownloadStreamId(preference.voiceoverId);
  if (serverId.isEmpty) return 'legacy';
  return 'server=${Uri.encodeComponent(serverId)}&voiceover='
      '${Uri.encodeComponent(voiceoverId)}';
}

bool sameDownloadedStreamVariant(
  DownloadStreamPreference left,
  DownloadStreamPreference right,
) {
  final bool leftPrecise = hasPreciseDownloadStreamIdentity(left);
  final bool rightPrecise = hasPreciseDownloadStreamIdentity(right);
  if (!leftPrecise || !rightPrecise) return !leftPrecise && !rightPrecise;
  return cleanDownloadStreamId(left.serverId) ==
          cleanDownloadStreamId(right.serverId) &&
      cleanDownloadStreamId(left.voiceoverId) ==
          cleanDownloadStreamId(right.voiceoverId);
}

bool downloadPreferenceMatchesStream(
  DownloadStreamPreference preference, {
  required String? serverId,
  required String? voiceoverId,
}) {
  if (!hasPreciseDownloadStreamIdentity(preference)) return false;
  return cleanDownloadStreamId(preference.serverId) ==
          cleanDownloadStreamId(serverId) &&
      cleanDownloadStreamId(preference.voiceoverId) ==
          cleanDownloadStreamId(voiceoverId);
}

String downloadStreamVariantPathToken(DownloadStreamPreference preference) {
  final String digest = sha256
      .convert(utf8.encode(downloadStreamVariantKey(preference)))
      .toString()
      .substring(0, 12);
  return 'stream_$digest';
}

String downloadEpisodeRecordId({
  required String mediaId,
  required String addonId,
  required String episodeHref,
  required int seasonNumber,
  required double episodeNumber,
  required DownloadStreamPreference streamPreference,
}) {
  final String episodeIdentity = normalizeDownloadedEpisodeHref(episodeHref);
  final String fallbackEpisode = 'S${seasonNumber}E$episodeNumber';
  final String raw = <String>[
    mediaId.trim(),
    addonId.trim(),
    episodeIdentity.isEmpty ? fallbackEpisode : episodeIdentity,
    downloadStreamVariantKey(streamPreference),
  ].join('|');
  return 'download:${sha256.convert(utf8.encode(raw))}';
}
