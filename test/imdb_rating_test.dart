import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/media_details/application/imdb_rating_provider.dart';
import 'package:mirushin/features/media_details/data/imdb_ratings_client.dart';
import 'package:mirushin/features/metadata/data/tmdb_metadata_provider.dart';
import 'package:mirushin/features/metadata/domain/tmdb_media_identity.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('IMDb client reads the requested title rating', () async {
    late RequestOptions request;
    final ImdbRatingsClient client = ImdbRatingsClient(
      dio: _respondingDio(
        (RequestOptions value) => request = value,
        <Map<String, dynamic>>[
          <String, dynamic>{
            'imdbId': 'tt0111161',
            'rating': 9.3,
            'votes': 2800000,
          },
        ],
      ),
    );

    expect(await client.fetchRating('tt0111161'), 9.3);
    expect(request.path, '/api/ratings');
    expect(request.queryParameters['id'], 'tt0111161');
  });

  test('TMDB client reads imdb_id from movie external IDs', () async {
    late RequestOptions request;
    final TmdbMetadataProvider tmdb = TmdbMetadataProvider(
      readAccessToken: 'token',
      dio: _respondingDio(
        (RequestOptions value) => request = value,
        <String, dynamic>{'imdb_id': 'tt0137523'},
        baseUrl: 'https://api.themoviedb.org/3',
      ),
    );

    expect(
      await tmdb.imdbIdForTmdbMedia(
        const TmdbMediaIdentity(id: 550, kind: TmdbMediaKind.movie),
      ),
      'tt0137523',
    );
    expect(request.path, '/movie/550/external_ids');
  });

  test('IMDb identity resolver uses the AniList to TMDB bridge', () async {
    int animeResolutionCalls = 0;
    TmdbMediaIdentity? requestedIdentity;
    final ImdbIdentityResolver resolver = ImdbIdentityResolver(
      resolveAnimeTmdbIdentity: (MediaItem item) async {
        animeResolutionCalls += 1;
        return const TmdbMediaIdentity(id: 372058, kind: TmdbMediaKind.movie);
      },
      resolveTmdbImdbId: (TmdbMediaIdentity identity) async {
        requestedIdentity = identity;
        return 'tt5311514';
      },
    );

    expect(
      await resolver.resolve(
        _media(
          id: 'anilist:21519',
          type: MediaType.anime,
          externalIds: const <String, String>{
            'anilist': '21519',
            'anilist_type': 'ANIME',
          },
        ),
      ),
      'tt5311514',
    );
    expect(animeResolutionCalls, 1);
    expect(
      requestedIdentity,
      const TmdbMediaIdentity(id: 372058, kind: TmdbMediaKind.movie),
    );
  });

  test('IMDb identity resolver skips AniList manga', () async {
    int calls = 0;
    final ImdbIdentityResolver resolver = ImdbIdentityResolver(
      resolveAnimeTmdbIdentity: (MediaItem item) async {
        calls += 1;
        return const TmdbMediaIdentity(id: 1, kind: TmdbMediaKind.tv);
      },
    );

    expect(
      await resolver.resolve(
        _media(
          id: 'anilist:manga:30013',
          type: MediaType.anime,
          externalIds: const <String, String>{
            'anilist': '30013',
            'anilist_type': 'MANGA',
          },
        ),
      ),
      isNull,
    );
    expect(calls, 0);
  });

  test('repository returns cached IMDb rating and refreshes it', () async {
    final _MemoryMetadataCacheStore cache = _MemoryMetadataCacheStore();
    cache.values['imdb.identity.v1.tmdb:movie:550'] = <String, dynamic>{
      'imdbId': 'tt0137523',
    };
    cache.values['imdb.rating.v1.tt0137523'] = <String, dynamic>{'rating': 8.8};
    final _FakeImdbRatingsClient client = _FakeImdbRatingsClient(8.9);
    final ImdbRatingRepository repository = ImdbRatingRepository(
      identityResolver: const ImdbIdentityResolver(),
      client: client,
      cache: cache,
    );

    expect(
      await repository.ratingFor(
        _media(
          id: 'tmdb:movie:550',
          type: MediaType.movie,
          externalIds: const <String, String>{'tmdb': '550'},
        ),
      ),
      8.8,
    );
    await Future<void>.delayed(Duration.zero);

    expect(client.calls, 1);
    expect(cache.values['imdb.rating.v1.tt0137523']?['rating'], 8.9);
  });
}

MediaItem _media({
  required String id,
  required MediaType type,
  required Map<String, String> externalIds,
}) {
  return MediaItem(
    id: id,
    title: 'Title',
    originalTitle: 'Original Title',
    overview: '',
    type: type,
    year: 2026,
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
  String baseUrl = 'https://api.agregarr.org',
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

class _FakeImdbRatingsClient extends ImdbRatingsClient {
  _FakeImdbRatingsClient(this.rating);

  final double? rating;
  int calls = 0;

  @override
  Future<double?> fetchRating(String imdbId) async {
    calls += 1;
    return rating;
  }
}
