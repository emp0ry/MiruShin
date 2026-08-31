import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/media_details/application/fanart_gallery_provider.dart';
import 'package:mirushin/features/media_details/data/fanart_tv_client.dart';
import 'package:mirushin/features/media_details/domain/fanart_gallery.dart';
import 'package:mirushin/features/metadata/data/tmdb_metadata_provider.dart';
import 'package:mirushin/features/metadata/domain/tmdb_media_identity.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('runtime Fanart.tv API key overrides the optional build key', () {
    const SettingsState settings = SettingsState(
      fanartTvApiKey: '  user-project-key  ',
    );

    expect(settings.effectiveFanartTvApiKey, 'user-project-key');
    expect(settings.hasFanartTvApiKey, isTrue);
  });

  group('FanartBackground', () {
    test('parses v3.2 string dimensions and original URL', () {
      final FanartBackground image =
          FanartBackground.fromJson(<String, dynamic>{
            'id': '42',
            'url': 'https://assets.fanart.tv/image.jpg?source=api',
            'width': '3840',
            'height': '2160',
            'likes': '17',
            'lang': '00',
            'added': '2026-01-02T03:04:05Z',
          });

      expect(image.width, 3840);
      expect(image.height, 2160);
      expect(image.likes, 17);
      expect(image.is4K, isTrue);
      expect(image.url, 'https://assets.fanart.tv/image.jpg?source=api');
      expect(image.added, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });
  });

  group('FanartGallery classification', () {
    test('classifies UHD widths and keeps lower resolutions regular', () {
      final FanartGallery gallery =
          FanartGallery.fromBackgrounds(<FanartBackground>[
            _background('uhd', 3840, 2160),
            _background('cinema', 4096, 2160),
            _background('full-hd', 1920, 1080),
            _background('quad-hd', 2560, 1440),
          ]);

      expect(
        gallery.fourKBackgrounds.map((FanartBackground image) => image.id),
        containsAll(<String>['uhd', 'cinema']),
      );
      expect(
        gallery.backgrounds.map((FanartBackground image) => image.id),
        containsAll(<String>['full-hd', 'quad-hd']),
      );
      expect(
        gallery.backgrounds.any((FanartBackground image) => image.is4K),
        isFalse,
      );
      expect(gallery.allBackgrounds.length, 4);
    });

    test('filters portrait, malformed, and duplicate artwork', () {
      final FanartGallery gallery =
          FanartGallery.fromBackgrounds(<FanartBackground>[
            _background('valid', 1920, 1080),
            _background('valid', 1920, 1080),
            _background(
              'duplicate-url',
              2560,
              1440,
              url: 'https://assets.fanart.tv/valid.jpg',
            ),
            _background('portrait', 1080, 1920),
            _background('broken', 0, 0),
          ]);

      expect(gallery.allBackgrounds, hasLength(1));
      expect(gallery.allBackgrounds.single.id, 'valid');
    });
  });

  group('FanartIdentityResolver', () {
    test('uses a TMDB movie ID directly', () async {
      bool resolvedTvdb = false;
      final FanartIdentityResolver resolver = FanartIdentityResolver(
        resolveTmdbTvdbId: (int id) async {
          resolvedTvdb = true;
          return 9;
        },
      );

      final FanartIdentity? identity = await resolver.resolve(
        _media(
          id: 'tmdb:movie:550',
          type: MediaType.movie,
          externalIds: const <String, String>{
            'tmdb': '550',
            'tmdb_media_type': 'movie',
          },
        ),
      );

      expect(
        identity,
        const FanartIdentity(id: 550, kind: FanartMediaKind.movie),
      );
      expect(resolvedTvdb, isFalse);
    });

    test('resolves TMDB TV through external_ids.tvdb_id', () async {
      int? requestedTmdbId;
      final FanartIdentityResolver resolver = FanartIdentityResolver(
        resolveTmdbTvdbId: (int id) async {
          requestedTmdbId = id;
          return 81189;
        },
      );

      final FanartIdentity? identity = await resolver.resolve(
        _media(
          id: 'tmdb:tv:1399',
          type: MediaType.series,
          externalIds: const <String, String>{
            'tmdb': '1399',
            'tmdb_media_type': 'tv',
          },
        ),
      );

      expect(requestedTmdbId, 1399);
      expect(
        identity,
        const FanartIdentity(id: 81189, kind: FanartMediaKind.tv),
      );
    });

    test('uses the existing AniList to TMDB resolver', () async {
      int calls = 0;
      final FanartIdentityResolver resolver = FanartIdentityResolver(
        resolveAnimeTmdbIdentity: (MediaItem item) async {
          calls += 1;
          return const TmdbMediaIdentity(id: 372058, kind: TmdbMediaKind.movie);
        },
      );

      final FanartIdentity? identity = await resolver.resolve(
        _media(
          id: 'anilist:1',
          type: MediaType.anime,
          externalIds: const <String, String>{'anilist': '1'},
        ),
      );

      expect(calls, 1);
      expect(
        identity,
        const FanartIdentity(id: 372058, kind: FanartMediaKind.movie),
      );
    });

    test('returns no identity when AniList mapping is missing', () async {
      final FanartIdentityResolver resolver = FanartIdentityResolver(
        resolveAnimeTmdbIdentity: (MediaItem item) async => null,
      );
      expect(
        await resolver.resolve(
          _media(
            id: 'anilist:2',
            type: MediaType.anime,
            externalIds: const <String, String>{'anilist': '2'},
          ),
        ),
        isNull,
      );
    });

    test('returns no identity when a TMDB TV item has no TVDB ID', () async {
      final FanartIdentityResolver resolver = FanartIdentityResolver(
        resolveTmdbTvdbId: (int id) async => null,
      );
      expect(
        await resolver.resolve(
          _media(
            id: 'tmdb:tv:10',
            type: MediaType.series,
            externalIds: const <String, String>{
              'tmdb': '10',
              'tmdb_media_type': 'tv',
            },
          ),
        ),
        isNull,
      );
    });
  });

  group('FanartTvClient', () {
    test('reads movie4kbackground before moviebackground', () async {
      late RequestOptions request;
      final Dio dio = _respondingDio(
        (RequestOptions value) => request = value,
        <String, dynamic>{
          'movie4kbackground': <Map<String, String>>[
            <String, String>{
              'id': 'movie-4k-art',
              'url': 'https://assets.fanart.tv/movie-4k.jpg',
              'width': '3840',
              'height': '2160',
              'likes': '8',
              'lang': '00',
            },
          ],
          'moviebackground': <Map<String, String>>[
            <String, String>{
              'id': 'movie-art',
              'url': 'https://assets.fanart.tv/movie.jpg',
              'width': '1920',
              'height': '1080',
              'likes': '5',
              'lang': '00',
            },
          ],
        },
      );
      final FanartGallery gallery =
          await FanartTvClient(apiKey: 'project-key', dio: dio).fetchGallery(
            const FanartIdentity(id: 550, kind: FanartMediaKind.movie),
          );

      expect(request.path, '/movies/550');
      expect(request.baseUrl, 'https://webservice.fanart.tv/v3.2');
      expect(
        request.uri.toString(),
        'https://webservice.fanart.tv/v3.2/movies/550',
      );
      expect(request.headers['api-key'], 'project-key');
      expect(gallery.fourKBackgrounds.single.id, 'movie-4k-art');
      expect(gallery.backgrounds.single.id, 'movie-art');
    });

    test('reads show4kbackground before showbackground', () async {
      late RequestOptions request;
      final Dio dio = _respondingDio(
        (RequestOptions value) => request = value,
        <String, dynamic>{
          'show4kbackground': <Map<String, String>>[
            <String, String>{
              'id': 'tv-4k-art',
              'url': 'https://assets.fanart.tv/tv-4k.jpg',
              'width': '3840',
              'height': '2160',
              'likes': '7',
              'lang': '00',
            },
          ],
          'showbackground': <Map<String, String>>[
            <String, String>{
              'id': 'tv-art',
              'url': 'https://assets.fanart.tv/tv.jpg',
              'width': '1920',
              'height': '1080',
              'likes': '5',
              'lang': '00',
            },
          ],
        },
      );
      final FanartGallery gallery = await FanartTvClient(
        apiKey: 'project-key',
        dio: dio,
      ).fetchGallery(const FanartIdentity(id: 81189, kind: FanartMediaKind.tv));

      expect(request.path, '/tv/81189');
      expect(gallery.fourKBackgrounds.single.id, 'tv-4k-art');
      expect(gallery.backgrounds.single.id, 'tv-art');
    });

    test('normalizes an empty Fanart response to an empty Gallery', () async {
      final FanartGallery gallery = await FanartTvClient(
        apiKey: 'project-key',
        dio: _respondingDio((_) {}, <String, dynamic>{}),
      ).fetchGallery(const FanartIdentity(id: 1, kind: FanartMediaKind.movie));
      expect(gallery.isEmpty, isTrue);
    });
  });

  test('TMDB client reads tvdb_id from the external IDs endpoint', () async {
    late RequestOptions request;
    final TmdbMetadataProvider tmdb = TmdbMetadataProvider(
      readAccessToken: 'token',
      dio: _respondingDio(
        (RequestOptions value) => request = value,
        <String, dynamic>{'tvdb_id': '81189'},
        baseUrl: 'https://api.themoviedb.org/3',
      ),
    );

    expect(await tmdb.tvdbIdForTmdbTv(1399), 81189);
    expect(request.path, '/tv/1399/external_ids');
  });

  test('existing TMDB matcher resolves an AniList movie', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.themoviedb.org/3'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final Object data = options.path == '/search/movie'
              ? <String, dynamic>{
                  'results': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 372058,
                      'title': 'Your Name',
                      'original_title': 'Kimi no Na wa',
                      'release_date': '2016-08-26',
                      'genre_ids': <int>[16],
                      'vote_average': 8.5,
                    },
                  ],
                }
              : <String, dynamic>{'results': <Object>[]};
          handler.resolve(
            Response<Object>(
              requestOptions: options,
              statusCode: 200,
              data: data,
            ),
          );
        },
      ),
    );
    final TmdbMetadataProvider tmdb = TmdbMetadataProvider(
      readAccessToken: 'token',
      dio: dio,
    );

    final TmdbMediaIdentity? identity = await tmdb.resolveAnimeTmdbIdentity(
      _media(
        id: 'anilist:21519',
        type: MediaType.anime,
        title: 'Your Name',
        originalTitle: 'Kimi no Na wa',
        year: 2016,
        externalIds: const <String, String>{
          'anilist': '21519',
          'anilist_format': 'MOVIE',
        },
      ),
    );

    expect(
      identity,
      const TmdbMediaIdentity(id: 372058, kind: TmdbMediaKind.movie),
    );
  });

  test('repository deduplicates simultaneous requests for one media', () async {
    final _CountingFanartClient client = _CountingFanartClient();
    final FanartGalleryRepository repository = FanartGalleryRepository(
      identityResolver: const FanartIdentityResolver(),
      client: client,
      cache: _MemoryMetadataCacheStore(),
    );
    final MediaItem item = _media(
      id: 'tmdb:movie:550',
      type: MediaType.movie,
      externalIds: const <String, String>{
        'tmdb': '550',
        'tmdb_media_type': 'movie',
      },
    );

    final List<FanartGallery> results = await Future.wait(
      <Future<FanartGallery>>[
        repository.galleryFor(item),
        repository.galleryFor(item),
      ],
    );
    expect(
      results.every((FanartGallery gallery) => gallery.isNotEmpty),
      isTrue,
    );
    expect(client.calls, 1);
  });

  test(
    'repository retries an old empty cache after the API key changes',
    () async {
      final _CountingFanartClient client = _CountingFanartClient();
      final _MemoryMetadataCacheStore cache = _MemoryMetadataCacheStore();
      final MediaItem item = _media(
        id: 'tmdb:movie:550',
        type: MediaType.movie,
        externalIds: const <String, String>{
          'tmdb': '550',
          'tmdb_media_type': 'movie',
        },
      );
      cache.values['fanart.gallery.v2.${item.id}'] = FanartGallery.empty
          .toJson();
      final FanartGalleryRepository repository = FanartGalleryRepository(
        identityResolver: const FanartIdentityResolver(),
        client: client,
        cache: cache,
      );

      expect((await repository.galleryFor(item)).isNotEmpty, isTrue);
      expect(client.calls, 1);
    },
  );
}

FanartBackground _background(String id, int width, int height, {String? url}) {
  return FanartBackground(
    id: id,
    url: url ?? 'https://assets.fanart.tv/$id.jpg',
    width: width,
    height: height,
    likes: 0,
    language: '00',
  );
}

MediaItem _media({
  required String id,
  required MediaType type,
  required Map<String, String> externalIds,
  String title = 'Title',
  String originalTitle = 'Original Title',
  int year = 2026,
}) {
  return MediaItem(
    id: id,
    title: title,
    originalTitle: originalTitle,
    overview: '',
    type: type,
    year: year,
    posterUrl: '',
    backdropUrl: '',
    rating: 0,
    genres: const <String>[],
    sourceProvider: '',
    externalIds: externalIds,
    statusLabel: '',
  );
}

Dio _respondingDio(
  void Function(RequestOptions options) onRequest,
  Object? data, {
  String baseUrl = 'https://webservice.fanart.tv/v3.2',
}) {
  final Dio dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        onRequest(options);
        handler.resolve(
          Response<Object>(
            requestOptions: options,
            statusCode: 200,
            data: data,
          ),
        );
      },
    ),
  );
  return dio;
}

class _MemoryMetadataCacheStore extends MetadataCacheStore {
  _MemoryMetadataCacheStore();

  final Map<String, Map<String, dynamic>> values =
      <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    values[key] = value;
  }
}

class _CountingFanartClient extends FanartTvClient {
  _CountingFanartClient() : super(apiKey: 'test');

  int calls = 0;

  @override
  Future<FanartGallery> fetchGallery(FanartIdentity identity) async {
    calls += 1;
    await Future<void>.delayed(Duration.zero);
    return FanartGallery.fromBackgrounds(<FanartBackground>[
      _background('result', 1920, 1080),
    ]);
  }
}
