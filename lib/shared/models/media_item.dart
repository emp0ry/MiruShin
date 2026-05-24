enum MediaType { movie, series, anime }

extension MediaTypeLabel on MediaType {
  String get labelKey {
    return switch (this) {
      MediaType.movie => 'Movie',
      MediaType.series => 'Series type',
      MediaType.anime => 'Anime type',
    };
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.type,
    required this.year,
    required this.posterUrl,
    required this.backdropUrl,
    required this.rating,
    required this.genres,
    required this.sourceProvider,
    required this.externalIds,
    this.runtimeMinutes,
    this.episodeCount,
    this.seasons = const <MediaSeason>[],
    required this.statusLabel,
    this.aliases = const <String>[],
    this.originalLanguage = '',
  });

  final String id;
  final String title;
  final String originalTitle;
  final String overview;
  final MediaType type;
  final int year;
  final String posterUrl;
  final String backdropUrl;
  final double rating;
  final List<String> genres;
  final String sourceProvider;
  final Map<String, String> externalIds;
  final int? runtimeMinutes;
  final int? episodeCount;
  final List<MediaSeason> seasons;
  final String statusLabel;
  final List<String> aliases;
  final String originalLanguage;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: _string(json['id']),
      title: _string(json['title']),
      originalTitle: _string(json['originalTitle']),
      overview: _string(json['overview']),
      type: MediaType.values.firstWhere(
        (MediaType type) => type.name == json['type'],
        orElse: () => MediaType.movie,
      ),
      year: _int(json['year']),
      posterUrl: _string(json['posterUrl']),
      backdropUrl: _string(json['backdropUrl']),
      rating: _double(json['rating']),
      genres: _stringList(json['genres']),
      sourceProvider: _string(json['sourceProvider']),
      externalIds: _stringMap(json['externalIds']),
      runtimeMinutes: _nullableInt(json['runtimeMinutes']),
      episodeCount: _nullableInt(json['episodeCount']),
      seasons: _seasonList(json['seasons']),
      statusLabel: _string(json['statusLabel']),
      aliases: _stringList(json['aliases']),
      originalLanguage: _string(json['originalLanguage']),
    );
  }

  MediaItem copyWith({
    String? title,
    String? overview,
    String? backdropUrl,
    double? rating,
    List<MediaSeason>? seasons,
  }) {
    return MediaItem(
      id: id,
      title: title ?? this.title,
      originalTitle: originalTitle,
      overview: overview ?? this.overview,
      type: type,
      year: year,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      rating: rating ?? this.rating,
      genres: genres,
      sourceProvider: sourceProvider,
      externalIds: externalIds,
      runtimeMinutes: runtimeMinutes,
      episodeCount: episodeCount,
      seasons: seasons ?? this.seasons,
      statusLabel: statusLabel,
      aliases: aliases,
      originalLanguage: originalLanguage,
    );
  }

  String get durationLabel {
    if (runtimeMinutes != null) {
      return '$runtimeMinutes min';
    }
    if (episodeCount != null) {
      return '$episodeCount episodes';
    }
    return statusLabel;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'originalTitle': originalTitle,
      'overview': overview,
      'type': type.name,
      'year': year,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'rating': rating,
      'genres': genres,
      'sourceProvider': sourceProvider,
      'externalIds': externalIds,
      'runtimeMinutes': runtimeMinutes,
      'episodeCount': episodeCount,
      'seasons': seasons
          .map((MediaSeason season) => season.toJson())
          .toList(growable: false),
      'statusLabel': statusLabel,
      'aliases': aliases,
      'originalLanguage': originalLanguage,
    };
  }

  static List<MediaSeason> _seasonList(Object? value) {
    if (value is! List<dynamic>) {
      return const <MediaSeason>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(MediaSeason.fromJson)
        .toList(growable: false);
  }

  static String _string(Object? value) {
    return value is String ? value : '';
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final int parsed = _int(value);
    return parsed == 0 ? null : parsed;
  }

  static double _double(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) {
      return <String>[];
    }
    return value.whereType<String>().toList();
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return <String, String>{};
    }
    return value.map(
      (Object? key, Object? mapValue) =>
          MapEntry<String, String>(key.toString(), mapValue.toString()),
    );
  }
}

class MediaSeason {
  const MediaSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    required this.posterUrl,
    required this.overview,
    this.originalName = '',
    this.aliases = const <String>[],
    this.isSpecials = false,
    this.externalIds = const <String, String>{},
    this.year = 0,
    this.rating = 0.0,
    this.format = '',
    this.relationType = '',
  });

  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String posterUrl;
  final String overview;
  final String originalName;
  final List<String> aliases;
  final bool isSpecials;
  final Map<String, String> externalIds;
  final int year;
  final double rating;
  final String format;
  final String relationType;

  factory MediaSeason.fromJson(Map<String, dynamic> json) {
    final int seasonNumber = MediaItem._int(json['seasonNumber']);
    return MediaSeason(
      seasonNumber: seasonNumber,
      name: MediaItem._string(json['name']),
      episodeCount: MediaItem._int(json['episodeCount']),
      posterUrl: MediaItem._string(json['posterUrl']),
      overview: MediaItem._string(json['overview']),
      originalName: MediaItem._string(json['originalName']),
      aliases: MediaItem._stringList(json['aliases']),
      isSpecials: json['isSpecials'] == true || seasonNumber == 0,
      externalIds: MediaItem._stringMap(json['externalIds']),
      year: MediaItem._int(json['year']),
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      format: MediaItem._string(json['format']),
      relationType: MediaItem._string(json['relationType']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'seasonNumber': seasonNumber,
      'name': name,
      'episodeCount': episodeCount,
      'posterUrl': posterUrl,
      'overview': overview,
      'originalName': originalName,
      'aliases': aliases,
      'isSpecials': isSpecials,
      'externalIds': externalIds,
      'year': year,
      'rating': rating,
      'format': format,
      'relationType': relationType,
    };
  }
}
