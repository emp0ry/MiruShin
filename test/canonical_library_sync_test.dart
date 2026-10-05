import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/data/canonical_library_database_open_io.dart';
import 'package:mirushin/features/library/domain/canonical_library_models.dart';
import 'package:mirushin/features/library/domain/cloud_replica_models.dart';
import 'package:mirushin/features/tracking/data/canonical_tracking_sync_store.dart';
import 'package:mirushin/features/tracking/data/tracking_sync_store.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('AniList-compatible score formats', () {
    test('supports all five formats without rewriting scoreRaw', () {
      expect(CanonicalScoreFormat.point100.rawFromInput(87), 87);
      expect(CanonicalScoreFormat.point10Decimal.rawFromInput(8.7), 87);
      expect(CanonicalScoreFormat.point10.rawFromInput(9), 90);
      expect(CanonicalScoreFormat.point5.rawFromInput(4), 80);
      expect(CanonicalScoreFormat.point3.rawFromInput(1), 35);
      expect(CanonicalScoreFormat.point3.rawFromInput(2), 60);
      expect(CanonicalScoreFormat.point3.rawFromInput(3), 85);

      const int raw = 87;
      expect(CanonicalScoreFormat.point100.displayFromRaw(raw), 87);
      expect(CanonicalScoreFormat.point10Decimal.displayFromRaw(raw), 8.7);
      expect(CanonicalScoreFormat.point10.displayFromRaw(raw), 9);
      expect(CanonicalScoreFormat.point5.displayFromRaw(raw), 4);
      expect(CanonicalScoreFormat.point3.displayLabel(raw), ':)');
      expect(
        CanonicalScoreFormat.fromAniList('SMILEY'),
        CanonicalScoreFormat.point3,
      );
    });
  });

  group('canonical SQLite library', () {
    late CanonicalLibraryDatabase database;
    late CanonicalLibraryRepository repository;

    setUp(() {
      database = CanonicalLibraryDatabase(NativeDatabase.memory());
      repository = CanonicalLibraryRepository(database);
    });

    tearDown(() => database.close());

    test(
      'native Library reads do not wait for a Drive write transaction',
      () async {
        final Directory temporary = await Directory.systemTemp.createTemp(
          'mirushin-library-read-pool-',
        );
        final CanonicalLibraryDatabase fileDatabase = CanonicalLibraryDatabase(
          canonicalLibraryNativeConnection(
            File('${temporary.path}/library.sqlite'),
          ),
        );
        final CanonicalLibraryRepository fileRepository =
            CanonicalLibraryRepository(fileDatabase);
        final Completer<void> writerStarted = Completer<void>();
        final Completer<void> finishWriter = Completer<void>();
        Future<void>? writer;
        try {
          await fileRepository.saveTrackingStates(<UserMediaState>[
            _state(progress: 6),
          ]);
          writer = fileDatabase.transaction(() async {
            await fileDatabase.customStatement(
              "UPDATE legacy_bucket_records SET value_json = 'busy' "
              "WHERE bucket = 'meta.deviceId'",
            );
            writerStarted.complete();
            await finishWriter.future;
          });
          await writerStarted.future;
          final Future<List<UserMediaState>> read = fileRepository
              .loadTrackingStates();
          final bool returnedWhileWriting = await Future.any(<Future<bool>>[
            read.then(
              (List<UserMediaState> rows) =>
                  rows.length == 1 && rows.single.progress == 6,
            ),
            Future<bool>.delayed(const Duration(seconds: 2), () => false),
          ]);
          expect(returnedWhileWriting, isTrue);
        } finally {
          finishWriter.complete();
          if (writer != null) await writer;
          await fileDatabase.close();
          await temporary.delete(recursive: true);
        }
      },
    );

    test(
      'upgrades a v1 database without losing local state or journal',
      () async {
        final Directory temporary = await Directory.systemTemp.createTemp(
          'mirushin-library-migration-',
        );
        final File file = File('${temporary.path}/library.sqlite');
        try {
          final CanonicalLibraryDatabase oldDatabase = CanonicalLibraryDatabase(
            NativeDatabase(file),
          );
          final CanonicalLibraryRepository oldRepository =
              CanonicalLibraryRepository(oldDatabase);
          final UserMediaState state = _state(progress: 6);
          final SyncJournalEntry queued = _journal(
            state,
            UserMediaPatch(progress: 6),
          );
          await oldRepository.importTrackingData(
            states: <UserMediaState>[state],
            journal: <SyncJournalEntry>[queued],
            favorites: const <LocalMediaFavoriteState>[],
            health: const <TrackerSource, TrackerProviderHealth>{},
          );
          // Recreate the pre-v2 file shape while preserving its real rows.
          await oldDatabase.customStatement(
            'DROP INDEX outbox_operation_target_account_idx',
          );
          await oldDatabase.customStatement(
            'DROP INDEX library_operation_local_time_idx',
          );
          await oldDatabase.customStatement('PRAGMA user_version = 1');
          await oldDatabase.close();

          final CanonicalLibraryDatabase upgraded = CanonicalLibraryDatabase(
            NativeDatabase(file),
          );
          try {
            final CanonicalLibraryRepository repository =
                CanonicalLibraryRepository(upgraded);
            expect((await repository.loadTrackingStates()).single.progress, 6);
            expect(await repository.loadJournal(), hasLength(1));
            final indexes = await upgraded
                .customSelect("PRAGMA index_list('outbox_delivery_records')")
                .get();
            expect(
              indexes.map((row) => row.read<String>('name')),
              contains('outbox_operation_target_account_idx'),
            );
            final version = await upgraded
                .customSelect('PRAGMA user_version')
                .getSingle();
            expect(version.read<int>('user_version'), 2);
          } finally {
            await upgraded.close();
          }
        } finally {
          await temporary.delete(recursive: true);
        }
      },
    );

    test(
      'Device B pulls an A operation without creating Drive upload work',
      () async {
        final UserMediaState original = _state(progress: 2);
        await repository.saveTrackingStates(<UserMediaState>[original]);
        final DriveLibrarySnapshot initial = await repository
            .buildDriveSnapshot();
        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        addTearDown(peerDatabase.close);
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        await peer.applyDriveSnapshot(initial);
        expect(await peer.pendingDriveDeliveryCount(), 0);

        final UserMediaPatch patch = UserMediaPatch(progress: 7);
        final UserMediaState changed = original.apply(
          patch,
          DateTime.utc(2026, 9, 28),
        );
        await repository.commitTrackingMutation(
          operationId: 'device-a-progress-7',
          states: <UserMediaState>[changed],
          journal: <SyncJournalEntry>[
            SyncJournalEntry(
              operationId: 'device-a-progress-7',
              identity: changed.identity,
              patch: patch,
              pendingTargets: const <TrackerSource>{},
              createdAt: DateTime.utc(2026, 9, 28),
              updatedAt: DateTime.utc(2026, 9, 28),
            ),
          ],
          favorites: const <LocalMediaFavoriteState>[],
          identity: changed.identity,
          patch: patch,
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 28),
        );
        final DriveReplicaSegment segment = (await repository
            .buildPendingDriveSegment())!;
        expect(
          await peer.applyDriveSegment(
            segment,
            trackerTargets: const <TrackerSource>{},
          ),
          1,
        );
        expect((await peer.loadTrackingStates()).single.progress, 7);
        expect(
          (await peer.loadTrackingStates()).single.updatedAt,
          DateTime.utc(2026, 9, 28),
          reason: 'Receiving a Drive operation must not change Updated sort.',
        );
        expect(await peer.pendingDriveDeliveryCount(), 0);
        expect(await peer.watchConflicts().first, isEmpty);
        expect(
          await peer.applyDriveSegment(
            segment,
            trackerTargets: const <TrackerSource>{},
          ),
          0,
        );
      },
    );

    test('delivery confirmation updates only its own operation', () async {
      final UserMediaState original = _state(progress: 2);
      await repository.saveTrackingStates(<UserMediaState>[original]);
      final UserMediaPatch firstPatch = UserMediaPatch(progress: 3);
      final UserMediaState first = original.apply(
        firstPatch,
        DateTime.utc(2026, 9, 28),
      );
      final SyncJournalEntry firstJournal = SyncJournalEntry(
        operationId: 'progress-3',
        identity: original.identity,
        patch: firstPatch,
        pendingTargets: const <TrackerSource>{TrackerSource.anilist},
        createdAt: DateTime.utc(2026, 9, 28),
        updatedAt: DateTime.utc(2026, 9, 28),
      );
      await repository.commitTrackingMutation(
        operationId: 'progress-3',
        states: <UserMediaState>[first],
        journal: <SyncJournalEntry>[firstJournal],
        favorites: const <LocalMediaFavoriteState>[],
        identity: first.identity,
        patch: firstPatch,
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 28),
      );
      final UserMediaPatch secondPatch = UserMediaPatch(progress: 4);
      final UserMediaState second = first.apply(
        secondPatch,
        DateTime.utc(2026, 9, 28, 0, 1),
      );
      await repository.commitTrackingMutation(
        operationId: 'progress-4',
        states: <UserMediaState>[second],
        journal: <SyncJournalEntry>[
          firstJournal,
          SyncJournalEntry(
            operationId: 'progress-4',
            identity: original.identity,
            patch: secondPatch,
            pendingTargets: const <TrackerSource>{TrackerSource.anilist},
            createdAt: DateTime.utc(2026, 9, 28, 0, 1),
            updatedAt: DateTime.utc(2026, 9, 28, 0, 1),
          ),
        ],
        favorites: const <LocalMediaFavoriteState>[],
        identity: second.identity,
        patch: secondPatch,
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 28, 0, 1),
      );
      await repository.updateTrackerDelivery(
        operationId: 'progress-3',
        accountId: 'viewer-1',
        identity: original.identity,
        target: TrackerSource.anilist,
        state: 'confirmed',
      );
      final List<LibraryActivityEvent> events = await repository
          .watchActivity()
          .first;
      expect(
        events
            .firstWhere((event) => event.operationId == 'progress-3')
            .deliveryStates['anilist'],
        'confirmed',
      );
      expect(
        events
            .firstWhere((event) => event.operationId == 'progress-4')
            .deliveryStates['anilist'],
        'pending',
      );
    });

    test(
      'Drive batches preserve delete then re-add across batch boundaries',
      () async {
        final UserMediaState original = _state(progress: 2);
        await repository.saveTrackingStates(<UserMediaState>[original]);
        final String localId =
            (await repository.loadTrackingStates()).single.identity.localId;
        await repository.appendOperation(
          LibraryOperationDraft(
            operationId: 'z-delete-first',
            localId: localId,
            originKind: LibraryOriginKind.user,
            intent: LibraryMutationIntent.remove,
            fields: const <String>{'membership'},
            before: <String, dynamic>{'state': original.toJson()},
            after: const <String, dynamic>{},
            targets: const <String>{},
            occurredAt: DateTime.utc(2026, 9, 28, 1),
          ),
        );
        await repository.appendOperation(
          LibraryOperationDraft(
            operationId: 'a-readd-second',
            localId: localId,
            originKind: LibraryOriginKind.user,
            intent: LibraryMutationIntent.add,
            fields: const <String>{'membership'},
            before: const <String, dynamic>{},
            after: <String, dynamic>{'state': original.toJson()},
            targets: const <String>{},
            occurredAt: DateTime.utc(2026, 9, 28, 2),
          ),
        );

        final DriveReplicaSegment first = (await repository
            .buildPendingDriveSegment(limit: 1))!;
        expect(first.operations.single['operationId'], 'z-delete-first');
        await repository.markDriveSegmentDelivered(
          first,
          remoteFileId: 'first',
        );
        final DriveReplicaSegment second = (await repository
            .buildPendingDriveSegment(limit: 1))!;
        expect(second.operations.single['operationId'], 'a-readd-second');
      },
    );

    test('recovers delete and re-add from the v1 operation outbox', () async {
      final UserMediaState initial = _state(progress: 2);
      await repository.saveTrackingStates(<UserMediaState>[initial]);
      final UserMediaPatch delete = UserMediaPatch(delete: true);
      await repository.commitTrackingMutation(
        states: const <UserMediaState>[],
        journal: <SyncJournalEntry>[_journal(initial, delete)],
        favorites: const <LocalMediaFavoriteState>[],
        identity: initial.identity,
        patch: delete,
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 28),
      );
      final UserMediaPatch add = UserMediaPatch(
        status: AniListListStatus.current,
        progress: 1,
      );
      final UserMediaState restored = initial.apply(
        add,
        DateTime.utc(2026, 9, 28, 0, 1),
      );
      await repository.commitTrackingMutation(
        states: <UserMediaState>[restored],
        // The old app kept only this final title-coalesced journal entry.
        journal: <SyncJournalEntry>[_journal(restored, add)],
        favorites: const <LocalMediaFavoriteState>[],
        identity: initial.identity,
        patch: add,
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 28, 0, 1),
      );

      await repository.recoverLegacyOperationDeliveries();
      final List<SyncJournalEntry> journal = await repository.loadJournal();
      expect(journal, hasLength(2));
      expect(journal.map((entry) => entry.patch.delete), <bool>[true, false]);
      expect(journal.every((entry) => entry.operationId != null), isTrue);
      expect(journal.every((entry) => entry.readbackBeforeWrite), isTrue);
      await repository.recoverLegacyOperationDeliveries();
      expect(await repository.loadJournal(), hasLength(2));
    });

    test('migrates 2.8.9 SharedPreferences exactly once', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      const SharedPreferencesTrackingSyncStore legacy =
          SharedPreferencesTrackingSyncStore();
      final UserMediaState legacyState = _state(progress: 6);
      final SyncJournalEntry legacyJournal = _journal(
        legacyState,
        UserMediaPatch(progress: 6),
      );
      await legacy.saveStates(<UserMediaState>[legacyState]);
      await legacy.saveJournal(<SyncJournalEntry>[legacyJournal]);

      final CanonicalTrackingSyncStore first = CanonicalTrackingSyncStore(
        repository: repository,
        legacy: legacy,
      );
      expect(await first.loadStates(), hasLength(1));
      expect(await first.loadJournal(), hasLength(1));
      expect(
        await repository.hasMigration('tracking.shared_preferences.v1'),
        isTrue,
      );

      final CanonicalTrackingSyncStore restarted = CanonicalTrackingSyncStore(
        repository: repository,
        legacy: legacy,
      );
      expect(await restarted.loadStates(), hasLength(1));
      expect(await restarted.loadJournal(), hasLength(1));
      expect(
        await legacy.loadStates(),
        isEmpty,
        reason: 'Verified SQLite migration removes the duplicate bulk payload.',
      );
      expect(await legacy.loadJournal(), isEmpty);
    });

    test(
      'full Drive snapshot bootstraps every render-ready library entry atomically',
      () async {
        final UserMediaState base = _state(progress: 7);
        final UserMediaState rich = base.withMediaItem(
          base.mediaItem.copyWith(
            overview: 'Complete offline presentation metadata',
            posterUrl: 'https://cdn.example/poster.jpg',
            externalIds: <String, String>{
              ...base.mediaItem.externalIds,
              'anilist_popularity': '123456',
              'anilist_favourites': '7890',
              anilistNextAiringEpisodeKey: '9',
              anilistNextAiringAtKey: '1790280000',
            },
          ),
        );
        await repository.saveTrackingStates(<UserMediaState>[rich]);
        final DriveLibrarySnapshot snapshot = await repository
            .buildDriveSnapshot();
        expect(snapshot.entryCount, 1);
        expect(snapshot.media.single['media'], isA<Map>());

        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        addTearDown(peerDatabase.close);
        final DriveSnapshotApplyResult result = await peer.applyDriveSnapshot(
          snapshot,
        );
        expect(result.freshBootstrap, isTrue);
        expect(result.cloudEntryCount, 1);
        expect(result.localEntryCount, 1);
        final UserMediaState restored =
            (await peer.loadTrackingStates()).single;
        expect(restored.progress, 7);
        expect(restored.mediaItem.posterUrl, contains('poster.jpg'));
        expect(restored.mediaItem.externalIds['anilist_popularity'], '123456');
        expect(
          restored.mediaItem.externalIds[anilistNextAiringEpisodeKey],
          '9',
        );
        expect(restored.providerStates[TrackerSource.anilist]?.entryId, 100);
      },
    );

    test(
      'Drive snapshot checksum changes only with replicated content',
      () async {
        await repository.saveTrackingStates(<UserMediaState>[
          _state(progress: 4),
        ]);
        final DriveLibrarySnapshot first = await repository
            .buildDriveSnapshot();
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final DriveLibrarySnapshot same = await repository.buildDriveSnapshot();

        expect(same.snapshotId, isNot(first.snapshotId));
        expect(same.createdAt, isNot(first.createdAt));
        expect(same.checksum, first.checksum);
        expect(
          same.legacyEnvelopeChecksum,
          isNot(first.legacyEnvelopeChecksum),
        );

        await repository.saveTrackingStates(<UserMediaState>[
          _state(progress: 5),
        ]);
        final DriveLibrarySnapshot changed = await repository
            .buildDriveSnapshot();
        expect(changed.checksum, isNot(first.checksum));
      },
    );

    test(
      'provider verification timestamps do not rewrite full backup',
      () async {
        final UserMediaState remote = _state(progress: 4);
        await repository.reconcileProviderSnapshot(
          source: TrackerSource.anilist,
          accountId: 'stable-viewer',
          mediaKind: 'anime',
          remote: <UserMediaState>[remote],
          journal: const <SyncJournalEntry>[],
          propagationTargets: const <TrackerSource>{},
          completeSnapshot: true,
        );
        await repository.approveProviderAccount(
          provider: 'anilist',
          accountId: 'stable-viewer',
        );
        await repository.reconcileProviderSnapshot(
          source: TrackerSource.anilist,
          accountId: 'stable-viewer',
          mediaKind: 'anime',
          remote: <UserMediaState>[remote],
          journal: const <SyncJournalEntry>[],
          propagationTargets: const <TrackerSource>{},
          completeSnapshot: true,
        );
        final String checksum =
            (await repository.buildDriveSnapshot()).checksum;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await repository.reconcileProviderSnapshot(
          source: TrackerSource.anilist,
          accountId: 'stable-viewer',
          mediaKind: 'anime',
          remote: <UserMediaState>[remote],
          journal: const <SyncJournalEntry>[],
          propagationTargets: const <TrackerSource>{},
          completeSnapshot: true,
        );
        expect((await repository.buildDriveSnapshot()).checksum, checksum);
      },
    );

    test('detail enrichment updates only metadata and queues Drive', () async {
      final UserMediaState initial = _state(progress: 6);
      await repository.saveTrackingStates(<UserMediaState>[initial]);
      final MediaItem rich = initial.mediaItem.copyWith(
        overview: 'Offline synopsis',
        backdropUrl: 'https://example.com/banner.jpg',
        genres: const <String>['Comedy'],
        externalIds: <String, String>{
          ...initial.mediaItem.externalIds,
          'anilist_tags': 'Slapstick:85:0:0:Theme',
          'anilist_studios': 'ENGI:1',
          'anilist_popularity': '12345',
        },
      );

      final MediaItem merged = await repository.enrichPresentationMetadata(
        identity: initial.identity,
        mediaItem: rich,
      );
      final UserMediaState stored =
          (await repository.loadTrackingStates()).single;

      expect(merged.overview, 'Offline synopsis');
      expect(stored.progress, 6);
      expect(stored.status, initial.status);
      expect(stored.mediaItem.backdropUrl, contains('banner.jpg'));
      expect(
        stored.mediaItem.externalIds['anilist_tags'],
        contains('Slapstick'),
      );
      expect(await repository.watchActivity().first, isEmpty);
      expect(await repository.watchPendingDriveDeliveryCount().first, 1);
    });

    test(
      'Drive checkpoint fills missing entries without whole-record overwrites',
      () async {
        final UserMediaState remoteShared = _state(progress: 7, score: 7);
        final UserMediaState remoteOnly = _remoteShikimoriState(333);
        await repository.saveTrackingStates(<UserMediaState>[
          remoteShared,
          remoteOnly,
        ]);
        final DriveLibrarySnapshot snapshot = await repository
            .buildDriveSnapshot();

        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        addTearDown(peerDatabase.close);
        await peer.saveTrackingStates(<UserMediaState>[
          _state(progress: 2, score: 9.5),
        ]);

        final DriveSnapshotApplyResult result = await peer.applyDriveSnapshot(
          snapshot,
        );
        final List<UserMediaState> restored = await peer.loadTrackingStates();
        final UserMediaState shared = restored.singleWhere(
          (UserMediaState value) => value.identity.anilistId == 10,
        );

        expect(result.freshBootstrap, isFalse);
        expect(result.restoredEntries, 1);
        expect(result.localEntryCount, 2);
        expect(shared.progress, 2);
        expect(shared.score, 9.5);
        expect(
          restored.any(
            (UserMediaState value) => value.identity.shikimoriId == 100333,
          ),
          isTrue,
        );
      },
    );

    test(
      'Drive checkpoint causally repairs a missed operation on an existing device',
      () async {
        final UserMediaState initial = _state(progress: 2);
        await repository.saveTrackingStates(<UserMediaState>[initial]);
        final DriveLibrarySnapshot initialSnapshot = await repository
            .buildDriveSnapshot();

        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        addTearDown(peerDatabase.close);
        await peer.applyDriveSnapshot(initialSnapshot);

        final UserMediaState updated = _state(progress: 7);
        final UserMediaPatch patch = UserMediaPatch(progress: 7);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[updated],
          journal: <SyncJournalEntry>[_journal(updated, patch)],
          favorites: const <LocalMediaFavoriteState>[],
          identity: updated.identity,
          patch: patch,
          targets: const <TrackerSource>{TrackerSource.mal},
          occurredAt: DateTime.utc(2026, 9, 24),
          mediaTitle: updated.mediaItem.title,
        );
        final DriveLibrarySnapshot repairedSnapshot = await repository
            .buildDriveSnapshot();

        final List<int> progressTotals = <int>[];
        final DriveSnapshotApplyResult result = await peer.applyDriveSnapshot(
          repairedSnapshot,
          trackerTargets: const <TrackerSource>{TrackerSource.mal},
          onProgress: (int _, int total) => progressTotals.add(total),
        );
        final UserMediaState restored =
            (await peer.loadTrackingStates()).single;

        expect(restored.progress, 7);
        expect(result.restoredEntries, 0);
        expect(result.recoveredOperations, 1);
        expect(progressTotals, isNotEmpty);
        expect(progressTotals.toSet(), <int>{1});
        expect(
          await peer.hasAppliedDriveSnapshot(repairedSnapshot.checksum),
          isTrue,
        );

        final DriveSnapshotApplyResult repeated = await peer.applyDriveSnapshot(
          repairedSnapshot,
          trackerTargets: const <TrackerSource>{TrackerSource.mal},
        );
        expect(repeated.recoveredOperations, 0);
        expect((await peer.loadTrackingStates()).single.progress, 7);
      },
    );

    test(
      'Drive checkpoint recovery never overwrites a concurrent local field edit',
      () async {
        final UserMediaState initial = _state(progress: 2);
        await repository.saveTrackingStates(<UserMediaState>[initial]);
        final DriveLibrarySnapshot initialSnapshot = await repository
            .buildDriveSnapshot();

        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        addTearDown(peerDatabase.close);
        await peer.applyDriveSnapshot(initialSnapshot);

        final UserMediaState localEdit = _state(progress: 4);
        final UserMediaPatch localPatch = UserMediaPatch(progress: 4);
        await peer.commitTrackingMutation(
          operationId: 'device-b-progress',
          states: <UserMediaState>[localEdit],
          journal: <SyncJournalEntry>[
            SyncJournalEntry(
              operationId: 'device-b-progress',
              identity: localEdit.identity,
              patch: localPatch,
              pendingTargets: const <TrackerSource>{TrackerSource.anilist},
              createdAt: DateTime.utc(2026, 9, 24, 1),
              updatedAt: DateTime.utc(2026, 9, 24, 1),
            ),
          ],
          favorites: const <LocalMediaFavoriteState>[],
          identity: localEdit.identity,
          patch: localPatch,
          targets: const <TrackerSource>{TrackerSource.anilist},
          occurredAt: DateTime.utc(2026, 9, 24, 1),
          mediaTitle: localEdit.mediaItem.title,
        );

        final UserMediaState remoteEdit = _state(progress: 7);
        final UserMediaPatch remotePatch = UserMediaPatch(progress: 7);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[remoteEdit],
          journal: <SyncJournalEntry>[_journal(remoteEdit, remotePatch)],
          favorites: const <LocalMediaFavoriteState>[],
          identity: remoteEdit.identity,
          patch: remotePatch,
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24, 2),
          mediaTitle: remoteEdit.mediaItem.title,
        );

        final DriveSnapshotApplyResult result = await peer.applyDriveSnapshot(
          await repository.buildDriveSnapshot(),
        );
        expect((await peer.loadTrackingStates()).single.progress, 4);
        expect(result.recoveredOperations, 0);
        expect(await peer.watchConflicts().first, isNotEmpty);
        expect(await peer.unresolvedConflictLocalOperationIds(), hasLength(1));

        final CanonicalLibraryConflict conflict =
            (await peer.watchConflicts().first).single;
        await peer.resolveConflict(
          conflictId: conflict.conflictId,
          takeIncoming: true,
          trackerTargets: const <TrackerSource>{TrackerSource.anilist},
        );
        final List<SyncJournalEntry> journal = await peer.loadJournal();
        expect(
          journal.any(
            (SyncJournalEntry value) =>
                value.operationId == 'device-b-progress',
          ),
          isFalse,
        );
        expect(journal.last.patch.progress, 7);
        expect(await peer.unresolvedConflictLocalOperationIds(), isEmpty);
        final LibraryActivityEvent staleOperation =
            (await peer.watchActivity().first).singleWhere(
              (LibraryActivityEvent value) =>
                  value.operationId == 'device-b-progress',
            );
        expect(staleOperation.deliveryStates['anilist'], 'superseded');

        final DriveReplicaSegment rebased = (await peer
            .buildPendingDriveSegment())!;
        expect(rebased.operations.first['operationId'], 'device-b-progress');
        await repository.applyDriveSegment(
          rebased,
          trackerTargets: const <TrackerSource>{},
        );
        expect((await repository.loadTrackingStates()).single.progress, 7);
        expect(await repository.watchConflicts().first, isEmpty);
      },
    );

    test(
      'Drive merges A progress with B score without a false conflict',
      () async {
        final UserMediaState initial = _state(progress: 2);
        await repository.saveTrackingStates(<UserMediaState>[initial]);
        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        addTearDown(peerDatabase.close);
        await peer.applyDriveSnapshot(await repository.buildDriveSnapshot());

        final UserMediaPatch scorePatch = UserMediaPatch(score: 9);
        final UserMediaState scoreEdit = initial.apply(
          scorePatch,
          DateTime.utc(2026, 9, 24, 1),
        );
        await peer.commitTrackingMutation(
          operationId: 'device-b-score',
          states: <UserMediaState>[scoreEdit],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: scoreEdit.identity,
          patch: scorePatch,
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24, 1),
        );

        final UserMediaPatch progressPatch = UserMediaPatch(progress: 7);
        final UserMediaState progressEdit = initial.apply(
          progressPatch,
          DateTime.utc(2026, 9, 24, 2),
        );
        await repository.commitTrackingMutation(
          operationId: 'device-a-progress',
          states: <UserMediaState>[progressEdit],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: progressEdit.identity,
          patch: progressPatch,
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24, 2),
        );
        final DriveReplicaSegment segment = (await repository
            .buildPendingDriveSegment())!;
        await peer.applyDriveSegment(
          segment,
          trackerTargets: const <TrackerSource>{},
        );

        final UserMediaState merged = (await peer.loadTrackingStates()).single;
        expect(merged.progress, 7);
        expect(merged.score, 9);
        expect(merged.updatedAt, DateTime.utc(2026, 9, 24, 2));
        expect(await peer.watchConflicts().first, isEmpty);
        expect(await peer.pendingDriveDeliveryCount(), 1);
      },
    );

    test(
      'Drive checkpoint recovery applies a missed removal to an existing device',
      () async {
        final UserMediaState initial = _state(progress: 2);
        await repository.saveTrackingStates(<UserMediaState>[initial]);

        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );
        addTearDown(peerDatabase.close);
        await peer.applyDriveSnapshot(await repository.buildDriveSnapshot());

        final UserMediaPatch removal = UserMediaPatch(delete: true);
        await repository.commitTrackingMutation(
          states: const <UserMediaState>[],
          journal: <SyncJournalEntry>[_journal(initial, removal)],
          favorites: const <LocalMediaFavoriteState>[],
          identity: initial.identity,
          patch: removal,
          targets: const <TrackerSource>{TrackerSource.anilist},
          occurredAt: DateTime.utc(2026, 9, 24),
          mediaTitle: initial.mediaItem.title,
        );

        final DriveSnapshotApplyResult result = await peer.applyDriveSnapshot(
          await repository.buildDriveSnapshot(),
        );
        expect(await peer.loadTrackingStates(), isEmpty);
        expect(result.recoveredOperations, 1);
        expect(result.localEntryCount, 0);
      },
    );

    test(
      'commits canonical state, operation and deliveries atomically',
      () async {
        final UserMediaState state = _state(progress: 12, completed: true);
        final UserMediaPatch patch = UserMediaPatch(
          status: AniListListStatus.completed,
          progress: 12,
          completedAt: DateTime.utc(2026, 9, 23),
        );
        final SyncJournalEntry queued = _journal(state, patch);

        await repository.commitTrackingMutation(
          states: <UserMediaState>[state],
          journal: <SyncJournalEntry>[queued],
          favorites: const <LocalMediaFavoriteState>[],
          identity: state.identity,
          patch: patch,
          targets: const <TrackerSource>{
            TrackerSource.anilist,
            TrackerSource.mal,
          },
          occurredAt: DateTime.utc(2026, 9, 23),
          mediaTitle: state.mediaItem.title,
        );

        final UserMediaState stored =
            (await repository.loadTrackingStates()).single;
        expect(stored.progress, 12);
        expect(stored.status, AniListListStatus.completed);
        final LibraryActivityEvent event =
            (await repository.watchActivity().first).single;
        expect(event.fields, containsAll(<String>['progress', 'status']));
        expect(event.deliveryStates, <String, String>{
          'drive': 'pending',
          'anilist': 'pending',
          'mal': 'pending',
        });
      },
    );

    test(
      'persists an exact Shikimori binding without changing user state',
      () async {
        final UserMediaState state = _state(
          progress: 4,
          includeShikimori: false,
        );
        await repository.saveTrackingStates(<UserMediaState>[state]);

        expect(
          await repository.attachVerifiedProviderBinding(
            identity: state.identity,
            provider: TrackerSource.shikimori,
            externalMediaId: 31553,
            evidence: 'exact_mal_id_lookup',
          ),
          isTrue,
        );

        final UserMediaState stored =
            (await repository.loadTrackingStates()).single;
        expect(stored.identity.shikimoriId, 31553);
        expect(stored.mediaItem.externalIds['shikimori'], '31553');
        expect(stored.progress, state.progress);
        expect(stored.status, state.status);
        expect(stored.updatedAt, state.updatedAt);
        expect(await repository.watchActivity().first, isEmpty);
      },
    );

    test(
      'repairs a provider-only Shikimori shell when its exact MAL id arrives',
      () async {
        final UserMediaState target = _state(
          progress: 4,
          includeShikimori: false,
        );
        await repository.saveTrackingStates(<UserMediaState>[target]);
        final UserMediaState storedTarget =
            (await repository.loadTrackingStates()).single;

        final MediaItem shellMedia = MediaItem(
          id: 'shikimori:30',
          title: 'Anime #30',
          originalTitle: '',
          overview: '',
          type: MediaType.anime,
          year: 0,
          posterUrl: '',
          backdropUrl: '',
          rating: 0,
          genres: const <String>[],
          sourceProvider: 'Shikimori',
          externalIds: const <String, String>{'shikimori': '30'},
          statusLabel: '',
        );
        final String shellLocalId = await repository.resolveOrCreateMedia(
          identity: const MediaIdentity(
            localId: 'anime:shikimori:30',
            kind: 'anime',
            shikimoriId: 30,
          ),
          mediaItem: shellMedia,
        );
        expect(shellLocalId, isNot(storedTarget.identity.localId));

        final DateTime now = DateTime.utc(2026, 9, 24);
        final UserMediaState incoming = UserMediaState(
          identity: const MediaIdentity(
            localId: 'anime:mal:20',
            kind: 'anime',
            malId: 20,
            shikimoriId: 30,
          ),
          mediaItem: shellMedia.copyWith(
            title: 'Canonical Example',
            externalIds: const <String, String>{'mal': '20', 'shikimori': '30'},
          ),
          status: AniListListStatus.planning,
          progress: 0,
          createdAt: now,
          updatedAt: now,
          source: TrackerSource.shikimori,
          providerStates: <TrackerSource, ProviderUserMediaState>{
            TrackerSource.shikimori: ProviderUserMediaState(
              provider: TrackerSource.shikimori,
              entryId: 300,
              rawStatus: 'planned',
              updatedAt: now,
            ),
          },
        );

        await repository.reconcileProviderSnapshot(
          source: TrackerSource.shikimori,
          accountId: 'shiki-viewer',
          mediaKind: 'anime',
          remote: <UserMediaState>[incoming],
          journal: const <SyncJournalEntry>[],
          propagationTargets: const <TrackerSource>{TrackerSource.anilist},
          completeSnapshot: true,
        );

        final UserMediaState repaired =
            (await repository.loadTrackingStates()).single;
        expect(repaired.identity.localId, storedTarget.identity.localId);
        expect(repaired.identity.shikimoriId, 30);
        expect(await repository.watchConflicts().first, isEmpty);
        expect(
          await repository.resolveOrCreateMedia(
            identity: const MediaIdentity(
              localId: 'anime:shikimori:30',
              kind: 'anime',
              shikimoriId: 30,
            ),
            mediaItem: shellMedia,
          ),
          storedTarget.identity.localId,
        );
      },
    );

    test(
      'empty provider metadata cannot regress rich canonical metadata',
      () async {
        final UserMediaState rich = _state(progress: 2);
        final MediaItem richMedia = MediaItem(
          id: rich.mediaItem.id,
          title: 'Rich AniList title',
          originalTitle: 'Original title',
          overview: 'Full description',
          type: MediaType.anime,
          year: 2026,
          posterUrl: 'https://example.com/poster.jpg',
          backdropUrl: 'https://example.com/backdrop.jpg',
          rating: 8.7,
          genres: const <String>['Drama'],
          sourceProvider: 'AniList',
          externalIds: rich.mediaItem.externalIds,
          episodeCount: 12,
          statusLabel: 'FINISHED',
        );
        await repository.saveTrackingStates(<UserMediaState>[
          rich.withMediaItem(richMedia),
        ]);

        final MediaItem partialShikimori = MediaItem(
          id: rich.mediaItem.id,
          title: 'Anime #30',
          originalTitle: '',
          overview: '',
          type: MediaType.anime,
          year: 0,
          posterUrl: '',
          backdropUrl: '',
          rating: 0,
          genres: const <String>[],
          sourceProvider: 'Shikimori',
          externalIds: rich.mediaItem.externalIds,
          statusLabel: '',
        );
        await repository.saveTrackingStates(<UserMediaState>[
          rich.withMediaItem(partialShikimori),
        ]);

        final MediaItem stored =
            (await repository.loadTrackingStates()).single.mediaItem;
        expect(stored.title, 'Rich AniList title');
        expect(stored.posterUrl, 'https://example.com/poster.jpg');
        expect(stored.overview, 'Full description');
        expect(stored.episodeCount, 12);
        expect(stored.sourceProvider, 'AniList');
      },
    );

    test(
      'add, edit, and remove create Drive work and update snapshot count',
      () async {
        expect(await repository.watchPendingDriveDeliveryCount().first, 0);
        final UserMediaState state = _state(progress: 5);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[state],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: state.identity,
          patch: UserMediaPatch(progress: 5),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24),
        );

        expect(await repository.watchPendingDriveDeliveryCount().first, 1);
        expect(await repository.pendingDriveDeliveryCount(), 1);
        expect(await repository.activeLibraryEntryCount(), 1);
        expect((await repository.buildDriveSnapshot()).entryCount, 1);
        DriveReplicaSegment segment = (await repository
            .buildPendingDriveSegment())!;
        await repository.markDriveSegmentDelivered(
          segment,
          remoteFileId: 'drive-file-1',
        );
        expect(await repository.watchPendingDriveDeliveryCount().first, 0);
        expect(await repository.pendingDriveDeliveryCount(), 0);

        final UserMediaState edited = _state(progress: 7);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[edited],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: edited.identity,
          patch: UserMediaPatch(progress: 7),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24, 0, 1),
        );
        expect(await repository.watchPendingDriveDeliveryCount().first, 1);
        expect((await repository.buildDriveSnapshot()).entryCount, 1);
        segment = (await repository.buildPendingDriveSegment())!;
        expect(segment.operations.single['intent'], 'progress');
        await repository.markDriveSegmentDelivered(
          segment,
          remoteFileId: 'drive-file-2',
        );
        expect(await repository.watchPendingDriveDeliveryCount().first, 0);

        await repository.commitTrackingMutation(
          states: const <UserMediaState>[],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: edited.identity,
          patch: UserMediaPatch(delete: true),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24, 0, 2),
        );
        expect(await repository.watchPendingDriveDeliveryCount().first, 1);
        expect(await repository.activeLibraryEntryCount(), 0);
        expect((await repository.buildDriveSnapshot()).entryCount, 0);
        segment = (await repository.buildPendingDriveSegment())!;
        expect(segment.operations.single['intent'], 'remove');
      },
    );

    test(
      'Drive checkpoint watermark survives later segment deliveries',
      () async {
        expect(await repository.pushedDriveSegmentCount(), 0);
        expect(await repository.checkpointedDriveSegmentCount(), 0);

        final UserMediaState original = _state(progress: 2);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[original],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: original.identity,
          patch: UserMediaPatch(progress: 2),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24),
        );
        final DriveReplicaSegment first = (await repository
            .buildPendingDriveSegment())!;
        await repository.markDriveSegmentDelivered(
          first,
          remoteFileId: 'first',
        );
        expect(await repository.pushedDriveSegmentCount(), 1);
        expect(await repository.checkpointedDriveSegmentCount(), 0);

        // A full sync captures this watermark before building its backup.
        final int captured = await repository.pushedDriveSegmentCount();
        final UserMediaState edited = _state(progress: 3);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[edited],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: edited.identity,
          patch: UserMediaPatch(progress: 3),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 24, 0, 1),
        );
        final DriveReplicaSegment second = (await repository
            .buildPendingDriveSegment())!;
        await repository.markDriveSegmentDelivered(
          second,
          remoteFileId: 'second',
        );
        await repository.markDriveSnapshotPublished(captured);
        expect(await repository.pushedDriveSegmentCount(), 2);
        expect(await repository.checkpointedDriveSegmentCount(), 1);

        final CanonicalLibraryRepository reopened = CanonicalLibraryRepository(
          database,
        );
        expect(await reopened.pushedDriveSegmentCount(), 2);
        expect(await reopened.checkpointedDriveSegmentCount(), 1);
      },
    );

    test('undo is append-only and restores unchanged fields safely', () async {
      final UserMediaState before = _state(progress: 3);
      await repository.commitTrackingMutation(
        states: <UserMediaState>[before],
        journal: const <SyncJournalEntry>[],
        favorites: const <LocalMediaFavoriteState>[],
        identity: before.identity,
        patch: UserMediaPatch(status: AniListListStatus.current, progress: 3),
        targets: const <TrackerSource>{},
        occurredAt: DateTime.utc(2026, 9, 22),
      );
      final UserMediaState after = _state(progress: 7);
      await repository.commitTrackingMutation(
        states: <UserMediaState>[after],
        journal: const <SyncJournalEntry>[],
        favorites: const <LocalMediaFavoriteState>[],
        identity: after.identity,
        patch: UserMediaPatch(progress: 7),
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 23),
      );
      final List<LibraryActivityEvent> events = await repository
          .watchActivity()
          .first;
      final String changedOperation = events.first.operationId;

      final String undoOperation = await repository.undo(changedOperation);

      expect((await repository.loadTrackingStates()).single.progress, 3);
      final List<LibraryActivityEvent> afterUndo = await repository
          .watchActivity()
          .first;
      expect(afterUndo.first.operationId, undoOperation);
      expect(afterUndo.first.undoOf, changedOperation);
      expect(afterUndo, hasLength(3));
    });

    test('field-level undo preserves unrelated newer edits', () async {
      final UserMediaState initial = _state(progress: 3, score: 6.5);
      await repository.commitTrackingMutation(
        states: <UserMediaState>[initial],
        journal: const <SyncJournalEntry>[],
        favorites: const <LocalMediaFavoriteState>[],
        identity: initial.identity,
        patch: UserMediaPatch(status: AniListListStatus.current, progress: 3),
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 20),
      );
      final UserMediaState progressed = _state(progress: 7, score: 6.5);
      await repository.commitTrackingMutation(
        states: <UserMediaState>[progressed],
        journal: const <SyncJournalEntry>[],
        favorites: const <LocalMediaFavoriteState>[],
        identity: progressed.identity,
        patch: UserMediaPatch(progress: 7),
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 21),
      );
      final String progressOperation =
          (await repository.watchActivity().first).first.operationId;
      final UserMediaState scored = _state(progress: 7, score: 9.5);
      await repository.commitTrackingMutation(
        states: <UserMediaState>[scored],
        journal: const <SyncJournalEntry>[],
        favorites: const <LocalMediaFavoriteState>[],
        identity: scored.identity,
        patch: UserMediaPatch(score: 9.5),
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 22),
      );

      final LibraryUndoPreview preview = await repository.previewUndo(
        progressOperation,
      );
      expect(preview.safeFields, <String>{'progress'});
      expect(preview.blockedFields, isEmpty);
      await repository.undo(
        progressOperation,
        fields: const <String>{'progress'},
      );

      final UserMediaState restored =
          (await repository.loadTrackingStates()).single;
      expect(restored.progress, 3);
      expect(restored.score, 9.5);
      expect(
        (await repository.loadJournal()).single.pendingTargets,
        <TrackerSource>{TrackerSource.anilist},
      );
    });

    test(
      'undo preview protects a field changed by a newer operation',
      () async {
        final UserMediaState initial = _state(progress: 3);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[initial],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: initial.identity,
          patch: UserMediaPatch(progress: 3),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 20),
        );
        final UserMediaState first = _state(progress: 7);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[first],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: first.identity,
          patch: UserMediaPatch(progress: 7),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 21),
        );
        final String older =
            (await repository.watchActivity().first).first.operationId;
        final UserMediaState newer = _state(progress: 9);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[newer],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          identity: newer.identity,
          patch: UserMediaPatch(progress: 9),
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 22),
        );

        final LibraryUndoPreview preview = await repository.previewUndo(older);
        expect(preview.safeFields, isEmpty);
        expect(preview.blockedFields, <String>{'progress'});
        await expectLater(
          repository.undo(older, fields: const <String>{'progress'}),
          throwsStateError,
        );
        expect((await repository.loadTrackingStates()).single.progress, 9);
      },
    );

    test(
      'Drive segments are idempotent and keep MiruShin UUID mapping',
      () async {
        final UserMediaState state = _state(progress: 5);
        final UserMediaPatch patch = UserMediaPatch(progress: 5);
        await repository.commitTrackingMutation(
          states: <UserMediaState>[state],
          journal: <SyncJournalEntry>[_journal(state, patch)],
          favorites: const <LocalMediaFavoriteState>[],
          identity: state.identity,
          patch: patch,
          targets: const <TrackerSource>{},
          occurredAt: DateTime.utc(2026, 9, 23),
        );
        final segment = (await repository.buildPendingDriveSegment())!;

        final CanonicalLibraryDatabase peerDatabase = CanonicalLibraryDatabase(
          NativeDatabase.memory(),
        );
        addTearDown(peerDatabase.close);
        final CanonicalLibraryRepository peer = CanonicalLibraryRepository(
          peerDatabase,
        );

        expect(
          await peer.applyDriveSegment(
            segment,
            trackerTargets: const <TrackerSource>{},
          ),
          1,
        );
        expect(
          await peer.applyDriveSegment(
            segment,
            trackerTargets: const <TrackerSource>{},
          ),
          0,
        );
        final UserMediaState imported =
            (await peer.loadTrackingStates()).single;
        expect(imported.progress, 5);
        expect(imported.identity.anilistId, 10);
        expect(imported.identity.localId, isNotEmpty);
      },
    );

    test('manga keeps its media kind after UUID normalization', () async {
      final UserMediaState manga = _state(progress: 18, manga: true);
      await repository.commitTrackingMutation(
        states: <UserMediaState>[manga],
        journal: const <SyncJournalEntry>[],
        favorites: const <LocalMediaFavoriteState>[],
        identity: manga.identity,
        patch: UserMediaPatch(progress: 18, progressVolumes: 3),
        targets: const <TrackerSource>{TrackerSource.anilist},
        occurredAt: DateTime.utc(2026, 9, 23),
      );

      final UserMediaState stored =
          (await repository.loadTrackingStates()).single;
      expect(stored.identity.localId, isNot(startsWith('manga:')));
      expect(stored.identity.mediaKind, 'manga');
      expect(stored.mediaItem.externalIds['anilist_type'], 'MANGA');
    });

    test('new provider account requires approval before import', () async {
      final UserMediaState remote = _state(progress: 4);

      final ProviderReconciliationResult preview = await repository
          .reconcileProviderSnapshot(
            source: TrackerSource.anilist,
            accountId: 'viewer-42',
            mediaKind: 'anime',
            remote: <UserMediaState>[remote],
            journal: const <SyncJournalEntry>[],
            propagationTargets: const <TrackerSource>{TrackerSource.mal},
            completeSnapshot: true,
          );

      expect(preview.requiresAccountApproval, isTrue);
      expect(preview.states, isEmpty);
      final List<ProviderAccountPreview> accountPreviews = await repository
          .pendingAccountPreviews();
      expect(accountPreviews, hasLength(1));
      expect(accountPreviews.single.entries, hasLength(1));
      expect(accountPreviews.single.entries.single.title, 'Canonical Example');
      expect(accountPreviews.single.entries.single.changeKind, 'new');
      expect(accountPreviews.single.entries.single.remoteProgress, 4);

      await repository.approveProviderAccount(
        provider: 'anilist',
        accountId: 'viewer-42',
      );
      final ProviderReconciliationResult imported = await repository
          .reconcileProviderSnapshot(
            source: TrackerSource.anilist,
            accountId: 'viewer-42',
            mediaKind: 'anime',
            remote: <UserMediaState>[remote],
            journal: const <SyncJournalEntry>[],
            propagationTargets: const <TrackerSource>{TrackerSource.mal},
            completeSnapshot: true,
          );
      expect(imported.importedChanges, 1);
      expect(imported.states.single.progress, 4);
      expect(imported.journal.single.pendingTargets, <TrackerSource>{
        TrackerSource.mal,
      });
    });

    test(
      'external Completed 0/12 repairs local progress and queues source',
      () async {
        final UserMediaState remote = _state(progress: 0, completed: true);
        final ProviderReconciliationResult preview = await repository
            .reconcileProviderSnapshot(
              source: TrackerSource.anilist,
              accountId: 'completed-viewer',
              mediaKind: 'anime',
              remote: <UserMediaState>[remote],
              journal: const <SyncJournalEntry>[],
              propagationTargets: const <TrackerSource>{TrackerSource.mal},
              propagationAccountIds: const <TrackerSource, String>{
                TrackerSource.mal: 'mal-viewer',
              },
              completeSnapshot: true,
            );
        expect(preview.requiresAccountApproval, isTrue);
        await repository.approveProviderAccount(
          provider: 'anilist',
          accountId: 'completed-viewer',
        );
        final ProviderReconciliationResult imported = await repository
            .reconcileProviderSnapshot(
              source: TrackerSource.anilist,
              accountId: 'completed-viewer',
              mediaKind: 'anime',
              remote: <UserMediaState>[remote],
              journal: const <SyncJournalEntry>[],
              propagationTargets: const <TrackerSource>{TrackerSource.mal},
              propagationAccountIds: const <TrackerSource, String>{
                TrackerSource.mal: 'mal-viewer',
              },
              completeSnapshot: true,
            );
        expect(imported.states.single.status, AniListListStatus.completed);
        expect(imported.states.single.progress, 12);
        expect(imported.journal.single.patch.progress, 12);
        expect(imported.journal.single.pendingTargets, <TrackerSource>{
          TrackerSource.anilist,
          TrackerSource.mal,
        });
        expect(
          imported.journal.single.targetAccountIds,
          <TrackerSource, String>{
            TrackerSource.anilist: 'completed-viewer',
            TrackerSource.mal: 'mal-viewer',
          },
        );
      },
    );

    test(
      'explicit account approval bypasses first-import mass quarantine',
      () async {
        final List<UserMediaState> remote = List<UserMediaState>.generate(
          25,
          (int index) => _remoteShikimoriState(index + 1000),
        );
        final ProviderReconciliationResult preview = await repository
            .reconcileProviderSnapshot(
              source: TrackerSource.shikimori,
              accountId: 'large-shiki-account',
              mediaKind: 'anime',
              remote: remote,
              journal: const <SyncJournalEntry>[],
              propagationTargets: const <TrackerSource>{},
              completeSnapshot: true,
            );
        expect(preview.requiresAccountApproval, isTrue);

        await repository.approveProviderAccount(
          provider: 'shikimori',
          accountId: 'large-shiki-account',
        );
        final ProviderReconciliationResult imported = await repository
            .reconcileProviderSnapshot(
              source: TrackerSource.shikimori,
              accountId: 'large-shiki-account',
              mediaKind: 'anime',
              remote: remote,
              journal: const <SyncJournalEntry>[],
              propagationTargets: const <TrackerSource>{},
              completeSnapshot: true,
            );

        expect(imported.quarantined, isFalse);
        expect(imported.importedChanges, 25);
        expect(imported.states, hasLength(25));
      },
    );

    test('destructive remote progress needs two matching snapshots', () async {
      final UserMediaState initial = _state(progress: 10);
      await repository.reconcileProviderSnapshot(
        source: TrackerSource.anilist,
        accountId: 'viewer-safe',
        mediaKind: 'anime',
        remote: <UserMediaState>[initial],
        journal: const <SyncJournalEntry>[],
        propagationTargets: const <TrackerSource>{TrackerSource.mal},
        completeSnapshot: true,
      );
      await repository.approveProviderAccount(
        provider: 'anilist',
        accountId: 'viewer-safe',
      );
      await repository.reconcileProviderSnapshot(
        source: TrackerSource.anilist,
        accountId: 'viewer-safe',
        mediaKind: 'anime',
        remote: <UserMediaState>[initial],
        journal: const <SyncJournalEntry>[],
        propagationTargets: const <TrackerSource>{TrackerSource.mal},
        completeSnapshot: true,
      );

      final UserMediaState reset = _state(progress: 4);
      final ProviderReconciliationResult first = await repository
          .reconcileProviderSnapshot(
            source: TrackerSource.anilist,
            accountId: 'viewer-safe',
            mediaKind: 'anime',
            remote: <UserMediaState>[reset],
            journal: const <SyncJournalEntry>[],
            propagationTargets: const <TrackerSource>{TrackerSource.mal},
            completeSnapshot: true,
          );
      expect(first.destructiveChangesPending, 1);
      expect(first.states.single.progress, 10);

      final ProviderReconciliationResult second = await repository
          .reconcileProviderSnapshot(
            source: TrackerSource.anilist,
            accountId: 'viewer-safe',
            mediaKind: 'anime',
            remote: <UserMediaState>[reset],
            journal: const <SyncJournalEntry>[],
            propagationTargets: const <TrackerSource>{TrackerSource.mal},
            completeSnapshot: true,
          );
      expect(second.destructiveChangesPending, 0);
      expect(second.states.single.progress, 4);
      expect(second.journal, hasLength(2));
      expect(second.journal.last.pendingTargets, <TrackerSource>{
        TrackerSource.mal,
      });
    });

    test(
      'Shikimori removal needs two snapshots before Local Library and Log change',
      () async {
        final UserMediaState initial = _state(progress: 6);
        await repository.reconcileProviderSnapshot(
          source: TrackerSource.shikimori,
          accountId: 'shiki-viewer',
          mediaKind: 'anime',
          remote: <UserMediaState>[initial],
          journal: const <SyncJournalEntry>[],
          propagationTargets: const <TrackerSource>{
            TrackerSource.anilist,
            TrackerSource.mal,
          },
          completeSnapshot: true,
        );
        await repository.approveProviderAccount(
          provider: 'shikimori',
          accountId: 'shiki-viewer',
        );
        await repository.reconcileProviderSnapshot(
          source: TrackerSource.shikimori,
          accountId: 'shiki-viewer',
          mediaKind: 'anime',
          remote: <UserMediaState>[initial],
          journal: const <SyncJournalEntry>[],
          propagationTargets: const <TrackerSource>{
            TrackerSource.anilist,
            TrackerSource.mal,
          },
          completeSnapshot: true,
        );
        final List<LibraryActivityEvent> activityBeforeRemoval =
            await repository.watchActivity().first;

        final ProviderReconciliationResult first = await repository
            .reconcileProviderSnapshot(
              source: TrackerSource.shikimori,
              accountId: 'shiki-viewer',
              mediaKind: 'anime',
              remote: const <UserMediaState>[],
              journal: const <SyncJournalEntry>[],
              propagationTargets: const <TrackerSource>{
                TrackerSource.anilist,
                TrackerSource.mal,
              },
              completeSnapshot: true,
            );
        expect(first.destructiveChangesPending, 1);
        expect(first.states, hasLength(1));
        expect(
          await repository.watchActivity().first,
          hasLength(activityBeforeRemoval.length),
        );

        final ProviderReconciliationResult second = await repository
            .reconcileProviderSnapshot(
              source: TrackerSource.shikimori,
              accountId: 'shiki-viewer',
              mediaKind: 'anime',
              remote: const <UserMediaState>[],
              journal: const <SyncJournalEntry>[],
              propagationTargets: const <TrackerSource>{
                TrackerSource.anilist,
                TrackerSource.mal,
              },
              completeSnapshot: true,
            );
        expect(second.destructiveChangesPending, 0);
        expect(second.states, isEmpty);
        expect(second.journal, hasLength(2));
        expect(second.journal.last.patch.delete, isTrue);
        expect(second.journal.last.pendingTargets, <TrackerSource>{
          TrackerSource.anilist,
          TrackerSource.mal,
        });
        final List<LibraryActivityEvent> activityAfterRemoval = await repository
            .watchActivity()
            .first;
        expect(
          activityAfterRemoval,
          hasLength(activityBeforeRemoval.length + 1),
        );
        final LibraryActivityEvent event = activityAfterRemoval.first;
        expect(event.intent, LibraryMutationIntent.remove);
        expect(event.originKind, LibraryOriginKind.provider);
        expect(event.originId, 'shikimori:shiki-viewer');
      },
    );

    test(
      'playback checkpoints are replicated without spamming the log',
      () async {
        final UserMediaState state = _state(progress: 1);

        await repository.saveEpisodeProgress(
          mediaId: state.mediaItem.id,
          season: 1,
          episode: 2,
          positionSeconds: 95,
          durationSeconds: 1440,
          mediaItem: state.mediaItem,
        );

        final segment = (await repository.buildPendingDriveSegment())!;
        expect(segment.operations, hasLength(1));
        expect(segment.episodeStates, hasLength(1));
        expect(segment.episodeStates.single['positionSeconds'], 95);
        expect(await repository.watchActivity().first, isEmpty);

        await repository.saveEpisodeProgress(
          mediaId: state.mediaItem.id,
          season: 1,
          episode: 2,
          positionSeconds: 1440,
          durationSeconds: 1440,
          completed: true,
          mediaItem: state.mediaItem,
        );
        final LibraryActivityEvent completed =
            (await repository.watchActivity().first).single;
        expect(completed.intent, LibraryMutationIntent.episodeCompleted);
        expect(completed.deliveryStates['drive'], 'pending');
      },
    );
  });
}

SyncJournalEntry _journal(UserMediaState state, UserMediaPatch patch) =>
    SyncJournalEntry(
      identity: state.identity,
      patch: patch,
      pendingTargets: const <TrackerSource>{TrackerSource.anilist},
      createdAt: DateTime.utc(2026, 9, 23),
      updatedAt: DateTime.utc(2026, 9, 23),
      mediaTitle: state.mediaItem.title,
    );

UserMediaState _state({
  required int progress,
  bool completed = false,
  bool manga = false,
  bool includeShikimori = true,
  double score = 8.7,
}) {
  final DateTime now = DateTime.utc(2026, 9, 23);
  final MediaIdentity identity = MediaIdentity(
    localId: manga ? 'manga:mal:20' : 'legacy:anime:10',
    kind: manga ? 'manga' : 'anime',
    anilistId: 10,
    malId: 20,
    shikimoriId: includeShikimori ? 30 : null,
  );
  return UserMediaState(
    identity: identity,
    mediaItem: MediaItem(
      id: manga ? 'anilist:manga:10' : 'anilist:10',
      title: 'Canonical Example',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.7,
      genres: <String>['Drama'],
      sourceProvider: 'AniList',
      externalIds: <String, String>{
        'anilist': '10',
        'mal': '20',
        if (includeShikimori) 'shikimori': '30',
        if (manga) 'anilist_type': 'MANGA',
      },
      episodeCount: 12,
      statusLabel: 'FINISHED',
    ),
    status: completed ? AniListListStatus.completed : AniListListStatus.current,
    progress: progress,
    score: score,
    startedAt: DateTime.utc(2026, 9, 1),
    completedAt: completed ? now : null,
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: now,
    source: TrackerSource.anilist,
    providerStates: <TrackerSource, ProviderUserMediaState>{
      TrackerSource.anilist: ProviderUserMediaState(
        provider: TrackerSource.anilist,
        entryId: 100,
        rawStatus: completed ? 'COMPLETED' : 'CURRENT',
        rawScore: score,
        updatedAt: now,
      ),
    },
  );
}

UserMediaState _remoteShikimoriState(int id) {
  final DateTime now = DateTime.utc(2026, 9, 24);
  return UserMediaState(
    identity: MediaIdentity(
      localId: 'anime:mal:$id',
      kind: 'anime',
      malId: id,
      shikimoriId: id + 100000,
    ),
    mediaItem: MediaItem(
      id: 'mal:$id',
      title: 'Shikimori Anime $id',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: 'Shikimori',
      externalIds: <String, String>{
        'mal': '$id',
        'shikimori': '${id + 100000}',
      },
      statusLabel: '',
    ),
    status: AniListListStatus.planning,
    progress: 0,
    createdAt: now,
    updatedAt: now,
    source: TrackerSource.shikimori,
    providerStates: <TrackerSource, ProviderUserMediaState>{
      TrackerSource.shikimori: ProviderUserMediaState(
        provider: TrackerSource.shikimori,
        entryId: id + 200000,
        rawStatus: 'planned',
        updatedAt: now,
      ),
    },
  );
}
