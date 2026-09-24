import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
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
      expect(await legacy.loadStates(), hasLength(1));
      expect(await legacy.loadJournal(), hasLength(1));
    });

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

    test('pending Drive delivery stream reacts without polling', () async {
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
      final DriveReplicaSegment segment = (await repository
          .buildPendingDriveSegment())!;
      await repository.markDriveSegmentDelivered(
        segment,
        remoteFileId: 'drive-file-1',
      );
      expect(await repository.watchPendingDriveDeliveryCount().first, 0);
    });

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
      expect(second.journal.single.pendingTargets, <TrackerSource>{
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
        expect(second.journal.single.patch.delete, isTrue);
        expect(second.journal.single.pendingTargets, <TrackerSource>{
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
