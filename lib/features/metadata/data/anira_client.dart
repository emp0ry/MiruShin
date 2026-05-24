import 'package:dio/dio.dart';

import '../domain/anira_models.dart';
export '../domain/anira_models.dart' show AniraWatchOrderEntry;

class AniraClient {
  AniraClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.anira.dev',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  DateTime? _lastRequestTime;

  static const int _maxCacheSize = 500;
  static const Duration _cacheTtl = Duration(hours: 1);
  static const Duration _throttle = Duration(milliseconds: 200);

  Future<void> _ensureThrottle() async {
    final DateTime? last = _lastRequestTime;
    if (last != null) {
      final Duration elapsed = DateTime.now().difference(last);
      if (elapsed < _throttle) {
        await Future<void>.delayed(_throttle - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  String _cacheKey(String path, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return path;
    final String sorted =
        (params.entries.toList()..sort(
              (MapEntry<String, dynamic> a, MapEntry<String, dynamic> b) =>
                  a.key.compareTo(b.key),
            ))
            .map((MapEntry<String, dynamic> e) => '${e.key}=${e.value}')
            .join('&');
    return '$path?$sorted';
  }

  T? _fromCache<T>(String key) {
    final _CacheEntry? entry = _cache[key];
    if (entry == null) return null;
    if (entry.expiry.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  void _toCache(String key, Object value) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(
      value: value,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }

  Future<List<Map<String, dynamic>>> searchMedia(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <Map<String, dynamic>>[];
    final Map<String, dynamic> params = <String, dynamic>{'q': trimmed};
    final String key = _cacheKey('/media/search', params);
    final List<Map<String, dynamic>>? cached =
        _fromCache<List<Map<String, dynamic>>>(key);
    if (cached != null) return cached;

    await _ensureThrottle();
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/media/search',
      queryParameters: params,
    );
    final List<Map<String, dynamic>> result = _toList(response.data);
    _toCache(key, result);
    return result;
  }

  Future<Map<String, dynamic>?> getMedia(
    String id, {
    String? mappingKey,
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'mapping_key': ?_nonEmpty(mappingKey),
    };
    final String key = _cacheKey('/media/$id', params);
    final Map<String, dynamic>? cached = _fromCache<Map<String, dynamic>>(key);
    if (cached != null) return cached;

    await _ensureThrottle();
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/media/$id',
      queryParameters: params.isEmpty ? null : params,
    );
    final Map<String, dynamic>? result = _toMap(response.data);
    if (result != null) _toCache(key, result);
    return result;
  }

  Future<AniraEpisodeTimeskips?> getEpisodeTimeskips(
    String id,
    int episode,
  ) async {
    final String path = '/media/$id/episodes/$episode';
    final String key = _cacheKey(path, null);
    final Map<String, dynamic>? cached = _fromCache<Map<String, dynamic>>(key);
    if (cached != null) return AniraEpisodeTimeskips.fromJson(cached);

    await _ensureThrottle();
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(path);
      final Map<String, dynamic>? result = _toMap(response.data);
      if (result != null) {
        _toCache(key, result);
        return AniraEpisodeTimeskips.fromJson(result);
      }
    } on DioException {
      // Episode timeskips are best-effort; 404 is common.
    }
    return null;
  }

  Future<AniraEpisodeTimeskips?> getTimeskips(String id, int episode) =>
      getEpisodeTimeskips(id, episode);

  Future<List<AniraWatchOrderEntry>> getWatchOrder(
    String id,
    String mappingKey,
  ) async {
    final String path = '/media/$id/watch_order';
    final Map<String, dynamic> params = <String, dynamic>{
      'mapping_key': mappingKey,
    };
    final String key = _cacheKey(path, params);
    final List<Map<String, dynamic>>? cached =
        _fromCache<List<Map<String, dynamic>>>(key);
    if (cached != null) {
      return cached
          .map(AniraWatchOrderEntry.fromJson)
          .toList(growable: false);
    }

    await _ensureThrottle();
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        path,
        queryParameters: params,
      );
      final List<Map<String, dynamic>> result = _toList(response.data);
      if (result.isNotEmpty) _toCache(key, result);
      return result.map(AniraWatchOrderEntry.fromJson).toList(growable: false);
    } on DioException {
      return const <AniraWatchOrderEntry>[];
    }
  }

  Future<AniraMappings?> resolveMappingsByTvdbId(int tvdbId) async {
    final String path = '/media/tvdb/$tvdbId';
    final String key = _cacheKey(path, null);
    final Map<String, dynamic>? cached = _fromCache<Map<String, dynamic>>(key);
    if (cached != null) return AniraMappings.fromJson(cached);

    await _ensureThrottle();
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(path);
      final Map<String, dynamic>? result = _toMap(response.data);
      if (result != null) {
        _toCache(key, result);
        return AniraMappings.fromJson(result);
      }
    } on DioException {
      // Not all TVDB IDs have Anira entries.
    }
    return null;
  }

  // ─── helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _toMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (Object? k, Object? v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    }
    if (value is List<dynamic>) {
      for (final Object? item in value) {
        if (item is Map) return _toMap(item);
      }
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      _toMap(value) ?? const <String, dynamic>{};

  static List<Map<String, dynamic>> _toList(Object? value) {
    if (value is List<dynamic>) {
      return value.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    final Map<String, dynamic> root = _asMap(value);
    for (final String key in const <String>['data', 'results', 'mappings']) {
      final Object? nested = root[key];
      if (nested is List<dynamic>) {
        return nested.whereType<Map<String, dynamic>>().toList(growable: false);
      }
    }
    return const <Map<String, dynamic>>[];
  }

  static String? _nonEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiry});
  final Object value;
  final DateTime expiry;
}
