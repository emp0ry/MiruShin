import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/metadata/data/shikimori_client.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';

Dio fakeDio(Object? Function(RequestOptions) response) {
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          try {
            handler.resolve(
              Response(
                requestOptions: options,
                data: response(options),
                statusCode: 200,
              ),
            );
          } on DioException catch (error) {
            handler.reject(error);
          }
        },
      ),
    );
}

Map<String, dynamic> anime(int malId) => {
  'id': malId + 10000,
  'idMal': malId,
  'type': 'ANIME',
  'format': 'TV',
  'title': {'english': 'Anime $malId'},
  'startDate': {'year': 2020, 'month': 3, 'day': 19},
  'relations': {
    'edges': [
      {
        'relationType': 'SEQUEL',
        'node': {'id': 10002, 'type': 'ANIME'},
      },
      {
        'relationType': 'ADAPTATION',
        'node': {'id': 9, 'type': 'MANGA'},
      },
      {'relationType': 'SEQUEL', 'node': null},
    ],
  },
};

void main() {
  test(
    'full Shikimori membership resolves distinct MAL IDs in batches',
    () async {
      final batches = <List<int>>[];
      final client = ShikimoriClient(
        dio: fakeDio((options) {
          if (options.method == 'GET') {
            expect(options.path, endsWith('/1/franchise'));
            return {
              'current_id': 1001,
              'nodes': [
                for (var id = 1001; id <= 1053; id++) {'id': id},
                {'id': 1001},
                {'id': -1},
                null,
              ],
              'links': [
                {
                  'source_id': 1053,
                  'target_id': 1001,
                  'relation': 'parent_story',
                },
                {
                  'source_id': 1001,
                  'target_id': 1053,
                  'source': 0,
                  'target': 52,
                  'relation': 'side_story',
                },
                {'source_id': 1001, 'target_id': 9999, 'relation': 'sequel'},
              ],
            };
          }
          final ids = (options.data['variables']['ids'] as String)
              .split(',')
              .map(int.parse)
              .toList();
          batches.add(ids);
          return {
            'data': {
              'animes': [
                for (final id in ids) {'id': '$id', 'malId': '${id - 1000}'},
              ],
            },
          };
        }),
      );
      final franchise = await client.fetchAnimeFranchise(1);
      expect(franchise.malIds, List.generate(53, (i) => i + 1));
      expect(batches.map((batch) => batch.length), [50, 3]);
      expect(franchise.links, hasLength(2));
      expect(franchise.links.first.sourceMalId, 53);
      expect(franchise.links.first.targetMalId, 1);
      expect(franchise.links.first.relation, 'PARENT');
      expect(franchise.links.last.sourceMalId, 1);
      expect(franchise.links.last.targetMalId, 53);
      expect(franchise.links.last.relation, 'SIDE_STORY');
    },
  );

  test('Shikimori does not assume its node ID is a missing MAL ID', () async {
    final client = ShikimoriClient(
      dio: fakeDio(
        (options) => options.method == 'GET'
            ? {
                'current_id': 1,
                'nodes': [
                  {'id': 1},
                  {'id': 2},
                ],
                'links': [],
              }
            : {
                'data': {
                  'animes': [
                    {'id': '1', 'malId': '1'},
                    {'id': '2', 'malId': null},
                  ],
                },
              },
      ),
    );
    final result = await client.fetchAnimeFranchise(1);
    expect(result.malIds, [1]);
    expect(result.unmappedCount, 1);
  });

  test('a colliding Shikimori ID never selects the wrong franchise', () async {
    final client = ShikimoriClient(
      dio: fakeDio(
        (options) => options.method == 'GET'
            ? {
                'current_id': 1,
                'nodes': [
                  {'id': 1},
                ],
                'links': [],
              }
            : {
                'data': {
                  'animes': [
                    {'id': '1', 'malId': '999'},
                  ],
                },
              },
      ),
    );
    expect((await client.fetchAnimeFranchise(1)).malIds, isEmpty);
  });

  test(
    'invalid MAL, empty tree and missing Shikimori entry are graceful',
    () async {
      var requests = 0;
      final client = ShikimoriClient(
        dio: fakeDio((options) {
          requests++;
          if (options.path.endsWith('/2/franchise')) {
            throw DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
            );
          }
          return {'current_id': 1, 'nodes': [], 'links': []};
        }),
      );
      expect((await client.fetchAnimeFranchise(0)).malIds, isEmpty);
      expect(requests, 0);
      expect((await client.fetchAnimeFranchise(1)).malIds, isEmpty);
      expect((await client.fetchAnimeFranchise(2)).malIds, isEmpty);
    },
  );

  test(
    'malformed Shikimori responses and API errors remain retryable',
    () async {
      final malformed = ShikimoriClient(
        dio: fakeDio((_) => {'nodes': 'invalid'}),
      );
      await expectLater(
        malformed.fetchAnimeFranchise(1),
        throwsFormatException,
      );
      final failing = ShikimoriClient(
        dio: fakeDio(
          (options) => options.method == 'GET'
              ? {
                  'current_id': 1,
                  'nodes': [
                    {'id': 1},
                  ],
                  'links': [],
                }
              : {
                  'errors': [
                    {'message': 'Rate limited'},
                  ],
                },
        ),
      );
      await expectLater(failing.fetchAnimeFranchise(1), throwsFormatException);
    },
  );

  test(
    'AniList batches all membership IDs and preserves precise dates and anime relations',
    () async {
      final batches = <List<int>>[];
      final client = AniListApiClient(
        dio: fakeDio((options) {
          final query = options.data['query'] as String;
          expect(query, contains('idMal_in:'));
          expect(query, contains('isAdult: false'));
          expect(query, isNot(contains('mediaListEntry')));
          expect(options.headers.containsKey('Authorization'), isFalse);
          final ids = List<int>.from(options.data['variables']['ids'] as List);
          batches.add(ids);
          return {
            'data': {
              'Page': {
                'media': [for (final id in ids) anime(id)],
              },
            },
          };
        }),
      );
      final result = await client.fetchWatchOrderMedia([
        0,
        1,
        ...List.generate(53, (i) => i + 1),
      ]);
      expect(batches.map((batch) => batch.length), [50, 3]);
      expect(result, hasLength(53));
      expect(result.first.startDate.toJson(), {
        'year': 2020,
        'month': 3,
        'day': 19,
      });
      expect(result.first.relations, hasLength(1));
      expect(result.first.relations.single.targetId, 10002);
      expect(result.first.item.seasons, isEmpty);
      expect(result.first.item.title, 'Anime 1');
    },
  );

  test(
    'AniList drops wrong IDs, manga, adult results and invalid edges',
    () async {
      final client = AniListApiClient(
        dio: fakeDio(
          (_) => {
            'data': {
              'Page': {
                'media': [
                  anime(1),
                  {...anime(2), 'type': 'MANGA'},
                  {...anime(3), 'isAdult': true},
                  anime(999),
                  {'id': 0, 'idMal': 2, 'type': 'ANIME'},
                ],
              },
            },
          },
        ),
      );
      final result = await client.fetchWatchOrderMedia([1, 2, 3]);
      expect(result.map((entry) => entry.malId), [1]);
    },
  );

  test(
    'adult preference is respected and missing AniList data is retryable',
    () async {
      final client = AniListApiClient(
        showAdultContent: true,
        dio: fakeDio((options) {
          expect(options.data['query'], isNot(contains('isAdult: false')));
          return {
            'data': {
              'Page': {
                'media': [
                  {...anime(1), 'isAdult': true},
                ],
              },
            },
          };
        }),
      );
      expect(await client.fetchWatchOrderMedia([1]), hasLength(1));
      final missing = AniListApiClient(dio: fakeDio((_) => {'data': {}}));
      await expectLater(
        missing.fetchWatchOrderMedia([1]),
        throwsFormatException,
      );
    },
  );
}
