import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../domain/tracker_models.dart';

/// REST client for the MyAnimeList v2 API.
///
/// Authenticated with a Bearer access token. When [onRefreshToken] is provided
/// and a request returns 401, the client refreshes the token once and retries.
class MalApiClient {
  MalApiClient({
    required String accessToken,
    Future<String?> Function()? onRefreshToken,
    Dio? dio,
  })  : _accessToken = accessToken,
        _onRefreshToken = onRefreshToken,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConstants.malApiBaseUrl,
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 18),
              ),
            );

  final Dio _dio;
  String _accessToken;
  final Future<String?> Function()? _onRefreshToken;

  static const String _listFields =
      'list_status,num_episodes,media_type,main_picture,alternative_titles,start_season,mean';

  Future<TrackerViewer> fetchViewer() async {
    final Response<dynamic> response = await _get(
      '/users/@me',
      queryParameters: <String, dynamic>{'fields': 'id,name,picture'},
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Unexpected MAL viewer response.');
    }
    return TrackerViewer(
      id: _int(data['id']),
      name: '${data['name'] ?? 'MyAnimeList User'}',
      avatarUrl: _nullableString(data['picture']),
    );
  }

  /// Fetches the signed-in user's full anime list, mapped into the shared
  /// folder/entry model so the existing library UI can render it unchanged.
  Future<List<AniListAnimeListFolder>> fetchAnimeList() async {
    final List<Map<String, dynamic>> nodes = <Map<String, dynamic>>[];
    String path =
        '/users/@me/animelist?fields=$_listFields&limit=1000&nsfw=true';
    int guard = 0;
    while (guard < 20) {
      guard++;
      final Response<dynamic> response = await _get(path);
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) break;
      final Object? list = data['data'];
      if (list is List<dynamic>) {
        nodes.addAll(list.whereType<Map<String, dynamic>>());
      }
      final Object? paging = data['paging'];
      final String? next =
          paging is Map<String, dynamic> ? paging['next'] as String? : null;
      if (next == null || next.trim().isEmpty) break;
      path = next;
    }
    return _foldersFromNodes(nodes);
  }

  Future<void> updateStatus({
    required int malId,
    AniListListStatus? status,
    int? episodesWatched,
    double? score,
  }) async {
    final Map<String, dynamic> form = <String, dynamic>{
      if (status != null) 'status': status.malValue,
      if (status != null) 'is_rewatching': status.malIsRewatching,
      'num_watched_episodes': ?episodesWatched,
      if (score != null) 'score': score.round().clamp(0, 10),
    };
    if (form.isEmpty) return;
    await _request(
      'PATCH',
      '/anime/$malId/my_list_status',
      data: form,
      contentType: Headers.formUrlEncodedContentType,
    );
  }

  Future<void> deleteEntry(int malId) async {
    await _request('DELETE', '/anime/$malId/my_list_status');
  }

  // --- internal helpers ---

  List<AniListAnimeListFolder> _foldersFromNodes(
    List<Map<String, dynamic>> nodes,
  ) {
    final Map<AniListListStatus, List<AniListAnimeListEntry>> grouped =
        <AniListListStatus, List<AniListAnimeListEntry>>{};
    for (final Map<String, dynamic> wrapper in nodes) {
      final Object? node = wrapper['node'];
      final Object? listStatus = wrapper['list_status'];
      if (node is! Map<String, dynamic>) continue;
      final Map<String, dynamic> ls = listStatus is Map<String, dynamic>
          ? listStatus
          : const <String, dynamic>{};
      final AniListListStatus status = malStatusToCanonical(
        ls['status'] as String?,
      );
      grouped
          .putIfAbsent(status, () => <AniListAnimeListEntry>[])
          .add(_entryFromNode(node, ls, status));
    }
    return _groupedToFolders(grouped);
  }

  List<AniListAnimeListFolder> _groupedToFolders(
    Map<AniListListStatus, List<AniListAnimeListEntry>> grouped,
  ) {
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

  AniListAnimeListEntry _entryFromNode(
    Map<String, dynamic> node,
    Map<String, dynamic> listStatus,
    AniListListStatus status,
  ) {
    final int malId = _int(node['id']);
    final double rawScore = _double(listStatus['score']);
    return AniListAnimeListEntry(
      id: malId,
      status: status,
      progress: _int(listStatus['num_episodes_watched']),
      score: rawScore > 0 ? rawScore : null,
      mediaItem: _mediaFromNode(node, malId),
    );
  }

  MediaItem _mediaFromNode(Map<String, dynamic> node, int malId) {
    final Object? picture = node['main_picture'];
    final String poster = picture is Map<String, dynamic>
        ? _string(picture['large']).isNotEmpty
            ? _string(picture['large'])
            : _string(picture['medium'])
        : '';
    final Object? altTitles = node['alternative_titles'];
    final String original = altTitles is Map<String, dynamic>
        ? _string(altTitles['ja'])
        : '';
    final Object? season = node['start_season'];
    final int year =
        season is Map<String, dynamic> ? _int(season['year']) : 0;
    return MediaItem(
      id: 'mal:$malId',
      title: _string(node['title']),
      originalTitle: original,
      overview: '',
      type: MediaType.anime,
      year: year,
      posterUrl: poster,
      backdropUrl: '',
      rating: _double(node['mean']),
      genres: const <String>[],
      sourceProvider: 'MyAnimeList',
      externalIds: <String, String>{'mal': '$malId'},
      episodeCount: _nullableInt(node['num_episodes']),
      statusLabel: '',
    );
  }

  Future<Response<dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _request('GET', path, queryParameters: queryParameters);
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    String? contentType,
    bool retried = false,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          contentType: contentType,
          headers: <String, String>{'Authorization': 'Bearer $_accessToken'},
        ),
      );
    } on DioException catch (error) {
      if (!retried &&
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
            contentType: contentType,
            retried: true,
          );
        }
      }
      rethrow;
    }
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
