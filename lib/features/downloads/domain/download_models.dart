import '../../../shared/models/media_item.dart';

/// Lifecycle of a single downloaded episode.
///
/// `queued`      — accepted, waiting for the engine.
/// `downloading` — actively fetching bytes/segments.
/// `paused`      — stopped by the user or carried over from a previous app run
///                 (in-progress downloads are reconciled to paused on launch).
/// `completed`   — fully on disk and playable offline.
/// `failed`      — stopped with an error; can be retried.
enum DownloadStatus { queued, downloading, paused, completed, failed }

/// Stream container we know how to download. `dash`/anything else is treated as
/// not downloadable and never enqueued.
enum DownloadKind { mp4, hls }

DownloadKind? downloadKindFromStreamType(String streamType) {
  switch (streamType.trim().toUpperCase()) {
    case 'HLS':
      return DownloadKind.hls;
    case 'MP4':
    case '':
      return DownloadKind.mp4;
    default:
      return null;
  }
}

class DownloadedSubtitle {
  const DownloadedSubtitle({
    required this.language,
    required this.label,
    required this.fileName,
  });

  final String language;
  final String label;

  /// File name relative to the episode directory (e.g. `sub_en.vtt`).
  final String fileName;

  factory DownloadedSubtitle.fromJson(Map<String, dynamic> json) {
    return DownloadedSubtitle(
      language: json['language'] as String? ?? '',
      label: json['label'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'language': language,
    'label': label,
    'fileName': fileName,
  };
}

class DownloadStreamPreference {
  const DownloadStreamPreference({
    this.serverId = '',
    this.serverTitle = '',
    this.qualityLabel = '',
    this.voiceoverId = '',
    this.voiceoverLabel = '',
  });

  static const DownloadStreamPreference empty = DownloadStreamPreference();

  final String serverId;
  final String serverTitle;
  final String qualityLabel;
  final String voiceoverId;
  final String voiceoverLabel;

  bool get isEmpty =>
      serverId.isEmpty &&
      serverTitle.isEmpty &&
      qualityLabel.isEmpty &&
      voiceoverId.isEmpty &&
      voiceoverLabel.isEmpty;

  factory DownloadStreamPreference.fromJson(Map<String, dynamic> json) {
    return DownloadStreamPreference(
      serverId: json['serverId'] as String? ?? '',
      serverTitle: json['serverTitle'] as String? ?? '',
      qualityLabel: json['qualityLabel'] as String? ?? '',
      voiceoverId: json['voiceoverId'] as String? ?? '',
      voiceoverLabel: json['voiceoverLabel'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (serverId.isNotEmpty) 'serverId': serverId,
    if (serverTitle.isNotEmpty) 'serverTitle': serverTitle,
    if (qualityLabel.isNotEmpty) 'qualityLabel': qualityLabel,
    if (voiceoverId.isNotEmpty) 'voiceoverId': voiceoverId,
    if (voiceoverLabel.isNotEmpty) 'voiceoverLabel': voiceoverLabel,
  };
}

/// One downloaded (or downloading) episode.
///
/// Paths are stored **relative** to the downloads root so they survive the
/// sandbox container path changing between launches (notably on iOS). Absolute
/// paths are rebuilt at use-time from the root resolved via path_provider.
class DownloadedEpisode {
  const DownloadedEpisode({
    required this.id,
    required this.mediaId,
    required this.media,
    required this.addonId,
    required this.addonName,
    required this.episodeHref,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.episodeTitle,
    required this.episodeImage,
    required this.qualityLabel,
    required this.kind,
    required this.relDir,
    required this.videoFileName,
    this.streamPreference = DownloadStreamPreference.empty,
    this.episodeData = const <String, dynamic>{},
    this.subtitles = const <DownloadedSubtitle>[],
    this.openingStart,
    this.openingEnd,
    this.endingStart,
    this.endingEnd,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.totalSegments = 0,
    this.doneSegments = 0,
    this.status = DownloadStatus.queued,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String mediaId;
  final MediaItem media;
  final String addonId;
  final String addonName;
  final String episodeHref;
  final double episodeNumber;
  final int seasonNumber;
  final String episodeTitle;
  final String episodeImage;
  final String qualityLabel;
  final DownloadKind kind;

  /// Episode directory relative to the downloads root.
  final String relDir;
  final String videoFileName;
  final DownloadStreamPreference streamPreference;

  /// Serialized `SoraEpisode` (raw fields) so the stream can be re-resolved
  /// faithfully on resume — module URLs expire and are never persisted.
  final Map<String, dynamic> episodeData;
  final List<DownloadedSubtitle> subtitles;

  final int? openingStart;
  final int? openingEnd;
  final int? endingStart;
  final int? endingEnd;

  final int totalBytes;
  final int receivedBytes;
  final int totalSegments;
  final int doneSegments;

  final DownloadStatus status;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isComplete => status == DownloadStatus.completed;
  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;

  double get progressFraction {
    if (status == DownloadStatus.completed) return 1;
    if (kind == DownloadKind.hls && totalSegments > 0) {
      return (doneSegments / totalSegments).clamp(0.0, 1.0);
    }
    if (totalBytes > 0) {
      return (receivedBytes / totalBytes).clamp(0.0, 1.0);
    }
    return 0;
  }

  String get displayNumber {
    if (episodeNumber <= 0) return '';
    if (episodeNumber == episodeNumber.roundToDouble()) {
      return episodeNumber.round().toString();
    }
    return episodeNumber.toString();
  }

  DownloadedEpisode copyWith({
    DownloadKind? kind,
    String? qualityLabel,
    String? videoFileName,
    DownloadStreamPreference? streamPreference,
    List<DownloadedSubtitle>? subtitles,
    int? totalBytes,
    int? receivedBytes,
    int? totalSegments,
    int? doneSegments,
    DownloadStatus? status,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return DownloadedEpisode(
      id: id,
      mediaId: mediaId,
      media: media,
      addonId: addonId,
      addonName: addonName,
      episodeHref: episodeHref,
      episodeNumber: episodeNumber,
      seasonNumber: seasonNumber,
      episodeTitle: episodeTitle,
      episodeImage: episodeImage,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      kind: kind ?? this.kind,
      relDir: relDir,
      videoFileName: videoFileName ?? this.videoFileName,
      streamPreference: streamPreference ?? this.streamPreference,
      episodeData: episodeData,
      subtitles: subtitles ?? this.subtitles,
      openingStart: openingStart,
      openingEnd: openingEnd,
      endingStart: endingStart,
      endingEnd: endingEnd,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalSegments: totalSegments ?? this.totalSegments,
      doneSegments: doneSegments ?? this.doneSegments,
      status: status ?? this.status,
      error: clearError ? null : error ?? this.error,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory DownloadedEpisode.fromJson(Map<String, dynamic> json) {
    final Object? mediaJson = json['media'];
    return DownloadedEpisode(
      id: json['id'] as String? ?? '',
      mediaId: json['mediaId'] as String? ?? '',
      media: mediaJson is Map<String, dynamic>
          ? MediaItem.fromJson(mediaJson)
          : MediaItem.fromJson(const <String, dynamic>{}),
      addonId: json['addonId'] as String? ?? '',
      addonName: json['addonName'] as String? ?? '',
      episodeHref: json['episodeHref'] as String? ?? '',
      episodeNumber: (json['episodeNumber'] as num?)?.toDouble() ?? 0,
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 1,
      episodeTitle: json['episodeTitle'] as String? ?? '',
      episodeImage: json['episodeImage'] as String? ?? '',
      qualityLabel: json['qualityLabel'] as String? ?? '',
      kind: DownloadKind.values.firstWhere(
        (DownloadKind k) => k.name == json['kind'],
        orElse: () => DownloadKind.mp4,
      ),
      relDir: json['relDir'] as String? ?? '',
      videoFileName: json['videoFileName'] as String? ?? 'video.mp4',
      streamPreference: json['streamPreference'] is Map
          ? DownloadStreamPreference.fromJson(
              (json['streamPreference'] as Map).cast<String, dynamic>(),
            )
          : DownloadStreamPreference.empty,
      episodeData:
          (json['episodeData'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      subtitles: (json['subtitles'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(DownloadedSubtitle.fromJson)
          .toList(growable: false),
      openingStart: (json['openingStart'] as num?)?.toInt(),
      openingEnd: (json['openingEnd'] as num?)?.toInt(),
      endingStart: (json['endingStart'] as num?)?.toInt(),
      endingEnd: (json['endingEnd'] as num?)?.toInt(),
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalSegments: (json['totalSegments'] as num?)?.toInt() ?? 0,
      doneSegments: (json['doneSegments'] as num?)?.toInt() ?? 0,
      status: DownloadStatus.values.firstWhere(
        (DownloadStatus s) => s.name == json['status'],
        orElse: () => DownloadStatus.queued,
      ),
      error: json['error'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'mediaId': mediaId,
    'media': media.toJson(),
    'addonId': addonId,
    'addonName': addonName,
    'episodeHref': episodeHref,
    'episodeNumber': episodeNumber,
    'seasonNumber': seasonNumber,
    'episodeTitle': episodeTitle,
    'episodeImage': episodeImage,
    'qualityLabel': qualityLabel,
    'kind': kind.name,
    'relDir': relDir,
    'videoFileName': videoFileName,
    if (!streamPreference.isEmpty)
      'streamPreference': streamPreference.toJson(),
    if (episodeData.isNotEmpty) 'episodeData': episodeData,
    'subtitles': subtitles.map((DownloadedSubtitle s) => s.toJson()).toList(),
    if (openingStart != null) 'openingStart': openingStart,
    if (openingEnd != null) 'openingEnd': openingEnd,
    if (endingStart != null) 'endingStart': endingStart,
    if (endingEnd != null) 'endingEnd': endingEnd,
    'totalBytes': totalBytes,
    'receivedBytes': receivedBytes,
    'totalSegments': totalSegments,
    'doneSegments': doneSegments,
    'status': status.name,
    if (error != null) 'error': error,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// A media title grouped with all of its downloaded episodes (across modules and
/// seasons). Built on demand from the flat download list.
class DownloadedTitle {
  const DownloadedTitle({required this.media, required this.episodes});

  final MediaItem media;
  final List<DownloadedEpisode> episodes;

  String get mediaId => media.id;
  int get completedCount =>
      episodes.where((DownloadedEpisode e) => e.isComplete).length;
  bool get hasActive => episodes.any((DownloadedEpisode e) => e.isActive);

  /// Distinct modules (addonId -> addonName) that have at least one episode for
  /// this title, used by the offline module chooser.
  Map<String, String> get modules {
    final Map<String, String> result = <String, String>{};
    for (final DownloadedEpisode e in episodes) {
      result.putIfAbsent(e.addonId, () => e.addonName);
    }
    return result;
  }
}

/// Groups a flat episode list into titles, newest activity first.
List<DownloadedTitle> groupDownloadsByTitle(List<DownloadedEpisode> episodes) {
  final Map<String, List<DownloadedEpisode>> byMedia =
      <String, List<DownloadedEpisode>>{};
  for (final DownloadedEpisode e in episodes) {
    byMedia.putIfAbsent(e.mediaId, () => <DownloadedEpisode>[]).add(e);
  }
  final List<DownloadedTitle> titles = byMedia.entries
      .map((MapEntry<String, List<DownloadedEpisode>> entry) {
        final List<DownloadedEpisode> eps = entry.value
          ..sort((DownloadedEpisode a, DownloadedEpisode b) {
            final int s = a.seasonNumber.compareTo(b.seasonNumber);
            if (s != 0) return s;
            return a.episodeNumber.compareTo(b.episodeNumber);
          });
        return DownloadedTitle(media: eps.first.media, episodes: eps);
      })
      .toList(growable: false);

  titles.sort((DownloadedTitle a, DownloadedTitle b) {
    final DateTime au = a.episodes
        .map((DownloadedEpisode e) => e.updatedAt)
        .reduce((DateTime x, DateTime y) => x.isAfter(y) ? x : y);
    final DateTime bu = b.episodes
        .map((DownloadedEpisode e) => e.updatedAt)
        .reduce((DateTime x, DateTime y) => x.isAfter(y) ? x : y);
    return bu.compareTo(au);
  });
  return titles;
}

/// Filesystem-safe token for ids like `tmdb:123` or addon ids/urls.
String sanitizeForPath(String value) {
  final String cleaned = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final String trimmed = cleaned.replaceAll(RegExp(r'^_+|_+$'), '');
  return trimmed.isEmpty ? 'item' : trimmed;
}
