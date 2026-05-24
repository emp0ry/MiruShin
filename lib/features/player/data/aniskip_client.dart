import 'package:dio/dio.dart';

import '../domain/player_models.dart';

class AniSkipClient {
  AniSkipClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.aniskip.com',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const <String, String>{'Accept': 'application/json'},
            ),
          );

  final Dio _dio;
  final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  static const Duration _cacheTtl = Duration(hours: 2);
  static const int _maxCacheSize = 600;

  Future<SkipMarkers> getSkipMarkers({
    required int malId,
    required int episode,
    required Duration episodeLength,
  }) async {
    if (malId <= 0 || episode <= 0) return const SkipMarkers();

    final int episodeLengthSeconds = episodeLength.inSeconds > 0
        ? episodeLength.inSeconds
        : 0;
    final String key = '$malId/$episode/$episodeLengthSeconds';
    final SkipMarkers? cached = _fromCache(key);
    if (cached != null) return cached;

    try {
      final String episodeLengthQuery = episodeLengthSeconds > 0
          ? '&episodeLength=$episodeLengthSeconds'
          : '';
      final Response<dynamic> response = await _dio.get<dynamic>(
        '/v2/skip-times/$malId/$episode'
        '?types=op&types=ed&types=mixed-op&types=mixed-ed'
        '$episodeLengthQuery',
      );
      final SkipMarkers markers = _parseMarkers(response.data);
      _toCache(key, markers);
      return markers;
    } on DioException {
      return const SkipMarkers();
    }
  }

  SkipMarkers _parseMarkers(Object? data) {
    final Map<String, dynamic> root = _asMap(data);
    final Object? results = root['results'];
    if (results is! List<dynamic>) return const SkipMarkers();

    Duration? openingStart;
    Duration? openingEnd;
    Duration? endingStart;
    Duration? endingEnd;

    for (final Object? item in results) {
      final Map<String, dynamic> json = _asMap(item);
      final String type = _string(json['skipType']).toLowerCase();
      final Map<String, dynamic> interval = _asMap(json['interval']);
      final Duration? start = _seconds(interval['startTime']);
      final Duration? end = _seconds(interval['endTime']);
      if (start == null || end == null || end <= start) continue;

      if (type == 'op' || type == 'mixed-op') {
        if (openingStart == null || start < openingStart) {
          openingStart = start;
          openingEnd = end;
        }
      } else if (type == 'ed' || type == 'mixed-ed') {
        if (endingStart == null || start > endingStart) {
          endingStart = start;
          endingEnd = end;
        }
      }
    }

    return SkipMarkers(
      openingStart: openingStart,
      openingEnd: openingEnd,
      endingStart: endingStart,
      endingEnd: endingEnd,
    );
  }

  SkipMarkers? _fromCache(String key) {
    final _CacheEntry? entry = _cache[key];
    if (entry == null) return null;
    if (entry.expiry.isBefore(DateTime.now())) {
      _cache.remove(key);
      return null;
    }
    return entry.markers;
  }

  void _toCache(String key, SkipMarkers markers) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(
      markers: markers,
      expiry: DateTime.now().add(_cacheTtl),
    );
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (Object? key, Object? mapValue) =>
            MapEntry<String, dynamic>(key.toString(), mapValue),
      );
    }
    return const <String, dynamic>{};
  }

  String _string(Object? value) => value is String ? value : '';

  Duration? _seconds(Object? value) {
    if (value is num) {
      return Duration(milliseconds: (value.toDouble() * 1000).round());
    }
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) {
        return Duration(milliseconds: (parsed * 1000).round());
      }
    }
    return null;
  }
}

class _CacheEntry {
  const _CacheEntry({required this.markers, required this.expiry});

  final SkipMarkers markers;
  final DateTime expiry;
}
