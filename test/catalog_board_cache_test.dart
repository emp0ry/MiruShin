import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:mirushin/features/catalog/application/catalog_repository.dart';
import 'package:mirushin/features/metadata/application/media_catalog.dart';
import 'package:mirushin/features/metadata/data/tmdb_metadata_provider.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:mirushin/features/tracking/data/mal_api_client.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('logical media pages preserve exact row-sized boundaries', () async {
    final List<int> requestedPages = <int>[];
    final List<MediaItem> secondPage = await loadLogicalMediaPage(
      page: 2,
      pageSize: 24,
      fetchPage: (int page) async {
        requestedPages.add(page);
        if (page > 3) return const <MediaItem>[];
        return _items(
          'page',
          MediaType.anime,
          start: (page - 1) * 20,
          count: 20,
        );
      },
    );

    expect(requestedPages, <int>[1, 2, 3]);
    expect(secondPage, hasLength(24));
    expect(secondPage.first.id, 'page:24');
    expect(secondPage.last.id, 'page:47');
  });

  group('board metadata cache', () {
    test(
      'TMDB shows the previous snapshot immediately and saves the refresh for '
      'the next launch',
      () async {
        final _RecordingCacheStore cache = _RecordingCacheStore();
        final TmdbCatalogRepository firstLaunch = TmdbCatalogRepository(
          tmdb: _ImmediateTmdbProvider('cached'),
          cache: cache,
          cacheScope: 'test.tmdb',
        );

        final BoardRails initial = await firstLaunch.boardRails();
        expect(initial.recentMovies, hasLength(24));
        expect(initial.recentMovies.first.title, 'cached-recent-movie 0');
        expect(initial.recentSeries, hasLength(24));
        expect(initial.topAnime, hasLength(24));
        expect(initial.topAnime.first.title, 'cached-anime 0');

        final _BlockingTmdbProvider refreshProvider = _BlockingTmdbProvider();
        final Future<void> refreshWritten = cache.nextWrite;
        final BoardRails shown = await TmdbCatalogRepository(
          tmdb: refreshProvider,
          cache: cache,
          cacheScope: 'test.tmdb',
        ).boardRails();

        expect(shown.topAnime.first.title, 'cached-anime 0');
        expect(refreshProvider.callCount, 3);
        expect(refreshProvider.recentMoviesRequested, isTrue);

        refreshProvider.complete('fresh');
        await refreshWritten.timeout(const Duration(seconds: 1));

        final Map<String, dynamic>? stored = await cache.read(
          'test.tmdb.board',
        );
        final List<dynamic> storedAnime = stored!['topAnime'] as List<dynamic>;
        expect(storedAnime, hasLength(24));
        expect(
          (storedAnime.first as Map<String, dynamic>)['title'],
          'fresh-anime 0',
        );
        expect(
          (storedAnime.first as Map<String, dynamic>)['runtimeMinutes'],
          24,
        );
        expect(
          (storedAnime.first as Map<String, dynamic>)['trailer'],
          isA<Map<String, dynamic>>(),
        );

        final _BlockingTmdbProvider nextRefreshProvider =
            _BlockingTmdbProvider();
        final BoardRails nextLaunch = await TmdbCatalogRepository(
          tmdb: nextRefreshProvider,
          cache: cache,
          cacheScope: 'test.tmdb',
        ).boardRails();

        expect(nextLaunch.topAnime.first.title, 'fresh-anime 0');
        expect(nextLaunch.topAnime.first.runtimeMinutes, 24);
        expect(nextLaunch.topAnime.first.trailer?.id, 'trailer-0');
        expect(nextRefreshProvider.callCount, 3);
      },
    );

    test('AniList uses the same 24-item next-launch snapshot policy', () async {
      final _RecordingCacheStore cache = _RecordingCacheStore();
      final AniListCatalogRepository firstLaunch = AniListCatalogRepository(
        client: _ImmediateAniListClient('cached'),
        cache: cache,
        cacheScope: 'test.anilist',
      );

      final BoardRails initial = await firstLaunch.boardRails();
      expect(initial.recentMovies, hasLength(24));
      expect(initial.recentSeries, hasLength(24));
      expect(initial.topAnime, hasLength(24));
      expect(initial.topAnime.first.title, 'cached-top 0');
      expect(
        initial.additionalSections.keys,
        containsAll(<String>[
          'Favorites',
          'Airing',
          'Upcoming',
          'Finished',
          'Newest',
          'Recently Updated',
        ]),
      );
      expect(initial.additionalSections.values, everyElement(hasLength(24)));

      final _BlockingAniListClient refreshClient = _BlockingAniListClient();
      final Future<void> refreshWritten = cache.nextWrite;
      final BoardRails shown = await AniListCatalogRepository(
        client: refreshClient,
        cache: cache,
        cacheScope: 'test.anilist',
      ).boardRails();

      expect(shown.topAnime.first.title, 'cached-top 0');
      await Future<void>.delayed(Duration.zero);
      expect(refreshClient.callCount, 1);

      refreshClient.complete('fresh');
      await refreshWritten.timeout(const Duration(seconds: 1));
      expect(refreshClient.callCount, 9);
      expect(refreshClient.requestedFilters, <String>[
        'Top Rated',
        'Favorites',
        'Airing',
        'Upcoming',
        'Finished',
        'Newest',
        'Recently Updated',
      ]);

      final Map<String, dynamic>? stored = await cache.read(
        'test.anilist.board.public',
      );
      final List<dynamic> storedAnime = stored!['topAnime'] as List<dynamic>;
      expect(storedAnime, hasLength(24));
      final Map<String, dynamic> storedSections =
          stored['additionalSections'] as Map<String, dynamic>;
      expect(storedSections, hasLength(6));
      expect(storedSections['Favorites'], hasLength(24));
      expect(
        (storedAnime.first as Map<String, dynamic>)['title'],
        'fresh-top 0',
      );
    });
  });

  group('details metadata cache', () {
    test(
      'TMDB restores the complete details page before refreshing it',
      () async {
        final _RecordingCacheStore cache = _RecordingCacheStore();
        const String id = 'tmdb:movie:42';
        final MediaItem? firstLoad = await TmdbCatalogRepository(
          tmdb: _ImmediateDetailsTmdbProvider('cached'),
          cache: cache,
          cacheScope: 'test.tmdb',
        ).details(id);

        expect(firstLoad?.overview, 'cached overview');
        expect(firstLoad?.posterUrl, 'https://example.com/cached-poster.jpg');
        expect(
          firstLoad?.backdropUrl,
          'https://example.com/cached-backdrop.jpg',
        );
        expect(firstLoad?.seasons.single.name, 'cached season');

        final _BlockingDetailsTmdbProvider refresh =
            _BlockingDetailsTmdbProvider();
        final Future<void> refreshWritten = cache.nextWrite;
        final MediaItem? restored = await TmdbCatalogRepository(
          tmdb: refresh,
          cache: cache,
          cacheScope: 'test.tmdb',
        ).details(id);

        expect(restored?.title, 'cached title');
        expect(restored?.originalTitle, 'cached original title');
        expect(restored?.genres, const <String>['Drama', 'Mystery']);
        expect(restored?.statusLabel, 'RELEASING');
        expect(restored?.aliases, const <String>['cached alias']);
        expect(restored?.trailer?.id, 'cached-trailer');
        expect(refresh.callCount, 1);

        refresh.complete(_detailsItem('fresh', id));
        await refreshWritten.timeout(const Duration(seconds: 1));

        final _BlockingDetailsTmdbProvider nextRefresh =
            _BlockingDetailsTmdbProvider();
        final MediaItem? nextLaunch = await TmdbCatalogRepository(
          tmdb: nextRefresh,
          cache: cache,
          cacheScope: 'test.tmdb',
        ).details(id);
        expect(nextLaunch?.title, 'fresh title');
        expect(nextLaunch?.seasons.single.overview, 'fresh season overview');
        expect(nextRefresh.callCount, 1);
      },
    );

    test('AniList details use the same cache-first restart policy', () async {
      final _RecordingCacheStore cache = _RecordingCacheStore();
      const String id = 'anilist:42';
      await AniListCatalogRepository(
        client: _ImmediateDetailsAniListClient('cached'),
        cache: cache,
        cacheScope: 'test.anilist',
      ).details(id);

      final _BlockingDetailsAniListClient refresh =
          _BlockingDetailsAniListClient();
      final MediaItem? restored = await AniListCatalogRepository(
        client: refresh,
        cache: cache,
        cacheScope: 'test.anilist',
      ).details(id);

      expect(restored?.title, 'cached title');
      expect(restored?.overview, 'cached overview');
      expect(restored?.seasons.single.episodeCount, 12);
      expect(refresh.callCount, 1);
    });
  });

  group('AniList MAL fallback', () {
    test('cold Board falls back to MAL rankings after AniList fails', () async {
      final _FallbackMalClient mal = _FallbackMalClient();
      final _FailingAniListClient aniList = _FailingAniListClient();
      final List<Object> primaryFailures = <Object>[];
      final BoardRails rails = await AniListCatalogRepository(
        client: aniList,
        malFallback: mal,
        cache: _RecordingCacheStore(),
        cacheScope: 'test.anilist.fallback',
        onPrimaryFailure: primaryFailures.add,
      ).boardRails();

      expect(rails.topAnime, hasLength(24));
      expect(rails.topAnime.first.id, startsWith('mal:'));
      expect(rails.topAnime.first.sourceProvider, 'MyAnimeList');
      expect(mal.requestedRankings, hasLength(9));
      expect(primaryFailures, hasLength(1));
      expect(aniList.callCount, 1);
    });

    test(
      'Discovery search and MAL details stay usable during outage',
      () async {
        final _FallbackMalClient mal = _FallbackMalClient();
        final AniListCatalogRepository repository = AniListCatalogRepository(
          client: _FailingAniListClient(),
          malFallback: mal,
          cache: _RecordingCacheStore(),
          cacheScope: 'test.anilist.fallback',
        );

        final List<MediaItem> results = await repository.discover(
          search: 'Fullmetal Alchemist',
          type: MediaType.anime,
          filter: 'Trending',
          page: 1,
        );
        final MediaItem? details = await repository.details(results.single.id);

        expect(results.single.id, 'mal:5114');
        expect(details?.id, 'mal:5114');
        expect(details?.overview, isNotEmpty);
        expect(catalogModeForMediaId('mal:5114'), CatalogMode.anilist);
        expect(mediaIdBelongsToMode('mal:5114', CatalogMode.anilist), isTrue);
      },
    );

    test(
      'known AniList identity resolves to MAL details during outage',
      () async {
        final AniListCatalogRepository repository = AniListCatalogRepository(
          client: _FailingAniListClient(),
          malFallback: _FallbackMalClient(),
          resolveMalId: (String mediaId) async =>
              mediaId == 'anilist:anime:21' ? 5114 : null,
          cache: _RecordingCacheStore(),
          cacheScope: 'test.anilist.identity-fallback',
        );

        final MediaItem? details = await repository.details('anilist:anime:21');

        expect(details?.id, 'mal:5114');
        expect(details?.sourceProvider, 'MyAnimeList');
      },
    );
  });
}

class _RecordingCacheStore extends MetadataCacheStore {
  final Map<String, Map<String, dynamic>> _values =
      <String, Map<String, dynamic>>{};
  Completer<void>? _pendingWrite;

  Future<void> get nextWrite {
    final Completer<void> completer = Completer<void>();
    _pendingWrite = completer;
    return completer.future;
  }

  @override
  Future<Map<String, dynamic>?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    _values[key] = value;
    final Completer<void>? pendingWrite = _pendingWrite;
    _pendingWrite = null;
    if (pendingWrite != null && !pendingWrite.isCompleted) {
      pendingWrite.complete();
    }
  }
}

class _ImmediateTmdbProvider extends TmdbMetadataProvider {
  _ImmediateTmdbProvider(this.prefix) : super(readAccessToken: 'test');

  final String prefix;

  @override
  Future<List<MediaItem>> getRecentlyReleasedMovies({int page = 1}) async {
    return _items('$prefix-recent-movie', MediaType.movie);
  }

  @override
  Future<List<MediaItem>> getPopular(MediaType type, {int page = 1}) async {
    return _items('$prefix-${type.name}', type);
  }
}

class _BlockingTmdbProvider extends TmdbMetadataProvider {
  _BlockingTmdbProvider() : super(readAccessToken: 'test');

  final Map<MediaType, Completer<List<MediaItem>>> _requests =
      <MediaType, Completer<List<MediaItem>>>{
        for (final MediaType type in MediaType.values)
          type: Completer<List<MediaItem>>(),
      };
  int callCount = 0;
  bool recentMoviesRequested = false;

  @override
  Future<List<MediaItem>> getRecentlyReleasedMovies({int page = 1}) {
    callCount += 1;
    recentMoviesRequested = true;
    return _requests[MediaType.movie]!.future;
  }

  @override
  Future<List<MediaItem>> getPopular(MediaType type, {int page = 1}) {
    callCount += 1;
    return _requests[type]!.future;
  }

  void complete(String prefix) {
    for (final MediaType type in MediaType.values) {
      _requests[type]!.complete(_items('$prefix-${type.name}', type));
    }
  }
}

class _ImmediateDetailsTmdbProvider extends TmdbMetadataProvider {
  _ImmediateDetailsTmdbProvider(this.prefix) : super(readAccessToken: 'test');

  final String prefix;

  @override
  Future<MediaItem?> getDetails(String id) async => _detailsItem(prefix, id);
}

class _BlockingDetailsTmdbProvider extends TmdbMetadataProvider {
  _BlockingDetailsTmdbProvider() : super(readAccessToken: 'test');

  final Completer<MediaItem?> _request = Completer<MediaItem?>();
  int callCount = 0;

  @override
  Future<MediaItem?> getDetails(String id) {
    callCount += 1;
    return _request.future;
  }

  void complete(MediaItem item) => _request.complete(item);
}

class _ImmediateAniListClient extends AniListApiClient {
  _ImmediateAniListClient(this.prefix);

  final String prefix;

  @override
  Future<List<MediaItem>> getTrendingCatalog({
    required String kind,
    int page = 1,
    int perPage = 20,
  }) async => _items('$prefix-trending', MediaType.anime);

  @override
  Future<List<MediaItem>> getPopularCatalog({
    required String kind,
    int page = 1,
    int perPage = 20,
  }) async => _items('$prefix-popular', MediaType.anime);

  @override
  Future<List<MediaItem>> getFilteredCatalog({
    required String kind,
    required String filter,
    int page = 1,
    int perPage = 20,
  }) async => _items('$prefix-top', MediaType.anime);

  @override
  Future<MediaItem> enrichHeroOverview(MediaItem item) async => item;
}

class _BlockingAniListClient extends AniListApiClient {
  final Map<String, Completer<List<MediaItem>>> _requests =
      <String, Completer<List<MediaItem>>>{
        'trending': Completer<List<MediaItem>>(),
        'popular': Completer<List<MediaItem>>(),
        'top': Completer<List<MediaItem>>(),
      };
  int callCount = 0;
  final List<String> requestedFilters = <String>[];

  @override
  Future<List<MediaItem>> getTrendingCatalog({
    required String kind,
    int page = 1,
    int perPage = 20,
  }) {
    callCount += 1;
    return _requests['trending']!.future;
  }

  @override
  Future<List<MediaItem>> getPopularCatalog({
    required String kind,
    int page = 1,
    int perPage = 20,
  }) {
    callCount += 1;
    return _requests['popular']!.future;
  }

  @override
  Future<List<MediaItem>> getFilteredCatalog({
    required String kind,
    required String filter,
    int page = 1,
    int perPage = 20,
  }) {
    callCount += 1;
    requestedFilters.add(filter);
    return _requests['top']!.future;
  }

  @override
  Future<MediaItem> enrichHeroOverview(MediaItem item) async => item;

  void complete(String prefix) {
    _requests['trending']!.complete(
      _items('$prefix-trending', MediaType.anime),
    );
    _requests['popular']!.complete(_items('$prefix-popular', MediaType.anime));
    _requests['top']!.complete(_items('$prefix-top', MediaType.anime));
  }
}

class _ImmediateDetailsAniListClient extends AniListApiClient {
  _ImmediateDetailsAniListClient(this.prefix);

  final String prefix;

  @override
  Future<MediaItem?> getCatalogDetails(String id) async =>
      _detailsItem(prefix, id);
}

class _BlockingDetailsAniListClient extends AniListApiClient {
  final Completer<MediaItem?> _request = Completer<MediaItem?>();
  int callCount = 0;

  @override
  Future<MediaItem?> getCatalogDetails(String id) {
    callCount += 1;
    return _request.future;
  }
}

class _FailingAniListClient extends AniListApiClient {
  int callCount = 0;

  Future<T> _failure<T>() {
    callCount += 1;
    return Future<T>.error(StateError('AniList outage'));
  }

  @override
  Future<List<MediaItem>> getTrendingCatalog({
    required String kind,
    int page = 1,
    int perPage = 20,
  }) => _failure<List<MediaItem>>();

  @override
  Future<List<MediaItem>> getPopularCatalog({
    required String kind,
    int page = 1,
    int perPage = 20,
  }) => _failure<List<MediaItem>>();

  @override
  Future<List<MediaItem>> getFilteredCatalog({
    required String kind,
    required String filter,
    int page = 1,
    int perPage = 20,
  }) => _failure<List<MediaItem>>();

  @override
  Future<List<MediaItem>> searchCatalog({
    required String kind,
    required String query,
    int page = 1,
    int perPage = 20,
  }) => _failure<List<MediaItem>>();

  @override
  Future<MediaItem?> getCatalogDetails(String id) => _failure<MediaItem?>();
}

class _FallbackMalClient extends MalApiClient {
  _FallbackMalClient() : super(accessToken: 'test');

  final List<String> requestedRankings = <String>[];

  @override
  Future<List<MediaItem>> fetchAnimeRanking({
    required String rankingType,
    int page = 1,
    int pageSize = 20,
  }) async {
    requestedRankings.add(rankingType);
    return List<MediaItem>.generate(
      pageSize,
      (int index) => _malItem(index + 1, title: '$rankingType $index'),
      growable: false,
    );
  }

  @override
  Future<List<MediaItem>> searchAnime(
    String query, {
    int page = 1,
    int pageSize = 20,
  }) async => <MediaItem>[_malItem(5114, title: 'Fullmetal Alchemist')];

  @override
  Future<MediaItem?> fetchAnimeDetails(int malId) async =>
      _malItem(malId, title: 'Fullmetal Alchemist', details: true);
}

MediaItem _malItem(int malId, {required String title, bool details = false}) {
  return MediaItem(
    id: 'mal:$malId',
    title: title,
    originalTitle: '鋼の錬金術師',
    overview: details ? 'MAL fallback details' : '',
    type: MediaType.anime,
    year: 2009,
    posterUrl: 'https://example.com/mal-$malId.jpg',
    backdropUrl: '',
    rating: 9.1,
    genres: const <String>['Action'],
    sourceProvider: 'MyAnimeList',
    externalIds: <String, String>{'mal': '$malId'},
    episodeCount: 64,
    statusLabel: 'FINISHED_AIRING',
  );
}

MediaItem _detailsItem(String prefix, String id) {
  return MediaItem(
    id: id,
    title: '$prefix title',
    originalTitle: '$prefix original title',
    overview: '$prefix overview',
    type: MediaType.anime,
    year: 2026,
    posterUrl: 'https://example.com/$prefix-poster.jpg',
    backdropUrl: 'https://example.com/$prefix-backdrop.jpg',
    rating: 9.1,
    genres: const <String>['Drama', 'Mystery'],
    sourceProvider: 'test',
    externalIds: const <String, String>{'anilist': '42', 'tmdb': '84'},
    runtimeMinutes: 24,
    episodeCount: 12,
    seasons: <MediaSeason>[
      MediaSeason(
        seasonNumber: 1,
        name: '$prefix season',
        episodeCount: 12,
        posterUrl: 'https://example.com/$prefix-season.jpg',
        overview: '$prefix season overview',
      ),
    ],
    statusLabel: 'RELEASING',
    aliases: <String>['$prefix alias'],
    originalLanguage: 'ja',
    trailer: MediaTrailer(id: '$prefix-trailer', site: 'youtube'),
  );
}

List<MediaItem> _items(
  String prefix,
  MediaType type, {
  int start = 0,
  int count = 25,
}) {
  return List<MediaItem>.generate(count, (int offset) {
    final int index = start + offset;
    return MediaItem(
      id: '$prefix:$index',
      title: '$prefix $index',
      originalTitle: 'Original $index',
      overview: 'Overview $index',
      type: type,
      year: 2026,
      posterUrl: 'https://example.com/poster-$index.jpg',
      backdropUrl: 'https://example.com/backdrop-$index.jpg',
      rating: 8.5,
      genres: const <String>['Animation'],
      sourceProvider: 'test',
      externalIds: <String, String>{'test': index.toString()},
      runtimeMinutes: 24 + index,
      episodeCount: 12,
      seasons: <MediaSeason>[
        MediaSeason(
          seasonNumber: 1,
          name: 'Season 1',
          episodeCount: 12,
          posterUrl: '',
          overview: '',
        ),
      ],
      statusLabel: 'RELEASING',
      aliases: <String>['Alias $index'],
      originalLanguage: 'ja',
      trailer: MediaTrailer(id: 'trailer-$index', site: 'youtube'),
    );
  }, growable: false);
}
