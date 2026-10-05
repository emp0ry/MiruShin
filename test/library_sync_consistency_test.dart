import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/domain/cloud_replica_models.dart';
import 'package:mirushin/features/tracking/application/anilist_favorite_provider.dart';
import 'package:mirushin/features/tracking/application/local_first_sync_engine.dart';
import 'package:mirushin/features/tracking/application/tracker_library_provider.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:mirushin/features/tracking/data/canonical_tracking_sync_store.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/features/tracking/presentation/anilist_entry_editor.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserMediaState example({
  bool completed = false,
  double? score = 8.5,
  TrackerSource source = TrackerSource.anilist,
  DateTime? at,
}) {
  final time = at ?? DateTime.utc(2026, 10, 5, 12);
  return UserMediaState(
    identity: const MediaIdentity(
      localId: 'anime:10',
      anilistId: 10,
      malId: 20,
    ),
    mediaItem: MediaItem(
      id: 'anilist:10',
      title: 'Sync audit example',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 8,
      genres: const [],
      sourceProvider: 'AniList',
      episodeCount: 12,
      statusLabel: 'FINISHED',
      externalIds: const {'anilist': '10', 'mal': '20'},
    ),
    status: completed ? AniListListStatus.completed : AniListListStatus.current,
    progress: completed ? 12 : 3,
    score: score,
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: time,
    source: source,
  );
}

CanonicalLibraryRepository memory() {
  final db = CanonicalLibraryDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return CanonicalLibraryRepository(db);
}

Future<void> mutate(
  CanonicalLibraryRepository repo,
  UserMediaState next,
  UserMediaPatch patch, {
  List<LocalMediaFavoriteState> favorites = const [],
}) {
  return repo.commitTrackingMutation(
    states: [next],
    journal: const [],
    favorites: favorites,
    identity: next.identity,
    patch: patch,
    targets: const {},
    occurredAt: next.updatedAt,
  );
}

Future<void> initialImport(
  CanonicalLibraryRepository repo,
  UserMediaState state,
) async {
  await repo.reconcileProviderSnapshot(
    source: state.source,
    accountId: 'same-viewer',
    mediaKind: 'anime',
    remote: [state],
    journal: const [],
    propagationTargets: const {},
    completeSnapshot: true,
  );
  await repo.approveProviderAccount(
    provider: state.source.name,
    accountId: 'same-viewer',
  );
  await repo.reconcileProviderSnapshot(
    source: state.source,
    accountId: 'same-viewer',
    mediaKind: 'anime',
    remote: [state],
    journal: const [],
    propagationTargets: const {},
    completeSnapshot: true,
  );
}

Future<int> conflicts(CanonicalLibraryRepository repo) async {
  return (await repo.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM library_conflict_records WHERE state = 'open'",
          )
          .getSingle())
      .read<int>('n');
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await AppLocalizations.load(const Locale('en'));
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Favorite should reach an existing device via a Drive operation',
    () async {
      final a = memory(), b = memory();
      final state = example();
      await a.saveTrackingStates([state]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await mutate(
        a,
        state,
        UserMediaPatch(favorite: true),
        favorites: [
          LocalMediaFavoriteState(
            identity: state.identity,
            favorite: true,
            updatedAt: state.updatedAt,
          ),
        ],
      );
      final segment = (await a.buildPendingDriveSegment())!;
      expect(
        segment.operations.single['after'],
        containsPair('favorite', true),
      );
      await b.applyDriveSegment(segment, trackerTargets: const {});
      expect(
        (await b.loadFavorites()).any((v) => v.favorite),
        isTrue,
        reason:
            'The received favorite operation must update canonical favorite state.',
      );
    },
  );

  test(
    'Favorite should survive a full Drive backup on a fresh device',
    () async {
      final a = memory(), b = memory();
      final state = example();
      await a.saveTrackingStates([state]);
      await mutate(
        a,
        state,
        UserMediaPatch(favorite: true),
        favorites: [
          LocalMediaFavoriteState(
            identity: state.identity,
            favorite: true,
            updatedAt: state.updatedAt,
          ),
        ],
      );
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      expect((await b.loadFavorites()).any((v) => v.favorite), isTrue);
    },
  );

  test(
    'The same provider state imported on two devices should not conflict',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await initialImport(b, example());
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(
        await conflicts(b),
        0,
        reason:
            'Both devices imported identical values, without independent user edits.',
      );
    },
  );

  test(
    'An unresolved operation should not produce duplicate conflicts on replay',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await initialImport(b, example());
      final segment = (await a.buildPendingDriveSegment())!;
      await b.applyDriveSegment(segment, trackerTargets: const {});
      final first = await conflicts(b);
      final replay = DriveReplicaSegment.fromJson({
        ...segment.toJson(),
        'segmentId': 'another-checkpoint-recovery',
      });
      await b.applyDriveSegment(replay, trackerTargets: const {});
      expect(
        await conflicts(b),
        first,
        reason:
            'Operation IDs, not segment IDs, must make conflict insertion idempotent.',
      );
    },
  );

  test(
    'Device B without edits should accept A progress after its first provider import',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      final actual = (await a.loadTrackingStates()).single;
      final updated = actual.apply(
        UserMediaPatch(progress: 4),
        DateTime.utc(2026, 10, 5, 15),
      );
      await mutate(a, updated, UserMediaPatch(progress: 4));
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(
        await conflicts(b),
        0,
        reason:
            'A must persist the initial provider operation revision before recording its next edit.',
      );
      expect((await b.loadTrackingStates()).single.progress, 4);
    },
  );

  test(
    'A stale live preview should preserve the canonical Completed state',
    () async {
      final repo = memory();
      final store = CanonicalTrackingSyncStore(repository: repo);
      await store.loadStates();
      await repo.saveTrackingStates([example(completed: true)]);
      final engine = LocalFirstSyncEngine(
        store: store,
        adapters: const {},
        primary: TrackerSource.anilist,
      );
      await engine.ingestRemoteStates(
        [example(at: DateTime.utc(2026, 10, 1))],
        snapshotSource: TrackerSource.anilist,
        confirmRemoteMutations: false,
        incomingProviderIsAuthoritative: true,
      );
      expect(
        (await repo.loadTrackingStates()).single.status,
        AniListListStatus.completed,
        reason:
            'A status-filtered preview must not overwrite canonical tracking fields.',
      );
    },
  );

  test(
    'An unrelated local note edit should preserve a concurrently imported Completed state',
    () async {
      final a = memory(), b = memory();
      final initial = example(score: null);
      await a.saveTrackingStates([initial]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      final staleRead = (await b.loadTrackingStates()).single;
      final done = example(
        completed: true,
        score: 8.5,
        at: DateTime.utc(2026, 10, 5, 13),
      );
      await mutate(
        a,
        done,
        UserMediaPatch(
          status: AniListListStatus.completed,
          progress: 12,
          score: 8.5,
        ),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      final completedRow = await b.database
          .customSelect(
            'SELECT field_revisions_json FROM canonical_library_records',
          )
          .getSingle();
      final beforeRevision =
          jsonDecode(completedRow.read<String>('field_revisions_json')) as Map;
      await mutate(
        b,
        staleRead.apply(
          UserMediaPatch(notes: 'A note'),
          DateTime.utc(2026, 10, 5, 14),
        ),
        UserMediaPatch(notes: 'A note'),
      );
      final now = (await b.loadTrackingStates()).single;
      final afterRow = await b.database
          .customSelect(
            'SELECT field_revisions_json FROM canonical_library_records',
          )
          .getSingle();
      final afterRevision =
          jsonDecode(afterRow.read<String>('field_revisions_json')) as Map;
      expect(afterRevision['status'], beforeRevision['status']);
      expect(
        now.status,
        AniListListStatus.completed,
        reason:
            'The status revision remains latest but the stale whole-list save overwrites its value.',
      );
      expect(now.score, 8.5);
    },
  );

  test(
    'A confirmed MAL rounded score should not replace the precise canonical score',
    () async {
      final repo = memory();
      await initialImport(repo, example(score: 0, source: TrackerSource.mal));
      final local = (await repo.loadTrackingStates()).single;
      final patch = UserMediaPatch(score: 8.5);
      final at = DateTime.utc(2026, 10, 5, 15);
      await repo.commitTrackingMutation(
        operationId: 'confirmed-score-edit',
        states: [local.apply(patch, at)],
        journal: const [],
        favorites: const [],
        identity: local.identity,
        patch: patch,
        targets: const {TrackerSource.mal},
        occurredAt: at,
      );
      await repo.updateTrackerDelivery(
        operationId: 'confirmed-score-edit',
        accountId: 'same-viewer',
        identity: local.identity,
        target: TrackerSource.mal,
        state: 'confirmed',
      );
      await repo.reconcileProviderSnapshot(
        source: TrackerSource.mal,
        accountId: 'same-viewer',
        mediaKind: 'anime',
        remote: [example(score: 9, source: TrackerSource.mal, at: at)],
        journal: const [],
        propagationTargets: const {},
        completeSnapshot: true,
      );
      expect(
        (await repo.loadTrackingStates()).single.score,
        8.5,
        reason:
            'MAL score 9 only acknowledges the 8.5 edit that was rounded for that provider.',
      );
    },
  );

  test(
    'Remote delivery confirmation preserves a precise score on Device B',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example(score: 0, source: TrackerSource.mal));
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      final before = (await a.loadTrackingStates()).single;
      final at = DateTime.utc(2026, 10, 5, 15);
      await a.commitTrackingMutation(
        operationId: 'remote-score',
        states: [before.apply(UserMediaPatch(score: 8.5), at)],
        journal: const [],
        favorites: const [],
        identity: before.identity,
        patch: UserMediaPatch(score: 8.5),
        targets: const {TrackerSource.mal},
        occurredAt: at,
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {TrackerSource.mal},
      );
      await a.updateTrackerDelivery(
        operationId: 'remote-score',
        accountId: 'same-viewer',
        identity: before.identity,
        target: TrackerSource.mal,
        state: 'confirmed',
      );
      final ledger = await a.confirmedTrackerDeliveryLedger();
      expect(ledger['remote-score:mal']?['accountId'], 'same-viewer');
      await b.applyRemoteDeliveryLedger(ledger);
      await b.reconcileProviderSnapshot(
        source: TrackerSource.mal,
        accountId: 'same-viewer',
        mediaKind: 'anime',
        remote: [example(score: 9, source: TrackerSource.mal, at: at)],
        journal: await b.loadJournal(),
        propagationTargets: const {},
        completeSnapshot: true,
      );
      expect((await b.loadTrackingStates()).single.score, 8.5);
      final snapshots = await b.database
          .select(b.database.providerSnapshotRecords)
          .get();
      final beforeReplay = snapshots.single.normalizedJson;
      await b.applyRemoteDeliveryLedger(ledger);
      expect(
        (await b.database.select(b.database.providerSnapshotRecords).get())
            .single
            .normalizedJson,
        beforeReplay,
        reason: 'A repeated ledger must not rewrite the comparison baseline.',
      );
    },
  );

  test('Delivery ledger cannot confirm a different provider account', () async {
    final repo = memory();
    final before = example();
    await repo.saveTrackingStates([before]);
    await repo.commitTrackingMutation(
      operationId: 'account-scoped-score',
      states: [before.apply(UserMediaPatch(score: 6), before.updatedAt)],
      journal: const [],
      favorites: const [],
      identity: before.identity,
      patch: UserMediaPatch(score: 6),
      targets: const {TrackerSource.mal},
      occurredAt: before.updatedAt,
    );
    await repo.updateTrackerDelivery(
      operationId: 'account-scoped-score',
      accountId: 'actual-account',
      identity: before.identity,
      target: TrackerSource.mal,
      state: 'delivered',
    );
    for (final accountId in <String?>['other-account', null]) {
      await repo.applyRemoteDeliveryLedger({
        'account-scoped-score:mal': {
          'state': 'confirmed',
          'accountId': ?accountId,
        },
      });
      final delivery = await repo.database
          .customSelect(
            "SELECT state, account_id FROM outbox_delivery_records WHERE delivery_id = 'account-scoped-score:mal'",
          )
          .getSingle();
      expect(delivery.read<String>('state'), 'delivered');
      expect(delivery.read<String>('account_id'), 'actual-account');
    }
  });

  testWidgets('Smiley editor should select the displayed score for raw 87', (
    tester,
  ) async {
    final theme = ThemeData();
    double? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AniListSmileyPicker(
            score: 8.7,
            onChanged: (value) => chosen = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.sentiment_very_satisfied),
    );
    expect(
      chosen,
      0,
      reason:
          'Library displays a happy face for 8.7, so Edit must select that same face.',
    );
  });

  test(
    'Divergent concurrent user edits remain a single real conflict on replay',
    () async {
      final a = memory(), b = memory();
      await a.saveTrackingStates([example()]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await mutate(
        a,
        example().apply(
          UserMediaPatch(progress: 4),
          DateTime.utc(2026, 10, 5, 13),
        ),
        UserMediaPatch(progress: 4),
      );
      await mutate(
        b,
        example().apply(
          UserMediaPatch(progress: 5),
          DateTime.utc(2026, 10, 5, 14),
        ),
        UserMediaPatch(progress: 5),
      );
      final segment = (await a.buildPendingDriveSegment())!;
      await b.applyDriveSegment(segment, trackerTargets: const {});
      expect(await conflicts(b), 1);
      expect((await b.loadTrackingStates()).single.progress, 5);
      await b.applyDriveSegment(
        DriveReplicaSegment.fromJson({
          ...segment.toJson(),
          'segmentId': 'replay',
        }),
        trackerTargets: const {},
      );
      expect(await conflicts(b), 1);
    },
  );

  test('Independent fields merge without losing either device edit', () async {
    final a = memory(), b = memory();
    await a.saveTrackingStates([example()]);
    await b.applyDriveSnapshot(await a.buildDriveSnapshot());
    await mutate(
      a,
      example().apply(
        UserMediaPatch(progress: 4),
        DateTime.utc(2026, 10, 5, 13),
      ),
      UserMediaPatch(progress: 4),
    );
    await mutate(
      b,
      example().apply(
        UserMediaPatch(notes: 'Offline note'),
        DateTime.utc(2026, 10, 5, 14),
      ),
      UserMediaPatch(notes: 'Offline note'),
    );
    await b.applyDriveSegment(
      (await a.buildPendingDriveSegment())!,
      trackerTargets: const {},
    );
    final state = (await b.loadTrackingStates()).single;
    expect(state.progress, 4);
    expect(state.notes, 'Offline note');
    expect(await conflicts(b), 0);
  });

  test(
    'A repeated identical import keeps causal parents for the next edit',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await initialImport(b, example());
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      final before = (await b.loadTrackingStates()).single;
      await mutate(
        b,
        before.apply(
          UserMediaPatch(progress: 4),
          DateTime.utc(2026, 10, 5, 15),
        ),
        UserMediaPatch(progress: 4),
      );
      await a.applyDriveSegment(
        (await b.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect((await a.loadTrackingStates()).single.progress, 4);
      expect(await conflicts(a), 0);
    },
  );

  test(
    'Historical provider imports cannot roll back an explicit Completed action',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await b.saveTrackingStates([example()]);
      await mutate(
        b,
        example(completed: true),
        UserMediaPatch(status: AniListListStatus.completed, progress: 12),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(
        (await b.loadTrackingStates()).single.status,
        AniListListStatus.completed,
      );
      expect((await b.loadTrackingStates()).single.progress, 12);
      expect(await conflicts(b), 0);
    },
  );

  test(
    'The canonical Library does not overlay an older pending Watching action',
    () {
      final current = foldersFromUserMediaStates([example(completed: true)]);
      final result = effectiveTrackerAnimeLibrary(
        providerFolders: foldersFromUserMediaStates([example()]),
        local: TrackerLocalAnimeLibrary(
          canonical: true,
          folders: current,
          pendingMutations: [
            TrackerLibraryOptimisticMutation(
              identity: example().identity,
              patch: UserMediaPatch(status: AniListListStatus.current),
              updatedAt: DateTime.utc(2026, 10, 1),
            ),
          ],
        ),
        optimistic: [
          TrackerLibraryOptimisticMutation(
            identity: example().identity,
            patch: UserMediaPatch(score: 0),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );
      expect(result.single.entries.single.status, AniListListStatus.completed);
      expect(result.single.entries.single.score, 8.5);
      expect(
        effectiveTrackerAnimeLibrary(
          providerFolders: current,
          local: const TrackerLocalAnimeLibrary(
            canonical: true,
            folders: [],
            pendingMutations: [],
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'A restored device does not upload an identical provider library again',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await initialImport(b, example());
      expect(await b.buildPendingDriveSegment(), isNull);
      expect(await conflicts(b), 0);
    },
  );

  test(
    'Library and Favorite providers react to a Drive import without invalidation',
    () async {
      final a = memory(), b = memory();
      final store = CanonicalTrackingSyncStore(repository: b);
      await store.loadStates();
      await a.saveTrackingStates([example()]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      final container = ProviderContainer(
        overrides: [
          canonicalLibraryRepositoryProvider.overrideWithValue(b),
          trackingSyncStoreProvider.overrideWithValue(store),
        ],
      );
      final librarySubscription = container.listen(
        trackerLocalAnimeLibraryProvider,
        (_, _) {},
      );
      final favoriteSubscription = container.listen(
        anilistFavoriteProvider,
        (_, _) {},
      );
      addTearDown(() {
        librarySubscription.close();
        favoriteSubscription.close();
        container.dispose();
      });
      expect(
        (await container.read(
          trackerLocalAnimeLibraryProvider.future,
        )).folders.single.entries.single.status,
        AniListListStatus.current,
      );
      await mutate(
        a,
        example(completed: true),
        UserMediaPatch(
          status: AniListListStatus.completed,
          progress: 12,
          favorite: true,
        ),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      for (int attempt = 0; attempt < 50; attempt++) {
        final status = container
            .read(trackerLocalAnimeLibraryProvider)
            .asData
            ?.value
            .folders
            .single
            .entries
            .single
            .status;
        final favorite = localFavoriteFor(
          container.read(anilistFavoriteProvider),
          example().identity,
        );
        if (status == AniListListStatus.completed && favorite == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        container
            .read(trackerLocalAnimeLibraryProvider)
            .requireValue
            .folders
            .single
            .entries
            .single
            .status,
        AniListListStatus.completed,
      );
      expect(
        localFavoriteFor(
          container.read(anilistFavoriteProvider),
          example().identity,
        ),
        true,
      );
    },
  );

  test(
    'Editor scoreRaw follows canonical score, not the old provider snapshot',
    () {
      final initial = example(score: 3.5).withProviderSnapshot(
        ProviderUserMediaState(
          provider: TrackerSource.anilist,
          data: const {'scoreRaw': 35},
        ),
      );
      final edited = initial.apply(
        UserMediaPatch(score: 8.7),
        DateTime.utc(2026, 10, 5),
      );
      final entry = foldersFromUserMediaStates([edited]).single.entries.single;
      expect(entry.score, 8.7);
      expect(entry.scoreRaw, 87);
    },
  );

  test(
    'Favorite outside the list replicates without adding membership',
    () async {
      final a = memory(), b = memory();
      await a.commitTrackingMutation(
        states: const [],
        journal: const [],
        favorites: const [],
        identity: example().identity,
        patch: UserMediaPatch(favorite: true),
        targets: const {},
        occurredAt: DateTime.utc(2026, 10, 5),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await b.loadTrackingStates(), isEmpty);
      expect((await b.loadFavorites()).single.favorite, true);
      final c = memory();
      await c.applyDriveSnapshot(await a.buildDriveSnapshot());
      expect(await c.loadTrackingStates(), isEmpty);
      expect((await c.loadFavorites()).single.favorite, true);
    },
  );

  test(
    'Favorite off and unrelated edits preserve the correct persisted value',
    () async {
      final a = memory(), b = memory();
      await a.saveTrackingStates([example()]);
      await mutate(a, example(), UserMediaPatch(favorite: true));
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await mutate(a, example(), UserMediaPatch(favorite: false));
      await mutate(
        a,
        example().apply(
          UserMediaPatch(notes: 'Keep the heart off'),
          DateTime.utc(2026, 10, 5),
        ),
        UserMediaPatch(notes: 'Keep the heart off'),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect((await b.loadFavorites()).single.favorite, false);
      expect((await b.loadTrackingStates()).single.notes, 'Keep the heart off');
    },
  );

  test(
    'A real MAL score change away from the confirmed projection is imported',
    () async {
      final repo = memory();
      await initialImport(repo, example(score: 0, source: TrackerSource.mal));
      final before = (await repo.loadTrackingStates()).single;
      await repo.commitTrackingMutation(
        operationId: 'score',
        states: [
          before.apply(UserMediaPatch(score: 8.5), DateTime.utc(2026, 10, 5)),
        ],
        journal: const [],
        favorites: const [],
        identity: before.identity,
        patch: UserMediaPatch(score: 8.5),
        targets: const {TrackerSource.mal},
        occurredAt: DateTime.utc(2026, 10, 5),
      );
      await repo.updateTrackerDelivery(
        operationId: 'score',
        accountId: 'same-viewer',
        identity: before.identity,
        target: TrackerSource.mal,
        state: 'confirmed',
      );
      await repo.reconcileProviderSnapshot(
        source: TrackerSource.mal,
        accountId: 'same-viewer',
        mediaKind: 'anime',
        remote: [example(score: 7, source: TrackerSource.mal)],
        journal: const [],
        propagationTargets: const {},
        completeSnapshot: true,
      );
      expect((await repo.loadTrackingStates()).single.score, 7);
    },
  );

  test(
    'A delivery pass cannot remove a concurrently appended local operation',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([example()]);
      final store = CanonicalTrackingSyncStore(repository: repo);
      await store.loadStates();
      final old = SyncJournalEntry(
        operationId: 'old',
        identity: example().identity,
        patch: UserMediaPatch(progress: 4),
        pendingTargets: const {TrackerSource.anilist},
        createdAt: DateTime.utc(2026, 10, 5),
        updatedAt: DateTime.utc(2026, 10, 5),
      );
      await repo.saveJournal([old]);
      final baseline = await repo.loadJournal();
      final added = SyncJournalEntry(
        operationId: 'new',
        identity: example().identity,
        patch: UserMediaPatch(notes: 'Next'),
        pendingTargets: const {TrackerSource.anilist},
        createdAt: DateTime.utc(2026, 10, 6),
        updatedAt: DateTime.utc(2026, 10, 6),
      );
      await repo.commitTrackingMutation(
        operationId: 'new',
        states: [example()],
        journal: [old, added],
        favorites: const [],
        identity: example().identity,
        patch: added.patch,
        targets: added.pendingTargets,
        occurredAt: added.createdAt,
      );
      await store.saveJournalChanges(baseline, const []);
      expect((await repo.loadJournal()).map((e) => e.operationId), ['new']);
      expect((await repo.loadTrackingStates()).single.notes, 'Next');
    },
  );

  test(
    'Consistency repair restores a revisioned value and remains idempotent',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([example()]);
      await mutate(
        repo,
        example(completed: true),
        UserMediaPatch(status: AniListListStatus.completed, progress: 12),
      );
      await repo.saveTrackingStates([
        example(),
      ]); // Reproduce the old stale whole-row write.
      await repo.repairSyncConsistency();
      expect(
        (await repo.loadTrackingStates()).single.status,
        AniListListStatus.completed,
      );
      expect((await repo.loadTrackingStates()).single.progress, 12);
      final before = (await repo.watchActivity().first).length;
      await repo.repairSyncConsistency();
      expect((await repo.watchActivity().first).length, before);
    },
  );

  test(
    'Consistency repair closes duplicate/equal historical conflicts only',
    () async {
      final a = memory(), b = memory();
      await a.saveTrackingStates([example()]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await mutate(
        a,
        example().apply(
          UserMediaPatch(progress: 4),
          DateTime.utc(2026, 10, 5, 13),
        ),
        UserMediaPatch(progress: 4),
      );
      await mutate(
        b,
        example().apply(
          UserMediaPatch(progress: 5),
          DateTime.utc(2026, 10, 5, 14),
        ),
        UserMediaPatch(progress: 5),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      await b.database.customStatement(
        "INSERT INTO library_conflict_records SELECT conflict_id || '-duplicate', local_id, field_name, local_value_json, incoming_value_json, local_operation_id, incoming_operation_id, state, created_at_ms, resolved_at_ms FROM library_conflict_records",
      );
      expect(await conflicts(b), 2);
      await b.repairSyncConsistency();
      expect(await conflicts(b), 1);
      expect((await b.loadTrackingStates()).single.progress, 5);
    },
  );

  test(
    'A stale local Favorite request cannot re-add a concurrently deleted title',
    () async {
      final repo = memory();
      final old = example();
      await repo.saveTrackingStates([old]);
      await mutate(repo, old, UserMediaPatch(delete: true));
      await mutate(repo, old, UserMediaPatch(favorite: true));
      expect(await repo.loadTrackingStates(), isEmpty);
      expect((await repo.loadFavorites()).single.favorite, true);
      final segment = (await repo.buildPendingDriveSegment())!;
      expect(segment.operations.last['fields'], ['favorite']);
      final b = memory();
      await b.applyDriveSegment(segment, trackerTargets: const {});
      expect(await b.loadTrackingStates(), isEmpty);
      expect((await b.loadFavorites()).single.favorite, true);
    },
  );

  test(
    'Provider removal checks the live journal, not a stale request copy',
    () async {
      final repo = memory();
      await initialImport(repo, example());
      final before = (await repo.loadTrackingStates()).single;
      final at = DateTime.utc(2026, 10, 5, 15);
      final patch = UserMediaPatch(progress: 4);
      await repo.commitTrackingMutation(
        operationId: 'pending-progress',
        states: [before.apply(patch, at)],
        journal: [
          SyncJournalEntry(
            operationId: 'pending-progress',
            identity: before.identity,
            patch: patch,
            pendingTargets: const {TrackerSource.anilist},
            createdAt: at,
            updatedAt: at,
          ),
        ],
        favorites: const [],
        identity: before.identity,
        patch: patch,
        targets: const {TrackerSource.anilist},
        occurredAt: at,
      );
      for (var pass = 0; pass < 2; pass++) {
        await repo.reconcileProviderSnapshot(
          source: TrackerSource.anilist,
          accountId: 'same-viewer',
          mediaKind: 'anime',
          remote: const [],
          journal: const [],
          propagationTargets: const {},
          completeSnapshot: true,
        );
      }
      expect((await repo.loadTrackingStates()).single.progress, 4);
      expect((await repo.loadJournal()).single.operationId, 'pending-progress');
    },
  );

  test(
    'Identical episode checkpoints merge across independent provider imports',
    () async {
      final a = memory(), b = memory();
      await initialImport(a, example());
      await initialImport(b, example());
      for (final repo in [a, b]) {
        await repo.saveEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
          positionSeconds: 95,
          durationSeconds: 1400,
          mediaItem: example().mediaItem,
        );
      }
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await conflicts(b), 0);
      expect(
        (await b.database.select(b.database.canonicalMediaRecords).get()),
        hasLength(1),
      );
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        95,
      );
    },
  );

  test(
    'Episode revisions are independent and a causal checkpoint ignores clock skew',
    () async {
      final a = memory(), b = memory();
      await a.saveTrackingStates([example()]);
      await a.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 95,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await b.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 2,
        positionSeconds: 60,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.database.customStatement(
        'UPDATE episode_state_records SET updated_at_ms = ?',
        [DateTime.utc(2030).millisecondsSinceEpoch],
      );
      await a.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 150,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await conflicts(b), 0);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        150,
      );
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 2,
        ))!.positionSeconds,
        60,
      );
    },
  );

  test(
    'A real same-episode conflict preserves the local position until resolved',
    () async {
      final a = memory(), b = memory();
      await a.saveTrackingStates([example()]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await a.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 90,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 150,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await conflicts(b), 1);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        150,
      );
      final conflict =
          (await b.database.select(b.database.libraryConflictRecords).get())
              .single;
      expect(
        jsonDecode(conflict.incomingValueJson)['episode']['positionSeconds'],
        90,
      );
      await b.resolveConflict(
        conflictId: conflict.conflictId,
        takeIncoming: true,
        trackerTargets: const {},
      );
      expect(await conflicts(b), 0);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        90,
      );
      await a.applyDriveSegment(
        (await b.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await conflicts(a), 0);
      expect(
        (await a.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        90,
      );
    },
  );

  test(
    'Episode checkpoints outside the list replicate without membership',
    () async {
      final a = memory(), b = memory();
      await a.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 95,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      expect(await b.loadTrackingStates(), isEmpty);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        95,
      );
      await a.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 150,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await b.loadTrackingStates(), isEmpty);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: example().mediaItem.id,
          season: 1,
          episode: 1,
        ))!.positionSeconds,
        150,
      );
      expect(await conflicts(b), 0);
    },
  );

  test(
    'Repair retires equal historical episode conflicts using exact checkpoints',
    () async {
      final a = memory(), b = memory();
      await a.saveTrackingStates([example()]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await a.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 90,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.saveEpisodeProgress(
        mediaId: example().mediaItem.id,
        season: 1,
        episode: 1,
        positionSeconds: 150,
        durationSeconds: 1400,
        mediaItem: example().mediaItem,
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      expect(await conflicts(b), 1);
      await b.database.customStatement(
        'UPDATE episode_state_records SET position_seconds = 90',
      );
      await b.repairSyncConsistency();
      expect(await conflicts(b), 0);
    },
  );

  test('A late Favorite edit never restores a deleted library entry', () async {
    final a = memory(), b = memory();
    await a.saveTrackingStates([example()]);
    await b.applyDriveSnapshot(await a.buildDriveSnapshot());
    await mutate(b, example(), UserMediaPatch(delete: true));
    await mutate(a, example(), UserMediaPatch(favorite: true));
    await b.applyDriveSegment(
      (await a.buildPendingDriveSegment())!,
      trackerTargets: const {TrackerSource.anilist},
    );
    expect(await b.loadTrackingStates(), isEmpty);
    expect((await b.loadFavorites()).single.favorite, true);
    expect((await b.loadJournal()).last.patch.fields, {
      UserMediaField.favorite,
    });
  });

  test(
    'A delete received before its original add leaves a durable tombstone',
    () async {
      final a = memory(), b = memory();
      await mutate(
        a,
        example(),
        UserMediaPatch(status: AniListListStatus.current, progress: 3),
      );
      final add = (await a.buildPendingDriveSegment())!;
      await mutate(a, example(), UserMediaPatch(delete: true));
      final full = (await a.buildPendingDriveSegment())!;
      final removal = DriveReplicaSegment.fromJson({
        ...full.toJson(),
        'segmentId': 'delete-first',
        'operations': [full.operations.last],
      });
      await b.applyDriveSegment(removal, trackerTargets: const {});
      await b.applyDriveSegment(add, trackerTargets: const {});
      expect(await b.loadTrackingStates(), isEmpty);
      expect(await conflicts(b), 0);
    },
  );

  test(
    'A stale raw provider payload cannot replace a separately edited priority',
    () async {
      final a = memory(), b = memory();
      final initial = example().apply(
        UserMediaPatch(priority: 1),
        DateTime.utc(2026, 10, 1),
      );
      await a.saveTrackingStates([initial]);
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await mutate(
        a,
        initial.apply(
          UserMediaPatch(notes: 'Note from A'),
          DateTime.utc(2026, 10, 5),
        ),
        UserMediaPatch(notes: 'Note from A'),
      );
      await mutate(
        b,
        initial.apply(UserMediaPatch(priority: 3), DateTime.utc(2026, 10, 5)),
        UserMediaPatch(priority: 3),
      );
      await b.applyDriveSegment(
        (await a.buildPendingDriveSegment())!,
        trackerTargets: const {},
      );
      final state = (await b.loadTrackingStates()).single;
      expect(state.providerStates[TrackerSource.anilist]!.data['priority'], 3);
      expect(state.notes, 'Note from A');
      expect(await conflicts(b), 0);
    },
  );

  test(
    'Repair restores membership lost by an old whole-list save, not a real deletion',
    () async {
      final restored = memory(), removed = memory();
      for (final repo in [restored, removed]) {
        await mutate(
          repo,
          example(),
          UserMediaPatch(status: AniListListStatus.current, progress: 3),
        );
      }
      await restored.saveTrackingStates(const []);
      await mutate(removed, example(), UserMediaPatch(delete: true));
      await restored.repairSyncConsistency();
      await removed.repairSyncConsistency();
      expect(await restored.loadTrackingStates(), hasLength(1));
      expect(await removed.loadTrackingStates(), isEmpty);
    },
  );
}
