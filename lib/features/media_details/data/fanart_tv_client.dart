import 'package:dio/dio.dart';

import '../domain/fanart_gallery.dart';

class FanartTvClient {
  FanartTvClient({required String apiKey, Dio? dio})
    : _apiKey = apiKey.trim(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://webservice.fanart.tv/v3.2',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const <String, String>{'Accept': 'application/json'},
            ),
          );

  final String _apiKey;
  final Dio _dio;
  DateTime? _retryAfter;

  Future<FanartGallery> fetchGallery(FanartIdentity identity) async {
    if (_apiKey.isEmpty) return FanartGallery.empty;
    final DateTime? retryAfter = _retryAfter;
    if (retryAfter != null && retryAfter.isAfter(DateTime.now())) {
      throw FanartTvRateLimitedException(retryAfter);
    }

    final String path = switch (identity.kind) {
      FanartMediaKind.movie => '/movies/${identity.id}',
      FanartMediaKind.tv => '/tv/${identity.id}',
    };
    final List<String> responseKeys = switch (identity.kind) {
      FanartMediaKind.movie => const <String>[
        'movie4kbackground',
        'moviebackground',
      ],
      FanartMediaKind.tv => const <String>[
        'show4kbackground',
        'showbackground',
      ],
    };

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        path,
        options: Options(headers: <String, String>{'api-key': _apiKey}),
      );
      return FanartGallery.fromBackgrounds(
        _parseBackgrounds(response.data, responseKeys),
      );
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      if (status == 404 || status == 401) return FanartGallery.empty;
      if (status == 429) {
        final DateTime retryAt = _retryAt(error.response);
        _retryAfter = retryAt;
        throw FanartTvRateLimitedException(retryAt);
      }
      rethrow;
    }
  }

  static List<FanartBackground> _parseBackgrounds(
    Object? response,
    Iterable<String> keys,
  ) {
    if (response is! Map) return const <FanartBackground>[];
    return keys
        .expand<Map>((String key) {
          final Object? raw = response[key];
          return raw is List ? raw.whereType<Map>() : const <Map>[];
        })
        .map(
          (Map<dynamic, dynamic> json) => FanartBackground.fromJson(
            json.map(
              (dynamic key, dynamic value) =>
                  MapEntry<String, dynamic>(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
  }

  static DateTime _retryAt(Response<dynamic>? response) {
    final String? raw = response?.headers.value('retry-after')?.trim();
    final int? seconds = int.tryParse(raw ?? '');
    if (seconds != null && seconds > 0) {
      return DateTime.now().add(Duration(seconds: seconds));
    }
    final DateTime? date = raw == null ? null : DateTime.tryParse(raw);
    if (date != null && date.isAfter(DateTime.now())) return date;
    return DateTime.now().add(const Duration(minutes: 5));
  }
}

class FanartTvRateLimitedException implements Exception {
  const FanartTvRateLimitedException(this.retryAfter);

  final DateTime retryAfter;
}
