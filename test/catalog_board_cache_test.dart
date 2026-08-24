import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/catalog/application/catalog_repository.dart';
import 'package:mirushin/features/metadata/application/media_catalog.dart';
import 'package:mirushin/features/metadata/data/tmdb_metadata_provider.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
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
        expect(initial.recentMovies, hasLength(20));
        expect(initial.recentMovies.first.title, 'cached-recent-movie 0');
        expect(initial.recentSeries, hasLength(20));
        expect(initial.topAnime, hasLength(20));
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
        expect(storedAnime, hasLength(20));
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

    test('AniList uses the same 20-item next-launch snapshot policy', () async {
      final _RecordingCacheStore cache = _RecordingCacheStore();
      final AniListCatalogRepository firstLaunch = AniListCatalogRepository(
        client: _ImmediateAniListClient('cached'),
        cache: cache,
        cacheScope: 'test.anilist',
      );

      final BoardRails initial = await firstLaunch.boardRails();
      expect(initial.recentMovies, hasLength(20));
      expect(initial.recentSeries, hasLength(20));
      expect(initial.topAnime, hasLength(20));
      expect(initial.topAnime.first.title, 'cached-top 0');

      final _BlockingAniListClient refreshClient = _BlockingAniListClient();
      final Future<void> refreshWritten = cache.nextWrite;
      final BoardRails shown = await AniListCatalogRepository(
        client: refreshClient,
        cache: cache,
        cacheScope: 'test.anilist',
      ).boardRails();

      expect(shown.topAnime.first.title, 'cached-top 0');
      await Future<void>.delayed(Duration.zero);
      expect(refreshClient.callCount, 3);

      refreshClient.complete('fresh');
      await refreshWritten.timeout(const Duration(seconds: 1));

      final Map<String, dynamic>? stored = await cache.read(
        'test.anilist.board.public',
      );
      final List<dynamic> storedAnime = stored!['topAnime'] as List<dynamic>;
      expect(storedAnime, hasLength(20));
      expect(
        (storedAnime.first as Map<String, dynamic>)['title'],
        'fresh-top 0',
      );
    });
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

class _ImmediateAniListClient extends AniListApiClient {
  _ImmediateAniListClient(this.prefix);

  final String prefix;

  @override
  Future<List<MediaItem>> getTrendingCatalog({
    required String kind,
    int page = 1,
  }) async => _items('$prefix-trending', MediaType.anime);

  @override
  Future<List<MediaItem>> getPopularCatalog({
    required String kind,
    int page = 1,
  }) async => _items('$prefix-popular', MediaType.anime);

  @override
  Future<List<MediaItem>> getFilteredCatalog({
    required String kind,
    required String filter,
    int page = 1,
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

  @override
  Future<List<MediaItem>> getTrendingCatalog({
    required String kind,
    int page = 1,
  }) {
    callCount += 1;
    return _requests['trending']!.future;
  }

  @override
  Future<List<MediaItem>> getPopularCatalog({
    required String kind,
    int page = 1,
  }) {
    callCount += 1;
    return _requests['popular']!.future;
  }

  @override
  Future<List<MediaItem>> getFilteredCatalog({
    required String kind,
    required String filter,
    int page = 1,
  }) {
    callCount += 1;
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

List<MediaItem> _items(String prefix, MediaType type) {
  return List<MediaItem>.generate(
    25,
    (int index) => MediaItem(
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
    ),
    growable: false,
  );
}
