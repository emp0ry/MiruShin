import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/media_details/data/watch_order_repository.dart';
import 'package:mirushin/features/media_details/domain/watch_order.dart';
import 'package:mirushin/features/metadata/data/shikimori_client.dart';
import 'package:mirushin/features/metadata/domain/shikimori_franchise.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:mirushin/features/tracking/data/mal_api_client.dart';
import 'package:mirushin/shared/models/media_item.dart';

import 'support/watch_order_fixtures.dart';

class MemoryCache extends MetadataCacheStore {
  final values = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    values[key] = value;
  }
}

class FakeShikimori extends ShikimoriClient {
  int calls = 0;
  bool fail = false;
  ShikimoriFranchise franchise = const ShikimoriFranchise(
    malIds: [101, 102, 103],
  );
  @override
  Future<ShikimoriFranchise> fetchAnimeFranchise(int malId) async {
    calls++;
    if (fail) throw StateError('offline');
    return franchise;
  }
}

class FakeAniList extends AniListApiClient {
  FakeAniList({super.titleLanguage, super.showAdultContent});
  int calls = 0;
  bool fail = false;
  List<int> requested = [];
  List<WatchOrderMedia> media = [watchMedia(1), watchMedia(2), watchMedia(3)];
  @override
  Future<List<WatchOrderMedia>> fetchWatchOrderMedia(List<int> malIds) async {
    calls++;
    requested = malIds;
    if (fail) throw StateError('rate limited');
    return media;
  }
}

class FakeMal extends MalApiClient {
  FakeMal() : super(accessToken: 'token');

  final List<int> requested = <int>[];
  bool fail = false;

  @override
  Future<MediaItem?> fetchAnimeDetails(int malId) async {
    requested.add(malId);
    if (fail) throw StateError('MAL unavailable');
    return MediaItem(
      id: 'mal:$malId',
      title: 'MAL Anime $malId',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2000 + malId - 101,
      posterUrl: '',
      backdropUrl: '',
      rating: 8,
      genres: const <String>[],
      sourceProvider: 'MyAnimeList',
      externalIds: <String, String>{
        'mal': '$malId',
        'mal_media_type': 'TV',
        'mal_start_date': '${2000 + malId - 101}-01-01',
      },
      episodeCount: 12,
      statusLabel: 'FINISHED_AIRING',
    );
  }
}

void main() {
  late FakeShikimori shikimori;
  late FakeAniList anilist;
  late MemoryCache cache;
  late WatchOrderRepository repository;
  setUp(() {
    shikimori = FakeShikimori();
    anilist = FakeAniList();
    cache = MemoryCache();
    repository = WatchOrderRepository(
      shikimori: shikimori,
      anilist: anilist,
      cache: cache,
    );
  });

  test(
    'discovers all franchise members even without direct AniList relations',
    () async {
      final order = await repository.get(101);
      expect(anilist.requested, [101, 102, 103]);
      expect(order.entries.map((entry) => entry.media.id), [1, 2, 3]);
    },
  );

  test(
    'coalesces concurrent requests and caches public graph for reuse',
    () async {
      final orders = await Future.wait([
        repository.get(101),
        repository.get(101),
      ]);
      expect(shikimori.calls, 1);
      expect(anilist.calls, 1);
      expect(orders.first.entries, hasLength(3));
      shikimori.fail = true;
      final fromDisk = await WatchOrderRepository(
        shikimori: shikimori,
        anilist: anilist,
        cache: cache,
      ).get(101);
      expect(fromDisk.entries, hasLength(3));
      expect(shikimori.calls, 1);
      expect(
        cache.values.values.single.toString(),
        isNot(contains('progress')),
      );
    },
  );

  test('fixed cache freshness expires even when read repeatedly', () async {
    await repository.get(101);
    cache.values.values.single['fetchedAt'] = DateTime.now()
        .subtract(const Duration(hours: 13))
        .millisecondsSinceEpoch;
    await repository.get(101);
    expect(shikimori.calls, 2);
  });

  test(
    'metadata cache is scoped by title language and adult preference',
    () async {
      await repository.get(101);
      await WatchOrderRepository(
        shikimori: shikimori,
        anilist: FakeAniList(titleLanguage: 'NATIVE'),
        cache: cache,
      ).get(101);
      await WatchOrderRepository(
        shikimori: shikimori,
        anilist: FakeAniList(showAdultContent: true),
        cache: cache,
      ).get(101);
      expect(shikimori.calls, 3);
      expect(cache.values, hasLength(3));
    },
  );

  test(
    'missing MAL or Shikimori data does not trigger invented membership',
    () async {
      expect((await repository.get(null)).entries, isEmpty);
      expect((await repository.get(0)).entries, isEmpty);
      expect(shikimori.calls, 0);
      shikimori.franchise = const ShikimoriFranchise();
      expect((await repository.get(101)).entries, isEmpty);
      expect(anilist.calls, 0);
      expect(cache.values, isEmpty);
    },
  );

  test(
    'partial mappings are counted while available titles remain usable',
    () async {
      shikimori.franchise = const ShikimoriFranchise(
        malIds: [101, 102, 103],
        unmappedCount: 2,
      );
      anilist.media = [watchMedia(1), watchMedia(2)];
      final order = await repository.get(101);
      expect(order.entries, hasLength(2));
      expect(order.missingEntries, 3);
    },
  );

  test(
    'network failure is not cached and retry performs discovery again',
    () async {
      anilist.fail = true;
      await expectLater(repository.get(101), throwsStateError);
      expect(cache.values, isEmpty);
      anilist.fail = false;
      expect((await repository.get(101)).entries, hasLength(3));
      expect(shikimori.calls, 2);
    },
  );

  test(
    'AniList outage falls back to MAL metadata and Shikimori order',
    () async {
      final FakeMal mal = FakeMal();
      anilist.fail = true;
      shikimori.franchise = const ShikimoriFranchise(
        malIds: <int>[101, 102, 103],
        links: <ShikimoriFranchiseLink>[
          ShikimoriFranchiseLink(101, 102, 'SEQUEL'),
          ShikimoriFranchiseLink(102, 103, 'SEQUEL'),
        ],
      );
      repository = WatchOrderRepository(
        shikimori: shikimori,
        anilist: anilist,
        malFallback: mal,
        cache: cache,
      );

      final WatchOrder order = await repository.get(101);

      expect(order.entries.map((entry) => entry.media.malId), <int>[
        101,
        102,
        103,
      ]);
      expect(order.entries.first.media.item.id, 'mal:101');
      expect(order.entries.first.media.startDate.year, 2000);
      expect(mal.requested, <int>[101, 102, 103]);
      expect(cache.values.values.single['source'], 'fallback');
    },
  );

  test(
    'public Shikimori cards remain usable when AniList and MAL fail',
    () async {
      anilist.fail = true;
      shikimori.franchise = const ShikimoriFranchise(
        malIds: <int>[101, 102],
        links: <ShikimoriFranchiseLink>[
          ShikimoriFranchiseLink(101, 102, 'SEQUEL'),
        ],
        members: <ShikimoriFranchiseMember>[
          ShikimoriFranchiseMember(
            shikimoriId: 1001,
            malId: 101,
            name: 'First',
            episodes: 12,
          ),
          ShikimoriFranchiseMember(
            shikimoriId: 1002,
            malId: 102,
            name: 'Second',
            episodes: 24,
          ),
        ],
      );

      final WatchOrder order = await repository.get(101);

      expect(order.entries.map((entry) => entry.media.item.title), <String>[
        'First',
        'Second',
      ]);
      expect(order.entries.first.media.item.externalIds['shikimori'], '1001');
    },
  );

  test('expired cache is still served when discovery is offline', () async {
    final WatchOrder online = await repository.get(101);
    cache.values.values.single['fetchedAt'] = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    shikimori.fail = true;
    anilist.fail = true;

    final WatchOrder offline = await repository.get(101);

    expect(
      offline.entries.map((entry) => entry.media.id),
      online.entries.map((entry) => entry.media.id),
    );
  });

  test('short fallback cache retries AniList after recovery', () async {
    DateTime now = DateTime.utc(2026, 9, 8, 12);
    final FakeMal mal = FakeMal();
    anilist.fail = true;
    repository = WatchOrderRepository(
      shikimori: shikimori,
      anilist: anilist,
      malFallback: mal,
      cache: cache,
      now: () => now,
    );
    await repository.get(101);
    expect(cache.values.values.single['source'], 'fallback');

    now = now.add(const Duration(minutes: 11));
    anilist.fail = false;
    final WatchOrder recovered = await repository.get(101);

    expect(recovered.entries.first.media.item.id, 'anilist:1');
    expect(anilist.calls, 2);
    expect(cache.values.values.single['source'], 'anilist');
  });

  test('Shikimori parent links fill absent AniList attachments', () async {
    shikimori.franchise = const ShikimoriFranchise(
      malIds: [101, 102, 103],
      links: [
        ShikimoriFranchiseLink(101, 103, 'SIDE_STORY'),
        ShikimoriFranchiseLink(102, 101, 'SEQUEL'),
      ],
    );
    anilist.media = [
      watchMedia(1, year: 2000),
      watchMedia(2, year: 2010),
      watchMedia(3, year: 2020, format: 'OVA'),
    ];
    final order = await repository.get(101);
    expect(order.entries.map((entry) => entry.media.id), [1, 3, 2]);
    expect(order.entries[1].parentId, 1);
  });

  test(
    'AniList parent takes precedence over Shikimori fallback attachment',
    () async {
      shikimori.franchise = const ShikimoriFranchise(
        malIds: [101, 102, 103],
        links: [ShikimoriFranchiseLink(101, 103, 'SIDE_STORY')],
      );
      anilist.media = [
        watchMedia(1),
        watchMedia(2),
        watchMedia(3, format: 'OVA', relations: [relation(2, 'PARENT')]),
      ];
      final order = await repository.get(101);
      expect(order.entries.map((entry) => entry.media.id), [1, 2, 3]);
      expect(order.entries.last.parentId, 2);
    },
  );

  test('corrupt cache can be replaced by a new graph', () async {
    cache.values['anilist.watchOrder.v1.ENGLISH.false.101'] = {
      'fetchedAt': 'invalid',
    };
    expect((await repository.get(101)).entries, hasLength(3));
    expect(cache.values.values.single['media'], isA<List>());
  });
}
