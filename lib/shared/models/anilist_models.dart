import 'media_item.dart';

enum AniListListStatus {
  current,
  planning,
  completed,
  dropped,
  paused,
  repeating,
}

extension AniListListStatusLabel on AniListListStatus {
  String get label {
    return switch (this) {
      AniListListStatus.current => 'Watching',
      AniListListStatus.planning => 'Planning',
      AniListListStatus.completed => 'Completed',
      AniListListStatus.dropped => 'Dropped',
      AniListListStatus.paused => 'Paused',
      AniListListStatus.repeating => 'Repeating',
    };
  }

  String get graphQlValue {
    return switch (this) {
      AniListListStatus.current => 'CURRENT',
      AniListListStatus.planning => 'PLANNING',
      AniListListStatus.completed => 'COMPLETED',
      AniListListStatus.dropped => 'DROPPED',
      AniListListStatus.paused => 'PAUSED',
      AniListListStatus.repeating => 'REPEATING',
    };
  }

  static AniListListStatus fromGraphQl(String? value) {
    return switch (value) {
      'CURRENT' => AniListListStatus.current,
      'PLANNING' => AniListListStatus.planning,
      'COMPLETED' => AniListListStatus.completed,
      'DROPPED' => AniListListStatus.dropped,
      'PAUSED' => AniListListStatus.paused,
      'REPEATING' => AniListListStatus.repeating,
      _ => AniListListStatus.planning,
    };
  }
}

class AniListViewer {
  const AniListViewer({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.bannerUrl,
    this.siteUrl,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? siteUrl;

  factory AniListViewer.fromJson(Map<String, dynamic> json) {
    return AniListViewer(
      id: _int(json['id']),
      name: _string(json['name'], fallback: 'AniList User'),
      avatarUrl: _nullableString(json['avatarUrl']),
      bannerUrl: _nullableString(json['bannerUrl']),
      siteUrl: _nullableString(json['siteUrl']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (bannerUrl != null) 'bannerUrl': bannerUrl,
      if (siteUrl != null) 'siteUrl': siteUrl,
    };
  }
}

class AniListAnimeListEntry {
  const AniListAnimeListEntry({
    required this.id,
    required this.status,
    required this.progress,
    this.score,
    required this.mediaItem,
    this.notes = '',
    this.repeat = 0,
    this.createdAt,
    this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.nextEpisode,
    this.airingAt,
    this.avgScore,
    this.format,
  });

  final int id;
  final AniListListStatus status;
  final int progress;
  final double? score;
  final MediaItem mediaItem;
  final String notes;
  final int repeat;
  final int? createdAt;
  final int? updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? nextEpisode;
  final DateTime? airingAt;
  final int? avgScore;
  final String? format;

  factory AniListAnimeListEntry.fromJson(Map<String, dynamic> json) {
    return AniListAnimeListEntry(
      id: _int(json['id']),
      status: AniListListStatusLabel.fromGraphQl(_string(json['status'])),
      progress: _int(json['progress']),
      score: _nullableDouble(json['score']),
      mediaItem: MediaItem.fromJson(
        json['mediaItem'] is Map<String, dynamic>
            ? json['mediaItem'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      notes: _string(json['notes']),
      repeat: _int(json['repeat']),
      createdAt: _nullableInt(json['createdAt']),
      updatedAt: _nullableInt(json['updatedAt']),
      startedAt: _date(json['startedAt']),
      completedAt: _date(json['completedAt']),
      nextEpisode: _nullableInt(json['nextEpisode']),
      airingAt: _date(json['airingAt']),
      avgScore: _nullableInt(json['avgScore']),
      format: _nullableString(json['format']),
    );
  }

  AniListAnimeListEntry copyWith({
    int? progress,
    AniListListStatus? status,
    double? score,
    String? notes,
    int? repeat,
  }) {
    return AniListAnimeListEntry(
      id: id,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      score: score ?? this.score,
      mediaItem: mediaItem,
      notes: notes ?? this.notes,
      repeat: repeat ?? this.repeat,
      createdAt: createdAt,
      updatedAt: updatedAt,
      startedAt: startedAt,
      completedAt: completedAt,
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      avgScore: avgScore,
      format: format,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'status': status.graphQlValue,
      'progress': progress,
      if (score != null) 'score': score,
      'mediaItem': mediaItem.toJson(),
      'notes': notes,
      'repeat': repeat,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      if (nextEpisode != null) 'nextEpisode': nextEpisode,
      if (airingAt != null) 'airingAt': airingAt!.toIso8601String(),
      if (avgScore != null) 'avgScore': avgScore,
      if (format != null) 'format': format,
    };
  }
}

class AniListAnimeListFolder {
  const AniListAnimeListFolder({
    required this.name,
    required this.status,
    required this.entries,
  });

  final String name;
  final AniListListStatus? status;
  final List<AniListAnimeListEntry> entries;

  factory AniListAnimeListFolder.fromJson(Map<String, dynamic> json) {
    final Object? entries = json['entries'];
    return AniListAnimeListFolder(
      name: _string(json['name'], fallback: 'Custom'),
      status: json['status'] == null
          ? null
          : AniListListStatusLabel.fromGraphQl(_string(json['status'])),
      entries: entries is List<dynamic>
          ? entries
                .whereType<Map<String, dynamic>>()
                .map(AniListAnimeListEntry.fromJson)
                .toList(growable: false)
          : const <AniListAnimeListEntry>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      if (status != null) 'status': status!.graphQlValue,
      'entries': entries
          .map((AniListAnimeListEntry entry) => entry.toJson())
          .toList(growable: false),
    };
  }
}

class AniListOAuthResult {
  const AniListOAuthResult({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;
  final DateTime expiresAt;
}

class AniListSavedAccount {
  const AniListSavedAccount({
    required this.viewerId,
    required this.viewerName,
    this.avatarUrl,
    required this.accessToken,
    required this.expiresAt,
  });

  final int viewerId;
  final String viewerName;
  final String? avatarUrl;
  final String accessToken;
  final DateTime expiresAt;

  bool get isValid =>
      accessToken.isNotEmpty && expiresAt.isAfter(DateTime.now());

  factory AniListSavedAccount.fromJson(Map<String, dynamic> json) {
    return AniListSavedAccount(
      viewerId: _int(json['viewerId']),
      viewerName: _string(json['viewerName'], fallback: 'AniList User'),
      avatarUrl: _nullableString(json['avatarUrl']),
      accessToken: _string(json['accessToken']),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'viewerId': viewerId,
    'viewerName': viewerName,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    'accessToken': accessToken,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  final int parsed = _int(value);
  return parsed == 0 ? null : parsed;
}

double? _nullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String? _nullableString(Object? value) {
  final String parsed = _string(value);
  return parsed.isEmpty ? null : parsed;
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
