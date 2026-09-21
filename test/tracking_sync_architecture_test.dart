import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/application/local_first_sync_engine.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
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

    test('clamps addon extras to the canonical tracker total', () {
      final TrackerEpisodeProgress update = normalizeTrackerEpisodeProgress(
        episode: 13,
        total: 12,
      );

      expect(update.progress, 12);
      expect(update.status, AniListListStatus.completed);
      expect(canonicalEpisodeProgress(13, 12), 12);
      expect(canonicalEpisodeProgress(13, null), 13);
    });

    test('repairs final progress that is still marked watching', () {
      final UserMediaState current = _state(
        source: TrackerSource.anilist,
        progress: 4,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final TrackerEpisodeProgress update = normalizeTrackerEpisodeProgress(
        episode: 4,
        total: 4,
        currentStatus: current.status,
      );

      expect(update.status, AniListListStatus.completed);
      expect(
        trackerEpisodeUpdateNeeded(current: current, update: update, total: 4),
        isTrue,
      );
      expect(
        trackerEpisodeUpdateNeeded(
          current: _state(
            source: TrackerSource.anilist,
            status: AniListListStatus.completed,
            progress: 4,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
          update: update,
          total: 4,
        ),
        isFalse,
      );
    });

    test('normalizes corrupt remote progress before it reaches the UI', () {
      final List<UserMediaState> states = userMediaStatesFromFolders(
        <AniListAnimeListFolder>[
          AniListAnimeListFolder(
            name: 'Watching',
            status: AniListListStatus.current,
            entries: <AniListAnimeListEntry>[
              AniListAnimeListEntry(
                id: 42,
                status: AniListListStatus.current,
                progress: 13,
                mediaItem: const MediaItem(
                  id: 'anilist:10',
                  title: 'Example',
                  originalTitle: '',
                  overview: '',
                  type: MediaType.anime,
                  year: 2026,
                  posterUrl: '',
                  backdropUrl: '',
                  rating: 0,
                  genres: <String>[],
                  sourceProvider: 'AniList',
                  externalIds: <String, String>{'anilist': '10'},
                  episodeCount: 12,
                  statusLabel: 'FINISHED',
                ),
              ),
            ],
          ),
        ],
        source: TrackerSource.anilist,
      );

      // Keep the raw provider value internally so the next sync can repair the
      // account, while never exposing the invalid 13/12 state in the library.
      expect(states.single.progress, 13);
      expect(states.single.status, AniListListStatus.current);
      final AniListAnimeListEntry displayed = foldersFromUserMediaStates(
        states,
      ).single.entries.single;
      expect(displayed.progress, 12);
      expect(displayed.status, AniListListStatus.completed);
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
    test('persists remote-confirmation targets across restarts', () {
      final SyncJournalEntry restored = SyncJournalEntry.fromJson(
        SyncJournalEntry(
          identity: const MediaIdentity(
            localId: 'anime:anilist:10',
            anilistId: 10,
          ),
          patch: UserMediaPatch(status: AniListListStatus.current),
          pendingTargets: const <TrackerSource>{},
          awaitingRemoteTargets: const <TrackerSource>{TrackerSource.anilist},
          createdAt: DateTime.utc(2026, 9, 8),
          updatedAt: DateTime.utc(2026, 9, 8),
        ).toJson(),
      );

      expect(restored.pendingTargets, isEmpty);
      expect(restored.awaitingRemoteTargets, <TrackerSource>{
        TrackerSource.anilist,
      });
      expect(restored.isSettled, isFalse);
    });

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
    test('a provider snapshot does not leak another account library', () async {
      final UserMediaState aniListState = _state(
        source: TrackerSource.anilist,
        progress: 3,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final UserMediaState malOnlyState = _stateForIdentity(
        source: TrackerSource.mal,
        anilistId: null,
        malId: 999,
        progress: 7,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
        ..states = <UserMediaState>[aniListState, malOnlyState];
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..remote = <UserMediaState>[aniListState];
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
        },
      );

      final LocalFirstLibraryResult result = await engine.refreshAnimeList(
        providerOrder: const <TrackerSource>[TrackerSource.anilist],
      );

      expect(result.states, hasLength(1));
      expect(result.states.single.identity.anilistId, 10);
      expect(store.states, hasLength(2));
    });

    test('offline cache stays scoped to the selected provider', () async {
      final UserMediaState aniListState = _state(
        source: TrackerSource.anilist,
        progress: 3,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final UserMediaState malOnlyState = _stateForIdentity(
        source: TrackerSource.mal,
        anilistId: null,
        malId: 999,
        progress: 7,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
        ..states = <UserMediaState>[aniListState, malOnlyState];
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..failFetch = true;
      final _FakeAdapter mal = _FakeAdapter(TrackerSource.mal)
        ..failFetch = true;
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
          TrackerSource.mal: mal,
        },
      );

      final LocalFirstLibraryResult result = await engine.refreshAnimeList(
        providerOrder: const <TrackerSource>[
          TrackerSource.anilist,
          TrackerSource.mal,
        ],
        cacheSource: TrackerSource.anilist,
      );

      expect(result.fromCache, isTrue);
      expect(result.states, hasLength(1));
      expect(result.states.single.identity.anilistId, 10);
    });

    test(
      'fallback stays readable without overriding cached AniList state',
      () async {
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
        expect(result.states.single.progress, 3);
        expect(result.states.single.source, TrackerSource.anilist);
        expect(
          result.states.single.providerStates.keys,
          containsAll(<TrackerSource>[
            TrackerSource.anilist,
            TrackerSource.mal,
          ]),
        );
        expect(
          store.health[TrackerSource.anilist]?.availability,
          TrackerProviderAvailability.unavailable,
        );
        expect(
          store.health[TrackerSource.mal]?.availability,
          TrackerProviderAvailability.healthy,
        );
      },
    );

    test('newer fallback cannot regress a completed primary entry', () {
      final UserMediaState completedAniList = _state(
        source: TrackerSource.anilist,
        status: AniListListStatus.completed,
        progress: 24,
        updatedAt: DateTime.utc(2026, 8, 1),
      );
      final UserMediaState newerMal = _state(
        source: TrackerSource.mal,
        status: AniListListStatus.current,
        progress: 6,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final UserMediaState merged = const UserMediaConflictResolver().merge(
        existing: completedAniList,
        incoming: newerMal,
        primary: TrackerSource.anilist,
      );

      expect(merged.status, AniListListStatus.completed);
      expect(merged.progress, 24);
      expect(merged.source, TrackerSource.anilist);
      expect(merged.providerStates[TrackerSource.mal]?.rawStatus, 'watching');
    });

    test(
      'fresh AniList schedule advances when the list timestamp is unchanged',
      () {
        final DateTime oldAiring = DateTime.utc(2026, 9, 14, 12);
        final DateTime freshAiring = DateTime.utc(2026, 9, 21, 12);
        final UserMediaState cached = _state(
          source: TrackerSource.mal,
          progress: 10,
          updatedAt: DateTime.utc(2026, 9, 1),
          nextEpisode: 11,
          airingAt: oldAiring,
        );
        final UserMediaState freshAniList = _state(
          source: TrackerSource.anilist,
          progress: 10,
          updatedAt: DateTime.utc(2026, 9, 1),
          nextEpisode: 12,
          airingAt: freshAiring,
        );

        final UserMediaState merged = const UserMediaConflictResolver().merge(
          existing: cached,
          incoming: freshAniList,
          primary: TrackerSource.mal,
          incomingAiringIsAuthoritative: true,
        );

        expect(merged.source, TrackerSource.mal);
        expect(merged.nextEpisode, 12);
        expect(merged.airingAt, freshAiring);
        expect(merged.mediaItem.externalIds[anilistNextAiringEpisodeKey], '12');
        expect(
          merged.mediaItem.externalIds[anilistNextAiringAtKey],
          '${freshAiring.millisecondsSinceEpoch ~/ 1000}',
        );
      },
    );

    test('fresh AniList snapshot clears a finished airing schedule', () {
      final UserMediaState cached = _state(
        source: TrackerSource.mal,
        progress: 11,
        updatedAt: DateTime.utc(2026, 9, 1),
        nextEpisode: 12,
        airingAt: DateTime.utc(2026, 9, 21, 12),
      );
      final UserMediaState freshAniList = _state(
        source: TrackerSource.anilist,
        progress: 12,
        status: AniListListStatus.completed,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final UserMediaState merged = const UserMediaConflictResolver().merge(
        existing: cached,
        incoming: freshAniList,
        primary: TrackerSource.mal,
        incomingAiringIsAuthoritative: true,
      );

      expect(merged.nextEpisode, isNull);
      expect(merged.airingAt, isNull);
      expect(
        merged.mediaItem.externalIds,
        isNot(contains(anilistNextAiringEpisodeKey)),
      );
      expect(
        merged.mediaItem.externalIds,
        isNot(contains(anilistNextAiringAtKey)),
      );
    });

    test('MAL fallback preserves the cached AniList schedule as one pair', () {
      final DateTime cachedAiring = DateTime.utc(2026, 9, 21, 12);
      final UserMediaState cached = _state(
        source: TrackerSource.mal,
        progress: 10,
        updatedAt: DateTime.utc(2026, 9, 1),
        nextEpisode: 12,
        airingAt: cachedAiring,
      );
      final UserMediaState freshMal = _state(
        source: TrackerSource.mal,
        progress: 11,
        updatedAt: DateTime.utc(2026, 9, 14),
      );

      final UserMediaState merged = const UserMediaConflictResolver().merge(
        existing: cached,
        incoming: freshMal,
        primary: TrackerSource.mal,
      );

      expect(merged.progress, 11);
      expect(merged.nextEpisode, 12);
      expect(merged.airingAt, cachedAiring);
    });

    test('cached AniList fallback cannot regress a newer schedule', () {
      final DateTime newerAiring = DateTime.utc(2026, 9, 21, 12);
      final UserMediaState current = _state(
        source: TrackerSource.mal,
        progress: 10,
        updatedAt: DateTime.utc(2026, 9, 1),
        nextEpisode: 12,
        airingAt: newerAiring,
      );
      final UserMediaState cachedAniList = _state(
        source: TrackerSource.anilist,
        progress: 10,
        updatedAt: DateTime.utc(2026, 9, 1),
        nextEpisode: 11,
        airingAt: DateTime.utc(2026, 9, 14, 12),
      );

      final UserMediaState merged = const UserMediaConflictResolver().merge(
        existing: current,
        incoming: cachedAniList,
        primary: TrackerSource.mal,
      );

      expect(merged.nextEpisode, 12);
      expect(merged.airingAt, newerAiring);
    });

    test('pending local fields still win over recovered primary data', () {
      final UserMediaState fallback = _state(
        source: TrackerSource.mal,
        status: AniListListStatus.current,
        progress: 4,
        score: 5,
        updatedAt: DateTime.utc(2026, 9, 2),
      );
      final UserMediaState recoveredAniList = _state(
        source: TrackerSource.anilist,
        status: AniListListStatus.completed,
        progress: 24,
        score: 6,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final UserMediaState merged = const UserMediaConflictResolver().merge(
        existing: fallback,
        incoming: recoveredAniList,
        primary: TrackerSource.anilist,
        pendingLocal: UserMediaPatch(
          status: AniListListStatus.paused,
          progress: 10,
          fields: const <UserMediaField>{
            UserMediaField.status,
            UserMediaField.progress,
          },
        ),
      );

      expect(merged.status, AniListListStatus.paused);
      expect(merged.progress, 10);
      expect(merged.score, 6);
      expect(merged.source, TrackerSource.anilist);
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

    test('mutation delivery attempts the configured primary first', () async {
      final List<TrackerSource> deliveryOrder = <TrackerSource>[];
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore();
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.mal: _FakeAdapter(
            TrackerSource.mal,
            applicationOrder: deliveryOrder,
          ),
          TrackerSource.shikimori: _FakeAdapter(
            TrackerSource.shikimori,
            applicationOrder: deliveryOrder,
          ),
          TrackerSource.anilist: _FakeAdapter(
            TrackerSource.anilist,
            applicationOrder: deliveryOrder,
          ),
        },
        primary: TrackerSource.anilist,
        now: () => DateTime.utc(2026, 9, 8),
      );

      await engine.recordMutation(
        identity: const MediaIdentity(
          localId: 'stable:anime',
          anilistId: 10,
          malId: 20,
          shikimoriId: 30,
        ),
        patch: UserMediaPatch(progress: 5),
        targets: const <TrackerSource>{
          TrackerSource.mal,
          TrackerSource.shikimori,
          TrackerSource.anilist,
        },
      );

      expect(deliveryOrder, <TrackerSource>[
        TrackerSource.anilist,
        TrackerSource.mal,
        TrackerSource.shikimori,
      ]);
      expect(store.journal, hasLength(1));
      expect(store.journal.single.pendingTargets, isEmpty);
      expect(store.journal.single.awaitingRemoteTargets, <TrackerSource>{
        TrackerSource.anilist,
        TrackerSource.mal,
        TrackerSource.shikimori,
      });
    });

    test(
      'successful create stays local while provider list is still stale',
      () async {
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore();
        final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist);
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: <TrackerSource, TrackerProviderAdapter>{
            TrackerSource.anilist: aniList,
          },
          now: () => DateTime.utc(2026, 9, 8),
        );
        const MediaItem media = MediaItem(
          id: 'anilist:10',
          title: 'Immediate Watching Entry',
          originalTitle: '',
          overview: '',
          type: MediaType.anime,
          year: 2026,
          posterUrl: '',
          backdropUrl: '',
          rating: 0,
          genres: <String>[],
          sourceProvider: 'AniList',
          externalIds: <String, String>{'anilist': '10'},
          episodeCount: 12,
          statusLabel: 'RELEASING',
        );

        final SyncDispatchResult saved = await engine.recordMutation(
          identity: MediaIdentity.fromExternalIds(
            media.externalIds,
            mediaId: media.id,
          ),
          mediaItem: media,
          patch: UserMediaPatch(status: AniListListStatus.current, progress: 1),
          targets: const <TrackerSource>{TrackerSource.anilist},
        );

        expect(saved.pendingTargets, isEmpty);
        expect(store.journal.single.awaitingRemoteTargets, <TrackerSource>{
          TrackerSource.anilist,
        });

        final LocalFirstLibraryResult stale = await engine.refreshAnimeList(
          providerOrder: const <TrackerSource>[TrackerSource.anilist],
        );
        expect(stale.states, hasLength(1));
        expect(stale.states.single.status, AniListListStatus.current);
        expect(stale.states.single.progress, 1);
        expect(store.journal, hasLength(1));

        aniList.remote = <UserMediaState>[
          _state(
            source: TrackerSource.anilist,
            progress: 1,
            updatedAt: DateTime.utc(2026, 9, 8, 0, 1),
          ),
        ];
        final LocalFirstLibraryResult confirmed = await engine.refreshAnimeList(
          providerOrder: const <TrackerSource>[TrackerSource.anilist],
        );
        expect(confirmed.states, hasLength(1));
        expect(store.journal, isEmpty);
      },
    );

    test(
      'status-filtered preview cannot settle a mutation before full Library',
      () async {
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore();
        final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist);
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: <TrackerSource, TrackerProviderAdapter>{
            TrackerSource.anilist: aniList,
          },
          now: () => DateTime.utc(2026, 9, 8),
        );
        const MediaItem media = MediaItem(
          id: 'anilist:10',
          title: 'Preview Race Entry',
          originalTitle: '',
          overview: '',
          type: MediaType.anime,
          year: 2026,
          posterUrl: '',
          backdropUrl: '',
          rating: 0,
          genres: <String>[],
          sourceProvider: 'AniList',
          externalIds: <String, String>{'anilist': '10', 'mal': '20'},
          episodeCount: 12,
          statusLabel: 'RELEASING',
        );

        await engine.recordMutation(
          identity: MediaIdentity.fromExternalIds(
            media.externalIds,
            mediaId: media.id,
          ),
          mediaItem: media,
          patch: UserMediaPatch(status: AniListListStatus.current, progress: 1),
          targets: const <TrackerSource>{TrackerSource.anilist},
        );
        final UserMediaState confirmedEntry = _state(
          source: TrackerSource.anilist,
          progress: 1,
          updatedAt: DateTime.utc(2026, 9, 8, 0, 1),
        );

        await engine.ingestRemoteStates(
          <UserMediaState>[confirmedEntry],
          snapshotSource: TrackerSource.anilist,
          confirmRemoteMutations: false,
        );

        expect(store.journal, hasLength(1));
        expect(store.journal.single.awaitingRemoteTargets, <TrackerSource>{
          TrackerSource.anilist,
        });

        await engine.ingestRemoteStates(
          <UserMediaState>[confirmedEntry],
          snapshotSource: TrackerSource.anilist,
          confirmRemoteMutations: true,
        );

        expect(store.journal, isEmpty);
      },
    );

    test(
      'successful edit stays local until the list confirms exact fields',
      () async {
        final UserMediaState existing = _state(
          source: TrackerSource.anilist,
          progress: 2,
          score: 6,
          updatedAt: DateTime.utc(2026, 9, 1),
        );
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
          ..states = <UserMediaState>[existing];
        final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
          ..remote = <UserMediaState>[existing];
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: <TrackerSource, TrackerProviderAdapter>{
            TrackerSource.anilist: aniList,
          },
          now: () => DateTime.utc(2026, 9, 8),
        );

        await engine.recordMutation(
          identity: existing.identity,
          patch: UserMediaPatch(progress: 5, score: 8),
          targets: const <TrackerSource>{TrackerSource.anilist},
        );
        expect(store.journal.single.awaitingRemoteTargets, <TrackerSource>{
          TrackerSource.anilist,
        });

        final LocalFirstLibraryResult stale = await engine.refreshAnimeList(
          providerOrder: const <TrackerSource>[TrackerSource.anilist],
        );
        expect(stale.states.single.progress, 5);
        expect(stale.states.single.score, 8);
        expect(store.journal, hasLength(1));

        aniList.remote = <UserMediaState>[
          _state(
            source: TrackerSource.anilist,
            progress: 5,
            score: 8,
            updatedAt: DateTime.utc(2026, 9, 8, 0, 1),
          ),
        ];
        await engine.refreshAnimeList(
          providerOrder: const <TrackerSource>[TrackerSource.anilist],
        );
        expect(store.journal, isEmpty);
      },
    );

    test('successful delete is not resurrected by a stale list read', () async {
      final UserMediaState existing = _state(
        source: TrackerSource.anilist,
        progress: 3,
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
        ..states = <UserMediaState>[existing];
      final _FakeAdapter aniList = _FakeAdapter(TrackerSource.anilist)
        ..remote = <UserMediaState>[existing];
      final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
        store: store,
        adapters: <TrackerSource, TrackerProviderAdapter>{
          TrackerSource.anilist: aniList,
        },
        now: () => DateTime.utc(2026, 9, 8),
      );

      await engine.recordMutation(
        identity: existing.identity,
        patch: UserMediaPatch(delete: true),
        targets: const <TrackerSource>{TrackerSource.anilist},
      );
      final LocalFirstLibraryResult stale = await engine.refreshAnimeList(
        providerOrder: const <TrackerSource>[TrackerSource.anilist],
      );

      expect(stale.states, isEmpty);
      expect(store.states, isEmpty);
      expect(store.journal.single.awaitingRemoteTargets, <TrackerSource>{
        TrackerSource.anilist,
      });

      aniList.remote = <UserMediaState>[];
      await engine.refreshAnimeList(
        providerOrder: const <TrackerSource>[TrackerSource.anilist],
      );
      expect(store.journal, isEmpty);
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
          targets: const <TrackerSource>{
            TrackerSource.anilist,
            TrackerSource.mal,
          },
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
      'mutation for another provider does not alter fallback timestamps',
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

        expect(result.states.single.progress, 3);
        expect(result.states.single.score, 4);
        expect(result.states.single.updatedAt, DateTime.utc(2026, 9, 1));
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

    test(
      'live primary snapshot repairs a timestamp polluted by another provider',
      () async {
        final DateTime providerTime = DateTime.utc(2026, 9, 1);
        final DateTime mutationTime = DateTime.utc(2026, 9, 2);
        final DateTime pollutedTime = DateTime.utc(2026, 9, 3);
        final UserMediaState liveAniList = _state(
          source: TrackerSource.anilist,
          progress: 3,
          updatedAt: providerTime,
        );
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
          ..states = <UserMediaState>[
            liveAniList.apply(UserMediaPatch(progress: 7), pollutedTime),
          ]
          ..journal = <SyncJournalEntry>[
            SyncJournalEntry(
              identity: liveAniList.identity,
              patch: UserMediaPatch(progress: 7),
              pendingTargets: const <TrackerSource>{TrackerSource.mal},
              awaitingRemoteTargets: const <TrackerSource>{
                TrackerSource.shikimori,
              },
              createdAt: mutationTime,
              updatedAt: mutationTime,
            ),
          ];
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          now: () => DateTime.utc(2026, 9, 20),
        );

        await engine.ingestRemoteStates(
          <UserMediaState>[liveAniList],
          snapshotSource: TrackerSource.anilist,
          confirmRemoteMutations: false,
          incomingProviderIsAuthoritative: true,
        );

        expect(store.states.single.progress, 3);
        expect(store.states.single.updatedAt, providerTime);
        expect(store.journal.single.pendingTargets, <TrackerSource>{
          TrackerSource.mal,
        });
        expect(store.journal.single.awaitingRemoteTargets, <TrackerSource>{
          TrackerSource.shikimori,
        });
      },
    );

    test(
      'pending patch keeps its timestamp across repeated target refreshes',
      () async {
        final DateTime primaryTime = DateTime.utc(2026, 9, 1);
        final DateTime mutationTime = DateTime.utc(2026, 9, 2);
        final UserMediaState primary = _state(
          source: TrackerSource.anilist,
          progress: 3,
          score: 4,
          updatedAt: primaryTime,
        );
        final UserMediaState malSnapshot = _state(
          source: TrackerSource.mal,
          progress: 6,
          score: 9,
          updatedAt: DateTime.utc(2026, 9, 3),
        );
        final _MemoryTrackingSyncStore store = _MemoryTrackingSyncStore()
          ..states = <UserMediaState>[primary]
          ..journal = <SyncJournalEntry>[
            SyncJournalEntry(
              identity: primary.identity,
              patch: UserMediaPatch(score: 7.5),
              pendingTargets: const <TrackerSource>{TrackerSource.mal},
              createdAt: mutationTime,
              updatedAt: mutationTime,
            ),
          ];
        final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
          store: store,
          adapters: const <TrackerSource, TrackerProviderAdapter>{},
          now: () => DateTime.utc(2026, 9, 20),
        );

        for (int refresh = 0; refresh < 2; refresh += 1) {
          await engine.ingestRemoteStates(
            <UserMediaState>[malSnapshot],
            snapshotSource: TrackerSource.mal,
            confirmRemoteMutations: false,
            incomingProviderIsAuthoritative: true,
          );
          expect(store.states.single.score, 7.5);
          expect(store.states.single.updatedAt, mutationTime);
        }
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
  _FakeAdapter(this.source, {this.applicationOrder});

  @override
  final TrackerSource source;
  final List<TrackerSource>? applicationOrder;
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
    applicationOrder?.add(source);
    applied.add(mutation);
  }
}

UserMediaState _state({
  required TrackerSource source,
  required int progress,
  AniListListStatus status = AniListListStatus.current,
  double? score,
  required DateTime updatedAt,
  int? nextEpisode,
  DateTime? airingAt,
}) {
  const MediaIdentity identity = MediaIdentity(
    localId: 'stable:anime',
    anilistId: 10,
    malId: 20,
    shikimoriId: 30,
  );
  final String rawStatus = switch ((source, status)) {
    (TrackerSource.anilist, AniListListStatus.completed) => 'COMPLETED',
    (TrackerSource.anilist, _) => 'CURRENT',
    (TrackerSource.mal, AniListListStatus.completed) => 'completed',
    (TrackerSource.mal, _) => 'watching',
    (TrackerSource.shikimori, AniListListStatus.completed) => 'completed',
    (TrackerSource.shikimori, _) => 'watching',
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
      externalIds: <String, String>{
        'anilist': '10',
        'mal': '20',
        'shikimori': '30',
        if (nextEpisode != null) anilistNextAiringEpisodeKey: '$nextEpisode',
        if (airingAt != null)
          anilistNextAiringAtKey: '${airingAt.millisecondsSinceEpoch ~/ 1000}',
      },
      statusLabel: '',
    ),
    status: status,
    progress: progress,
    score: score,
    nextEpisode: nextEpisode,
    airingAt: airingAt,
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

UserMediaState _stateForIdentity({
  required TrackerSource source,
  required int? anilistId,
  required int? malId,
  required int progress,
  required DateTime updatedAt,
}) {
  final MediaIdentity identity = MediaIdentity(
    localId: anilistId != null
        ? 'anime:anilist:$anilistId'
        : 'anime:mal:$malId',
    anilistId: anilistId,
    malId: malId,
  );
  return UserMediaState(
    identity: identity,
    mediaItem: MediaItem(
      id: anilistId != null ? 'anilist:$anilistId' : 'mal:$malId',
      title: 'Other account title',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: source.label,
      externalIds: <String, String>{
        if (anilistId != null) 'anilist': '$anilistId',
        if (malId != null) 'mal': '$malId',
      },
      statusLabel: '',
    ),
    status: AniListListStatus.current,
    progress: progress,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    source: source,
    providerStates: <TrackerSource, ProviderUserMediaState>{
      source: ProviderUserMediaState(provider: source, updatedAt: updatedAt),
    },
  );
}
