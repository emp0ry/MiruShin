import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../domain/tracker_models.dart';

/// REST/GraphQL client for the Shikimori API.
///
/// Shikimori requires a descriptive `User-Agent` on every request and a Bearer
/// access token for authenticated calls. When [onRefreshToken] is provided and
/// a request returns 401, the token is refreshed once and the call retried.
///
/// Note on ids: Shikimori keeps its anime ids aligned with MyAnimeList ids
/// (it imported from MAL), so the MAL id is used directly as the Shikimori
/// `target_id` for any anime that exists on MAL — which is exactly the set the
/// app carries a MAL id for.
class ShikimoriApiClient {
  ShikimoriApiClient({
    required String accessToken,
    required int userId,
    Future<String?> Function()? onRefreshToken,
    Dio? dio,
  })  : _accessToken = accessToken,
        _userId = userId,
        _onRefreshToken = onRefreshToken,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConstants.shikimoriApiBaseUrl,
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 18),
              ),
            );

  final Dio _dio;
  String _accessToken;
  int _userId;
  final Future<String?> Function()? _onRefreshToken;

  Future<TrackerViewer> fetchViewer() async {
    final Response<dynamic> response = await _request(
      'GET',
      '/api/users/whoami',
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected Shikimori viewer response.');
    }
    _userId = _int(data['id']);
    final Object? image = data['image'];
    final String? avatar = image is Map<String, dynamic>
        ? _nullableString(image['x160'] ?? image['x148'] ?? image['original'])
        : null;
    final String? avatarUrl =
        avatar != null ? _absoluteUrl(avatar) : null;
    return TrackerViewer(
      id: _userId,
      name: '${data['nickname'] ?? 'Shikimori User'}',
      avatarUrl: avatarUrl,
    );
  }

  /// Fetches the user's anime rates and enriches them with title/poster from
  /// the GraphQL API, mapped into the shared folder/entry model.
  Future<List<AniListAnimeListFolder>> fetchAnimeList() async {
    final List<Map<String, dynamic>> rates = <Map<String, dynamic>>[];
    int page = 1;
    while (page <= 50) {
      final Response<dynamic> response = await _request(
        'GET',
        '/api/v2/user_rates',
        queryParameters: <String, dynamic>{
          'user_id': _userId,
          'target_type': 'Anime',
          'limit': 1000,
          'page': page,
        },
      );
      final Object? data = response.data;
      if (data is! List<dynamic>) break;
      final List<Map<String, dynamic>> batch =
          data.whereType<Map<String, dynamic>>().toList();
      rates.addAll(batch);
      if (batch.length < 1000) break;
      page++;
    }
    if (rates.isEmpty) return const <AniListAnimeListFolder>[];

    final List<int> ids = rates
        .map((Map<String, dynamic> r) => _int(r['target_id']))
        .where((int id) => id > 0)
        .toSet()
        .toList(growable: false);
    final Map<int, Map<String, dynamic>> nodes = await _fetchAnimeNodes(ids);

    final Map<AniListListStatus, List<AniListAnimeListEntry>> grouped =
        <AniListListStatus, List<AniListAnimeListEntry>>{};
    for (final Map<String, dynamic> rate in rates) {
      final int targetId = _int(rate['target_id']);
      final AniListListStatus status = shikimoriStatusToCanonical(
        rate['status'] as String?,
      );
      final double score = _double(rate['score']);
      grouped.putIfAbsent(status, () => <AniListAnimeListEntry>[]).add(
            AniListAnimeListEntry(
              id: _int(rate['id']),
              status: status,
              progress: _int(rate['episodes']),
              score: score > 0 ? score : null,
              mediaItem: _mediaFromNode(nodes[targetId], targetId),
            ),
          );
    }
    final List<AniListAnimeListFolder> folders = <AniListAnimeListFolder>[];
    for (final AniListListStatus status in AniListListStatus.values) {
      final List<AniListAnimeListEntry>? entries = grouped[status];
      if (entries != null && entries.isNotEmpty) {
        folders.add(
          AniListAnimeListFolder(
            name: status.label,
            status: status,
            entries: entries,
          ),
        );
      }
    }
    return folders;
  }

  /// Creates or updates the user's rate for [malId] (used as the Shikimori
  /// target id).
  Future<void> updateUserRate({
    required int malId,
    AniListListStatus? status,
    int? episodes,
    double? score,
  }) async {
    final int? existingId = await _findRateId(malId);
    final Map<String, dynamic> rate = <String, dynamic>{
      if (status != null) 'status': status.shikimoriValue,
      'episodes': ?episodes,
      if (score != null) 'score': score.round().clamp(0, 10),
    };
    if (existingId != null) {
      if (rate.isEmpty) return;
      await _request(
        'PATCH',
        '/api/v2/user_rates/$existingId',
        data: <String, dynamic>{'user_rate': rate},
      );
    } else {
      await _request(
        'POST',
        '/api/v2/user_rates',
        data: <String, dynamic>{
          'user_rate': <String, dynamic>{
            'user_id': _userId,
            'target_id': malId,
            'target_type': 'Anime',
            ...rate,
          },
        },
      );
    }
  }

  Future<void> deleteUserRate(int malId) async {
    final int? existingId = await _findRateId(malId);
    if (existingId == null) return;
    await _request('DELETE', '/api/v2/user_rates/$existingId');
  }

  // --- internal helpers ---

  Future<int?> _findRateId(int targetId) async {
    try {
      final Response<dynamic> response = await _request(
        'GET',
        '/api/v2/user_rates',
        queryParameters: <String, dynamic>{
          'user_id': _userId,
          'target_id': targetId,
          'target_type': 'Anime',
        },
      );
      final Object? data = response.data;
      if (data is List<dynamic> && data.isNotEmpty) {
        final Object? first = data.first;
        if (first is Map<String, dynamic>) return _int(first['id']);
      }
    } catch (_) {
      // Treat as "no existing rate"; the caller will create one.
    }
    return null;
  }

  Future<Map<int, Map<String, dynamic>>> _fetchAnimeNodes(
    List<int> ids,
  ) async {
    final Map<int, Map<String, dynamic>> result =
        <int, Map<String, dynamic>>{};
    for (int i = 0; i < ids.length; i += 50) {
      final int end = i + 50 < ids.length ? i + 50 : ids.length;
      final String joined = ids.sublist(i, end).join(',');
      try {
        final Response<dynamic> response = await _request(
          'POST',
          '/api/graphql',
          data: <String, dynamic>{
            'query':
                '{ animes(ids: "$joined", limit: 50) { id name russian episodes score poster { originalUrl mainUrl } } }',
          },
          authenticated: false,
        );
        final Object? body = response.data;
        final Object? payload =
            body is Map<String, dynamic> ? body['data'] : null;
        final Object? animes =
            payload is Map<String, dynamic> ? payload['animes'] : null;
        if (animes is List<dynamic>) {
          for (final Object? node in animes) {
            if (node is Map<String, dynamic>) {
              result[_int(node['id'])] = node;
            }
          }
        }
      } catch (_) {
        // Best-effort enrichment; entries without metadata still render.
      }
    }
    return result;
  }

  MediaItem _mediaFromNode(Map<String, dynamic>? node, int malId) {
    final Object? poster = node?['poster'];
    final String posterUrl = poster is Map<String, dynamic>
        ? _absoluteUrl(
            _string(poster['originalUrl']).isNotEmpty
                ? _string(poster['originalUrl'])
                : _string(poster['mainUrl']),
          )
        : '';
    final String title = _string(node?['name']);
    final String russian = _string(node?['russian']);
    return MediaItem(
      id: 'mal:$malId',
      title: title.isNotEmpty ? title : 'Anime #$malId',
      originalTitle: russian,
      overview: '',
      type: MediaType.anime,
      year: 0,
      posterUrl: posterUrl,
      backdropUrl: '',
      rating: _double(node?['score']),
      genres: const <String>[],
      sourceProvider: 'Shikimori',
      externalIds: <String, String>{'mal': '$malId'},
      aliases: russian.isNotEmpty ? <String>[russian] : const <String>[],
      episodeCount: _nullableInt(node?['episodes']),
      statusLabel: '',
    );
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
    bool retried = false,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: <String, String>{
            'User-Agent': AppConstants.shikimoriUserAgent,
            'Accept': 'application/json',
            if (authenticated) 'Authorization': 'Bearer $_accessToken',
          },
        ),
      );
    } on DioException catch (error) {
      if (!retried &&
          authenticated &&
          error.response?.statusCode == 401 &&
          _onRefreshToken != null) {
        final String? fresh = await _onRefreshToken();
        if (fresh != null && fresh.trim().isNotEmpty) {
          _accessToken = fresh.trim();
          return _request(
            method,
            path,
            data: data,
            queryParameters: queryParameters,
            authenticated: authenticated,
            retried: true,
          );
        }
      }
      rethrow;
    }
  }

  static String _absoluteUrl(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.startsWith('http')) return trimmed;
    return '${AppConstants.shikimoriApiBaseUrl}$trimmed';
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static int? _nullableInt(Object? value) {
    final int parsed = _int(value);
    return parsed == 0 ? null : parsed;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static String _string(Object? value) =>
      value is String ? value.trim() : '';

  static String? _nullableString(Object? value) {
    final String parsed = _string(value);
    return parsed.isEmpty ? null : parsed;
  }
}
