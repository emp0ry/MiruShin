import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/application/local_first_sync_engine.dart';
import 'package:mirushin/features/tracking/data/tracking_sync_store.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('provider-agnostic identity and mappings', () {
    test('keeps stable local id while learning every provider id', () {
      const MediaIdentity existing = MediaIdentity(
        localId: 'local:42',
        anilistId: 100,
        malId: 200,
      );
      const MediaIdentity incoming = MediaIdentity(
        localId: 'anime:mal:200',
        malId: 200,
        shikimoriId: 300,
      );

      final MediaIdentity merged = existing.merge(incoming);

      expect(merged.localId, 'local:42');
      expect(merged.anilistId, 100);
      expect(merged.malId, 200);
      expect(merged.shikimoriId, 300);
      expect(existing.matches(incoming), isTrue);
      expect(
        existing.matches(
          const MediaIdentity(localId: 'manga:anilist:100', anilistId: 100),
        ),
        isFalse,
      );
    });

    test('uses safe status and score mappings', () {
      expect(AniListListStatus.repeating.malValue, 'watching');
      expect(AniListListStatus.repeating.malIsRewatching, isTrue);
      expect(AniListListStatus.repeating.shikimoriValue, 'rewatching');
      expect(malStatusToCanonical('on_hold'), AniListListStatus.paused);
      expect(
        shikimoriStatusToCanonical('rewatching'),
        AniListListStatus.repeating,
      );
      expect(integerProviderScore(7.6), 8);
      expect(normalizeCanonicalScore(14), 10);
      expect(normalizeCanonicalScore(-2), 0);
    });

    test('preserves every Library sort and flag field through local cache', () {
      final DateTime startedAt = DateTime(2026, 1, 2);
      final DateTime completedAt = DateTime(2026, 2, 3);
      final DateTime airingAt = DateTime.utc(2026, 9, 9, 12);
      final List<UserMediaState> states = userMediaStatesFromFolders(
        <AniListAnimeListFolder>[
          AniListAnimeListFolder(
            name: 'Completed',
            status: AniListListStatus.completed,
            entries: <AniListAnimeListEntry>[
              AniListAnimeListEntry(
                id: 42,
                status: AniListListStatus.completed,
                progress: 12,
                score: 8.5,
                mediaItem: const MediaItem(
                  id: 'anilist:10',
                  title: 'Example',
                  originalTitle: '',
                  overview: '',
                  type: MediaType.anime,
                  year: 2026,
                  posterUrl: '',
                  backdropUrl: '',
                  rating: 8.7,
                  genres: <String>['Drama'],
                  sourceProvider: 'AniList',
                  externalIds: <String, String>{'anilist': '10'},
                  statusLabel: 'RELEASING',
                ),
                notes: 'keep',
                repeat: 2,
                createdAt: 1767225600,
                updatedAt: 1788220800,
                startedAt: startedAt,
                completedAt: completedAt,
                nextEpisode: 13,
                airingAt: airingAt,
                avgScore: 87,
                format: 'TV',
              ),
            ],
          ),
        ],
        source: TrackerSource.anilist,
      );

      final UserMediaState restored = UserMediaState.fromJson(
        jsonDecode(jsonEncode(states.single.toJson())) as Map<String, dynamic>,
      );
      final AniListAnimeListEntry entry = foldersFromUserMediaStates(
        <UserMediaState>[restored],
      ).single.entries.single;

      expect(entry.createdAt, 1767225600);
      expect(entry.updatedAt, 1788220800);
      expect(entry.startedAt, startedAt);
      expect(entry.completedAt, completedAt);
      expect(entry.nextEpisode, 13);
      expect(entry.airingAt, airingAt);
      expect(entry.avgScore, 87);
      expect(entry.format, 'TV');
      expect(entry.repeat, 2);
      expect(entry.notes, 'keep');
    });
  });

  group('offline journal', () {
    test('coalesces fields and pending targets per stable identity', () async {
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore();
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: const <TrackerSource, TrackerProviderAdapter>{},
        now: () => DateTime.utc(2026, 9, 8),
      );
      const MediaIdentity identity = MediaIdentity(
        localId: 'anime:mal:20',
        anilistId: 10,
        malId: 20,
      );

      await engine.recordMutation(
        identity: identity,
        patch: UserMediaPatch(progress: 3),
        targets: const <TrackerSource>{TrackerSource.anilist},
      );
      await engine.recordMutation(
        identity: identity,
        patch: UserMediaPatch(
          status: AniListListStatus.current,
          progress: 5,
          score: 7.5,
        ),
        targets: const <TrackerSource>{TrackerSource.mal},
      );

      expect(store.journal, hasLength(1));
      final SyncJournalEntry queued = store.journal.single;
      expect(queued.patch.progress, 5);
      expect(queued.patch.score, 7.5);
      expect(queued.patch.status, AniListListStatus.current);
      expect(queued.pendingTargets, <TrackerSource>{
        TrackerSource.anilist,
        TrackerSource.mal,
      });
    });

    test('creates a local MAL-backed entry before AniList recovers', () async {
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore();
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..failMutation = true;
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
        },
        now: () => DateTime.utc(2026, 9, 8),
      );
      final MediaItem media = MediaItem(
        id: 'mal:5114',
        title: 'Fullmetal Alchemist: Brotherhood',
        originalTitle: 'Hagane no Renkinjutsushi',
        overview: 'Fallback details',
        type: MediaType.anime,
        year: 2009,
        posterUrl: 'https://example.com/poster.jpg',
        backdropUrl: '',
        rating: 9.1,
        genres: const <String>['Action'],
        sourceProvider: 'MyAnimeList',
        externalIds: const <String, String>{'mal': '5114'},
        episodeCount: 64,
        statusLabel: 'FINISHED_AIRING',
      );

      final SyncDispatchResult result = await engine.recordMutation(
        identity: MediaIdentity.fromExternalIds(
          media.externalIds,
          mediaId: media.id,
        ),
        mediaItem: media,
        mediaTitle: media.title,
        patch: UserMediaPatch(status: AniListListStatus.current, progress: 3),
        targets: const <TrackerSource>{TrackerSource.anilist},
      );

      expect(store.states, hasLength(1));
      expect(store.states.single.mediaItem.id, 'mal:5114');
      expect(store.states.single.mediaItem.posterUrl, media.posterUrl);
      expect(store.states.single.status, AniListListStatus.current);
      expect(store.states.single.progress, 3);
      expect(store.states.single.createdAt, DateTime.utc(2026, 9, 8));
      expect(store.states.single.updatedAt, DateTime.utc(2026, 9, 8));
      expect(store.states.single.startedAt, DateTime.utc(2026, 9, 8));
      expect(store.states.single.avgScore, 91);
      expect(store.journal, hasLength(1));
      expect(result.pendingTargets, <TrackerSource>{TrackerSource.anilist});
    });

    test('favorite stays local without creating a Planning entry', () async {
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore();
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..failMutation = true;
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
        },
        now: () => DateTime.utc(2026, 9, 8),
      );
      const MediaIdentity identity = MediaIdentity(
        localId: 'anime:mal:5114',
        malId: 5114,
      );

      await engine.recordMutation(
        identity: identity,
        patch: UserMediaPatch(favorite: true),
        targets: const <TrackerSource>{TrackerSource.anilist},
      );
      await engine.recordMutation(
        identity: identity,
        patch: UserMediaPatch(favorite: false),
        targets: const <TrackerSource>{TrackerSource.anilist},
      );

      expect(store.states, isEmpty);
      expect(store.favorites, hasLength(1));
      expect(store.favorites.single.favorite, isFalse);
      expect(store.journal, hasLength(1));
      expect(store.journal.single.patch.favorite, isFalse);
      expect(
        store.journal.single.patch.touches(UserMediaField.favorite),
        isTrue,
      );
    });

    test('favorite coalescing remains independent from list deletion', () {
      final UserMediaPatch favoriteThenDelete = UserMediaPatch(
        favorite: true,
      ).mergedWith(UserMediaPatch(delete: true));
      final UserMediaPatch deleteThenFavorite = UserMediaPatch(
        delete: true,
      ).mergedWith(UserMediaPatch(favorite: false));

      expect(favoriteThenDelete.delete, isTrue);
      expect(favoriteThenDelete.favorite, isTrue);
      expect(deleteThenFavorite.delete, isTrue);
      expect(deleteThenFavorite.favorite, isFalse);
    });

    test('migrates all legacy provider queues into one journal', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'anilist.pendingEdits': <String>[
          jsonEncode(<String, Object>{
            'kind': 'progress',
            'mediaId': 10,
            'status': 'CURRENT',
            'progress': 4,
          }),
        ],
        'mal.pendingEdits': <String>[
          jsonEncode(<String, Object>{'malId': 20, 'score': 8}),
        ],
        'shikimori.pendingEdits': <String>[
          jsonEncode(<String, Object>{'malId': 20, 'progress': 6}),
        ],
      });
      const SharedPreferencesTrackingSyncStore store =
          SharedPreferencesTrackingSyncStore();

      final List<SyncJournalEntry> journal = await store.loadJournal();

      expect(journal, hasLength(2));
      final SyncJournalEntry secondary = journal.firstWhere(
        (SyncJournalEntry entry) => entry.identity.malId == 20,
      );
      expect(secondary.patch.score, 8);
      expect(secondary.patch.progress, 6);
      expect(secondary.pendingTargets, <TrackerSource>{
        TrackerSource.mal,
        TrackerSource.shikimori,
      });
    });
  });

  group('outage, recovery and conflict resolution', () {
    test('falls back from AniList and records provider health', () async {
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
        ..states = <UserMediaState>[
          _state(
            source: TrackerSource.anilist,
            progress: 3,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ];
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..failFetch = true;
      final _FakeAdapter mal = _FakeAdapter(TrackerSource.mal)
        ..remote = <UserMediaState>[
          _state(
            source: TrackerSource.mal,
            progress: 4,
            updatedAt: DateTime.utc(2026, 9, 2),
          ),
        ];
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
          TrackerSource.mal: mal,
        },
        now: () => DateTime.utc(2026, 9, 8),
      );

      final LocalFirstLibraryResult result = await engine.refreshAnimeList(
        providerOrder: const <TrackerSource>[
          TrackerSource.anilist,
          TrackerSource.mal,
        ],
      );

      expect(result.remoteSource, TrackerSource.mal);
      expect(result.states.single.progress, 4);
      expect(
        store.health[TrackerSource.anilist]?.availability,
        TrackerProviderAvailability.unavailable,
      );
      expect(
        store.health[TrackerSource.mal]?.availability,
        TrackerProviderAvailability.healthy,
      );
    });

    test('replays queued AniList mutation after recovery', () async {
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
        ..states = <UserMediaState>[
          _state(
            source: TrackerSource.anilist,
            progress: 1,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ];
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..failMutation = true;
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
        },
        now: () => DateTime.utc(2026, 9, 8),
      );

      await engine.recordMutation(
        identity: store.states.single.identity,
        patch: UserMediaPatch(progress: 5),
        targets: const <TrackerSource>{TrackerSource.anilist},
      );
      expect(store.journal, hasLength(1));
      expect(store.states.single.progress, 5);

      aniList
        ..failMutation = false
        ..remote = <UserMediaState>[
          _state(
            source: TrackerSource.anilist,
            progress: 5,
            updatedAt: DateTime.utc(2026, 9, 8, 1),
          ),
        ];
      await engine.refreshAnimeList(
        providerOrder: const <TrackerSource>[TrackerSource.anilist],
      );

      expect(aniList.applied, hasLength(1));
      expect(store.journal, isEmpty);
      expect(
        store.health[TrackerSource.anilist]?.availability,
        TrackerProviderAvailability.healthy,
      );
    });

    test(
      'pending local deletion is not resurrected by fallback data',
      () async {
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
          ..states = <UserMediaState>[
            _state(
              source: TrackerSource.anilist,
              progress: 5,
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          ];
        final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
          ..failMutation = true
          ..failFetch = true;
        final _FakeAdapter mal = _FakeAdapter(TrackerSource.mal)
          ..remote = <UserMediaState>[
            _state(
              source: TrackerSource.mal,
              progress: 5,
              updatedAt: DateTime.utc(2026, 9, 2),
            ),
          ];
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: <TrackerSource, TrackerProviderAdapter>{
            TrackerSource.anilist: aniList,
            TrackerSource.mal: mal,
          },
          now: () => DateTime.utc(2026, 9, 8),
        );

        await engine.recordMutation(
          identity: store.states.single.identity,
          patch: UserMediaPatch(delete: true),
          targets: const <TrackerSource>{TrackerSource.anilist},
        );
        final LocalFirstLibraryResult result = await engine.refreshAnimeList(
          providerOrder: const <TrackerSource>[
            TrackerSource.anilist,
            TrackerSource.mal,
          ],
        );

        expect(result.remoteSource, TrackerSource.mal);
        expect(result.states, isEmpty);
        expect(store.journal, hasLength(1));
      },
    );

    test(
      'pending local fields win while untouched remote fields can advance',
      () async {
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
          ..states = <UserMediaState>[
            _state(
              source: TrackerSource.anilist,
              progress: 3,
              score: 4,
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          ]
          ..journal = <SyncJournalEntry>[
            SyncJournalEntry(
              identity: const MediaIdentity(
                localId: 'stable:anime',
                anilistId: 10,
                malId: 20,
              ),
              patch: UserMediaPatch(score: 7.5),
              pendingTargets: const <TrackerSource>{TrackerSource.anilist},
              createdAt: DateTime.utc(2026, 9, 2),
              updatedAt: DateTime.utc(2026, 9, 2),
            ),
          ];
        final _FakeAdapter mal = _FakeAdapter(TrackerSource.mal)
          ..remote = <UserMediaState>[
            _state(
              source: TrackerSource.mal,
              progress: 6,
              score: 9,
              updatedAt: DateTime.utc(2026, 9, 3),
            ),
          ];
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: <TrackerSource, TrackerProviderAdapter>{
            TrackerSource.mal: mal,
          },
          now: () => DateTime.utc(2026, 9, 4),
        );

        final LocalFirstLibraryResult result = await engine.refreshAnimeList(
          providerOrder: const <TrackerSource>[TrackerSource.mal],
        );

        expect(result.states.single.progress, 6);
        expect(result.states.single.score, 7.5);
        expect(
          result.states.single.providerStates.keys,
          containsAll(<TrackerSource>[
            TrackerSource.anilist,
            TrackerSource.mal,
          ]),
        );
        expect(
          result.states.single.providerStates[TrackerSource.mal]?.rawScore,
          9,
        );
      },
    );

    test('timestamp ties keep AniList canonical state', () {
      final UserMediaState aniList = _state(
        source: TrackerSource.anilist,
        progress: 5,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final UserMediaState mal = _state(
        source: TrackerSource.mal,
        progress: 8,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final UserMediaState merged = const UserMediaConflictResolver().merge(
        existing: aniList,
        incoming: mal,
        primary: TrackerSource.anilist,
      );

      expect(merged.progress, 5);
      expect(merged.providerStates, hasLength(2));
    });
  });
}

class _MemoryTrackingSyncStore implements TrackingSyncStore {
  List<UserMediaState> states = <UserMediaState>[];
  List<SyncJournalEntry> journal = <SyncJournalEntry>[];
  List<LocalMediaFavoriteState> favorites = <LocalMediaFavoriteState>[];
  Map<TrackerSource, TrackerProviderHealth> health =
      <TrackerSource, TrackerProviderHealth>{};

  @override
  Future<List<UserMediaState>> loadStates() async => <UserMediaState>[
    ...states,
  ];

  @override
  Future<void> saveStates(List<UserMediaState> values) async {
    states = <UserMediaState>[...values];
  }

  @override
  Future<List<SyncJournalEntry>> loadJournal() async => <SyncJournalEntry>[
    ...journal,
  ];

  @override
  Future<void> saveJournal(List<SyncJournalEntry> values) async {
    journal = <SyncJournalEntry>[...values];
  }

  @override
  Future<List<LocalMediaFavoriteState>> loadFavorites() async =>
      <LocalMediaFavoriteState>[...favorites];

  @override
  Future<void> saveFavorites(List<LocalMediaFavoriteState> values) async {
    favorites = <LocalMediaFavoriteState>[...values];
  }

  @override
  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth() async =>
      <TrackerSource, TrackerProviderHealth>{...health};

  @override
  Future<void> saveHealth(
    Map<TrackerSource, TrackerProviderHealth> values,
  ) async {
    health = <TrackerSource, TrackerProviderHealth>{...values};
  }
}

class _FakeAdapter implements TrackerProviderAdapter {
  _FakeAdapter(this.source);

  @override
  final TrackerSource source;
  bool failFetch = false;
  bool failMutation = false;
  List<UserMediaState> remote = <UserMediaState>[];
  final List<SyncJournalEntry> applied = <SyncJournalEntry>[];

  @override
  Future<List<UserMediaState>> fetchAnimeList() async {
    if (failFetch) throw StateError('${source.name} unavailable');
    return remote;
  }

  @override
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    if (failMutation) throw StateError('${source.name} unavailable');
    applied.add(mutation);
  }
}

UserMediaState _state({
  required TrackerSource source,
  required int progress,
  double? score,
  required DateTime updatedAt,
}) {
  const MediaIdentity identity = MediaIdentity(
    localId: 'stable:anime',
    anilistId: 10,
    malId: 20,
    shikimoriId: 30,
  );
  final String rawStatus = switch (source) {
    TrackerSource.anilist => 'CURRENT',
    TrackerSource.mal => 'watching',
    TrackerSource.shikimori => 'watching',
  };
  return UserMediaState(
    identity: identity,
    mediaItem: MediaItem(
      id: 'anilist:10',
      title: 'Example',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: source.label,
      externalIds: const <String, String>{
        'anilist': '10',
        'mal': '20',
        'shikimori': '30',
      },
      statusLabel: '',
    ),
    status: AniListListStatus.current,
    progress: progress,
    score: score,
    createdAt: updatedAt.subtract(const Duration(days: 30)),
    updatedAt: updatedAt,
    source: source,
    providerStates: <TrackerSource, ProviderUserMediaState>{
      source: ProviderUserMediaState(
        provider: source,
        entryId: 100 + source.index,
        rawStatus: rawStatus,
        rawScore: score,
        updatedAt: updatedAt,
      ),
    },
  );
}
