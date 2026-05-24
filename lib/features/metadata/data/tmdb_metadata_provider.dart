import 'package:dio/dio.dart';

import '../../../shared/models/calendar_item.dart';
import '../../../shared/models/media_item.dart';
import '../domain/metadata_provider.dart';

class TmdbConfigurationException implements Exception {
  const TmdbConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TmdbMetadataProvider implements PagedDiscoveryProvider {
  TmdbMetadataProvider({
    required String readAccessToken,
    Dio? dio,
    this.language = 'en-US',
    this.region = 'US',
  }) : _readAccessToken = readAccessToken.trim(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://api.themoviedb.org/3',
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 16),
             ),
           );

  final Dio _dio;
  final String _readAccessToken;
  final String language;
  final String region;

  @override
  String get id => 'tmdb';

  @override
  String get name => 'TMDB';

  @override
  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    _assertConfigured();
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getTrending();
    }

    final List<Map<String, dynamic>> responses = await Future.wait(
      <Future<Map<String, dynamic>>>[
        _getDataWithEnglishFallback(
          '/search/movie',
          MediaType.movie,
          <String, dynamic>{
            'query': trimmed,
            'include_adult': false,
            'page': page,
          },
        ),
        _getDataWithEnglishFallback(
          '/search/tv',
          MediaType.series,
          <String, dynamic>{
            'query': trimmed,
            'include_adult': false,
            'page': page,
          },
        ),
      ],
    );

    return <MediaItem>[
      ..._parseList(responses[0], MediaType.movie),
      ..._parseTvSearchList(responses[1]),
    ];
  }

  @override
  Future<List<MediaItem>> getPopular(MediaType type, {int page = 1}) async {
    _assertConfigured();
    return switch (type) {
      MediaType.movie => _getList(
        '/movie/popular',
        MediaType.movie,
        <String, dynamic>{'page': page},
      ),
      MediaType.series => _getList(
        '/tv/popular',
        MediaType.series,
        <String, dynamic>{'page': page},
      ),
      MediaType.anime =>
        _getList('/discover/tv', MediaType.anime, <String, dynamic>{
          'page': page,
          'with_genres': '16',
          'with_original_language': 'ja',
          'sort_by': 'popularity.desc',
        }),
    };
  }

  @override
  Future<List<MediaItem>> getTrending({int page = 1}) async {
    _assertConfigured();
    final Map<String, dynamic> data = await _getTrendingData(
      '/trending/all/week',
      <String, dynamic>{'page': page},
    );
    final Object? results = data['results'];
    if (results is! List<dynamic>) {
      return <MediaItem>[];
    }

    return results
        .whereType<Map<String, dynamic>>()
        .map(_fromTrending)
        .whereType<MediaItem>()
        .toList();
  }

  @override
  Future<List<MediaItem>> discoverPage({
    required String filter,
    required MediaType? type,
    required int page,
  }) async {
    _assertConfigured();
    if (filter == 'Trending') {
      final List<MediaItem> items = await getTrending(page: page);
      return type == null
          ? items
          : items.where((MediaItem item) => item.type == type).toList();
    }

    if (type == null) {
      final List<List<MediaItem>> results =
          await Future.wait(<Future<List<MediaItem>>>[
            discoverPage(filter: filter, type: MediaType.movie, page: page),
            discoverPage(filter: filter, type: MediaType.series, page: page),
            discoverPage(filter: filter, type: MediaType.anime, page: page),
          ]);
      final Map<String, MediaItem> byId = <String, MediaItem>{};
      for (final List<MediaItem> group in results) {
        for (final MediaItem item in group) {
          byId.putIfAbsent(item.id, () => item);
        }
      }
      return byId.values.toList();
    }

    return switch (filter) {
      'Top Rated' => _topRated(type, page),
      'New Releases' => _newReleases(type, page),
      'Coming Soon' => _comingSoon(type, page),
      'Popular' ||
      'Genres' ||
      'Year' ||
      'Rating' ||
      'Language' => getPopular(type, page: page),
      _ => getPopular(type, page: page),
    };
  }

  Future<List<MediaItem>> discoverPageAdvanced({
    required String filter,
    required MediaType? type,
    required int page,
    List<int>? genreIds,
    int? yearFrom,
    int? yearTo,
    double? minRating,
    String? originalLanguage,
  }) async {
    _assertConfigured();
    if (type == null) {
      final List<List<MediaItem>> results =
          await Future.wait(<Future<List<MediaItem>>>[
            discoverPageAdvanced(
              filter: filter,
              type: MediaType.movie,
              page: page,
              genreIds: genreIds,
              yearFrom: yearFrom,
              yearTo: yearTo,
              minRating: minRating,
              originalLanguage: originalLanguage,
            ),
            discoverPageAdvanced(
              filter: filter,
              type: MediaType.series,
              page: page,
              genreIds: genreIds,
              yearFrom: yearFrom,
              yearTo: yearTo,
              minRating: minRating,
              originalLanguage: originalLanguage,
            ),
          ]);
      final Map<String, MediaItem> byId = <String, MediaItem>{};
      for (final List<MediaItem> group in results) {
        for (final MediaItem item in group) {
          byId.putIfAbsent(item.id, () => item);
        }
      }
      return byId.values.toList();
    }

    final String sortBy = _sortByForFilter(filter, type);
    final Map<String, dynamic> params = <String, dynamic>{
      'page': page,
      'sort_by': sortBy,
      if (minRating != null && minRating > 0) 'vote_average.gte': minRating,
      if (filter == 'Top Rated') 'vote_count.gte': 50,
    };

    if (type == MediaType.anime) {
      final List<int> genres = <int>[
        16,
        ...?genreIds?.where((int id) => id != 16),
      ];
      params['with_genres'] = genres.join(',');
      params['with_original_language'] = 'ja';
    } else {
      if (genreIds != null && genreIds.isNotEmpty) {
        params['with_genres'] = genreIds.join(',');
      }
      if (originalLanguage != null) {
        params['with_original_language'] = originalLanguage;
      }
    }

    final DateTime now = DateTime.now();
    if (filter == 'New Releases') {
      final DateTime start = now.subtract(const Duration(days: 120));
      if (type == MediaType.movie) {
        params.putIfAbsent('primary_release_date.gte', () => _date(start));
        params.putIfAbsent('primary_release_date.lte', () => _date(now));
      } else {
        params.putIfAbsent('first_air_date.gte', () => _date(start));
        params.putIfAbsent('first_air_date.lte', () => _date(now));
      }
    } else if (filter == 'Coming Soon') {
      final DateTime end = now.add(const Duration(days: 180));
      if (type == MediaType.movie) {
        params.putIfAbsent('primary_release_date.gte', () => _date(now));
        params.putIfAbsent('primary_release_date.lte', () => _date(end));
      } else {
        params.putIfAbsent('first_air_date.gte', () => _date(now));
        params.putIfAbsent('first_air_date.lte', () => _date(end));
      }
    }

    if (yearFrom != null) {
      if (type == MediaType.movie) {
        params.putIfAbsent('primary_release_date.gte', () => '$yearFrom-01-01');
      } else {
        params.putIfAbsent('first_air_date.gte', () => '$yearFrom-01-01');
      }
    }
    if (yearTo != null) {
      if (type == MediaType.movie) {
        params.putIfAbsent('primary_release_date.lte', () => '$yearTo-12-31');
      } else {
        params.putIfAbsent('first_air_date.lte', () => '$yearTo-12-31');
      }
    }

    if (type == MediaType.movie) {
      return _getList('/discover/movie', MediaType.movie, params);
    }
    return _getList(
      '/discover/tv',
      type == MediaType.anime ? MediaType.anime : MediaType.series,
      params,
    );
  }

  static String _sortByForFilter(String filter, MediaType type) {
    return switch (filter) {
      'Top Rated' => 'vote_average.desc',
      'New Releases' => type == MediaType.movie
          ? 'primary_release_date.desc'
          : 'first_air_date.desc',
      'Coming Soon' => type == MediaType.movie
          ? 'primary_release_date.asc'
          : 'first_air_date.asc',
      _ => 'popularity.desc',
    };
  }

  Future<List<CalendarItem>> getCalendarItems({
    required DateTime from,
    required DateTime to,
  }) async {
    _assertConfigured();
    final String fromDate = _date(from);
    final String toDate = _date(to);
    final List<Map<String, dynamic>> responses = await Future.wait(
      <Future<Map<String, dynamic>>>[
        _getDataWithEnglishFallback(
          '/movie/upcoming',
          MediaType.movie,
          <String, dynamic>{
            'primary_release_date.gte': fromDate,
            'primary_release_date.lte': toDate,
          },
        ),
        _getDataWithEnglishFallback(
          '/discover/tv',
          MediaType.series,
          <String, dynamic>{
            'first_air_date.gte': fromDate,
            'first_air_date.lte': toDate,
            'sort_by': 'first_air_date.asc',
          },
        ),
        _getDataWithEnglishFallback(
          '/discover/tv',
          MediaType.anime,
          <String, dynamic>{
            'first_air_date.gte': fromDate,
            'first_air_date.lte': toDate,
            'sort_by': 'first_air_date.asc',
            'with_genres': '16',
            'with_original_language': 'ja',
          },
        ),
      ],
    );

    final List<CalendarItem> items = <CalendarItem>[
      ..._parseCalendarList(
        responses[0],
        MediaType.movie,
        CalendarItemType.movieRelease,
      ),
      ..._parseCalendarList(
        responses[1],
        MediaType.series,
        CalendarItemType.episode,
      ),
      ..._parseCalendarList(
        responses[2],
        MediaType.anime,
        CalendarItemType.animeAiring,
      ),
    ];
    items.sort((CalendarItem a, CalendarItem b) => a.date.compareTo(b.date));
    return items;
  }

  @override
  Future<MediaItem?> getDetails(String id) async {
    _assertConfigured();
    final _TmdbId? parsed = _TmdbId.tryParse(id);
    if (parsed == null) {
      return null;
    }

    final Map<String, dynamic> data = await _getDataWithEnglishFallback(
      parsed.type == MediaType.movie
          ? '/movie/${parsed.id}'
          : '/tv/${parsed.id}',
      parsed.type,
    );
    return _fromDetails(data, parsed.type);
  }

  Future<List<MediaItem>> _getList(
    String path,
    MediaType type, [
    Map<String, dynamic> extra = const <String, dynamic>{},
  ]) async {
    final Map<String, dynamic> data = await _getDataWithEnglishFallback(
      path,
      type,
      extra,
    );
    return _parseList(data, type);
  }

  Future<List<MediaItem>> _topRated(MediaType type, int page) {
    return switch (type) {
      MediaType.movie => _getList(
        '/movie/top_rated',
        MediaType.movie,
        <String, dynamic>{'page': page},
      ),
      MediaType.series => _getList(
        '/tv/top_rated',
        MediaType.series,
        <String, dynamic>{'page': page},
      ),
      MediaType.anime =>
        _getList('/discover/tv', MediaType.anime, <String, dynamic>{
          'page': page,
          'with_genres': '16',
          'with_original_language': 'ja',
          'vote_count.gte': 50,
          'sort_by': 'vote_average.desc',
        }),
    };
  }

  Future<List<MediaItem>> _newReleases(MediaType type, int page) {
    final DateTime now = DateTime.now();
    final DateTime start = now.subtract(const Duration(days: 120));
    return switch (type) {
      MediaType.movie =>
        _getList('/discover/movie', MediaType.movie, <String, dynamic>{
          'page': page,
          'primary_release_date.gte': _date(start),
          'primary_release_date.lte': _date(now),
          'sort_by': 'primary_release_date.desc',
        }),
      MediaType.series =>
        _getList('/discover/tv', MediaType.series, <String, dynamic>{
          'page': page,
          'first_air_date.gte': _date(start),
          'first_air_date.lte': _date(now),
          'sort_by': 'first_air_date.desc',
        }),
      MediaType.anime =>
        _getList('/discover/tv', MediaType.anime, <String, dynamic>{
          'page': page,
          'first_air_date.gte': _date(start),
          'first_air_date.lte': _date(now),
          'sort_by': 'first_air_date.desc',
          'with_genres': '16',
          'with_original_language': 'ja',
        }),
    };
  }

  Future<List<MediaItem>> _comingSoon(MediaType type, int page) {
    final DateTime now = DateTime.now();
    final DateTime end = now.add(const Duration(days: 180));
    return switch (type) {
      MediaType.movie => _getList(
        '/movie/upcoming',
        MediaType.movie,
        <String, dynamic>{'page': page},
      ),
      MediaType.series =>
        _getList('/discover/tv', MediaType.series, <String, dynamic>{
          'page': page,
          'first_air_date.gte': _date(now),
          'first_air_date.lte': _date(end),
          'sort_by': 'first_air_date.asc',
        }),
      MediaType.anime =>
        _getList('/discover/tv', MediaType.anime, <String, dynamic>{
          'page': page,
          'first_air_date.gte': _date(now),
          'first_air_date.lte': _date(end),
          'sort_by': 'first_air_date.asc',
          'with_genres': '16',
          'with_original_language': 'ja',
        }),
    };
  }

  Future<double> findRatingByImdbId(String imdbId) async {
    try {
      _assertConfigured();
      final Response<dynamic> response = await _get(
        '/find/$imdbId',
        <String, dynamic>{'external_source': 'imdb_id'},
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) return 0.0;
      for (final String key in const <String>[
        'movie_results',
        'tv_results',
        'tv_episode_results',
      ]) {
        final Object? results = data[key];
        if (results is List<dynamic> && results.isNotEmpty) {
          final Object? first = results.first;
          if (first is Map<String, dynamic>) {
            final double rating = _num(
              first['vote_average'],
            ).toDouble().clamp(0.0, 10.0);
            if (rating > 0) return rating;
          }
        }
      }
    } catch (_) {}
    return 0.0;
  }

  Future<Response<dynamic>> _get(
    String path, [
    Map<String, dynamic> query = const <String, dynamic>{},
    String? languageOverride,
  ]) {
    return _dio.get<dynamic>(
      path,
      queryParameters: <String, dynamic>{
        'language': languageOverride ?? language,
        'region': region,
        ...query,
      },
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer $_readAccessToken',
          'accept': 'application/json',
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _getDataWithEnglishFallback(
    String path,
    MediaType type, [
    Map<String, dynamic> query = const <String, dynamic>{},
  ]) async {
    final Response<dynamic> localized = await _get(path, query);
    final Object? localizedData = localized.data;
    if (_isEnglishLanguage || localizedData is! Map<String, dynamic>) {
      return localizedData is Map<String, dynamic>
          ? localizedData
          : <String, dynamic>{};
    }

    final Response<dynamic> english = await _get(path, query, 'en-US');
    final Object? englishData = english.data;
    if (englishData is! Map<String, dynamic>) {
      return localizedData;
    }
    return _mergeEnglishFallbackPayload(localizedData, englishData, type);
  }

  Future<Map<String, dynamic>> _getTrendingData(
    String path, [
    Map<String, dynamic> query = const <String, dynamic>{},
  ]) async {
    final Response<dynamic> localized = await _get(path, query);
    final Object? localizedData = localized.data;
    if (_isEnglishLanguage || localizedData is! Map<String, dynamic>) {
      return localizedData is Map<String, dynamic>
          ? localizedData
          : <String, dynamic>{};
    }

    final Response<dynamic> english = await _get(path, query, 'en-US');
    final Object? englishData = english.data;
    if (englishData is! Map<String, dynamic>) {
      return localizedData;
    }

    final Object? localizedResults = localizedData['results'];
    final Object? englishResults = englishData['results'];
    if (localizedResults is! List<dynamic> ||
        englishResults is! List<dynamic>) {
      return localizedData;
    }
    final Map<String, Map<String, dynamic>> englishByKey =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> item
        in englishResults.whereType<Map<String, dynamic>>()) {
      final String key = '${item['media_type'] ?? ''}:${item['id'] ?? ''}';
      englishByKey[key] = item;
    }
    return <String, dynamic>{
      ...localizedData,
      'results': localizedResults
          .map((Object? item) {
            if (item is! Map<String, dynamic>) {
              return item;
            }
            final String mediaType = item['media_type']?.toString() ?? '';
            final MediaType? type = switch (mediaType) {
              'movie' => MediaType.movie,
              'tv' => MediaType.series,
              _ => null,
            };
            if (type == null) {
              return item;
            }
            final String key = '$mediaType:${item['id'] ?? ''}';
            return _mergeEnglishTitleFallback(item, englishByKey[key], type);
          })
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _mergeEnglishFallbackPayload(
    Map<String, dynamic> localized,
    Map<String, dynamic> english,
    MediaType type,
  ) {
    final Object? localizedResults = localized['results'];
    final Object? englishResults = english['results'];
    if (localizedResults is List<dynamic> && englishResults is List<dynamic>) {
      final Map<String, Map<String, dynamic>> englishById =
          <String, Map<String, dynamic>>{};
      for (final Map<String, dynamic> item
          in englishResults.whereType<Map<String, dynamic>>()) {
        englishById['${item['id'] ?? ''}'] = item;
      }
      return <String, dynamic>{
        ...localized,
        'results': localizedResults
            .map((Object? item) {
              if (item is! Map<String, dynamic>) {
                return item;
              }
              return _mergeEnglishTitleFallback(
                item,
                englishById['${item['id'] ?? ''}'],
                type,
              );
            })
            .toList(growable: false),
      };
    }
    return _mergeEnglishTitleFallback(localized, english, type);
  }

  Map<String, dynamic> _mergeEnglishTitleFallback(
    Map<String, dynamic> localized,
    Map<String, dynamic>? english,
    MediaType type,
  ) {
    if (english == null) {
      return localized;
    }
    final String titleKey = type == MediaType.movie ? 'title' : 'name';
    final String originalKey = type == MediaType.movie
        ? 'original_title'
        : 'original_name';
    final String localizedTitle = _string(localized[titleKey]);
    final String originalTitle = _string(localized[originalKey]);
    final String englishTitle = _string(english[titleKey]);
    final String targetLanguage = language.split('-').first.toLowerCase();
    final String originalLanguage = _string(
      localized['original_language'],
    ).toLowerCase();
    final bool missingLocalizedTitle =
        localizedTitle.isEmpty ||
        (targetLanguage != originalLanguage &&
            originalTitle.isNotEmpty &&
            localizedTitle == originalTitle);
    final Map<String, dynamic> merged = <String, dynamic>{...localized};
    if (missingLocalizedTitle && englishTitle.isNotEmpty) {
      merged[titleKey] = englishTitle;
    }
    if (_string(merged['overview']).isEmpty &&
        _string(english['overview']).isNotEmpty) {
      merged['overview'] = _string(english['overview']);
    }
    return merged;
  }

  bool get _isEnglishLanguage =>
      language.split('-').first.toLowerCase() == 'en';

  List<MediaItem> _parseList(Object? data, MediaType type) {
    if (data is! Map<String, dynamic>) {
      return <MediaItem>[];
    }
    final Object? results = data['results'];
    if (results is! List<dynamic>) {
      return <MediaItem>[];
    }
    return results
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => _fromListItem(json, type))
        .toList();
  }

  List<MediaItem> _parseTvSearchList(Object? data) {
    if (data is! Map<String, dynamic>) {
      return <MediaItem>[];
    }
    final Object? results = data['results'];
    if (results is! List<dynamic>) {
      return <MediaItem>[];
    }
    return results.whereType<Map<String, dynamic>>().map((
      Map<String, dynamic> json,
    ) {
      final List<int> genreIds = _intList(json['genre_ids']);
      final bool looksLikeAnime =
          genreIds.contains(16) && _string(json['original_language']) == 'ja';
      return _fromListItem(
        json,
        looksLikeAnime ? MediaType.anime : MediaType.series,
      );
    }).toList();
  }

  List<CalendarItem> _parseCalendarList(
    Object? data,
    MediaType type,
    CalendarItemType itemType,
  ) {
    if (data is! Map<String, dynamic>) {
      return <CalendarItem>[];
    }
    final Object? results = data['results'];
    if (results is! List<dynamic>) {
      return <CalendarItem>[];
    }
    return results
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) {
          final MediaItem media = _fromListItem(json, type);
          final DateTime? date = _releaseDate(json, type);
          if (date == null) {
            return null;
          }
          final String typeLabel = switch (type) {
            MediaType.movie => 'Movie release',
            MediaType.series => 'Series airing',
            MediaType.anime => 'Anime airing',
          };
          return CalendarItem(
            id: 'tmdb-calendar:${media.externalIds['tmdb']}:${date.toIso8601String()}',
            mediaItem: media,
            date: date,
            title: '$typeLabel · ${media.title}',
            description: media.overview,
            type: itemType,
            isFromLibrary: false,
          );
        })
        .whereType<CalendarItem>()
        .toList();
  }

  MediaItem? _fromTrending(Map<String, dynamic> json) {
    final String? mediaType = json['media_type'] as String?;
    if (mediaType == 'movie') {
      return _fromListItem(json, MediaType.movie);
    }
    if (mediaType == 'tv') {
      final MediaItem item = _fromListItem(json, MediaType.series);
      final List<int> genreIds = _intList(json['genre_ids']);
      if (genreIds.contains(16) && _string(json['original_language']) == 'ja') {
        return _fromListItem(json, MediaType.anime);
      }
      return item;
    }
    return null;
  }

  MediaItem _fromListItem(Map<String, dynamic> json, MediaType type) {
    final int id = _int(json['id']);
    final String title = type == MediaType.movie
        ? _string(json['title'], fallback: _string(json['original_title']))
        : _string(json['name'], fallback: _string(json['original_name']));
    final String originalTitle = type == MediaType.movie
        ? _string(json['original_title'], fallback: title)
        : _string(json['original_name'], fallback: title);
    final String releaseDate = type == MediaType.movie
        ? _string(json['release_date'])
        : _string(json['first_air_date']);
    final int year = int.tryParse(releaseDate.split('-').first) ?? 0;
    final List<String> genres = _intList(json['genre_ids'])
        .map((int id) => _genreName(id, type))
        .where((String value) => value.isNotEmpty)
        .toList();

    return MediaItem(
      id:
          'tmdb:${switch (type) {
            MediaType.movie => 'movie',
            MediaType.series => 'tv',
            MediaType.anime => 'anime',
          }}:$id',
      title: title.isEmpty ? originalTitle : title,
      originalTitle: originalTitle.isEmpty ? title : originalTitle,
      overview: _string(
        json['overview'],
        fallback: 'No overview from TMDB yet.',
      ),
      type: type,
      year: year == 0 ? DateTime.now().year : year,
      posterUrl: _imageUrl(
        _string(json['poster_path']),
        fallbackSeed: 'tmdb-poster-$id',
        poster: true,
      ),
      backdropUrl: _imageUrl(
        _string(json['backdrop_path']),
        fallbackSeed: 'tmdb-backdrop-$id',
      ),
      rating: (_num(json['vote_average']) / 1).clamp(0, 10),
      genres: genres,
      sourceProvider: name,
      externalIds: <String, String>{
        'tmdb': id.toString(),
        'tmdb_media_type': type == MediaType.movie ? 'movie' : 'tv',
      },
      statusLabel: 'TMDB',
    );
  }

  MediaItem _fromDetails(Map<String, dynamic> json, MediaType type) {
    final MediaItem base = _fromListItem(json, type);
    final Object? genresJson = json['genres'];
    final List<String> genres = genresJson is List<dynamic>
        ? genresJson
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> genre) => _string(genre['name']))
              .where((String name) => name.isNotEmpty)
              .toList()
        : base.genres;

    return MediaItem(
      id: base.id,
      title: base.title,
      originalTitle: base.originalTitle,
      overview: base.overview,
      type: base.type,
      year: base.year,
      posterUrl: base.posterUrl,
      backdropUrl: base.backdropUrl,
      rating: base.rating,
      genres: genres,
      sourceProvider: base.sourceProvider,
      externalIds: base.externalIds,
      runtimeMinutes: type == MediaType.movie ? _int(json['runtime']) : null,
      episodeCount: type == MediaType.series || type == MediaType.anime
          ? _int(json['number_of_episodes'])
          : null,
      seasons: type == MediaType.series || type == MediaType.anime
          ? _seasonList(json['seasons'])
          : const <MediaSeason>[],
      statusLabel: _string(json['status'], fallback: 'TMDB'),
    );
  }

  List<MediaSeason> _seasonList(Object? value) {
    if (value is! List<dynamic>) {
      return const <MediaSeason>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) {
          return MediaSeason(
            seasonNumber: _int(json['season_number']),
            name: _string(json['name']),
            episodeCount: _int(json['episode_count']),
            posterUrl: _imageUrl(
              _string(json['poster_path']),
              fallbackSeed: 'tmdb-season-${json['id'] ?? ''}',
              poster: true,
            ),
            overview: _string(json['overview']),
          );
        })
        .where(
          (MediaSeason season) =>
              season.seasonNumber > 0 && season.episodeCount > 0,
        )
        .toList(growable: false);
  }

  String _imageUrl(
    String path, {
    required String fallbackSeed,
    bool poster = false,
  }) {
    if (path.isEmpty) {
      return '';
    }
    return 'https://image.tmdb.org/t/p/${poster ? 'w500' : 'w1280'}$path';
  }

  void _assertConfigured() {
    if (_readAccessToken.isEmpty) {
      throw const TmdbConfigurationException(
        'TMDB read access token is not configured.',
      );
    }
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

  static num _num(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value) ?? 0;
    }
    return 0;
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static DateTime? _releaseDate(Map<String, dynamic> json, MediaType type) {
    final String value = type == MediaType.movie
        ? _string(json['release_date'])
        : _string(json['first_air_date']);
    return value.isEmpty ? null : DateTime.tryParse(value);
  }

  static String _date(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static List<int> _intList(Object? value) {
    if (value is! List<dynamic>) {
      return <int>[];
    }
    return value.map(_int).where((int id) => id > 0).toList();
  }

  static String _genreName(int id, MediaType type) {
    return switch (id) {
      16 => 'Animation',
      18 => 'Drama',
      35 => 'Comedy',
      80 => 'Crime',
      99 => 'Documentary',
      10751 => 'Family',
      10759 => 'Action & Adventure',
      10762 => 'Kids',
      10765 => 'Sci-Fi & Fantasy',
      10768 => 'War & Politics',
      28 => 'Action',
      12 => 'Adventure',
      14 => 'Fantasy',
      27 => 'Horror',
      53 => 'Thriller',
      878 => 'Science Fiction',
      9648 => 'Mystery',
      10749 => 'Romance',
      _ => type == MediaType.anime ? 'Anime' : '',
    };
  }
}

class _TmdbId {
  const _TmdbId({required this.id, required this.type});

  final int id;
  final MediaType type;

  static _TmdbId? tryParse(String value) {
    final List<String> parts = value.split(':');
    if (parts.length != 3 || parts.first != 'tmdb') {
      return null;
    }
    final int? id = int.tryParse(parts[2]);
    if (id == null) {
      return null;
    }
    final MediaType? type = switch (parts[1]) {
      'movie' => MediaType.movie,
      'tv' => MediaType.series,
      'anime' => MediaType.anime,
      _ => null,
    };
    if (type == null) {
      return null;
    }
    return _TmdbId(id: id, type: type);
  }
}
