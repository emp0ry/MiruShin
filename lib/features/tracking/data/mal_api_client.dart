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
    this.cancelToken,
    this.readListStatusCache,
    this.writeListStatusCache,
    this.priorityListStatusIds,
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
  final CancelToken? cancelToken;
  String _accessToken;
  final Future<String?> Function()? _onRefreshToken;
  final Future<Map<String, dynamic>> Function(String kind)? readListStatusCache;
  final Future<void> Function(String kind, Map<String, dynamic> values)?
  writeListStatusCache;
  final Future<Set<int>> Function(String kind)? priorityListStatusIds;
  final Map<String, Map<String, dynamic>> _listStatusCache = {};

  static const String _listFields =
      'num_episodes,media_type,main_picture,alternative_titles,'
      'start_season,start_date,end_date,mean,synopsis,genres,status,source,'
      'nsfw,average_episode_duration,pictures,num_chapters,num_volumes,'
      'rank,popularity,num_list_users,num_scoring_users';
  static const String _catalogFields =
      'num_episodes,media_type,main_picture,alternative_titles,start_season,'
      'start_date,end_date,mean,synopsis,genres,status,source,nsfw,'
      'average_episode_duration,pictures,num_chapters,num_volumes,'
      'rank,popularity,num_list_users,num_scoring_users';

  static String _statusSelection(bool manga, {bool details = false}) =>
      '${details ? 'my_list_status' : 'list_status'}{status,score,'
      '${manga ? 'num_chapters_read,num_volumes_read,is_rereading,num_times_reread,reread_value' : 'num_episodes_watched,is_rewatching,num_times_rewatched,rewatch_value'},'
      'start_date,finish_date,priority,tags,updated_at${details ? ',comments' : ''}}';

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
    return _fetchUserList(
      '/users/@me/animelist?fields=${Uri.encodeQueryComponent('${_statusSelection(false)},$_listFields')}&limit=1000&nsfw=true',
      manga: false,
    );
  }

  Future<List<AniListAnimeListFolder>> fetchMangaList() async {
    return _fetchUserList(
      '/users/@me/mangalist?fields=${Uri.encodeQueryComponent('${_statusSelection(true)},$_listFields')}&limit=1000&nsfw=true',
      manga: true,
    );
  }

  Future<List<AniListAnimeListFolder>> _fetchUserList(
    String initialPath, {
    required bool manga,
  }) async {
    final List<Map<String, dynamic>> nodes = <Map<String, dynamic>>[];
    String path = initialPath;
    int guard = 0;
    while (guard < 20) {
      guard++;
      final Response<dynamic> response = await _get(path);
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('MAL returned a malformed list page.');
      }
      final Object? list = data['data'];
      if (list is! List ||
          list.any(
            (node) =>
                node is! Map<String, dynamic> ||
                node['node'] is! Map ||
                node['list_status'] is! Map,
          )) {
        throw const FormatException('MAL returned an incomplete list page.');
      }
      nodes.addAll(list.cast<Map<String, dynamic>>());
      final Object? paging = data['paging'];
      final String? next = paging is Map<String, dynamic>
          ? paging['next'] as String?
          : null;
      if (next == null || next.trim().isEmpty) break;
      if (guard == 20) {
        throw const FormatException('MAL list pagination is incomplete.');
      }
      path = next;
    }
    await _hydrateOmittedListFields(nodes, manga: manga);
    return _foldersFromNodes(nodes, manga: manga);
  }

  /// MAL excludes comments from list responses. Fetch only changed/missing
  /// notes, with a bounded batch and a durable account/kind-specific cache.
  /// Membership and the other bulk fields remain available immediately.
  Future<void> _hydrateOmittedListFields(
    List<Map<String, dynamic>> nodes, {
    required bool manga,
  }) async {
    final kind = manga ? 'manga' : 'anime';
    final cache = _listStatusCache[kind] ??=
        await readListStatusCache?.call(kind) ?? {};
    int budget = 10;
    final priority = await priorityListStatusIds?.call(kind) ?? const <int>{};
    final ordered = [...nodes]
      ..sort(
        (first, second) =>
            (priority.contains(_int((second['node'] as Map)['id'])) ? 1 : 0)
                .compareTo(
                  priority.contains(_int((first['node'] as Map)['id'])) ? 1 : 0,
                ),
      );
    for (final node in ordered) {
      final id = _int((node['node'] as Map)['id']);
      var status = Map<String, dynamic>.from(node['list_status'] as Map);
      final stamp = status['updated_at'];
      final cached = cache['$id'];
      if (!status.containsKey('comments') &&
          stamp != null &&
          cached is Map &&
          cached['updated_at'] == stamp &&
          cached.containsKey('comments')) {
        status['comments'] = cached['comments'];
      }
      if (!status.containsKey('comments') && budget > 0) {
        budget--;
        final response = await _get(
          '/$kind/$id',
          queryParameters: {'fields': _statusSelection(manga, details: true)},
        );
        final data = response.data;
        final details = data is Map ? data['my_list_status'] : null;
        if (details is! Map ||
            !details.containsKey('comments') ||
            !details.containsKey('updated_at')) {
          throw const FormatException(
            'MAL returned incomplete list-status details.',
          );
        }
        // A detail request may observe a later edit than the preceding list.
        status = Map<String, dynamic>.from(details);
        cache['$id'] = status;
        await writeListStatusCache?.call(kind, cache);
      }
      // These nullable dates were explicitly requested. MAL may omit unset
      // dates from an otherwise complete list-status object.
      if (status.containsKey('updated_at') &&
          status.containsKey('score') &&
          status.containsKey(
            manga ? 'num_chapters_read' : 'num_episodes_watched',
          )) {
        status.putIfAbsent('start_date', () => null);
        status.putIfAbsent('finish_date', () => null);
      }
      node['list_status'] = status;
    }
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

  Future<MediaItem?> fetchMangaDetails(int malId) async {
    if (malId <= 0) return null;
    final Response<dynamic> response = await _get(
      '/manga/$malId',
      queryParameters: const <String, dynamic>{
        'fields':
            'num_chapters,num_volumes,media_type,main_picture,'
            'alternative_titles,start_date,mean,synopsis,genres,status,'
            'nsfw,pictures',
      },
    );
    final Object? data = response.data;
    if (data is! Map<String, dynamic>) return null;
    return _mediaFromNode(data, malId, manga: true);
  }

  Future<Map<String, dynamic>?> updateStatus({
    required int malId,
    String mediaKind = 'anime',
    AniListListStatus? status,
    int? episodesWatched,
    int? volumesRead,
    double? score,
    bool? isRewatching,
    int? numTimesRewatched,
    int? rewatchValue,
    int? priority,
    List<String>? tags,
    String? comments,
    DateTime? startDate,
    DateTime? finishDate,
    bool clearStartDate = false,
    bool clearFinishDate = false,
  }) async {
    final bool? effectiveRewatching = isRewatching ?? status?.malIsRewatching;
    final bool manga = mediaKind == 'manga';
    final Map<String, dynamic> form = <String, dynamic>{
      if (status != null)
        'status': manga ? status.malMangaValue : status.malValue,
      if (manga)
        'is_rereading': ?effectiveRewatching
      else
        'is_rewatching': ?effectiveRewatching,
      if (manga)
        'num_chapters_read': ?episodesWatched
      else
        'num_watched_episodes': ?episodesWatched,
      if (manga) 'num_volumes_read': ?volumesRead,
      if (score != null) 'score': score.round().clamp(0, 10),
      if (manga)
        'num_times_reread': ?numTimesRewatched
      else
        'num_times_rewatched': ?numTimesRewatched,
      if (manga)
        'reread_value': ?rewatchValue
      else
        'rewatch_value': ?rewatchValue,
      if (priority != null) 'priority': priority.clamp(0, 2),
      if (tags != null) 'tags': tags.join(','),
      'comments': ?comments,
      if (startDate != null) 'start_date': _apiDate(startDate),
      if (clearStartDate) 'start_date': '',
      if (finishDate != null) 'finish_date': _apiDate(finishDate),
      if (clearFinishDate) 'finish_date': '',
    };
    if (form.isEmpty) return null;
    final response = await _request(
      'PATCH',
      '/${manga ? 'manga' : 'anime'}/$malId/my_list_status',
      data: form,
      contentType: Headers.formUrlEncodedContentType,
    );
    return response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : null;
  }

  Future<void> deleteEntry(int malId, {String mediaKind = 'anime'}) async {
    await _request(
      'DELETE',
      '/${mediaKind == 'manga' ? 'manga' : 'anime'}/$malId/my_list_status',
    );
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
    List<Map<String, dynamic>> nodes, {
    required bool manga,
  }) {
    final Map<AniListListStatus, List<AniListAnimeListEntry>> grouped =
        <AniListListStatus, List<AniListAnimeListEntry>>{};
    for (final Map<String, dynamic> wrapper in nodes) {
      final Object? node = wrapper['node'];
      final Object? listStatus = wrapper['list_status'];
      if (node is! Map<String, dynamic>) continue;
      final Map<String, dynamic> ls = listStatus is Map<String, dynamic>
          ? listStatus
          : const <String, dynamic>{};
      final AniListListStatus status =
          (manga ? ls['is_rereading'] : ls['is_rewatching']) == true
          ? AniListListStatus.repeating
          : malStatusToCanonical(ls['status'] as String?);
      grouped
          .putIfAbsent(status, () => <AniListAnimeListEntry>[])
          .add(_entryFromNode(node, ls, status, manga: manga));
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
    AniListListStatus status, {
    required bool manga,
  }) {
    final int malId = _int(node['id']);
    final double rawScore = _double(listStatus['score']);
    return AniListAnimeListEntry(
      id: malId,
      status: status,
      progress: _int(
        manga
            ? listStatus['num_chapters_read']
            : listStatus['num_episodes_watched'],
      ),
      progressVolumes: manga ? _int(listStatus['num_volumes_read']) : 0,
      score: rawScore > 0 ? rawScore : null,
      mediaItem: _mediaFromNode(node, malId, manga: manga),
      notes: _string(listStatus['comments']),
      repeat: _int(
        manga
            ? listStatus['num_times_reread']
            : listStatus['num_times_rewatched'],
      ),
      priority: _int(listStatus['priority']),
      providerData: <String, dynamic>{
        'presentFields': [
          for (final entry in {
            'status': 'status',
            'score': 'score',
            'notes': 'comments',
            'progress': manga ? 'num_chapters_read' : 'num_episodes_watched',
            'progressVolumes': 'num_volumes_read',
            'repeat': manga ? 'num_times_reread' : 'num_times_rewatched',
            'malPriority': 'priority',
            'malTags': 'tags',
            'malRewatchValue': manga ? 'reread_value' : 'rewatch_value',
            'startedAt': 'start_date',
            'completedAt': 'finish_date',
          }.entries)
            if (listStatus.containsKey(entry.value)) entry.key,
        ],
        'status': _string(listStatus['status']),
        manga ? 'isRereading' : 'isRewatching':
            (manga
                ? listStatus['is_rereading']
                : listStatus['is_rewatching']) ==
            true,
        manga ? 'numTimesReread' : 'numTimesRewatched': _int(
          manga
              ? listStatus['num_times_reread']
              : listStatus['num_times_rewatched'],
        ),
        manga ? 'rereadValue' : 'rewatchValue': _int(
          manga ? listStatus['reread_value'] : listStatus['rewatch_value'],
        ),
        'priority': _int(listStatus['priority']),
        'tags': listStatus['tags'] is List
            ? List<String>.from(
                (listStatus['tags'] as List<dynamic>).whereType<String>(),
              )
            : const <String>[],
        'comments': _string(listStatus['comments']),
        'score': rawScore,
        if (manga) ...<String, dynamic>{
          'numChaptersRead': _int(listStatus['num_chapters_read']),
          'numVolumesRead': _int(listStatus['num_volumes_read']),
        } else
          'numEpisodesWatched': _int(listStatus['num_episodes_watched']),
        if (listStatus['start_date'] != null)
          'startDate': _string(listStatus['start_date']),
        if (listStatus['finish_date'] != null)
          'finishDate': _string(listStatus['finish_date']),
        if (listStatus['created_at'] != null)
          'createdAt': _string(listStatus['created_at']),
        if (listStatus['updated_at'] != null)
          'updatedAt': _string(listStatus['updated_at']),
      },
      createdAt: _epochSeconds(listStatus['created_at']),
      updatedAt: _epochSeconds(listStatus['updated_at']),
      startedAt: _date(listStatus['start_date']),
      completedAt: _date(listStatus['finish_date']),
      avgScore: _meanScore(node['mean']),
      format: _mediaFormat(node['media_type']),
    );
  }

  MediaItem _mediaFromNode(
    Map<String, dynamic> node,
    int malId, {
    bool manga = false,
  }) {
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
    final String endDate = _string(node['end_date']);
    final int rank = _int(node['rank']);
    final int popularity = _int(node['popularity']);
    final int listUsers = _int(node['num_list_users']);
    final int scoringUsers = _int(node['num_scoring_users']);
    return MediaItem(
      id: manga ? 'mal:manga:$malId' : 'mal:$malId',
      title: _string(node['title']),
      originalTitle: original,
      overview: _string(node['synopsis']),
      type: manga ? MediaType.manga : MediaType.anime,
      year: year,
      posterUrl: poster,
      backdropUrl: backdrop,
      rating: _double(node['mean']),
      genres: genres,
      sourceProvider: 'MyAnimeList',
      externalIds: <String, String>{
        'mal': '$malId',
        if (manga) 'anilist_type': 'MANGA',
        if (source.isNotEmpty) 'mal_source': source,
        if (nsfw.isNotEmpty) 'mal_nsfw': nsfw,
        if (mediaType.isNotEmpty) 'mal_media_type': mediaType,
        if (startDate.isNotEmpty) 'mal_start_date': startDate,
        if (endDate.isNotEmpty) 'mal_end_date': endDate,
        if (rank > 0) 'mal_rank': '$rank',
        if (popularity > 0) 'mal_popularity': '$popularity',
        if (listUsers > 0) 'mal_num_list_users': '$listUsers',
        if (scoringUsers > 0) 'mal_num_scoring_users': '$scoringUsers',
        'mirushin_mal_metadata': 'rich_v2',
      },
      runtimeMinutes: durationSeconds > 0
          ? (durationSeconds / 60).round()
          : null,
      episodeCount: _nullableInt(node[manga ? 'num_chapters' : 'num_episodes']),
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
        cancelToken: cancelToken,
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

String _apiDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
