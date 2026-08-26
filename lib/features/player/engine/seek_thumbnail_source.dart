import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/player_models.dart';
import 'local_hls_proxy.dart';
import 'player_engine.dart';
import 'seek_thumbnail.dart';

SeekThumbnailPlan buildSeekThumbnailPlan({
  required MediaPlaybackItem item,
  required MediaServer server,
  required StreamQuality activeQuality,
}) {
  final bool offline = server.id == 'offline';
  if (offline) {
    final String url = server.url.trim();
    if (url.isEmpty) {
      return const SeekThumbnailPlan(
        sessionKey: 'offline-empty',
        candidates: <SeekThumbnailSource>[],
        isOffline: true,
      );
    }
    final String stableId =
        item.externalIds['mirushin_offline_download_id']?.trim() ?? item.id;
    final String relativeMedia =
        item.externalIds['mirushin_offline_media_path']?.trim() ?? '';
    final String identity = _hash(<String>[
      'offline',
      stableId,
      relativeMedia,
      server.streamType.name,
      item.externalIds['mirushin_offline_quality']?.trim() ?? '',
    ]);
    final PlayerSource source = PlayerSource(
      url: url,
      headers: server.headers,
      streamType: server.streamType,
      allowDirectFallback: false,
    );
    return SeekThumbnailPlan(
      sessionKey: identity,
      candidates: <SeekThumbnailSource>[
        SeekThumbnailSource(
          source: source,
          sourceKey: identity,
          decoderKey: seekThumbnailDecoderFingerprint(source),
          label: 'offline local media',
          isOffline: true,
        ),
      ],
      isOffline: true,
    );
  }

  final List<({StreamQuality quality, int index})> explicit =
      <({StreamQuality quality, int index})>[
        for (int index = 0; index < server.qualities.length; index++)
          if (!server.qualities[index].isAuto &&
              server.qualities[index].url.trim().isNotEmpty &&
              !isClearlyAudioOnlyQuality(server.qualities[index]))
            (quality: server.qualities[index], index: index),
      ]..sort((a, b) {
        final int? aHeight = seekPreviewQualityHeight(a.quality);
        final int? bHeight = seekPreviewQualityHeight(b.quality);
        if (aHeight != null || bHeight != null) {
          final int height = (aHeight ?? 1 << 30).compareTo(bHeight ?? 1 << 30);
          if (height != 0) return height;
        }
        final int? aBitrate = a.quality.bitrate;
        final int? bBitrate = b.quality.bitrate;
        if (aBitrate != null || bBitrate != null) {
          final int bitrate = (aBitrate ?? 1 << 30).compareTo(
            bBitrate ?? 1 << 30,
          );
          if (bitrate != 0) return bitrate;
        }
        // Sora qualities are stored highest-to-lowest. Preserve that useful signal
        // for providers whose labels do not expose a numeric resolution.
        return b.index.compareTo(a.index);
      });

  final List<SeekThumbnailSource> candidates = <SeekThumbnailSource>[];
  final Set<String> seen = <String>{};

  void addCandidate({
    required String url,
    required Map<String, String> headers,
    required String label,
    required StreamType fallbackType,
  }) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final StreamType streamType = seekPreviewStreamTypeForUrl(
      trimmed,
      fallbackType,
    );
    final PlayerSource source = PlayerSource(
      url: trimmed,
      headers: headers,
      streamType: streamType,
      allowDirectFallback: false,
    );
    final String key = seekThumbnailSourceFingerprint(source);
    if (!seen.add(key)) return;
    candidates.add(
      SeekThumbnailSource(
        source: source,
        sourceKey: key,
        decoderKey: seekThumbnailDecoderFingerprint(source),
        label: label,
        isOffline: false,
      ),
    );
  }

  for (final ({StreamQuality quality, int index}) entry in explicit) {
    final StreamQuality quality = entry.quality;
    addCandidate(
      url: quality.url,
      headers: quality.headers.isNotEmpty ? quality.headers : server.headers,
      label: quality.label,
      fallbackType: server.streamType,
    );
  }
  if (!activeQuality.isAuto && !isClearlyAudioOnlyQuality(activeQuality)) {
    addCandidate(
      url: activeQuality.url,
      headers: activeQuality.headers.isNotEmpty
          ? activeQuality.headers
          : server.headers,
      label: activeQuality.label,
      fallbackType: server.streamType,
    );
  }
  addCandidate(
    url: server.url,
    headers: server.headers,
    label: explicit.isEmpty ? 'current single-quality stream' : 'server source',
    fallbackType: server.streamType,
  );

  final String sessionKey = _hash(<String>[
    'online',
    playbackItemRouteKey(item),
    server.id,
    server.sourceName,
    for (final SeekThumbnailSource candidate in candidates) candidate.sourceKey,
  ]);
  return SeekThumbnailPlan(
    sessionKey: sessionKey,
    candidates: candidates,
    isOffline: false,
  );
}

bool isClearlyAudioOnlyQuality(StreamQuality quality) {
  if ((quality.height ?? 0) > 0) return false;
  final String label = '${quality.id} ${quality.label}'.toLowerCase();
  if (RegExp(r'\b(audio|audio-only|aac|opus|mp3|m4a)\b').hasMatch(label)) {
    return true;
  }
  final Uri? uri = Uri.tryParse(quality.url);
  final String path = (uri?.path ?? quality.url).toLowerCase();
  return path.endsWith('.aac') ||
      path.endsWith('.m4a') ||
      path.endsWith('.mp3') ||
      path.endsWith('.opus');
}

int? seekPreviewQualityHeight(StreamQuality quality) {
  final int? height = quality.height;
  if (height != null && height > 0) return height;
  final String label = '${quality.label} ${quality.id}'.toLowerCase();
  if (label.contains('4k')) return 2160;
  if (label.contains('2k')) return 1440;
  final RegExpMatch? match = RegExp(
    r'(2160|1440|1080|720|576|540|480|360|240|144)\s*p?\b',
  ).firstMatch(label);
  if (match != null) return int.tryParse(match.group(1)!);
  if (label.contains('low') || label.contains('sd')) return 480;
  if (label.contains('hd')) return 720;
  return null;
}

StreamType seekPreviewStreamTypeForUrl(String url, StreamType fallback) {
  if (LocalHlsProxy.isInlineDashUrl(url)) return StreamType.dash;
  final Uri? uri = Uri.tryParse(url);
  if (uri?.scheme.toLowerCase() == 'file' && fallback == StreamType.dash) {
    return StreamType.dash;
  }
  final String lower = (uri?.path ?? url).toLowerCase();
  if (lower.endsWith('.m3u8')) return StreamType.hls;
  if (lower.endsWith('.mpd')) return StreamType.dash;
  if (lower.endsWith('.mp4') || lower.endsWith('.mkv')) return StreamType.mp4;
  return fallback;
}

String seekThumbnailSourceFingerprint(PlayerSource source) {
  final List<MapEntry<String, String>> headers = source.headers.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return _hash(<String>[
    source.streamType.name,
    _stableSourceUrl(source.url),
    for (final MapEntry<String, String> header in headers)
      _stableHeaderIdentity(header),
  ]);
}

String seekThumbnailDecoderFingerprint(PlayerSource source) {
  final List<MapEntry<String, String>> headers = source.headers.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return _hash(<String>[
    source.streamType.name,
    source.url,
    for (final MapEntry<String, String> header in headers)
      '${header.key.toLowerCase()}:${header.value}',
  ]);
}

String _stableHeaderIdentity(MapEntry<String, String> header) {
  final String key = header.key.toLowerCase();
  const Set<String> rotatingCredentials = <String>{
    'authorization',
    'cookie',
    'proxy-authorization',
    'x-api-key',
    'x-auth-token',
  };
  return rotatingCredentials.contains(key)
      ? '$key:<credential>'
      : '$key:${header.value}';
}

String _stableSourceUrl(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null) return value;
  final Map<String, List<String>> stableQuery = <String, List<String>>{
    for (final MapEntry<String, List<String>> entry
        in uri.queryParametersAll.entries)
      if (!_isRotatingQueryParameter(entry.key)) entry.key: entry.value,
  };
  return uri
      .replace(
        query: stableQuery.isEmpty ? '' : null,
        queryParameters: stableQuery.isEmpty ? null : stableQuery,
        fragment: '',
      )
      .toString();
}

bool _isRotatingQueryParameter(String value) {
  final String key = value.toLowerCase().replaceAll('_', '-');
  return key == 'token' ||
      key == 'expires' ||
      key == 'expiry' ||
      key == 'exp' ||
      key == 'signature' ||
      key == 'sig' ||
      key == 'policy' ||
      key == 'credential' ||
      key == 'hdnea' ||
      key.startsWith('x-amz-') ||
      key.startsWith('x-goog-') ||
      key.endsWith('-token') ||
      key.endsWith('-signature');
}

String _hash(List<String> values) {
  return sha256.convert(utf8.encode(values.join('\u0000'))).toString();
}
