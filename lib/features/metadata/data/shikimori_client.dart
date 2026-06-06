import 'package:dio/dio.dart';

class ShikimoriSearchHit {
  const ShikimoriSearchHit({
    this.id = 0,
    required this.malId,
    required this.russian,
    required this.name,
  });
  final int id;
  final int malId;
  final String russian;
  final String name;
}

class ShikiMoriClient {
  ShikiMoriClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 14),
            ),
          );

  final Dio _dio;
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  static const String _restUrl = 'https://shikimori.one/api/animes';
  static const String _graphqlUrl = 'https://shikimori.one/api/graphql';
  static const Duration _cacheTtl = Duration(hours: 12);
  static const int _maxCacheSize = 300;

  // Direct lookup by MAL ID via GraphQL — reliable, no 301.
  Future<String?> findRussianTitleByMalId(int malId) async {
    final String key = 'mal:$malId';
    final _CacheEntry? cached = _cache[key];
    if (cached != null && cached.expiry.isAfter(DateTime.now())) {
      return cached.value;
    }

    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        _graphqlUrl,
        data: <String, dynamic>{
          'query': '{ animes(ids: "$malId") { russian } }',
        },
        options: Options(
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );

      final Object? body = response.data;
      if (body is! Map) return null;
      final Object? animes = (body['data'] as Map?)?['animes'];
      if (animes is! List<dynamic> || animes.isEmpty) return null;
      final Object? first = animes.first;
      if (first is! Map) return null;
      final Object? russian = first['russian'];
      final String? result = russian is String && russian.trim().isNotEmpty
          ? russian.trim()
          : null;
      _putCache(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<String?> findRussianTitle(String query) async {
    final String key = query.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) {
      final _CacheEntry entry = _cache[key]!;
      if (entry.expiry.isAfter(DateTime.now())) {
        return entry.value;
      }
      _cache.remove(key);
    }

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        _restUrl,
        queryParameters: <String, String>{
          'search': query.trim(),
          'limit': '3',
          'censored': 'false',
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );

      final Object? data = response.data;
      if (data is! List<dynamic> || data.isEmpty) {
        return null;
      }

      final Object? first = data.first;
      if (first is! Map) return null;

      final Object? russian = first['russian'];
      final String? result = russian is String && russian.trim().isNotEmpty
          ? russian.trim()
          : null;
      _putCache(key, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  // Search anime by Russian (or any) query; returns up to [limit] hits.
  Future<List<ShikimoriSearchHit>> searchByQuery(
    String query, {
    int limit = 20,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <ShikimoriSearchHit>[];
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        _restUrl,
        queryParameters: <String, String>{
          'search': trimmed,
          'limit': limit.toString(),
          'censored': 'false',
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) return const <ShikimoriSearchHit>[];
      final List<ShikimoriSearchHit> hits = <ShikimoriSearchHit>[];
      for (final Object? item in data) {
        if (item is! Map) continue;
        final int? shikimoriId = _parseInt(item['id']);
        final int? malId = _parseInt(item['id_mal']);
        if ((shikimoriId == null || shikimoriId <= 0) &&
            (malId == null || malId <= 0)) {
          continue;
        }
        final String russian = item['russian']?.toString().trim() ?? '';
        final String name = item['name']?.toString().trim() ?? '';
        hits.add(
          ShikimoriSearchHit(
            id: shikimoriId ?? malId ?? 0,
            malId: malId ?? shikimoriId ?? 0,
            russian: russian,
            name: name,
          ),
        );
      }
      return hits;
    } catch (_) {
      return const <ShikimoriSearchHit>[];
    }
  }

  // Batch-fetch Russian titles for a list of MAL IDs via REST.
  Future<Map<int, String>> batchRussianTitles(List<int> ids) async {
    if (ids.isEmpty) return const <int, String>{};

    final List<int> uniqueIds = ids
        .where((int id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (uniqueIds.isEmpty) return const <int, String>{};

    final DateTime now = DateTime.now();
    final Map<int, String> result = <int, String>{};
    final List<int> pendingIds = <int>[];
    for (final int id in uniqueIds) {
      final String cacheKey = 'mal:$id';
      final _CacheEntry? cached = _cache[cacheKey];
      if (cached != null && cached.expiry.isAfter(now)) {
        final String? value = cached.value;
        if (value != null && value.isNotEmpty) {
          result[id] = value;
        }
        continue;
      }
      if (cached != null) _cache.remove(cacheKey);
      pendingIds.add(id);
    }

    for (int i = 0; i < pendingIds.length; i += 50) {
      final int end = i + 50 < pendingIds.length ? i + 50 : pendingIds.length;
      result.addAll(await _fetchRussianTitleBatch(pendingIds.sublist(i, end)));
    }

    return result;
  }

  Future<Map<int, String>> _fetchRussianTitleBatch(List<int> ids) async {
    if (ids.isEmpty) return const <int, String>{};
    final String joined = ids.join(',');
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        _restUrl,
        queryParameters: <String, String>{
          'ids': joined,
          'limit': ids.length.clamp(1, 50).toString(),
          'censored': 'false',
        },
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) return const <int, String>{};
      final Map<int, String> result = <int, String>{};
      for (final Object? item in data) {
        if (item is! Map) continue;
        // id_mal is the MAL ID; Shikimori's own `id` may differ.
        final int? malId = _parseInt(item['id_mal'] ?? item['id']);
        if (malId == null || malId <= 0) continue;
        final String? russian = item['russian']?.toString().trim();
        if (russian != null && russian.isNotEmpty) {
          result[malId] = russian;
          _putCache('mal:$malId', russian);
        }
      }
      for (final int id in ids) {
        if (!result.containsKey(id)) {
          _putCache('mal:$id', null);
        }
      }
      return result;
    } catch (_) {
      return const <int, String>{};
    }
  }

  // Fetch full details from Shikimori REST for Russian description.
  Future<({String title, String description})?> getRussianDetails(
    int id, {
    int? expectedMalId,
  }) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$_restUrl/$id',
        options: Options(
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': 'MiruShin/1.0',
          },
        ),
      );
      final Object? data = response.data;
      if (data is! Map) return null;
      if (expectedMalId != null && expectedMalId > 0) {
        final int? actualMalId = _parseInt(data['id_mal']);
        if (actualMalId != expectedMalId) return null;
      }
      final String russian = data['russian']?.toString().trim() ?? '';
      final String description = _stripMarkup(
        data['description']?.toString().trim() ?? '',
      );
      if (russian.isEmpty && description.isEmpty) return null;
      return (title: russian, description: description);
    } catch (_) {
      return null;
    }
  }

  Future<({String title, String description})?> getRussianDetailsForMedia({
    int? malId,
    Iterable<String> queries = const <String>[],
  }) async {
    if (malId != null && malId > 0) {
      final ({String title, String description})? direct =
          await getRussianDetails(malId, expectedMalId: malId);
      if (_hasDetails(direct)) return direct;
    }

    final Set<String> seenQueries = <String>{};
    for (final String rawQuery in queries) {
      final String query = rawQuery.trim();
      if (query.isEmpty || !seenQueries.add(query.toLowerCase())) continue;
      final List<ShikimoriSearchHit> hits = await searchByQuery(
        query,
        limit: 5,
      );
      if (hits.isEmpty) continue;
      final ShikimoriSearchHit hit = _bestHit(hits, malId);
      final bool exactMalMatch =
          malId == null || malId <= 0 || hit.malId == malId;
      final int detailId = hit.id > 0 ? hit.id : hit.malId;
      final ({String title, String description})? details =
          await getRussianDetails(
            detailId,
            expectedMalId: malId != null && malId > 0 ? malId : null,
          );
      if (_hasDetails(details)) return details;
      if (exactMalMatch && hit.russian.isNotEmpty) {
        return (title: hit.russian, description: '');
      }
    }

    return null;
  }

  static ShikimoriSearchHit _bestHit(
    List<ShikimoriSearchHit> hits,
    int? malId,
  ) {
    if (malId == null || malId <= 0) return hits.first;
    for (final ShikimoriSearchHit hit in hits) {
      if (hit.malId == malId) return hit;
    }
    return hits.first;
  }

  static bool _hasDetails(({String title, String description})? details) {
    return details != null &&
        (details.title.trim().isNotEmpty ||
            details.description.trim().isNotEmpty);
  }

  static String _stripMarkup(String text) {
    // [tag=id text content] -> "text content"
    String result = text.replaceAllMapped(
      RegExp(r'\[\w+=\d+\s+([^\]]+)\]'),
      (Match m) => m.group(1) ?? '',
    );
    // [tag=id]content[/tag] -> "content"
    result = result.replaceAllMapped(
      RegExp(r'\[\w+=\d+\]([^\[]*)\[/\w+\]'),
      (Match m) => m.group(1) ?? '',
    );
    // strip any remaining [tag] or [/tag]
    result = result.replaceAll(RegExp(r'\[/?[^\]]*\]'), '');
    return result.trim();
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _putCache(String key, String? value) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiry});
  final String? value;
  final DateTime expiry;
}
