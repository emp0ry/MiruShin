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
  }) : _accessToken = accessToken,
       _onRefreshToken = onRefreshToken,
       _dio =
           dio ??
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
      'list_status,num_episodes,media_type,main_picture,alternative_titles,'
      'start_season,mean,genres,status,source,nsfw,'
      'average_episode_duration';
  static const String _catalogFields =
      'num_episodes,media_type,main_picture,alternative_titles,start_season,'
      'start_date,mean,synopsis,genres,status,source,nsfw,'
      'average_episode_duration,'
      'pictures';

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
      final String? next = paging is Map<String, dynamic>
          ? paging['next'] as String?
          : null;
      if (next == null || next.trim().isEmpty) break;
      path = next;
    }
    return _foldersFromNodes(nodes);
  }

  /// Search/read endpoints used only when AniList reads are unavailable.
  /// They never mutate MAL and require the already connected MAL session.
  Future<List<MediaItem>> searchAnime(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final String normalized = query.trim();
    if (normalized.isEmpty) return const <MediaItem>[];
    return _fetchCatalogPage(
      '/anime',
      page: page,
      pageSize: pageSize,
      queryParameters: <String, dynamic>{'q': normalized, 'nsfw': true},
    );
  }

  Future<List<MediaItem>> fetchAnimeRanking({
    required String rankingType,
    int page = 1,
    int pageSize = 20,
  }) {
    return _fetchCatalogPage(
      '/anime/ranking',
      page: page,
      pageSize: pageSize,
      queryParameters: <String, dynamic>{
        'ranking_type': rankingType,
        'nsfw': true,
      },
    );
  }

  Future<MediaItem?> fetchAnimeDetails(int malId) async {
    if (malId <= 0) return null;
    final Response<dynamic> response = await _get(
      '/anime/$malId',
      queryParameters: const <String, dynamic>{'fields': _catalogFields},
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) return null;
    return _mediaFromNode(data, malId);
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

  // Internal helpers

  Future<List<MediaItem>> _fetchCatalogPage(
    String path, {
    required int page,
    required int pageSize,
    required Map<String, dynamic> queryParameters,
  }) async {
    final int safePage = page < 1 ? 1 : page;
    final int safeSize = pageSize.clamp(1, 100);
    final Response<dynamic> response = await _get(
      path,
      queryParameters: <String, dynamic>{
        ...queryParameters,
        'limit': safeSize,
        'offset': (safePage - 1) * safeSize,
        'fields': _catalogFields,
      },
    );
    final Object? body = response.data;
    final Object? data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! List<dynamic>) return const <MediaItem>[];
    return <MediaItem>[
      for (final Object? wrapper in data)
        if (wrapper is Map<String, dynamic> &&
            wrapper['node'] is Map<String, dynamic>)
          _mediaFromNode(
            wrapper['node'] as Map<String, dynamic>,
            _int((wrapper['node'] as Map<String, dynamic>)['id']),
          ),
    ].where((MediaItem item) => item.externalIds['mal'] != '0').toList();
  }

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
      final AniListListStatus status = ls['is_rewatching'] == true
          ? AniListListStatus.repeating
          : malStatusToCanonical(ls['status'] as String?);
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
      notes: _string(listStatus['comments']),
      repeat: _int(listStatus['num_times_rewatched']),
      createdAt: _epochSeconds(listStatus['created_at']),
      updatedAt: _epochSeconds(listStatus['updated_at']),
      startedAt: _date(listStatus['start_date']),
      completedAt: _date(listStatus['finish_date']),
      avgScore: _meanScore(node['mean']),
      format: _mediaFormat(node['media_type']),
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
    final List<String> aliases = <String>{
      if (altTitles is Map<String, dynamic>) _string(altTitles['en']),
      if (altTitles is Map<String, dynamic>) _string(altTitles['ja']),
      if (altTitles is Map<String, dynamic> && altTitles['synonyms'] is List)
        ...(altTitles['synonyms'] as List<dynamic>).whereType<String>().map(
          (String value) => value.trim(),
        ),
    }.where((String value) => value.isNotEmpty).toList(growable: false);
    final Object? season = node['start_season'];
    final int year = season is Map<String, dynamic> ? _int(season['year']) : 0;
    final Object? pictures = node['pictures'];
    String backdrop = '';
    if (pictures is List<dynamic> && pictures.isNotEmpty) {
      final Object? first = pictures.first;
      if (first is Map<String, dynamic>) {
        backdrop = _string(first['large']);
        if (backdrop.isEmpty) backdrop = _string(first['medium']);
      }
    }
    final Object? rawGenres = node['genres'];
    final List<String> genres = rawGenres is List<dynamic>
        ? rawGenres
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> genre) => _string(genre['name']))
              .where((String name) => name.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final int durationSeconds = _int(node['average_episode_duration']);
    final String source = _string(node['source']).toUpperCase();
    final String nsfw = _string(node['nsfw']).toLowerCase();
    final String mediaType = _string(node['media_type']).toUpperCase();
    final String startDate = _string(node['start_date']);
    return MediaItem(
      id: 'mal:$malId',
      title: _string(node['title']),
      originalTitle: original,
      overview: _string(node['synopsis']),
      type: MediaType.anime,
      year: year,
      posterUrl: poster,
      backdropUrl: backdrop,
      rating: _double(node['mean']),
      genres: genres,
      sourceProvider: 'MyAnimeList',
      externalIds: <String, String>{
        'mal': '$malId',
        if (source.isNotEmpty) 'mal_source': source,
        if (nsfw.isNotEmpty) 'mal_nsfw': nsfw,
        if (mediaType.isNotEmpty) 'mal_media_type': mediaType,
        if (startDate.isNotEmpty) 'mal_start_date': startDate,
      },
      runtimeMinutes: durationSeconds > 0
          ? (durationSeconds / 60).round()
          : null,
      episodeCount: _nullableInt(node['num_episodes']),
      statusLabel: _string(node['status']).toUpperCase(),
      aliases: aliases,
      originalLanguage: 'ja',
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

  static String _string(Object? value) => value is String ? value.trim() : '';

  static String? _nullableString(Object? value) {
    final String parsed = _string(value);
    return parsed.isEmpty ? null : parsed;
  }

  static int? _epochSeconds(Object? value) {
    final DateTime? parsed = DateTime.tryParse('${value ?? ''}');
    return parsed?.toUtc().millisecondsSinceEpoch == null
        ? null
        : parsed!.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  static DateTime? _date(Object? value) {
    final String raw = _string(value);
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  static int? _meanScore(Object? value) {
    final double parsed = _double(value);
    if (parsed <= 0) return null;
    return (parsed * 10).round().clamp(1, 100);
  }

  static String? _mediaFormat(Object? value) {
    return switch (_string(value).toLowerCase()) {
      'tv' => 'TV',
      'movie' => 'Movie',
      'ova' => 'OVA',
      'ona' => 'ONA',
      'special' => 'Special',
      'music' => 'Music',
      'tv_special' => 'TV Special',
      _ => null,
    };
  }
}
