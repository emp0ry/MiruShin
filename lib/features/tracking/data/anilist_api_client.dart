import 'package:dio/dio.dart';

import '../../profile/domain/anilist_profile_models.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/calendar_item.dart';
import '../../../shared/models/media_item.dart';
import '../../metadata/data/shikimori_client.dart';

int aniListDisplayScoreToRaw(double score) =>
    (score * 10).round().clamp(0, 100).toInt();

class AniListMediaTagInfo {
  const AniListMediaTagInfo({
    required this.name,
    required this.category,
    required this.isAdult,
  });

  final String name;
  final String category;
  final bool isAdult;
}

class AniListApiClient {
  AniListApiClient({
    String? accessToken,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration receiveTimeout = const Duration(seconds: 18),
    this.titleLanguage = 'ENGLISH',
    this.showAdultContent = false,
    this.shikimori,
  }) : _accessToken = accessToken,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: 'https://graphql.anilist.co',
               connectTimeout: connectTimeout,
               receiveTimeout: receiveTimeout,
             ),
           );

  final Dio _dio;
  final String? _accessToken;
  final String titleLanguage;
  final bool showAdultContent;
  final ShikiMoriClient? shikimori;

  bool get _wantsRussian => titleLanguage == 'RUSSIAN' && shikimori != null;

  String get _isAdultClause => showAdultContent ? '' : ', isAdult: false';

  Future<List<MediaItem>> searchAnime(String query, {int page = 1}) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getPopularAnime(page: page);
    }
    if (shikimori != null && _hasCyrillic(trimmed)) {
      return _searchByCyrillic(trimmed, page);
    }
    return _animePage(
      r'''
      query SearchAnime($search: String, $page: Int) {
        Page(page: $page, perPage: 20) {
          media(type: ANIME, search: $search, sort: POPULARITY_DESC) {
            ''' +
          _mediaFields +
          r'''
          }
        }
      }
      ''',
      <String, dynamic>{'search': trimmed, 'page': page},
    );
  }

  Future<List<MediaItem>> getPopularAnime({int page = 1}) {
    return _animePage(
      r'''
      query PopularAnime($page: Int) {
        Page(page: $page, perPage: 20) {
          media(type: ANIME, sort: POPULARITY_DESC) {
            ''' +
          _mediaFields +
          r'''
          }
        }
      }
      ''',
      <String, dynamic>{'page': page},
    );
  }

  Future<List<MediaItem>> getTrendingAnime({int page = 1}) {
    return _animePage(
      r'''
      query TrendingAnime($page: Int) {
        Page(page: $page, perPage: 20) {
          media(type: ANIME, sort: TRENDING_DESC) {
            ''' +
          _mediaFields +
          r'''
          }
        }
      }
      ''',
      <String, dynamic>{'page': page},
    );
  }

  Future<List<MediaItem>> searchCatalog({
    required String kind,
    required String query,
    int page = 1,
  }) {
    final String normalizedKind = _normalizedKind(kind);
    final String trimmed = query.trim();
    final String mediaType = normalizedKind == 'manga' ? 'MANGA' : 'ANIME';
    return switch (normalizedKind) {
      'character' || 'characters' => _namedNodePage(
        kind: 'character',
        rootField: 'characters',
        search: trimmed,
        page: page,
      ),
      'staff' => _namedNodePage(
        kind: 'staff',
        rootField: 'staff',
        search: trimmed,
        page: page,
      ),
      'studio' || 'studios' => _studioPage(search: trimmed, page: page),
      'user' || 'users' => _userPage(search: trimmed, page: page),
      'review' || 'reviews' => _reviewPage(search: trimmed, page: page),
      'recommendation' || 'recommendations' => _recommendationsPage(page: page),
      _ =>
        trimmed.isEmpty
            ? getPopularCatalog(kind: kind, page: page)
            : (mediaType == 'ANIME' &&
                      shikimori != null &&
                      _hasCyrillic(trimmed)
                  ? _searchByCyrillic(trimmed, page)
                  : _mediaSearchPage(mediaType, trimmed, page)),
    };
  }

  Future<List<MediaItem>> getPopularCatalog({
    required String kind,
    int page = 1,
  }) {
    final String normalizedKind = _normalizedKind(kind);
    return switch (normalizedKind) {
      'character' || 'characters' => _namedNodePage(
        kind: 'character',
        rootField: 'characters',
        search: '',
        page: page,
      ),
      'staff' => _namedNodePage(
        kind: 'staff',
        rootField: 'staff',
        search: '',
        page: page,
      ),
      'studio' || 'studios' => _studioPage(search: '', page: page),
      'user' || 'users' => _userPage(search: '', page: page),
      'review' || 'reviews' => _reviewPage(search: '', page: page),
      'recommendation' || 'recommendations' => _recommendationsPage(page: page),
      _ => _mediaSortedPage(
        normalizedKind == 'manga' ? 'MANGA' : 'ANIME',
        'POPULARITY_DESC',
        page,
      ),
    };
  }

  Future<List<MediaItem>> getTrendingCatalog({
    required String kind,
    int page = 1,
  }) {
    final String normalizedKind = _normalizedKind(kind);
    return switch (normalizedKind) {
      'recommendation' || 'recommendations' => _recommendationsPage(page: page),
      _ => _mediaSortedPage(
        normalizedKind == 'manga' ? 'MANGA' : 'ANIME',
        'TRENDING_DESC',
        page,
      ),
    };
  }

  Future<List<MediaItem>> getFilteredCatalog({
    required String kind,
    required String filter,
    int page = 1,
  }) {
    final String normalizedKind = _normalizedKind(kind);
    final String type = normalizedKind == 'manga' ? 'MANGA' : 'ANIME';
    final ({String sort, String? status}) query = _mediaFilter(filter);
    return switch (normalizedKind) {
      'anime' || 'manga' => _mediaFilteredPage(
        type: type,
        sort: query.sort,
        status: query.status,
        page: page,
      ),
      'recommendation' || 'recommendations' => _recommendationsPage(page: page),
      'review' || 'reviews' => _reviewPage(search: '', page: page),
      'character' || 'characters' => _namedNodePage(
        kind: 'character',
        rootField: 'characters',
        search: '',
        page: page,
      ),
      'staff' => _namedNodePage(
        kind: 'staff',
        rootField: 'staff',
        search: '',
        page: page,
      ),
      'studio' || 'studios' => _studioPage(search: '', page: page),
      'user' || 'users' => _userPage(search: '', page: page),
      _ => _mediaFilteredPage(
        type: type,
        sort: query.sort,
        status: query.status,
        page: page,
      ),
    };
  }

  Future<List<MediaItem>> getAdvancedFilteredCatalog({
    required String type,
    List<String>? formatIn,
    List<String>? formatNotIn,
    List<String>? statusIn,
    List<String>? statusNotIn,
    List<String>? sourceIn,
    String? season,
    int? startDateGreater,
    int? startDateLesser,
    String? countryOfOrigin,
    List<String>? genreIn,
    List<String>? genreNotIn,
    List<String>? tagIn,
    List<String>? tagNotIn,
    bool? isAdult,
    bool? isLicensed,
    bool? onList,
    String sort = 'POPULARITY_DESC',
    int page = 1,
  }) {
    final Map<String, dynamic> variables = <String, dynamic>{
      'type': type,
      'sort': sort,
      'page': page,
      'format_in': ?(formatIn?.isEmpty == false ? formatIn : null),
      'format_not_in': ?(formatNotIn?.isEmpty == false ? formatNotIn : null),
      'status_in': ?(statusIn?.isEmpty == false ? statusIn : null),
      'status_not_in': ?(statusNotIn?.isEmpty == false ? statusNotIn : null),
      'source_in': ?(sourceIn?.isEmpty == false ? sourceIn : null),
      'season': ?season,
      'startDate_greater': ?startDateGreater,
      'startDate_lesser': ?startDateLesser,
      'countryOfOrigin': ?countryOfOrigin,
      'genre_in': ?(genreIn?.isEmpty == false ? genreIn : null),
      'genre_not_in': ?(genreNotIn?.isEmpty == false ? genreNotIn : null),
      'tag_in': ?(tagIn?.isEmpty == false ? tagIn : null),
      'tag_not_in': ?(tagNotIn?.isEmpty == false ? tagNotIn : null),
      'isAdult': ?isAdult,
      'isLicensed': ?isLicensed,
      'onList': ?onList,
    };
    final String adultClause = isAdult == null ? _isAdultClause : '';
    return _catalogMediaPage(
      type: type,
      query:
          '''
      query AdvancedFilter(
        \$type: MediaType,
        \$sort: [MediaSort],
        \$page: Int,
        \$format_in: [MediaFormat],
        \$format_not_in: [MediaFormat],
        \$status_in: [MediaStatus],
        \$status_not_in: [MediaStatus],
        \$source_in: [MediaSource],
        \$season: MediaSeason,
        \$startDate_greater: FuzzyDateInt,
        \$startDate_lesser: FuzzyDateInt,
        \$countryOfOrigin: CountryCode,
        \$genre_in: [String],
        \$genre_not_in: [String],
        \$tag_in: [String],
        \$tag_not_in: [String],
        \$isAdult: Boolean,
        \$isLicensed: Boolean,
        \$onList: Boolean
      ) {
        Page(page: \$page, perPage: 20) {
          media(
            type: \$type,
            sort: \$sort,
            format_in: \$format_in,
            format_not_in: \$format_not_in,
            status_in: \$status_in,
            status_not_in: \$status_not_in,
            source_in: \$source_in,
            season: \$season,
            startDate_greater: \$startDate_greater,
            startDate_lesser: \$startDate_lesser,
            countryOfOrigin: \$countryOfOrigin,
            genre_in: \$genre_in,
            genre_not_in: \$genre_not_in,
            tag_in: \$tag_in,
            tag_not_in: \$tag_not_in,
            isAdult: \$isAdult,
            isLicensed: \$isLicensed,
            onList: \$onList
            $adultClause
          ) {
            $_mediaFields
          }
        }
      }
      ''',
      variables: variables,
    );
  }

  Future<List<String>> fetchGenres() async {
    final Map<String, dynamic> data = await _post(r'''
      query Genres {
        GenreCollection
      }
      ''', const <String, dynamic>{});
    final Object? genres = data['GenreCollection'];
    if (genres is! List<dynamic>) return const <String>[];
    return genres.whereType<String>().toList(growable: false);
  }

  Future<List<AniListMediaTagInfo>> fetchMediaTags() async {
    final Map<String, dynamic> data = await _post(r'''
      query MediaTags {
        MediaTagCollection {
          name
          category
          isAdult
        }
      }
      ''', const <String, dynamic>{});
    final Object? tags = data['MediaTagCollection'];
    if (tags is! List<dynamic>) return const <AniListMediaTagInfo>[];
    return tags
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) {
          return AniListMediaTagInfo(
            name: _string(json['name']),
            category: _string(json['category'], fallback: 'Other'),
            isAdult: json['isAdult'] == true,
          );
        })
        .where((AniListMediaTagInfo tag) => tag.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<MediaItem?> getAnimeDetails(int id) async {
    return getMediaDetails(id, type: 'ANIME');
  }

  Future<MediaItem?> getMediaDetails(int id, {String type = 'ANIME'}) async {
    final Map<String, dynamic> data = await _post(
      '''
      query MediaDetails(\$id: Int, \$type: MediaType) {
        Media(id: \$id, type: \$type) {
          $_mediaDetailsFields
        }
      }
      ''',
      <String, dynamic>{'id': id, 'type': type},
    );
    final Object? media = data['Media'];
    if (media is! Map<String, dynamic>) return null;
    MediaItem item = _mediaFromJson(media);
    final String upperType = type.toUpperCase();
    if (_wantsRussian && (upperType == 'ANIME' || upperType == 'MANGA')) {
      final ({String title, String description})? details =
          await _russianDetailsForItem(item);
      if (details != null) {
        item = item.copyWith(
          title: details.title.isNotEmpty ? details.title : null,
          overview: details.description.isNotEmpty ? details.description : null,
        );
      }
      if (item.seasons.isNotEmpty) {
        final List<int> malIds = item.seasons
            .map((MediaSeason s) => int.tryParse(s.externalIds['mal'] ?? ''))
            .whereType<int>()
            .toList();
        if (malIds.isNotEmpty) {
          final Map<int, String> ruTitles = await shikimori!.batchRussianTitles(
            malIds,
          );
          if (ruTitles.isNotEmpty) {
            item = item.copyWith(
              seasons: item.seasons
                  .map((MediaSeason s) {
                    final int? id = int.tryParse(s.externalIds['mal'] ?? '');
                    final String? ruName = id != null ? ruTitles[id] : null;
                    if (ruName == null || ruName.isEmpty) return s;
                    return MediaSeason(
                      seasonNumber: s.seasonNumber,
                      name: ruName,
                      episodeCount: s.episodeCount,
                      posterUrl: s.posterUrl,
                      overview: s.overview,
                      originalName: s.originalName,
                      aliases: s.aliases,
                      isSpecials: s.isSpecials,
                      externalIds: s.externalIds,
                    );
                  })
                  .toList(growable: false),
            );
          }
        }
      }
    }
    return item;
  }

  Future<bool?> fetchMediaFavouriteStatus(int mediaId) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query MediaFavouriteStatus($id: Int) {
        Media(id: $id) {
          isFavourite
        }
      }
      ''',
      <String, dynamic>{'id': mediaId},
      authenticated: true,
    );
    final Object? media = data['Media'];
    if (media is! Map<String, dynamic>) return null;
    final Object? value = media['isFavourite'];
    return value is bool ? value : null;
  }

  // ─── Russian / Shikimori helpers ─────────────────────────────────────────────

  static bool _hasCyrillic(String text) => RegExp(r'[а-яёА-ЯЁ]').hasMatch(text);

  Future<List<MediaItem>> _enrichWithRussian(List<MediaItem> items) async {
    if (items.isEmpty) return items;
    // The batch endpoint is anime-only; manga entries skip it and resolve
    // through the per-item (manga-aware) fallback below.
    final List<int> malIds = items
        .where((MediaItem i) => !_itemIsManga(i))
        .map((MediaItem i) => int.tryParse(i.externalIds['mal'] ?? ''))
        .whereType<int>()
        .toList();
    final Map<int, String> russianTitles = malIds.isEmpty
        ? const <int, String>{}
        : await shikimori!.batchRussianTitles(malIds);
    final Map<int, String?> resolvedTitlesByIndex = <int, String?>{};
    final List<int> fallbackIndexes = <int>[];
    for (int index = 0; index < items.length; index += 1) {
      final MediaItem item = items[index];
      final int? malId = int.tryParse(item.externalIds['mal'] ?? '');
      final String? ruTitle = malId != null ? russianTitles[malId] : null;
      if (ruTitle == null || ruTitle.isEmpty) {
        fallbackIndexes.add(index);
      } else {
        resolvedTitlesByIndex[index] = ruTitle;
      }
    }

    // Resolve misses in small batches so a few unknown MAL IDs do not stall
    // the whole library behind a fully sequential set of Shikimori requests.
    const int fallbackBatchSize = 8;
    for (int i = 0; i < fallbackIndexes.length; i += fallbackBatchSize) {
      final int end = (i + fallbackBatchSize).clamp(0, fallbackIndexes.length);
      final List<int> batch = fallbackIndexes.sublist(i, end);
      await Future.wait(
        batch.map((int index) async {
          resolvedTitlesByIndex[index] = await _russianTitleForItem(
            items[index],
          );
        }),
      );
    }

    final List<MediaItem> enriched = <MediaItem>[];
    for (int index = 0; index < items.length; index += 1) {
      final MediaItem item = items[index];
      final String? ruTitle = resolvedTitlesByIndex[index];
      enriched.add(
        ruTitle != null && ruTitle.isNotEmpty
            ? item.copyWith(title: ruTitle)
            : item,
      );
    }
    return enriched;
  }

  static bool _itemIsManga(MediaItem item) {
    return item.externalIds['anilist_type'] == 'MANGA' ||
        item.id.toLowerCase().startsWith('anilist:manga:');
  }

  Future<({String title, String description})?> _russianDetailsForItem(
    MediaItem item,
  ) {
    return shikimori!.getRussianDetailsForMedia(
      malId: _malIdForItem(item),
      queries: _russianQueriesForItem(item),
      isManga: _itemIsManga(item),
    );
  }

  Future<String?> _russianTitleForItem(MediaItem item) async {
    final ({String title, String description})? details =
        await _russianDetailsForItem(item);
    final String title = details?.title.trim() ?? '';
    return title.isEmpty ? null : title;
  }

  int? _malIdForItem(MediaItem item) {
    final int? malId = int.tryParse(item.externalIds['mal'] ?? '');
    return malId != null && malId > 0 ? malId : null;
  }

  Iterable<String> _russianQueriesForItem(MediaItem item) sync* {
    final Set<String> seen = <String>{};
    for (final String query in <String>[
      item.originalTitle,
      item.title,
      ...item.aliases,
    ]) {
      final String trimmed = query.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) yield trimmed;
    }
  }

  Future<List<MediaItem>> _searchByCyrillic(String query, int page) async {
    final List<ShikimoriSearchHit> hits = await shikimori!.searchByQuery(
      query,
      limit: 20,
    );
    if (hits.isEmpty) {
      // No Shikimori results — fall back to AniList text search unchanged.
      return _animePage(
        '''
        query SearchAnime(\$search: String, \$page: Int) {
          Page(page: \$page, perPage: 20) {
            media(type: ANIME, search: \$search, sort: POPULARITY_DESC) {
              $_mediaFields
            }
          }
        }
        ''',
        <String, dynamic>{'search': query, 'page': page},
      );
    }
    final List<int> malIds = hits
        .map((ShikimoriSearchHit h) => h.malId)
        .toList();
    final List<MediaItem> items = await _fetchByMalIds(malIds, page: page);
    if (!_wantsRussian) return items;
    final Map<int, String> russianMap = <int, String>{
      for (final ShikimoriSearchHit h in hits)
        if (h.russian.isNotEmpty) h.malId: h.russian,
    };
    return items.map((MediaItem item) {
      final int? malId = int.tryParse(item.externalIds['mal'] ?? '');
      final String? ruTitle = malId != null ? russianMap[malId] : null;
      return ruTitle != null ? item.copyWith(title: ruTitle) : item;
    }).toList();
  }

  Future<List<MediaItem>> _fetchByMalIds(
    List<int> malIds, {
    int page = 1,
  }) async {
    if (malIds.isEmpty) return const <MediaItem>[];
    return _mediaPage(
      '''
      query MediaByMalIds(\$ids: [Int], \$page: Int) {
        Page(page: \$page, perPage: 20) {
          media(type: ANIME, idMal_in: \$ids, sort: POPULARITY_DESC$_isAdultClause) {
            $_mediaFields
          }
        }
      }
      ''',
      <String, dynamic>{'ids': malIds, 'page': page},
    );
  }

  Future<MediaItem?> getCatalogDetails(String id) async {
    final List<String> parts = id.split(':');
    if (parts.length == 2 && parts.first == 'anilist') {
      final int? mediaId = int.tryParse(parts[1]);
      return mediaId == null ? null : getMediaDetails(mediaId);
    }
    if (parts.length < 3 || parts.first != 'anilist') {
      return null;
    }
    final int? entityId = int.tryParse(parts.last);
    if (entityId == null) return null;
    return switch (parts[1]) {
      'anime' => getMediaDetails(entityId),
      'manga' => getMediaDetails(entityId, type: 'MANGA'),
      'character' => _characterDetails(entityId),
      'staff' => _staffDetails(entityId),
      'studio' => _studioDetails(entityId),
      'user' => _userDetails(entityId),
      'review' => _reviewDetails(entityId),
      _ => null,
    };
  }

  Future<AniListViewer> fetchViewer() async {
    final Map<String, dynamic> data = await _post(
      '''
      query Viewer {
        Viewer {
          id
          name
          avatar { large }
          bannerImage
          siteUrl
        }
      }
      ''',
      const <String, dynamic>{},
      authenticated: true,
    );

    final Object? viewer = data['Viewer'];
    if (viewer is! Map<String, dynamic>) {
      throw StateError('AniList Viewer response was empty.');
    }
    return AniListViewer(
      id: _int(viewer['id']),
      name: _string(viewer['name'], fallback: 'AniList User'),
      avatarUrl: _nestedString(viewer, const <String>['avatar', 'large']),
      bannerUrl: _string(viewer['bannerImage']),
      siteUrl: _string(viewer['siteUrl']),
    );
  }

  Future<AniListUserSettings> fetchUserSettings() async {
    final Map<String, dynamic> data = await _post(
      '''
      query ViewerSettings {
        Viewer {
          options {
            titleLanguage
            staffNameLanguage
            activityMergeTime
            displayAdultContent
            airingNotifications
            notificationOptions { type enabled }
            restrictMessagesToFollowing
            disabledListActivity { type disabled }
          }
          mediaListOptions {
            scoreFormat
            rowOrder
            animeList {
              splitCompletedSectionByFormat
              customLists
              advancedScoring
              advancedScoringEnabled
            }
            mangaList {
              splitCompletedSectionByFormat
              customLists
            }
          }
        }
      }
      ''',
      const <String, dynamic>{},
      authenticated: true,
    );
    final Object? viewer = data['Viewer'];
    if (viewer is! Map<String, dynamic>) {
      throw StateError('AniList Viewer settings response was empty.');
    }
    return AniListUserSettings.fromViewerJson(viewer);
  }

  Future<AniListUserSettings> updateUserSettings(
    AniListUserSettings settings,
  ) async {
    final Map<String, dynamic> data = await _post(
      '''
      mutation UpdateSettings(
        \$titleLanguage: UserTitleLanguage,
        \$staffNameLanguage: UserStaffNameLanguage,
        \$activityMergeTime: Int,
        \$displayAdultContent: Boolean,
        \$airingNotifications: Boolean,
        \$scoreFormat: ScoreFormat,
        \$rowOrder: String,
        \$notificationOptions: [NotificationOptionInput],
        \$splitCompletedAnime: Boolean,
        \$splitCompletedManga: Boolean,
        \$restrictMessagesToFollowing: Boolean,
        \$advancedScoringEnabled: Boolean,
        \$advancedScoring: [String],
        \$disabledListActivity: [ListActivityOptionInput]
      ) {
        UpdateUser(
          titleLanguage: \$titleLanguage,
          staffNameLanguage: \$staffNameLanguage,
          activityMergeTime: \$activityMergeTime,
          displayAdultContent: \$displayAdultContent,
          airingNotifications: \$airingNotifications,
          restrictMessagesToFollowing: \$restrictMessagesToFollowing,
          scoreFormat: \$scoreFormat,
          rowOrder: \$rowOrder,
          notificationOptions: \$notificationOptions,
          disabledListActivity: \$disabledListActivity,
          animeListOptions: {
            splitCompletedSectionByFormat: \$splitCompletedAnime,
            advancedScoringEnabled: \$advancedScoringEnabled,
            advancedScoring: \$advancedScoring
          },
          mangaListOptions: {
            splitCompletedSectionByFormat: \$splitCompletedManga
          }
        ) {
          options {
            titleLanguage
            staffNameLanguage
            activityMergeTime
            displayAdultContent
            airingNotifications
            notificationOptions { type enabled }
            restrictMessagesToFollowing
            disabledListActivity { type disabled }
          }
          mediaListOptions {
            scoreFormat
            rowOrder
            animeList {
              splitCompletedSectionByFormat
              customLists
              advancedScoring
              advancedScoringEnabled
            }
            mangaList {
              splitCompletedSectionByFormat
              customLists
            }
          }
        }
      }
      ''',
      settings.toGraphQlVariables(),
      authenticated: true,
    );
    final Object? user = data['UpdateUser'];
    if (user is! Map<String, dynamic>) {
      throw StateError('AniList settings update response was empty.');
    }
    return AniListUserSettings.fromViewerJson(user);
  }

  Future<AniListUserProfile> fetchUserProfile({int? userId}) async {
    final int resolvedUserId = userId ?? (await fetchViewer()).id;
    final Map<String, dynamic> data = await _post(
      '''
      query UserProfile(\$id: Int) {
        User(id: \$id) {
          id
          name
          about
          avatar { large }
          bannerImage
          isFollowing
          isFollower
          isBlocked
          siteUrl
          statistics {
            anime {
              count
              meanScore
              standardDeviation
              minutesWatched
              episodesWatched
              chaptersRead
              volumesRead
              scores(sort: MEAN_SCORE) { count meanScore minutesWatched chaptersRead score }
              lengths { count meanScore minutesWatched chaptersRead length }
              formats { count meanScore minutesWatched chaptersRead format }
              statuses { count meanScore minutesWatched chaptersRead status }
              countries { count meanScore minutesWatched chaptersRead country }
            }
            manga {
              count
              meanScore
              standardDeviation
              minutesWatched
              episodesWatched
              chaptersRead
              volumesRead
              scores(sort: MEAN_SCORE) { count meanScore minutesWatched chaptersRead score }
              lengths { count meanScore minutesWatched chaptersRead length }
              formats { count meanScore minutesWatched chaptersRead format }
              statuses { count meanScore minutesWatched chaptersRead status }
              countries { count meanScore minutesWatched chaptersRead country }
            }
          }
        }
      }
      ''',
      <String, dynamic>{'id': resolvedUserId},
      authenticated: true,
    );
    final Object? user = data['User'];
    if (user is! Map<String, dynamic>) {
      throw StateError('AniList profile response was empty.');
    }
    return _userProfileFromJson(user);
  }

  Future<AniListPagedChunk<AniListActivity>> fetchActivities({
    int? userId,
    int? userIdNot,
    bool? isFollowing,
    bool? hasRepliesOrText,
    List<String>? typeIn,
    int page = 1,
  }) async {
    final Map<String, dynamic> data = await _post(
      '''
      query Activities(
        \$userId: Int,
        \$userIdNot: Int,
        \$page: Int,
        \$isFollowing: Boolean,
        \$hasRepliesOrText: Boolean,
        \$typeIn: [ActivityType]
      ) {
        Page(page: \$page) {
          pageInfo { hasNextPage total }
          activities(
            userId: \$userId,
            userId_not: \$userIdNot,
            isFollowing: \$isFollowing,
            hasRepliesOrTypeText: \$hasRepliesOrText,
            type_in: \$typeIn,
            sort: [PINNED, ID_DESC]
          ) {
            ... on TextActivity {
              id
              type
              replyCount
              likeCount
              isLiked
              isSubscribed
              isPinned
              createdAt
              siteUrl
              text
              user { id name avatar { large } }
            }
            ... on ListActivity {
              id
              type
              replyCount
              likeCount
              isLiked
              isSubscribed
              isPinned
              createdAt
              siteUrl
              status
              progress
              user { id name avatar { large } }
              media {
                $_mediaFields
              }
            }
            ... on MessageActivity {
              id
              type
              replyCount
              likeCount
              isLiked
              isSubscribed
              isPrivate
              createdAt
              siteUrl
              message
              messenger { id name avatar { large } }
              recipient { id name avatar { large } }
            }
          }
        }
      }
      ''',
      <String, dynamic>{
        'userId': userId,
        'userIdNot': userIdNot,
        'page': page,
        'isFollowing': isFollowing,
        'hasRepliesOrText': hasRepliesOrText,
        'typeIn': typeIn,
      },
      authenticated: true,
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) {
      return const AniListPagedChunk<AniListActivity>(
        items: <AniListActivity>[],
        hasNextPage: false,
      );
    }
    final Object? items = pageData['activities'];
    final List<AniListActivity> mapped = items is List<dynamic>
        ? items
              .whereType<Map<String, dynamic>>()
              .map(_activityFromJson)
              .toList(growable: false)
        : const <AniListActivity>[];
    return AniListPagedChunk<AniListActivity>(
      items: mapped,
      hasNextPage: _pageHasNext(pageData['pageInfo']),
      total: _pageTotal(pageData['pageInfo']),
    );
  }

  Future<AniListPagedChunk<MediaItem>> fetchFavouritePage({
    required int userId,
    required AniListFavouriteKind kind,
    int page = 1,
  }) async {
    final Map<String, dynamic> flags = <String, dynamic>{
      'withAnime': kind == AniListFavouriteKind.anime,
      'withManga': kind == AniListFavouriteKind.manga,
      'withCharacters': kind == AniListFavouriteKind.characters,
      'withStaff': kind == AniListFavouriteKind.staff,
      'withStudios': kind == AniListFavouriteKind.studios,
    };
    final Map<String, dynamic> data = await _post(
      '''
      query Favorites(
        \$userId: Int,
        \$page: Int,
        \$withAnime: Boolean = false,
        \$withManga: Boolean = false,
        \$withCharacters: Boolean = false,
        \$withStaff: Boolean = false,
        \$withStudios: Boolean = false
      ) {
        User(id: \$userId) {
          favourites {
            anime(page: \$page) @include(if: \$withAnime) {
              pageInfo { hasNextPage total }
              nodes {
                id
                idMal
                type
                title { romaji english native userPreferred }
                coverImage { extraLarge large }
                isFavourite
                siteUrl
              }
            }
            manga(page: \$page) @include(if: \$withManga) {
              pageInfo { hasNextPage total }
              nodes {
                id
                idMal
                type
                title { romaji english native userPreferred }
                coverImage { extraLarge large }
                isFavourite
                siteUrl
              }
            }
            characters(page: \$page) @include(if: \$withCharacters) {
              pageInfo { hasNextPage total }
              nodes {
                id
                name { userPreferred full native }
                image { large }
                siteUrl
              }
            }
            staff(page: \$page) @include(if: \$withStaff) {
              pageInfo { hasNextPage total }
              nodes {
                id
                name { userPreferred full native }
                image { large }
                siteUrl
              }
            }
            studios(page: \$page) @include(if: \$withStudios) {
              pageInfo { hasNextPage total }
              nodes {
                id
                name
                siteUrl
              }
            }
          }
        }
      }
      ''',
      <String, dynamic>{'userId': userId, 'page': page, ...flags},
      authenticated: true,
    );
    final Object? user = data['User'];
    if (user is! Map<String, dynamic>) {
      return const AniListPagedChunk<MediaItem>(
        items: <MediaItem>[],
        hasNextPage: false,
      );
    }
    final Object? favourites = user['favourites'];
    if (favourites is! Map<String, dynamic>) {
      return const AniListPagedChunk<MediaItem>(
        items: <MediaItem>[],
        hasNextPage: false,
      );
    }
    final Object? connection =
        favourites[switch (kind) {
          AniListFavouriteKind.anime => 'anime',
          AniListFavouriteKind.manga => 'manga',
          AniListFavouriteKind.characters => 'characters',
          AniListFavouriteKind.staff => 'staff',
          AniListFavouriteKind.studios => 'studios',
        }];
    if (connection is! Map<String, dynamic>) {
      return const AniListPagedChunk<MediaItem>(
        items: <MediaItem>[],
        hasNextPage: false,
      );
    }
    final Object? nodes = connection['nodes'];
    final List<MediaItem> items = nodes is! List<dynamic>
        ? const <MediaItem>[]
        : nodes
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> json) {
                return switch (kind) {
                  AniListFavouriteKind.anime ||
                  AniListFavouriteKind.manga => _mediaFromJson(json),
                  AniListFavouriteKind.characters => _namedNodeFromJson(
                    json,
                    'character',
                  ),
                  AniListFavouriteKind.staff => _namedNodeFromJson(
                    json,
                    'staff',
                  ),
                  AniListFavouriteKind.studios => _simpleEntityFromJson(
                    json,
                    'studio',
                  ),
                };
              })
              .toList(growable: false);
    return AniListPagedChunk<MediaItem>(
      items: items,
      hasNextPage: _pageHasNext(connection['pageInfo']),
      total: _pageTotal(connection['pageInfo']),
    );
  }

  Future<AniListPagedChunk<AniListUserSnippet>> fetchSocialUsers({
    required int userId,
    required bool following,
    int page = 1,
  }) async {
    final String rootField = following ? 'following' : 'followers';
    final Map<String, dynamic> data = await _post(
      '''
      query SocialUsers(\$userId: Int!, \$page: Int) {
        Page(page: \$page) {
          pageInfo { hasNextPage total }
          $rootField(userId: \$userId, sort: USERNAME) {
            id
            name
            avatar { large }
          }
        }
      }
      ''',
      <String, dynamic>{'userId': userId, 'page': page},
      authenticated: true,
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) {
      return const AniListPagedChunk<AniListUserSnippet>(
        items: <AniListUserSnippet>[],
        hasNextPage: false,
      );
    }
    final Object? items = pageData[rootField];
    final List<AniListUserSnippet> mapped = items is List<dynamic>
        ? items
              .whereType<Map<String, dynamic>>()
              .map(_userSnippetFromJson)
              .toList(growable: false)
        : const <AniListUserSnippet>[];
    return AniListPagedChunk<AniListUserSnippet>(
      items: mapped,
      hasNextPage: _pageHasNext(pageData['pageInfo']),
      total: _pageTotal(pageData['pageInfo']),
    );
  }

  Future<AniListPagedChunk<AniListForumThread>> fetchSocialThreads({
    required int userId,
    int page = 1,
  }) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query SocialThreads($userId: Int!, $page: Int) {
        Page(page: $page) {
          pageInfo { hasNextPage total }
          threads(userId: $userId, sort: ID_DESC) {
            id
            title
            viewCount
            likeCount
            replyCount
            isSticky
            isLocked
            siteUrl
            createdAt
            repliedAt
            categories { name }
            mediaCategories { title { userPreferred } }
            user { id name avatar { large } }
            replyUser { id name avatar { large } }
          }
        }
      }
      ''',
      <String, dynamic>{'userId': userId, 'page': page},
      authenticated: true,
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) {
      return const AniListPagedChunk<AniListForumThread>(
        items: <AniListForumThread>[],
        hasNextPage: false,
      );
    }
    final Object? items = pageData['threads'];
    final List<AniListForumThread> mapped = items is List<dynamic>
        ? items
              .whereType<Map<String, dynamic>>()
              .map(_threadFromJson)
              .toList(growable: false)
        : const <AniListForumThread>[];
    return AniListPagedChunk<AniListForumThread>(
      items: mapped,
      hasNextPage: _pageHasNext(pageData['pageInfo']),
      total: _pageTotal(pageData['pageInfo']),
    );
  }

  Future<AniListPagedChunk<AniListForumComment>> fetchSocialComments({
    required int userId,
    int page = 1,
  }) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query SocialComments($userId: Int!, $page: Int) {
        Page(page: $page) {
          pageInfo { hasNextPage total }
          threadComments(userId: $userId, sort: ID_DESC) {
            id
            comment
            likeCount
            isLiked
            isLocked
            createdAt
            siteUrl
            user { id name avatar { large } }
            thread { id title }
          }
        }
      }
      ''',
      <String, dynamic>{'userId': userId, 'page': page},
      authenticated: true,
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) {
      return const AniListPagedChunk<AniListForumComment>(
        items: <AniListForumComment>[],
        hasNextPage: false,
      );
    }
    final Object? items = pageData['threadComments'];
    final List<AniListForumComment> mapped = items is List<dynamic>
        ? items
              .whereType<Map<String, dynamic>>()
              .map(_threadCommentFromJson)
              .toList(growable: false)
        : const <AniListForumComment>[];
    return AniListPagedChunk<AniListForumComment>(
      items: mapped,
      hasNextPage: _pageHasNext(pageData['pageInfo']),
      total: _pageTotal(pageData['pageInfo']),
    );
  }

  Future<AniListPagedChunk<AniListReviewItem>> fetchUserReviews({
    required int userId,
    int page = 1,
    String? mediaType,
    String sort = 'CREATED_AT_DESC',
  }) async {
    final Map<String, dynamic> data = await _post(
      '''
      query UserReviews(
        \$userId: Int,
        \$page: Int,
        \$mediaType: MediaType,
        \$sort: [ReviewSort]
      ) {
        Page(page: \$page) {
          pageInfo { hasNextPage total }
          reviews(userId: \$userId, mediaType: \$mediaType, sort: \$sort) {
            id
            summary
            body(asHtml: false)
            score
            rating
            ratingAmount
            siteUrl
            media {
              id
              idMal
              type
              title { romaji english native userPreferred }
              coverImage { extraLarge large }
              bannerImage
            }
            user { id name avatar { large } }
          }
        }
      }
      ''',
      <String, dynamic>{
        'userId': userId,
        'page': page,
        'mediaType': mediaType,
        'sort': <String>[sort],
      },
      authenticated: true,
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) {
      return const AniListPagedChunk<AniListReviewItem>(
        items: <AniListReviewItem>[],
        hasNextPage: false,
      );
    }
    final Object? items = pageData['reviews'];
    final List<AniListReviewItem> mapped = items is List<dynamic>
        ? items
              .whereType<Map<String, dynamic>>()
              .map(_profileReviewFromJson)
              .toList(growable: false)
        : const <AniListReviewItem>[];
    return AniListPagedChunk<AniListReviewItem>(
      items: mapped,
      hasNextPage: _pageHasNext(pageData['pageInfo']),
      total: _pageTotal(pageData['pageInfo']),
    );
  }

  Future<void> saveTextActivity({String? text, int? id}) async {
    await _post(
      r'''
      mutation SaveStatusActivity($id: Int, $text: String) {
        SaveTextActivity(id: $id, text: $text) {
          id
        }
      }
      ''',
      <String, dynamic>{'id': id, 'text': text},
      authenticated: true,
    );
  }

  Future<void> toggleActivityLike(int id) async {
    await _post(
      r'''
      mutation ToggleActivityLike($id: Int) {
        ToggleLikeV2(id: $id, type: ACTIVITY) {
          ... on TextActivity { id likeCount isLiked }
          ... on ListActivity { id likeCount isLiked }
          ... on MessageActivity { id likeCount isLiked }
        }
      }
      ''',
      <String, dynamic>{'id': id},
      authenticated: true,
    );
  }

  Future<void> toggleActivitySubscription({
    required int id,
    required bool subscribe,
  }) async {
    await _post(
      r'''
      mutation ToggleActivitySubscription($id: Int, $subscribe: Boolean) {
        ToggleActivitySubscription(activityId: $id, subscribe: $subscribe) {
          ... on TextActivity { id isSubscribed }
          ... on ListActivity { id isSubscribed }
          ... on MessageActivity { id isSubscribed }
        }
      }
      ''',
      <String, dynamic>{'id': id, 'subscribe': subscribe},
      authenticated: true,
    );
  }

  Future<List<AniListAnimeListFolder>> fetchAnimeListCollection({int? userId}) {
    return fetchMediaListCollection(userId: userId, type: 'ANIME');
  }

  Future<List<AniListAnimeListFolder>> fetchMangaListCollection({int? userId}) {
    return fetchMediaListCollection(userId: userId, type: 'MANGA');
  }

  Future<List<AniListAnimeListFolder>> fetchMediaListCollection({
    int? userId,
    required String type,
    List<String>? sort,
    List<String>? statusIn,
  }) async {
    final int resolvedUserId = userId ?? (await fetchViewer()).id;
    final Map<String, dynamic> variables = <String, dynamic>{
      'userId': resolvedUserId,
      'type': type,
    };
    if (sort != null && sort.isNotEmpty) variables['sort'] = sort;
    if (statusIn != null && statusIn.isNotEmpty) {
      variables['statusIn'] = statusIn;
    }
    final String sortDecl = sort != null ? r', $sort: [MediaListSort]' : '';
    final String sortArg = sort != null ? r', sort: $sort' : '';
    final Map<String, dynamic> data = await _post(
      '''
      query MediaListCollection(
        \$userId: Int,
        \$type: MediaType$sortDecl,
        \$statusIn: [MediaListStatus]
      ) {
        MediaListCollection(
          userId: \$userId,
          type: \$type$sortArg,
          status_in: \$statusIn
        ) {
          lists {
            name
            status
            entries {
              id
              status
              progress
              score(format: POINT_10_DECIMAL)
              notes
              repeat
              createdAt
              updatedAt
              startedAt { year month day }
              completedAt { year month day }
              media {
                $_collectionMediaFields
                format
                nextAiringEpisode { episode airingAt }
              }
            }
          }
        }
      }
      ''',
      variables,
      authenticated: true,
    );

    final Object? collection = data['MediaListCollection'];
    if (collection is! Map<String, dynamic>) {
      return <AniListAnimeListFolder>[];
    }
    final Object? lists = collection['lists'];
    if (lists is! List<dynamic>) {
      return <AniListAnimeListFolder>[];
    }
    return lists
        .whereType<Map<String, dynamic>>()
        .map(_folderFromJson)
        .where((AniListAnimeListFolder folder) => folder.entries.isNotEmpty)
        .toList();
  }

  Future<AniListAnimeListEntry?> fetchMediaListEntry({
    int? userId,
    required int mediaId,
  }) async {
    final int resolvedUserId = userId ?? (await fetchViewer()).id;
    final Map<String, dynamic> data = await _post(
      '''
      query MediaListEntry(\$userId: Int, \$mediaId: Int) {
        MediaList(userId: \$userId, mediaId: \$mediaId) {
          id
          status
          progress
          score(format: POINT_10_DECIMAL)
          notes
          repeat
          createdAt
          updatedAt
          startedAt { year month day }
          completedAt { year month day }
          media {
            $_mediaFields
            format
            nextAiringEpisode { episode airingAt }
          }
        }
      }
      ''',
      <String, dynamic>{'userId': resolvedUserId, 'mediaId': mediaId},
      authenticated: true,
    );
    final Object? entry = data['MediaList'];
    return entry is Map<String, dynamic> ? _entryFromJson(entry) : null;
  }

  Future<void> updateProgress({
    required int mediaId,
    required int progress,
    AniListListStatus? status,
  }) async {
    await updateListEntry(mediaId: mediaId, progress: progress, status: status);
  }

  Future<void> updateListEntry({
    required int mediaId,
    AniListListStatus? status,
    int? progress,
    double? score,
    int? scoreRaw,
    String? notes,
    int? repeat,
  }) async {
    final Map<String, dynamic> variables = <String, dynamic>{
      'mediaId': mediaId,
    };
    if (status != null) variables['status'] = status.graphQlValue;
    if (progress != null) variables['progress'] = progress;
    if (scoreRaw != null) {
      variables['scoreRaw'] = scoreRaw.clamp(0, 100).toInt();
    } else if (score != null) {
      variables['score'] = score;
    }
    if (notes != null) variables['notes'] = notes;
    if (repeat != null) variables['repeat'] = repeat;

    await _post(
      '''
      mutation SaveListEntry(
        \$mediaId: Int,
        \$status: MediaListStatus,
        \$progress: Int,
        \$score: Float,
        \$scoreRaw: Int,
        \$notes: String,
        \$repeat: Int
      ) {
        SaveMediaListEntry(
          mediaId: \$mediaId,
          status: \$status,
          progress: \$progress,
          score: \$score,
          scoreRaw: \$scoreRaw,
          notes: \$notes,
          repeat: \$repeat
        ) {
          id
          status
          progress
          score(format: POINT_10_DECIMAL)
          notes
          repeat
        }
      }
      ''',
      variables,
      authenticated: true,
    );
  }

  Future<void> addToList(int mediaId, AniListListStatus status) async {
    await _post(
      r'''
      mutation AddToList($mediaId: Int, $status: MediaListStatus) {
        SaveMediaListEntry(mediaId: $mediaId, status: $status) { id }
      }
      ''',
      <String, dynamic>{'mediaId': mediaId, 'status': status.graphQlValue},
      authenticated: true,
    );
  }

  Future<void> deleteListEntry(int entryId) async {
    await _post(
      r'''
      mutation DeleteListEntry($id: Int) {
        DeleteMediaListEntry(id: $id) { deleted }
      }
      ''',
      <String, dynamic>{'id': entryId},
      authenticated: true,
    );
  }

  Future<void> toggleFavouriteMedia({
    required int mediaId,
    required bool isManga,
  }) async {
    await _post(
      r'''
      mutation ToggleFavorite($anime: Int, $manga: Int) {
        ToggleFavourite(animeId: $anime, mangaId: $manga) {
          __typename
        }
      }
      ''',
      isManga
          ? <String, dynamic>{'manga': mediaId}
          : <String, dynamic>{'anime': mediaId},
      authenticated: true,
    );
  }

  Future<List<CalendarItem>> getAiringSchedule({
    required DateTime from,
    required DateTime to,
    int page = 1,
  }) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query Airing($page: Int, $from: Int, $to: Int) {
        Page(page: $page, perPage: 50) {
          airingSchedules(
            airingAt_greater: $from,
            airingAt_lesser: $to,
            sort: TIME
          ) {
            airingAt
            episode
            media {
              ''' +
          _mediaFields +
          r'''
            }
          }
        }
      }
      ''',
      <String, dynamic>{
        'page': page,
        'from': from.millisecondsSinceEpoch ~/ 1000,
        'to': to.millisecondsSinceEpoch ~/ 1000,
      },
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) return const <CalendarItem>[];
    final Object? schedules = pageData['airingSchedules'];
    if (schedules is! List<dynamic>) return const <CalendarItem>[];
    return schedules
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) {
          final Object? mediaJson = json['media'];
          if (mediaJson is! Map<String, dynamic>) return null;
          final MediaItem media = _mediaFromJson(mediaJson);
          final DateTime? date = _epochToDateTime(_int(json['airingAt']));
          if (date == null) return null;
          final int episode = _int(json['episode']);
          return CalendarItem(
            id: 'anilist-calendar:${media.externalIds['anilist']}:$episode',
            mediaItem: media,
            date: date,
            title: 'Episode $episode · ${media.title}',
            description: media.overview,
            type: CalendarItemType.animeAiring,
            isFromLibrary: false,
          );
        })
        .whereType<CalendarItem>()
        .toList(growable: false);
  }

  Future<List<CalendarItem>> getAiringAnime({
    required DateTime from,
    required DateTime to,
    int page = 1,
  }) {
    return getAiringSchedule(from: from, to: to, page: page);
  }

  Future<List<MediaItem>> enrichWithRussian(List<MediaItem> items) =>
      _wantsRussian
      ? _enrichWithRussian(items)
      : Future<List<MediaItem>>.value(items);

  Future<MediaItem> enrichHeroOverview(MediaItem item) async {
    MediaItem result = item;

    // Collection queries omit bannerImage and description to save bandwidth;
    // missing description is filled with a placeholder string (not empty).
    // Fetch the real values so the hero always has a backdrop and overview.
    final bool needsBackdrop = result.backdropUrl.isEmpty;
    final bool needsDescription =
        result.overview.trim().isEmpty ||
        result.overview == 'No AniList description yet.';
    if (needsBackdrop || needsDescription) {
      final String? idStr =
          result.externalIds['anilist'] ??
          (result.id.startsWith('anilist:') ? result.id.substring(8) : null);
      final int? anilistId = idStr != null ? int.tryParse(idStr) : null;
      if (anilistId != null) {
        final ({String banner, String description})? visuals =
            await _fetchHeroVisuals(anilistId);
        if (visuals != null) {
          result = result.copyWith(
            backdropUrl: needsBackdrop && visuals.banner.isNotEmpty
                ? visuals.banner
                : null,
            overview: needsDescription && visuals.description.isNotEmpty
                ? visuals.description
                : null,
          );
        }
      }
    }

    if (_wantsRussian) {
      final ({String title, String description})? details =
          await _russianDetailsForItem(result);
      if (details != null) {
        result = result.copyWith(
          title: details.title.isNotEmpty ? details.title : null,
          overview: details.description.isNotEmpty ? details.description : null,
        );
      }
    }

    return result;
  }

  Future<({String banner, String description})?> _fetchHeroVisuals(
    int anilistId,
  ) async {
    try {
      final Map<String, dynamic> data = await _post(
        r'''
        query HeroVisuals($id: Int) {
          Media(id: $id) {
            bannerImage
            description(asHtml: false)
          }
        }
        ''',
        <String, dynamic>{'id': anilistId},
      );
      final Object? media = data['Media'];
      if (media is! Map<String, dynamic>) return null;
      return (
        banner: _string(media['bannerImage']),
        description: _stripHtml(_string(media['description'])),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<MediaItem>> _animePage(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final List<MediaItem> items = await _mediaPage(query, variables);
    return _wantsRussian ? _enrichWithRussian(items) : items;
  }

  Future<List<MediaItem>> _mediaPage(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final Map<String, dynamic> data = await _post(query, variables);
    final Object? page = data['Page'];
    if (page is! Map<String, dynamic>) {
      return <MediaItem>[];
    }
    final Object? media = page['media'];
    if (media is! List<dynamic>) {
      return <MediaItem>[];
    }
    return media.whereType<Map<String, dynamic>>().map(_mediaFromJson).toList();
  }

  Future<List<MediaItem>> _mediaSearchPage(
    String type,
    String search,
    int page,
  ) {
    return _catalogMediaPage(
      type: type,
      query:
          '''
      query SearchMedia(\$type: MediaType, \$search: String, \$page: Int) {
        Page(page: \$page, perPage: 20) {
          media(type: \$type, search: \$search, sort: SEARCH_MATCH$_isAdultClause) {
            $_mediaFields
          }
        }
      }
      ''',
      variables: <String, dynamic>{
        'type': type,
        'search': search,
        'page': page,
      },
    );
  }

  Future<List<MediaItem>> _mediaSortedPage(String type, String sort, int page) {
    return _catalogMediaPage(
      type: type,
      query:
          '''
      query SortedMedia(\$type: MediaType, \$sort: [MediaSort], \$page: Int) {
        Page(page: \$page, perPage: 20) {
          media(type: \$type, sort: \$sort$_isAdultClause) {
            $_mediaFields
          }
        }
      }
      ''',
      variables: <String, dynamic>{'type': type, 'sort': sort, 'page': page},
    );
  }

  Future<List<MediaItem>> _mediaFilteredPage({
    required String type,
    required String sort,
    required String? status,
    required int page,
  }) {
    final Map<String, dynamic> variables = <String, dynamic>{
      'type': type,
      'sort': sort,
      'page': page,
      'status': ?status,
    };
    return _catalogMediaPage(
      type: type,
      query:
          '''
      query FilteredMedia(
        \$type: MediaType,
        \$sort: [MediaSort],
        \$status: MediaStatus,
        \$page: Int
      ) {
        Page(page: \$page, perPage: 20) {
          media(type: \$type, sort: \$sort, status: \$status$_isAdultClause) {
            $_mediaFields
          }
        }
      }
      ''',
      variables: variables,
    );
  }

  Future<List<MediaItem>> _catalogMediaPage({
    required String type,
    required String query,
    required Map<String, dynamic> variables,
  }) async {
    final List<MediaItem> items = await _mediaPage(query, variables);
    if (type == 'ANIME' && _wantsRussian) {
      return _enrichWithRussian(items);
    }
    return items;
  }

  Future<List<MediaItem>> _namedNodePage({
    required String kind,
    required String rootField,
    required String search,
    required int page,
  }) async {
    final String query =
        '''
      query NamedNodes(\$page: Int, \$search: String) {
        Page(page: \$page, perPage: 20) {
          $rootField(search: \$search, sort: FAVOURITES_DESC) {
            id
            name { userPreferred full native }
            image { large }
            description(asHtml: false)
            siteUrl
          }
        }
      }
      ''';
    final Map<String, dynamic> data = await _post(query, <String, dynamic>{
      'page': page,
      'search': search.isEmpty ? null : search,
    });
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) return const <MediaItem>[];
    final Object? nodes = pageData[rootField];
    if (nodes is! List<dynamic>) return const <MediaItem>[];
    return nodes
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => _namedNodeFromJson(json, kind))
        .toList(growable: false);
  }

  Future<List<MediaItem>> _studioPage({
    required String search,
    required int page,
  }) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query Studios($page: Int, $search: String) {
        Page(page: $page, perPage: 20) {
          studios(search: $search, sort: FAVOURITES_DESC) {
            id
            name
            siteUrl
          }
        }
      }
      ''',
      <String, dynamic>{'page': page, 'search': search.isEmpty ? null : search},
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) return const <MediaItem>[];
    final Object? nodes = pageData['studios'];
    if (nodes is! List<dynamic>) return const <MediaItem>[];
    return nodes
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> json) => _simpleEntityFromJson(json, 'studio'),
        )
        .toList(growable: false);
  }

  Future<List<MediaItem>> _userPage({
    required String search,
    required int page,
  }) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query Users($page: Int, $search: String) {
        Page(page: $page, perPage: 20) {
          users(search: $search, sort: USERNAME) {
            id
            name
            avatar { large }
            bannerImage
            about
            siteUrl
          }
        }
      }
      ''',
      <String, dynamic>{'page': page, 'search': search.isEmpty ? null : search},
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) return const <MediaItem>[];
    final Object? nodes = pageData['users'];
    if (nodes is! List<dynamic>) return const <MediaItem>[];
    return nodes
        .whereType<Map<String, dynamic>>()
        .map(_userFromJson)
        .toList(growable: false);
  }

  Future<List<MediaItem>> _reviewPage({
    required String search,
    required int page,
  }) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query Reviews($page: Int) {
        Page(page: $page, perPage: 20) {
          reviews(sort: RATING_DESC) {
            id
            summary
            score
            rating
            ratingAmount
            media {
              id
              type
              title { userPreferred english romaji native }
              coverImage { extraLarge large }
              bannerImage
            }
            user { name avatar { large } }
          }
        }
      }
      ''',
      <String, dynamic>{'page': page},
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) return const <MediaItem>[];
    final Object? nodes = pageData['reviews'];
    if (nodes is! List<dynamic>) return const <MediaItem>[];
    return nodes
        .whereType<Map<String, dynamic>>()
        .map(_reviewFromJson)
        .where(
          (MediaItem item) =>
              search.isEmpty ||
              item.title.toLowerCase().contains(search.toLowerCase()),
        )
        .toList(growable: false);
  }

  Future<List<MediaItem>> _recommendationsPage({required int page}) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query Recommendations($page: Int) {
        Page(page: $page, perPage: 20) {
          recommendations(sort: RATING_DESC) {
            rating
            mediaRecommendation {
              ''' +
          _mediaFields +
          r'''
            }
          }
        }
      }
      ''',
      <String, dynamic>{'page': page},
    );
    final Object? pageData = data['Page'];
    if (pageData is! Map<String, dynamic>) return const <MediaItem>[];
    final Object? nodes = pageData['recommendations'];
    if (nodes is! List<dynamic>) return const <MediaItem>[];
    return nodes
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => json['mediaRecommendation'])
        .whereType<Map<String, dynamic>>()
        .map(_mediaFromJson)
        .toList(growable: false);
  }

  Future<MediaItem?> _characterDetails(int id) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query CharacterDetails($id: Int) {
        Character(id: $id) {
          id
          name { userPreferred full native }
          image { large }
          description(asHtml: false)
          siteUrl
          media(page: 1, perPage: 12, sort: POPULARITY_DESC) {
            nodes {
              id
              type
              title { userPreferred english romaji native }
              coverImage { extraLarge large }
            }
          }
        }
      }
      ''',
      <String, dynamic>{'id': id},
    );
    final Object? node = data['Character'];
    return node is Map<String, dynamic>
        ? _namedNodeFromJson(node, 'character')
        : null;
  }

  Future<MediaItem?> _staffDetails(int id) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query StaffDetails($id: Int) {
        Staff(id: $id) {
          id
          name { userPreferred full native }
          image { large }
          description(asHtml: false)
          primaryOccupations
          siteUrl
        }
      }
      ''',
      <String, dynamic>{'id': id},
    );
    final Object? node = data['Staff'];
    return node is Map<String, dynamic>
        ? _namedNodeFromJson(node, 'staff')
        : null;
  }

  Future<MediaItem?> _studioDetails(int id) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query StudioDetails($id: Int) {
        Studio(id: $id) {
          id
          name
          siteUrl
          media(page: 1, perPage: 12, sort: POPULARITY_DESC) {
            nodes {
              id
              type
              title { userPreferred english romaji native }
              coverImage { extraLarge large }
            }
          }
        }
      }
      ''',
      <String, dynamic>{'id': id},
    );
    final Object? node = data['Studio'];
    return node is Map<String, dynamic>
        ? _simpleEntityFromJson(node, 'studio')
        : null;
  }

  Future<MediaItem?> _userDetails(int id) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query UserDetails($id: Int) {
        User(id: $id) {
          id
          name
          avatar { large }
          bannerImage
          about
          siteUrl
        }
      }
      ''',
      <String, dynamic>{'id': id},
    );
    final Object? node = data['User'];
    return node is Map<String, dynamic> ? _userFromJson(node) : null;
  }

  Future<MediaItem?> _reviewDetails(int id) async {
    final Map<String, dynamic> data = await _post(
      r'''
      query ReviewDetails($id: Int) {
        Review(id: $id) {
          id
          summary
          body(asHtml: false)
          score
          rating
          ratingAmount
          siteUrl
          media {
            id
            type
            title { userPreferred english romaji native }
            coverImage { extraLarge large }
            bannerImage
          }
          user { name avatar { large } }
        }
      }
      ''',
      <String, dynamic>{'id': id},
    );
    final Object? node = data['Review'];
    return node is Map<String, dynamic> ? _reviewFromJson(node) : null;
  }

  Future<Map<String, dynamic>> _post(
    String query,
    Map<String, dynamic> variables, {
    bool authenticated = false,
  }) async {
    if (authenticated && (_accessToken?.trim().isEmpty ?? true)) {
      throw StateError('AniList access token is not configured.');
    }

    final Response<dynamic> response = await _dio.post<dynamic>(
      '',
      data: <String, dynamic>{'query': query, 'variables': variables},
      options: Options(
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (authenticated) 'Authorization': 'Bearer $_accessToken',
        },
      ),
    );

    final Object? body = response.data;
    if (body is! Map<String, dynamic>) {
      throw StateError('AniList response was not JSON.');
    }
    final Object? errors = body['errors'];
    if (errors is List<dynamic> && errors.isNotEmpty) {
      throw StateError('AniList error: ${errors.first}');
    }
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }
    return data;
  }

  AniListAnimeListFolder _folderFromJson(Map<String, dynamic> json) {
    final AniListListStatus? status = json['status'] == null
        ? null
        : AniListListStatusLabel.fromGraphQl(_string(json['status']));
    final Object? entries = json['entries'];
    return AniListAnimeListFolder(
      name: _string(json['name'], fallback: status?.label ?? 'Custom'),
      status: status,
      entries: entries is List<dynamic>
          ? entries
                .whereType<Map<String, dynamic>>()
                .map(_entryFromJson)
                .whereType<AniListAnimeListEntry>()
                .toList()
          : <AniListAnimeListEntry>[],
    );
  }

  AniListAnimeListEntry? _entryFromJson(Map<String, dynamic> json) {
    final Object? media = json['media'];
    if (media is! Map<String, dynamic>) {
      return null;
    }
    final int rawAvgScore = _int(media['averageScore']);
    final Object? nextAiring = media['nextAiringEpisode'];
    int? nextEpisode;
    DateTime? airingAt;
    if (nextAiring is Map<String, dynamic>) {
      nextEpisode = _int(nextAiring['episode']) == 0
          ? null
          : _int(nextAiring['episode']);
      airingAt = _epochToDateTime(_int(nextAiring['airingAt']));
    }
    final String fmt = _string(media['format']);
    return AniListAnimeListEntry(
      id: _int(json['id']),
      status: AniListListStatusLabel.fromGraphQl(_string(json['status'])),
      progress: _int(json['progress']),
      score: _num(json['score'])?.toDouble(),
      mediaItem: _mediaFromJson(media),
      notes: _string(json['notes']),
      repeat: _int(json['repeat']),
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : null,
      updatedAt: json['updatedAt'] is int ? json['updatedAt'] as int : null,
      startedAt: _fuzzyDate(json['startedAt']),
      completedAt: _fuzzyDate(json['completedAt']),
      nextEpisode: nextEpisode,
      airingAt: airingAt,
      avgScore: rawAvgScore == 0 ? null : rawAvgScore,
      format: fmt.isEmpty ? null : _humanizeFormat(fmt),
    );
  }

  static DateTime? _fuzzyDate(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final int year = _int(value['year']);
    if (year == 0) return null;
    final int month = _int(value['month']);
    final int day = _int(value['day']);
    return DateTime(year, month == 0 ? 1 : month, day == 0 ? 1 : day);
  }

  static DateTime? _epochToDateTime(int seconds) {
    if (seconds == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static String _humanizeFormat(String raw) {
    return switch (raw.toUpperCase()) {
      'TV' => 'TV',
      'TV_SHORT' => 'TV Short',
      'MOVIE' => 'Movie',
      'SPECIAL' => 'Special',
      'OVA' => 'OVA',
      'ONA' => 'ONA',
      'MUSIC' => 'Music',
      _ => raw,
    };
  }

  static String _normalizedKind(String raw) {
    return raw.toLowerCase();
  }

  static ({String sort, String? status}) _mediaFilter(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'trending' => (sort: 'TRENDING_DESC', status: null),
      'popular' => (sort: 'POPULARITY_DESC', status: null),
      'top rated' || 'top rated anime' => (sort: 'SCORE_DESC', status: null),
      'favorites' ||
      'most favorited' => (sort: 'FAVOURITES_DESC', status: null),
      'newest' || 'new releases' => (sort: 'START_DATE_DESC', status: null),
      'oldest' => (sort: 'START_DATE', status: null),
      'airing' || 'releasing' => (sort: 'TRENDING_DESC', status: 'RELEASING'),
      'upcoming' => (sort: 'START_DATE', status: 'NOT_YET_RELEASED'),
      'finished' ||
      'completed' => (sort: 'POPULARITY_DESC', status: 'FINISHED'),
      'recently updated' ||
      'updated' => (sort: 'UPDATED_AT_DESC', status: null),
      _ => (sort: 'POPULARITY_DESC', status: null),
    };
  }

  MediaItem _mediaFromJson(Map<String, dynamic> json) {
    final int id = _int(json['id']);
    final String mediaType = _string(
      json['type'],
      fallback: 'ANIME',
    ).toUpperCase();
    final String english = _nestedString(json, const <String>[
      'title',
      'english',
    ]);
    final String romaji = _nestedString(json, const <String>[
      'title',
      'romaji',
    ]);
    final String native = _nestedString(json, const <String>[
      'title',
      'native',
    ]);
    final String title = switch (titleLanguage) {
      'ROMAJI' => romaji.isNotEmpty ? romaji : english,
      'NATIVE' => native.isNotEmpty ? native : romaji,
      _ => english.isNotEmpty ? english : romaji,
    };
    final int startYear = _int(
      _nested(json, const <String>['startDate', 'year']),
    );
    final String cover = _nestedString(json, const <String>[
      'coverImage',
      'extraLarge',
    ]);
    final String banner = _string(json['bannerImage']);
    final int? duration = _int(json['duration']) == 0
        ? null
        : _int(json['duration']);
    final int rawEpisodes = _int(json['episodes']);
    final int rawChapters = _int(json['chapters']);
    final int? progressTotal = mediaType == 'MANGA'
        ? (rawChapters == 0 ? null : rawChapters)
        : (rawEpisodes == 0 ? null : rawEpisodes);
    final num? averageScore = _num(json['averageScore']);
    final int malId = _int(json['idMal']);
    final List<String> aliases = <String>{
      if (romaji.isNotEmpty) romaji,
      if (english.isNotEmpty) english,
      if (native.isNotEmpty) native,
      ..._stringList(json['synonyms']),
    }.where((String value) => value.trim().isNotEmpty).toList(growable: false);
    final List<MediaSeason> relations = _relationsFromJson(json);
    final String idPrefix = mediaType == 'MANGA' ? 'anilist:manga' : 'anilist';

    // Extra detail fields (present only in full detail queries)
    final String source = _string(json['source']);
    final String season = _string(json['season']);
    final int seasonYear = _int(json['seasonYear']);
    final String country = _string(json['countryOfOrigin']);
    final String format = _string(json['format']);
    final int popularity = _int(json['popularity']);
    final int favourites = _int(json['favourites']);
    final bool? isAdult = json['isAdult'] is bool
        ? json['isAdult'] as bool
        : null;
    final bool? isLicensed = json['isLicensed'] is bool
        ? json['isLicensed'] as bool
        : null;
    final MediaTrailer? trailer = _trailerFromJson(json['trailer']);

    // Build full start/end date strings
    final Map<String, dynamic>? startDateMap =
        json['startDate'] is Map<String, dynamic>
        ? json['startDate'] as Map<String, dynamic>
        : null;
    final Map<String, dynamic>? endDateMap =
        json['endDate'] is Map<String, dynamic>
        ? json['endDate'] as Map<String, dynamic>
        : null;
    String buildDate(Map<String, dynamic>? d) {
      if (d == null) return '';
      final int y = _int(d['year']);
      final int m = _int(d['month']);
      final int dy = _int(d['day']);
      if (y == 0) return '';
      if (m == 0) return '$y';
      if (dy == 0) return '$y-${m.toString().padLeft(2, '0')}';
      return '$y-${m.toString().padLeft(2, '0')}-${dy.toString().padLeft(2, '0')}';
    }

    final String startDate = buildDate(startDateMap);
    final String endDate = buildDate(endDateMap);

    // Studios: "name:1" = animation studio, "name:0" = producer
    final Object? studioNodesRaw = json['studios'] is Map<String, dynamic>
        ? (json['studios'] as Map<String, dynamic>)['nodes']
        : null;
    final List<dynamic> studioNodes = studioNodesRaw is List
        ? studioNodesRaw
        : <dynamic>[];
    final StringBuffer studioBuf = StringBuffer();
    for (final dynamic node in studioNodes) {
      if (node is! Map<String, dynamic>) continue;
      final String sName = _string(node['name']);
      if (sName.isEmpty) continue;
      final bool isAnim = node['isAnimationStudio'] == true;
      if (studioBuf.isNotEmpty) studioBuf.write('|');
      studioBuf.write('$sName:${isAnim ? '1' : '0'}');
    }

    // Tags: "name:rank:generalSpoiler:mediaSpoiler:category"
    final List<dynamic> tagList = json['tags'] is List
        ? json['tags'] as List<dynamic>
        : <dynamic>[];
    final StringBuffer tagBuf = StringBuffer();
    for (final dynamic tag in tagList) {
      if (tag is! Map<String, dynamic>) continue;
      final String tName = _string(tag['name']);
      if (tName.isEmpty) continue;
      final int rank = _int(tag['rank']);
      final bool gs = tag['isGeneralSpoiler'] == true;
      final bool ms = tag['isMediaSpoiler'] == true;
      final String category = _string(tag['category']);
      if (tagBuf.isNotEmpty) tagBuf.write('|');
      tagBuf.write(
        '$tName:$rank:${gs ? '1' : '0'}:${ms ? '1' : '0'}:$category',
      );
    }

    return MediaItem(
      id: '$idPrefix:$id',
      title: title.isEmpty ? native : title,
      originalTitle: native.isEmpty ? romaji : native,
      overview: _stripHtml(
        _string(json['description'], fallback: 'No AniList description yet.'),
      ),
      type: MediaType.anime,
      year: startYear == 0 ? DateTime.now().year : startYear,
      posterUrl: cover,
      backdropUrl: banner,
      rating: averageScore == null
          ? 0
          : (averageScore / 10).clamp(0, 10).toDouble(),
      genres: _stringList(json['genres']),
      sourceProvider: mediaType == 'MANGA' ? 'AniList Manga' : 'AniList',
      externalIds: <String, String>{
        'anilist': id.toString(),
        'anilist_type': mediaType,
        if (romaji.isNotEmpty) 'anilist_title_romaji': romaji,
        if (english.isNotEmpty) 'anilist_title_english': english,
        if (native.isNotEmpty) 'anilist_title_native': native,
        if (malId > 0) 'mal': malId.toString(),
        if (_string(json['siteUrl']).isNotEmpty)
          'site_url': _string(json['siteUrl']),
        if (source.isNotEmpty) 'anilist_source': source,
        if (season.isNotEmpty) 'anilist_season': season,
        if (seasonYear > 0) 'anilist_season_year': seasonYear.toString(),
        if (country.isNotEmpty) 'anilist_country': country,
        if (format.isNotEmpty) 'anilist_format': format,
        if (isAdult != null) 'anilist_is_adult': isAdult.toString(),
        if (isLicensed != null) 'anilist_is_licensed': isLicensed.toString(),
        if (json['isFavourite'] is bool)
          'anilist_is_favourite': (json['isFavourite'] == true).toString(),
        if (popularity > 0) 'anilist_popularity': popularity.toString(),
        if (favourites > 0) 'anilist_favourites': favourites.toString(),
        if (startDate.isNotEmpty) 'anilist_start_date': startDate,
        if (endDate.isNotEmpty) 'anilist_end_date': endDate,
        if (studioBuf.isNotEmpty) 'anilist_studios': studioBuf.toString(),
        if (tagBuf.isNotEmpty) 'anilist_tags': tagBuf.toString(),
      },
      runtimeMinutes: duration,
      episodeCount: progressTotal,
      seasons: relations,
      statusLabel: _string(json['status'], fallback: 'AniList'),
      aliases: aliases,
      trailer: trailer,
    );
  }

  MediaTrailer? _trailerFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final String id = _string(value['id']).trim();
    final String site = _string(value['site']).trim();
    if (id.isEmpty || site.isEmpty) {
      return null;
    }
    return MediaTrailer(
      id: id,
      site: site,
      title: 'Trailer',
      thumbnailUrl: _string(value['thumbnail']),
    );
  }

  MediaItem _namedNodeFromJson(Map<String, dynamic> json, String kind) {
    final int id = _int(json['id']);
    final String preferred = _nestedString(json, const <String>[
      'name',
      'userPreferred',
    ]);
    final String full = _nestedString(json, const <String>['name', 'full']);
    final String native = _nestedString(json, const <String>['name', 'native']);
    final String title = preferred.isNotEmpty
        ? preferred
        : full.isNotEmpty
        ? full
        : native;
    final List<String> aliases = <String>{
      full,
      native,
      ..._stringList(json['primaryOccupations']),
    }.where((String value) => value.trim().isNotEmpty).toList(growable: false);
    return MediaItem(
      id: 'anilist:$kind:$id',
      title: title.isEmpty ? 'AniList ${_humanizeKind(kind)}' : title,
      originalTitle: native,
      overview: _stripHtml(_string(json['description'])),
      type: MediaType.anime,
      year: DateTime.now().year,
      posterUrl: _nestedString(json, const <String>['image', 'large']),
      backdropUrl: '',
      rating: 0,
      genres: aliases.take(4).toList(growable: false),
      sourceProvider: 'AniList ${_humanizeKind(kind)}',
      externalIds: <String, String>{
        'anilist': id.toString(),
        'anilist_kind': kind.toUpperCase(),
        if (_string(json['siteUrl']).isNotEmpty)
          'site_url': _string(json['siteUrl']),
      },
      statusLabel: 'AniList',
      aliases: aliases,
    );
  }

  MediaItem _simpleEntityFromJson(Map<String, dynamic> json, String kind) {
    final int id = _int(json['id']);
    final String name = _string(
      json['name'],
      fallback: 'AniList ${_humanizeKind(kind)}',
    );
    return MediaItem(
      id: 'anilist:$kind:$id',
      title: name,
      originalTitle: name,
      overview: _string(json['description']),
      type: MediaType.anime,
      year: DateTime.now().year,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: 'AniList ${_humanizeKind(kind)}',
      externalIds: <String, String>{
        'anilist': id.toString(),
        'anilist_kind': kind.toUpperCase(),
        if (_string(json['siteUrl']).isNotEmpty)
          'site_url': _string(json['siteUrl']),
      },
      statusLabel: 'AniList',
    );
  }

  MediaItem _userFromJson(Map<String, dynamic> json) {
    final int id = _int(json['id']);
    final String name = _string(json['name'], fallback: 'AniList User');
    return MediaItem(
      id: 'anilist:user:$id',
      title: name,
      originalTitle: name,
      overview: _stripHtml(_string(json['about'])),
      type: MediaType.anime,
      year: DateTime.now().year,
      posterUrl: _nestedString(json, const <String>['avatar', 'large']),
      backdropUrl: _string(json['bannerImage']),
      rating: 0,
      genres: const <String>[],
      sourceProvider: 'AniList User',
      externalIds: <String, String>{
        'anilist': id.toString(),
        'anilist_kind': 'USER',
        if (_string(json['siteUrl']).isNotEmpty)
          'site_url': _string(json['siteUrl']),
      },
      statusLabel: 'AniList',
    );
  }

  MediaItem _reviewFromJson(Map<String, dynamic> json) {
    final int id = _int(json['id']);
    final Object? mediaJson = json['media'];
    final String mediaTitle = mediaJson is Map<String, dynamic>
        ? _nestedString(mediaJson, const <String>['title', 'userPreferred'])
        : '';
    final String userName = _nestedString(json, const <String>['user', 'name']);
    final String summary = _string(json['summary'], fallback: mediaTitle);
    final num? score = _num(json['score']) ?? _num(json['rating']);
    final String poster = mediaJson is Map<String, dynamic>
        ? _nestedString(mediaJson, const <String>['coverImage', 'extraLarge'])
        : '';
    return MediaItem(
      id: 'anilist:review:$id',
      title: summary.isEmpty ? 'Review for $mediaTitle' : summary,
      originalTitle: mediaTitle,
      overview: _stripHtml(_string(json['body'], fallback: summary)),
      type: MediaType.anime,
      year: DateTime.now().year,
      posterUrl: poster,
      backdropUrl: mediaJson is Map<String, dynamic>
          ? _string(mediaJson['bannerImage'])
          : '',
      rating: score == null ? 0 : (score / 10).clamp(0, 10).toDouble(),
      genres: <String>[
        if (userName.isNotEmpty) 'by $userName',
        if (_int(json['ratingAmount']) > 0)
          '${_int(json['ratingAmount'])} ratings',
      ],
      sourceProvider: 'AniList Review',
      externalIds: <String, String>{
        'anilist': id.toString(),
        'anilist_kind': 'REVIEW',
        if (_string(json['siteUrl']).isNotEmpty)
          'site_url': _string(json['siteUrl']),
      },
      statusLabel: 'AniList',
    );
  }

  AniListReviewItem _profileReviewFromJson(Map<String, dynamic> json) {
    final Object? mediaJson = json['media'];
    final Map<String, dynamic> media = mediaJson is Map<String, dynamic>
        ? mediaJson
        : const <String, dynamic>{};
    final String mediaTitle = _nestedString(media, const <String>[
      'title',
      'userPreferred',
    ]);
    final String userName = _nestedString(json, const <String>['user', 'name']);
    final String summary = _string(json['summary'], fallback: mediaTitle);
    return AniListReviewItem(
      id: _int(json['id']),
      mediaId: _int(media['id']),
      mediaTitle: mediaTitle.isEmpty ? 'AniList media' : mediaTitle,
      userName: userName.isEmpty ? 'AniList user' : userName,
      summary: summary.isEmpty ? 'Review' : summary,
      rating: _int(json['rating']),
      ratingAmount: _int(json['ratingAmount']),
      score: _int(json['score']),
      body: _stripHtml(_string(json['body'])),
      bannerUrl: _string(media['bannerImage']),
      coverUrl: _nestedString(media, const <String>[
        'coverImage',
        'extraLarge',
      ]),
      siteUrl: _string(json['siteUrl']),
    );
  }

  AniListForumThread _threadFromJson(Map<String, dynamic> json) {
    final Object? user = json['user'];
    final Object? replyUser = json['replyUser'];
    return AniListForumThread(
      id: _int(json['id']),
      title: _string(json['title'], fallback: 'AniList thread'),
      user: _userSnippetFromJson(
        user is Map<String, dynamic> ? user : const <String, dynamic>{},
      ),
      replyUser: replyUser is Map<String, dynamic>
          ? _userSnippetFromJson(replyUser)
          : null,
      replyCount: _int(json['replyCount']),
      likeCount: _int(json['likeCount']),
      viewCount: _int(json['viewCount']),
      isSticky: json['isSticky'] == true,
      isLocked: json['isLocked'] == true,
      siteUrl: _string(json['siteUrl']),
      createdAt: _epochToDateTime(_int(json['createdAt'])),
      repliedAt: _epochToDateTime(_int(json['repliedAt'])),
      categories: _namedStringList(json['categories'], 'name'),
      mediaCategories: _nestedNamedStringList(
        json['mediaCategories'],
        const <String>['title', 'userPreferred'],
      ),
    );
  }

  AniListForumComment _threadCommentFromJson(Map<String, dynamic> json) {
    final Object? user = json['user'];
    final Object? thread = json['thread'];
    final Map<String, dynamic> threadMap = thread is Map<String, dynamic>
        ? thread
        : const <String, dynamic>{};
    return AniListForumComment(
      id: _int(json['id']),
      user: _userSnippetFromJson(
        user is Map<String, dynamic> ? user : const <String, dynamic>{},
      ),
      threadId: _int(threadMap['id']),
      threadTitle: _string(threadMap['title'], fallback: 'AniList thread'),
      comment: _stripHtml(_string(json['comment'])),
      likeCount: _int(json['likeCount']),
      isLiked: json['isLiked'] == true,
      isLocked: json['isLocked'] == true,
      siteUrl: _string(json['siteUrl']),
      createdAt: _epochToDateTime(_int(json['createdAt'])),
    );
  }

  AniListUserProfile _userProfileFromJson(Map<String, dynamic> json) {
    final Object? statistics = json['statistics'];
    final Map<String, dynamic> statisticsMap =
        statistics is Map<String, dynamic>
        ? statistics
        : const <String, dynamic>{};
    return AniListUserProfile(
      id: _int(json['id']),
      name: _string(json['name'], fallback: 'AniList User'),
      about: _stripHtml(_string(json['about'])),
      avatarUrl: _nestedString(json, const <String>['avatar', 'large']),
      bannerUrl: _string(json['bannerImage']),
      siteUrl: _string(json['siteUrl']),
      isFollowing: json['isFollowing'] == true,
      isFollower: json['isFollower'] == true,
      isBlocked: json['isBlocked'] == true,
      animeStats: _userStatisticsFromJson(statisticsMap['anime']),
      mangaStats: _userStatisticsFromJson(statisticsMap['manga']),
    );
  }

  AniListUserStatistics _userStatisticsFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const AniListUserStatistics();
    }
    return AniListUserStatistics(
      count: _int(value['count']),
      meanScore: (_num(value['meanScore']) ?? 0).toDouble(),
      standardDeviation: (_num(value['standardDeviation']) ?? 0).toDouble(),
      minutesWatched: _int(value['minutesWatched']),
      episodesWatched: _int(value['episodesWatched']),
      chaptersRead: _int(value['chaptersRead']),
      volumesRead: _int(value['volumesRead']),
      scores: _statValues(value['scores'], 'score'),
      lengths: _statValues(value['lengths'], 'length'),
      formats: _statValues(value['formats'], 'format'),
      statuses: _statValues(value['statuses'], 'status'),
      countries: _statValues(value['countries'], 'country'),
    );
  }

  List<AniListStatisticValue> _statValues(Object? value, String labelKey) {
    if (value is! List<dynamic>) return const <AniListStatisticValue>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> json) => AniListStatisticValue(
            label: _string(json[labelKey], fallback: '—'),
            count: _int(json['count']),
            meanScore: (_num(json['meanScore']) ?? 0).toDouble(),
            minutesWatched: _int(json['minutesWatched']),
            chaptersRead: _int(json['chaptersRead']),
            value: _int(json['score'] ?? json['length']),
          ),
        )
        .toList(growable: false);
  }

  AniListUserSnippet _userSnippetFromJson(Map<String, dynamic> json) {
    return AniListUserSnippet(
      id: _int(json['id']),
      name: _string(json['name'], fallback: 'AniList User'),
      avatarUrl: _nestedString(json, const <String>['avatar', 'large']),
    );
  }

  AniListActivity _activityFromJson(Map<String, dynamic> json) {
    final String type = _string(json['type'], fallback: 'TEXT');
    final AniListUserSnippet primaryUser = switch (type) {
      'MESSAGE' => _userSnippetFromJson(
        json['messenger'] is Map<String, dynamic>
            ? json['messenger'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      _ => _userSnippetFromJson(
        json['user'] is Map<String, dynamic>
            ? json['user'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
    };
    final AniListUserSnippet? secondaryUser = type == 'MESSAGE'
        ? _userSnippetFromJson(
            json['recipient'] is Map<String, dynamic>
                ? json['recipient'] as Map<String, dynamic>
                : const <String, dynamic>{},
          )
        : null;
    final MediaItem? media = json['media'] is Map<String, dynamic>
        ? _mediaFromJson(json['media'] as Map<String, dynamic>)
        : null;
    return AniListActivity(
      id: _int(json['id']),
      type: type,
      primaryUser: primaryUser,
      secondaryUser: secondaryUser,
      media: media,
      text: _stripHtml(
        _string(json['text'], fallback: _string(json['message'])),
      ),
      progressLabel: _string(json['progress']),
      statusLabel: _string(json['status']),
      replyCount: _int(json['replyCount']),
      likeCount: _int(json['likeCount']),
      isLiked: json['isLiked'] == true,
      isSubscribed: json['isSubscribed'] == true,
      isPinned: json['isPinned'] == true,
      isPrivate: json['isPrivate'] == true,
      createdAt: _epochToDateTime(_int(json['createdAt'])),
      siteUrl: _string(json['siteUrl']),
    );
  }

  bool _pageHasNext(Object? value) {
    return value is Map<String, dynamic> && value['hasNextPage'] == true;
  }

  int? _pageTotal(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final int total = _int(value['total']);
    return total == 0 ? null : total;
  }

  static const Set<String> _keptRelationTypes = <String>{
    'PREQUEL',
    'SEQUEL',
    'SIDE_STORY',
    'SPIN_OFF',
  };
  static const Set<String> _keptFormats = <String>{'MOVIE', 'OVA', 'SPECIAL'};

  List<MediaSeason> _relationsFromJson(Map<String, dynamic> json) {
    final Object? relations = json['relations'];
    if (relations is! Map<String, dynamic>) return const <MediaSeason>[];
    final Object? edges = relations['edges'];
    if (edges is! List<dynamic>) return const <MediaSeason>[];
    int index = 0;
    return edges
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> edge) {
          final Object? node = edge['node'];
          if (node is! Map<String, dynamic>) return null;
          final int relatedId = _int(node['id']);
          if (relatedId <= 0) return null;
          if (_string(node['type'], fallback: 'ANIME') == 'MANGA') return null;

          final String relType = _string(edge['relationType']);
          final String format = _string(node['format']);
          if (!_keptRelationTypes.contains(relType) &&
              !_keptFormats.contains(format)) {
            return null;
          }

          final int relatedMalId = _int(node['idMal']);
          final String english = _nestedString(node, const <String>[
            'title',
            'english',
          ]);
          final String romaji = _nestedString(node, const <String>[
            'title',
            'romaji',
          ]);
          final String native = _nestedString(node, const <String>[
            'title',
            'native',
          ]);
          final String name = english.isNotEmpty
              ? english
              : romaji.isNotEmpty
              ? romaji
              : native;

          final Object? startDate = _nested(node, const <String>['startDate']);
          final int year = startDate is Map ? _int(startDate['year']) : 0;
          final int rawScore = _int(node['averageScore']);
          final double rating = rawScore > 0 ? rawScore / 10.0 : 0.0;

          index += 1;
          return MediaSeason(
            seasonNumber: index,
            name: name,
            episodeCount: _int(node['episodes']),
            posterUrl: _nestedString(node, const <String>[
              'coverImage',
              'extraLarge',
            ]),
            overview: _stripHtml(_string(node['description'])),
            originalName: native,
            aliases: <String>[
              if (romaji.isNotEmpty) romaji,
              if (english.isNotEmpty) english,
              if (native.isNotEmpty) native,
            ],
            externalIds: <String, String>{
              'anilist': relatedId.toString(),
              if (relatedMalId > 0) 'mal': relatedMalId.toString(),
            },
            year: year,
            rating: rating,
            format: format,
            relationType: relType,
          );
        })
        .whereType<MediaSeason>()
        .toList(growable: false);
  }

  static const String _mediaFields = '''
    id
    idMal
    type
    title { romaji english native }
    description(asHtml: false)
    coverImage { extraLarge large color }
    bannerImage
    averageScore
    genres
    synonyms
    episodes
    chapters
    volumes
    duration
    trailer { id site thumbnail }
    status
    isFavourite
    source
    isAdult
    isLicensed
    startDate { year }
    siteUrl
  ''';

  // Leaner field set for library collection queries — omits heavy per-entry fields
  // (description, synonyms, bannerImage) that are only needed on detail pages.
  // Keeps response size manageable for users with large libraries (500+ entries).
  static const String _collectionMediaFields = '''
    id
    idMal
    type
    title { romaji english native }
    coverImage { extraLarge large color }
    averageScore
    genres
    episodes
    chapters
    volumes
    duration
    status
    isFavourite
    source
    isAdult
    isLicensed
    tags { name rank isGeneralSpoiler isMediaSpoiler category }
    startDate { year }
    siteUrl
  ''';

  static const String _mediaDetailsFields = '''
    id
    idMal
    type
    format
    title { romaji english native }
    description(asHtml: false)
    coverImage { extraLarge large color }
    bannerImage
    averageScore
    genres
    synonyms
    episodes
    chapters
    volumes
    duration
    status
    isFavourite
    isAdult
    isLicensed
    source
    season
    seasonYear
    countryOfOrigin
    popularity
    favourites
    startDate { year month day }
    endDate { year month day }
    siteUrl
    studios { nodes { id name isAnimationStudio } }
    tags { name rank isGeneralSpoiler isMediaSpoiler category }
    relations {
      edges {
        relationType(version: 2)
        node {
          id
          idMal
          type
          format
          title { romaji english native }
          description(asHtml: false)
          coverImage { extraLarge large }
          averageScore
          episodes
          duration
          status
          startDate { year }
        }
      }
    }
  ''';

  static String _humanizeKind(String value) {
    final String lower = value.toLowerCase();
    return lower.isEmpty
        ? 'Entity'
        : '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  static String _stripHtml(String value) {
    return value.replaceAll(RegExp('<[^>]*>'), '').replaceAll('&amp;', '&');
  }

  static Object? _nested(Map<String, dynamic> json, List<String> keys) {
    Object? current = json;
    for (final String key in keys) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[key];
    }
    return current;
  }

  static String _nestedString(Map<String, dynamic> json, List<String> keys) {
    return _string(_nested(json, keys));
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static num? _num(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) {
      return <String>[];
    }
    return value.whereType<String>().toList();
  }

  static List<String> _namedStringList(Object? value, String key) {
    if (value is! List<dynamic>) return const <String>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> item) => _string(item[key]))
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _nestedNamedStringList(Object? value, List<String> keys) {
    if (value is! List<dynamic>) return const <String>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> item) => _nestedString(item, keys))
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
