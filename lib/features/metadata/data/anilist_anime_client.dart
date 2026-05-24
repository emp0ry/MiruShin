import 'package:dio/dio.dart';

class AniListAnimeClient {
  AniListAnimeClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://graphql.anilist.co',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 18),
            ),
          );

  final Dio _dio;
  final Map<String, _CacheEntry<List<AniListAnimeDetails>>> _searchCache =
      <String, _CacheEntry<List<AniListAnimeDetails>>>{};
  final Map<int, _CacheEntry<AniListAnimeDetails>> _detailsCache =
      <int, _CacheEntry<AniListAnimeDetails>>{};

  static const Duration _cacheTtl = Duration(hours: 6);
  static const int _maxCacheSize = 200;

  static const String _mediaFields = '''
    id
    idMal
    title { romaji english native }
    format
    status
    episodes
    startDate { year }
    coverImage { extraLarge }
    bannerImage
    averageScore
    relations {
      edges {
        relationType(version: 2)
        node {
          id
          title { romaji english native }
          format
          episodes
          startDate { year }
          coverImage { extraLarge }
        }
      }
    }
  ''';

  Future<List<AniListAnimeDetails>> search(String query) async {
    final String key = query.trim().toLowerCase();
    if (key.isEmpty) return const <AniListAnimeDetails>[];
    final List<AniListAnimeDetails>? cached = _searchCache[key]?.valueIfFresh;
    if (cached != null) return cached;

    final Map<String, dynamic> data = await _post(
      '''
      query SearchAnime(\$search: String) {
        Page(page: 1, perPage: 8) {
          media(type: ANIME, search: \$search, sort: POPULARITY_DESC) {
            $_mediaFields
          }
        }
      }
      ''',
      <String, dynamic>{'search': query.trim()},
    );

    final Object? page = data['Page'];
    final List<AniListAnimeDetails> results = <AniListAnimeDetails>[];
    if (page is Map<String, dynamic>) {
      final Object? media = page['media'];
      if (media is List<dynamic>) {
        for (final Object? item in media) {
          if (item is Map<String, dynamic>) {
            results.add(_fromJson(item));
          }
        }
      }
    }
    _putSearchCache(key, results);
    return results;
  }

  Future<AniListAnimeDetails?> getById(int id) async {
    final AniListAnimeDetails? cached = _detailsCache[id]?.valueIfFresh;
    if (cached != null) return cached;

    final Map<String, dynamic> data = await _post(
      '''
      query AnimeById(\$id: Int) {
        Media(id: \$id, type: ANIME) {
          $_mediaFields
        }
      }
      ''',
      <String, dynamic>{'id': id},
    );

    final Object? media = data['Media'];
    if (media is! Map<String, dynamic>) return null;
    final AniListAnimeDetails details = _fromJson(media);
    _putDetailsCache(id, details);
    return details;
  }

  void _putSearchCache(String key, List<AniListAnimeDetails> value) {
    if (_searchCache.length >= _maxCacheSize) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = _CacheEntry<List<AniListAnimeDetails>>(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }

  void _putDetailsCache(int id, AniListAnimeDetails value) {
    if (_detailsCache.length >= _maxCacheSize) {
      _detailsCache.remove(_detailsCache.keys.first);
    }
    _detailsCache[id] = _CacheEntry<AniListAnimeDetails>(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }

  AniListAnimeDetails _fromJson(Map<String, dynamic> json) {
    final int id = _int(json['id']);
    final int? malId = _nullableInt(json['idMal']);
    final Map<String, dynamic> titleMap =
        _map(json['title']) ?? const <String, dynamic>{};
    final String romaji = _str(titleMap['romaji']);
    final String english = _str(titleMap['english']);
    final String native = _str(titleMap['native']);
    final String format = _str(json['format']);
    final String status = _str(json['status']);
    final int? episodes = _nullableInt(json['episodes']);
    final int year = _int(_nested(json, <String>['startDate', 'year']));
    final String cover = _str(
      _nested(json, <String>['coverImage', 'extraLarge']),
    );
    final String banner = _str(json['bannerImage']);
    final int? score = _nullableInt(json['averageScore']);
    final List<AniListRelation> relations = _parseRelations(json['relations']);

    return AniListAnimeDetails(
      id: id,
      malId: malId,
      titleRomaji: romaji,
      titleEnglish: english,
      titleNative: native,
      format: format,
      status: status,
      episodes: episodes,
      startYear: year,
      coverImage: cover.isEmpty ? null : cover,
      bannerImage: banner.isEmpty ? null : banner,
      averageScore: score,
      relations: relations,
    );
  }

  List<AniListRelation> _parseRelations(Object? value) {
    if (value is! Map<String, dynamic>) return const <AniListRelation>[];
    final Object? edges = value['edges'];
    if (edges is! List<dynamic>) return const <AniListRelation>[];
    final List<AniListRelation> result = <AniListRelation>[];
    for (final Object? edge in edges) {
      if (edge is! Map<String, dynamic>) continue;
      final String relType = _str(edge['relationType']);
      final Object? node = edge['node'];
      if (node is! Map<String, dynamic>) continue;
      final Map<String, dynamic> titleMap =
          _map(node['title']) ?? const <String, dynamic>{};
      final int year = _int(_nested(node, <String>['startDate', 'year']));
      final String cover = _str(
        _nested(node, <String>['coverImage', 'extraLarge']),
      );
      result.add(
        AniListRelation(
          nodeId: _int(node['id']),
          relationType: relType,
          format: _str(node['format']),
          titleRomaji: _str(titleMap['romaji']),
          titleEnglish: _str(titleMap['english']),
          titleNative: _str(titleMap['native']),
          episodes: _nullableInt(node['episodes']),
          startYear: year,
          coverImage: cover.isEmpty ? null : cover,
        ),
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> _post(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '',
      data: <String, dynamic>{'query': query, 'variables': variables},
      options: Options(
        headers: const <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    final Object? body = response.data;
    if (body is! Map<String, dynamic>) return const <String, dynamic>{};
    final Object? data = body['data'];
    return data is Map<String, dynamic> ? data : const <String, dynamic>{};
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    final int v = _int(value);
    return v == 0 ? null : v;
  }

  static String _str(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return '';
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  static Object? _nested(Map<String, dynamic> json, List<String> keys) {
    Object? current = json;
    for (final String key in keys) {
      if (current is! Map<String, dynamic>) return null;
      current = current[key];
    }
    return current;
  }
}

class AniListAnimeDetails {
  const AniListAnimeDetails({
    required this.id,
    this.malId,
    required this.titleRomaji,
    required this.titleEnglish,
    required this.titleNative,
    required this.format,
    required this.status,
    this.episodes,
    required this.startYear,
    this.coverImage,
    this.bannerImage,
    this.averageScore,
    required this.relations,
  });

  final int id;
  final int? malId;
  final String titleRomaji;
  final String titleEnglish;
  final String titleNative;
  final String format;
  final String status;
  final int? episodes;
  final int startYear;
  final String? coverImage;
  final String? bannerImage;
  final int? averageScore;
  final List<AniListRelation> relations;

  String get displayTitle =>
      titleEnglish.isNotEmpty ? titleEnglish : titleRomaji;
}

class AniListRelation {
  const AniListRelation({
    required this.nodeId,
    required this.relationType,
    required this.format,
    required this.titleRomaji,
    required this.titleEnglish,
    required this.titleNative,
    this.episodes,
    required this.startYear,
    this.coverImage,
  });

  final int nodeId;
  final String relationType;
  final String format;
  final String titleRomaji;
  final String titleEnglish;
  final String titleNative;
  final int? episodes;
  final int startYear;
  final String? coverImage;

  String get displayTitle =>
      titleEnglish.isNotEmpty ? titleEnglish : titleRomaji;
}

class _CacheEntry<T> {
  const _CacheEntry({required this.value, required this.expiry});
  final T value;
  final DateTime expiry;

  T? get valueIfFresh => expiry.isAfter(DateTime.now()) ? value : null;
}
