import 'package:dio/dio.dart';

class ImdbRatingsClient {
  ImdbRatingsClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.agregarr.org',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 12),
            ),
          );

  final Dio _dio;

  Future<double?> fetchRating(String imdbId) async {
    final String normalizedId = imdbId.trim();
    if (!RegExp(r'^tt\d+$').hasMatch(normalizedId)) return null;

    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/ratings',
      queryParameters: <String, dynamic>{'id': normalizedId},
    );
    final Object? data = response.data;
    if (data is! List<dynamic>) return null;

    for (final Object? value in data) {
      if (value is! Map) continue;
      if (value['imdbId'] != normalizedId) continue;
      final Object? rawRating = value['rating'];
      final double? rating = switch (rawRating) {
        final num number => number.toDouble(),
        final String text => double.tryParse(text),
        _ => null,
      };
      if (rating != null && rating > 0 && rating <= 10) return rating;
    }
    return null;
  }
}
