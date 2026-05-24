class AniraMappings {
  const AniraMappings({
    this.aniraId = '',
    this.tvdbId,
    this.tvdbSeason,
    this.tvdbEpoffset,
    this.anilistId,
    this.malId,
    this.anidbId,
    this.imdbId,
    this.tmdbShowId,
    this.tmdbMovieId,
  });

  final String aniraId;
  final int? tvdbId;
  final int? tvdbSeason;
  final int? tvdbEpoffset;
  final int? anilistId;
  final int? malId;
  final int? anidbId;
  final String? imdbId;
  final int? tmdbShowId;
  final int? tmdbMovieId;

  factory AniraMappings.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> merged = _mergeWithMappings(json);
    return AniraMappings(
      aniraId: _nonEmpty(json['id']) ?? '',
      tvdbId: _nullableInt(merged['tvdb_id']),
      tvdbSeason: _nullableInt(merged['tvdb_season']),
      tvdbEpoffset: _nullableInt(merged['tvdb_epoffset']),
      anilistId: _nullableInt(merged['anilist_id']),
      malId: _nullableInt(merged['mal_id']),
      anidbId: _nullableInt(merged['anidb_id']),
      imdbId: _nonEmpty(merged['imdb_id']),
      tmdbShowId: _nullableInt(merged['tmdb_show_id']),
      tmdbMovieId: _nullableInt(merged['tmdb_movie_id']),
    );
  }

  static Map<String, dynamic> _mergeWithMappings(Map<String, dynamic> json) {
    final Object? nested = json['mappings'];
    if (nested is Map<String, dynamic>) {
      return <String, dynamic>{...json, ...nested};
    }
    return json;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value == 0 ? null : value;
    if (value is num) {
      final int v = value.round();
      return v == 0 ? null : v;
    }
    if (value is String) {
      final int? v = int.tryParse(value);
      return (v == null || v == 0) ? null : v;
    }
    return null;
  }

  static String? _nonEmpty(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }
}

class AniraWatchOrderEntry {
  const AniraWatchOrderEntry({
    required this.title,
    required this.coverUrl,
    this.anilistId,
    this.malId,
  });

  final String title;
  final String coverUrl;
  final int? anilistId;
  final int? malId;

  factory AniraWatchOrderEntry.fromJson(Map<String, dynamic> json) {
    final Object? mappings = json['mappings'];
    int? anilistId;
    int? malId;
    if (mappings is Map) {
      anilistId = AniraMappings._nullableInt(mappings['anilist_id']);
      malId = AniraMappings._nullableInt(mappings['mal_id']);
    }
    return AniraWatchOrderEntry(
      title: (json['title'] as String?) ?? '',
      coverUrl: (json['cover'] as String?) ?? '',
      anilistId: anilistId,
      malId: malId,
    );
  }
}

class AniraEpisodeTimeskips {
  const AniraEpisodeTimeskips({
    this.openingStart,
    this.openingEnd,
    this.endingStart,
    this.endingEnd,
  });

  final double? openingStart;
  final double? openingEnd;
  final double? endingStart;
  final double? endingEnd;

  factory AniraEpisodeTimeskips.fromJson(Map<String, dynamic> json) {
    double? opStart, opEnd, edStart, edEnd;

    // Anira API returns skips as an array: [{type:"op",start,end},{type:"ed",...}]
    final Object? skips = json['skips'];
    if (skips is List) {
      for (final Object? skip in skips) {
        if (skip is Map) {
          final String type = (skip['type'] as String?) ?? '';
          final double? s = _nullableDouble(skip['start']);
          final double? e = _nullableDouble(skip['end']);
          if (type == 'op') {
            opStart = s;
            opEnd = e;
          }
          if (type == 'ed') {
            edStart = s;
            edEnd = e;
          }
        }
      }
    }

    // Fallback: flat field names from older API versions
    return AniraEpisodeTimeskips(
      openingStart:
          opStart ??
          _nullableDouble(json['openingStart'] ?? json['opening_start']),
      openingEnd:
          opEnd ?? _nullableDouble(json['openingEnd'] ?? json['opening_end']),
      endingStart:
          edStart ??
          _nullableDouble(json['endingStart'] ?? json['ending_start']),
      endingEnd:
          edEnd ?? _nullableDouble(json['endingEnd'] ?? json['ending_end']),
    );
  }

  static double? _nullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
