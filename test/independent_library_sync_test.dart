import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/local_first_sync_engine.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:mirushin/features/tracking/data/canonical_tracking_sync_store.dart';
import 'package:mirushin/features/tracking/domain/provider_field_projection.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

final epoch = DateTime.utc(2026, 10, 1);

UserMediaState sample({
  TrackerSource source = TrackerSource.anilist,
  int progress = 3,
  int hour = 0,
  int id = 10,
  String kind = 'anime',
  List<String>? present,
}) {
  final at = epoch.add(Duration(hours: hour));
  return UserMediaState(
    identity: MediaIdentity(
      localId: '$kind:$id',
      kind: kind,
      anilistId: id,
      malId: id + 100,
      shikimoriId: id + 200,
    ),
    mediaItem: MediaItem(
      id: 'anilist:$id',
      title: 'Sync title $id',
      originalTitle: '',
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const [],
      sourceProvider: 'AniList',
      externalIds: {'anilist': '$id', 'mal': '${id + 100}'},
      statusLabel: '',
    ),
    status: AniListListStatus.current,
    progress: progress,
    score: 8.7,
    createdAt: epoch,
    updatedAt: at,
    startedAt: epoch,
    source: source,
    providerStates: {
      source: ProviderUserMediaState(
        provider: source,
        updatedAt: at,
        data: {'presentFields': ?present},
      ),
    },
  );
}

CanonicalLibraryRepository memory() {
  final db = CanonicalLibraryDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return CanonicalLibraryRepository(db);
}

Future<ProviderReconciliationResult> ingest(
  CanonicalLibraryRepository repo,
  TrackerSource source,
  List<UserMediaState> remote, {
  Set<TrackerSource> targets = const {},
  bool complete = true,
}) => repo.reconcileProviderSnapshot(
  source: source,
  accountId: source.name,
  mediaKind: 'anime',
  remote: remote,
  journal: const [],
  propagationTargets: targets,
  completeSnapshot: complete,
);

Future<void> approve(CanonicalLibraryRepository repo, TrackerSource source) =>
    repo.approveProviderAccount(provider: source.name, accountId: source.name);

Future<void> edit(
  CanonicalLibraryRepository repo,
  UserMediaPatch patch,
  int hour, {
  Set<TrackerSource> targets = const {},
}) async {
  final current = (await repo.loadTrackingStates()).single;
  final at = epoch.add(Duration(hours: hour));
  final engine = LocalFirstSyncEngine(
    store: CanonicalTrackingSyncStore(repository: repo),
    adapters: const {},
    now: () => at,
    targetAccountIds: {for (final target in targets) target: target.name},
  );
  await engine.recordMutation(
    identity: current.identity,
    patch: patch,
    targets: targets,
    backgroundDelivery: true,
  );
}

class Adapter
    implements TrackerProviderAdapter, AcknowledgingTrackerProviderAdapter {
  Adapter(this.source, {List<UserMediaState>? entries})
    : entries = entries ?? [sample(source: source)];
  @override
  final TrackerSource source;
  @override
  String get accountId => source.name;
  List<UserMediaState> entries;
  final applied = <SyncJournalEntry>[];
  final delivered = Completer<void>();
  final entered = Completer<void>();
  final mangaEntered = Completer<void>();
  Completer<void>? gate;
  int failures = 0;
  Object? failure;
  int fetches = 0;
  bool acknowledges = true;
  @override
  Future<List<UserMediaState>> fetchAnimeList() async {
    fetches++;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (failures > 0) {
      failures--;
      throw failure ?? StateError('simulated outage');
    }
    return entries;
  }

  @override
  Future<List<UserMediaState>> fetchMangaList() async {
    if (!mangaEntered.isCompleted) mangaEntered.complete();
    return [];
  }

  @override
  Future<void> applyMutation(SyncJournalEntry mutation) async {
    applied.add(mutation);
    final old = entries
        .where((state) => state.identity.matches(mutation.identity))
        .firstOrNull;
    entries.removeWhere((state) => state.identity.matches(mutation.identity));
    if (!mutation.patch.delete) {
      entries.add(
        (old ?? sample(source: source)).apply(
          mutation.patch,
          mutation.updatedAt,
          providerSource: source,
        ),
      );
    }
    if (!delivered.isCompleted) delivered.complete();
  }

  @override
  Future<bool> applyAndConfirm(SyncJournalEntry mutation) async {
    await applyMutation(mutation);
    return acknowledges;
  }
}

Future<TrackerSyncCoordinator> coordinator(
  CanonicalLibraryRepository repo,
  Map<TrackerSource, Adapter> adapters,
) async {
  final container = ProviderContainer();
  final settings = SettingsState(
    anilistAccessToken: adapters.containsKey(TrackerSource.anilist)
        ? 'test'
        : '',
    anilistExpiresAt: DateTime.now().add(const Duration(days: 1)),
    anilistViewerId: 1,
    malAccessToken: adapters.containsKey(TrackerSource.mal) ? 'test' : '',
    malViewerId: 2,
    shikimoriAccessToken: adapters.containsKey(TrackerSource.shikimori)
        ? 'test'
        : '',
    shikimoriViewerId: 3,
  );
  // The adapter's account IDs deliberately match the repository approvals.
  final provider = Provider(
    (ref) => TrackerSyncCoordinator(
      ref,
      repository: repo,
      store: CanonicalTrackingSyncStore(repository: repo),
      settings: settings,
      beforeTrackerNetwork: () async => true,
      adapterFactory: (source) async => adapters[source],
    ),
  );
  final result = container.read(provider);
  addTearDown(() async {
    await result.prepareForExit();
    container.dispose();
  });
  return result;
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final auditDatabase = Platform.environment['MIRUSHIN_SYNC_AUDIT_DATABASE'];
  test(
    'existing backlog migration preserves audit history and is idempotent',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'mirushin-backlog-migration-',
      );
      final file = await File(
        auditDatabase!,
      ).copy('${temporary.path}/library.sqlite');
      final db = CanonicalLibraryDatabase(NativeDatabase(file));
      try {
        final repo = CanonicalLibraryRepository(db);
        final before =
            (await db
                    .customSelect(
                      'SELECT count(*) AS n FROM library_operation_records',
                    )
                    .getSingle())
                .read<int>('n');
        final store = CanonicalTrackingSyncStore(repository: repo);
        await store.loadStates();
        expect(await repo.hasMigration('sync.independent.v3'), isTrue);
        expect(
          (await db
                  .customSelect(
                    'SELECT count(*) AS n FROM library_operation_records',
                  )
                  .getSingle())
              .read<int>('n'),
          before,
        );
        final journal = jsonEncode(
          (await repo.loadJournal()).map((job) => job.toJson()).toList(),
        );
        await repo.recoverIndependentSyncBacklog();
        expect(
          jsonEncode(
            (await repo.loadJournal()).map((job) => job.toJson()).toList(),
          ),
          journal,
        );
        expect(
          (await db.customSelect('PRAGMA integrity_check').getSingle())
              .data
              .values
              .single,
          'ok',
        );
      } finally {
        await db.close();
        await temporary.delete(recursive: true);
      }
    },
    skip: auditDatabase == null
        ? 'Set MIRUSHIN_SYNC_AUDIT_DATABASE to test a copied existing backlog.'
        : false,
  );

  for (final source in TrackerSource.values) {
    test(
      '$source newer catalog edit supersedes older queued local fields',
      () async {
        final repo = memory();
        await approve(repo, source);
        await ingest(repo, source, [sample(source: source)]);
        await edit(
          repo,
          UserMediaPatch(progress: 8, notes: 'Local note'),
          1,
          targets: {source},
        );
        final remote = sample(
          source: source,
          progress: 2,
          hour: 2,
          present: ['status', 'progress', 'score'],
        );
        final result = await ingest(repo, source, [
          remote,
        ], targets: TrackerSource.values.toSet()..remove(source));
        expect(result.states.single.progress, 2);
        expect(result.states.single.notes, 'Local note');
        final sourceJob = (await repo.loadJournal())
            .where((job) => job.tracks(source))
            .single;
        expect(sourceJob.patch.fields, {UserMediaField.notes});
        expect(await repo.watchConflicts().first, isEmpty);
        expect(result.journal.last.updatedAt, remote.updatedAt);
      },
    );

    test(
      '$source timestamp-only write echo is not a new catalog edit',
      () async {
        final repo = memory();
        await approve(repo, source);
        await ingest(repo, source, [sample(source: source)]);
        await edit(repo, UserMediaPatch(progress: 6), 1, targets: {source});
        final adapter = Adapter(source);
        await LocalFirstSyncEngine(
          store: CanonicalTrackingSyncStore(repository: repo),
          adapters: {source: adapter},
        ).flush();
        final count = (await repo.watchActivity().first).length;
        await ingest(repo, source, [
          sample(source: source, progress: 6, hour: 5),
        ]);
        expect((await repo.watchActivity().first).length, count);
        final row = await repo.database
            .select(repo.database.canonicalLibraryRecords)
            .getSingle();
        final revision =
            (jsonDecode(row.fieldRevisionsJson) as Map)['progress'] as Map;
        expect(revision['origin'], 'user');
        expect(
          revision['occurredAtMs'],
          epoch.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        );
      },
    );

    test(
      '$source older external edit queues canonical repair without changing edit time',
      () async {
        final repo = memory();
        await approve(repo, source);
        await ingest(repo, source, [sample(source: source)]);
        await edit(repo, UserMediaPatch(progress: 8), 3);
        final count = (await repo.watchActivity().first).length;
        await ingest(repo, source, [
          sample(source: source, progress: 5, hour: 2),
        ]);
        expect((await repo.loadTrackingStates()).single.progress, 8);
        expect((await repo.loadJournal()).single.patch.progress, 8);
        expect((await repo.watchActivity().first).length, count);
        final adapter = Adapter(source);
        await LocalFirstSyncEngine(
          store: CanonicalTrackingSyncStore(repository: repo),
          adapters: {source: adapter},
        ).flush();
        expect(adapter.applied.single.patch.progress, 8);
      },
    );

    test(
      '$source unrelated write echo cannot reopen Completed or clear a reviewed date',
      () async {
        final repo = memory();
        await approve(repo, source);
        final initial = sample(source: source).apply(
          UserMediaPatch(completedAt: epoch, notes: 'Original note'),
          epoch,
          providerSource: source,
        );
        await ingest(repo, source, [initial]);
        final finish = epoch.add(const Duration(days: 1));
        await edit(
          repo,
          UserMediaPatch(
            status: AniListListStatus.completed,
            progress: 6,
            completedAt: finish,
            notes: 'Local note',
          ),
          1,
        );
        final disputed = sample(source: source, hour: 1);
        await ingest(repo, source, [disputed]);
        expect(
          (await repo.watchConflicts().first).map((c) => c.fieldName),
          unorderedEquals([
            'notes',
            if (source != TrackerSource.shikimori) 'completedAt',
          ]),
        );
        await edit(repo, UserMediaPatch(score: 8), 2, targets: {source});
        final adapter = Adapter(source, entries: [disputed]);
        await LocalFirstSyncEngine(
          store: CanonicalTrackingSyncStore(repository: repo),
          adapters: {source: adapter},
        ).flush();
        final echo = sample(source: source, hour: 5).apply(
          UserMediaPatch(score: 8),
          epoch.add(const Duration(hours: 5)),
          providerSource: source,
        );
        await ingest(repo, source, [echo]);
        final saved = (await repo.loadTrackingStates()).single;
        expect(saved.status, AniListListStatus.completed);
        expect(saved.progress, 6);
        expect(saved.completedAt, finish);
        expect(saved.notes, 'Local note');
        final review = (await repo.watchConflicts().first).singleWhere(
          (c) => c.fieldName == 'notes',
        );
        expect(
          (review.incomingValue as Map)['editAt'],
          epoch.add(const Duration(hours: 1)).toIso8601String(),
        );
        // A 2.9.15 backlog already has entry-wide echo dates, but no per-field
        // timestamps. Its pending proposal is still valid evidence of the date.
        for (final row
            in await repo.database
                .select(repo.database.providerSnapshotRecords)
                .get()) {
          if (row.provider != source.name || row.accountId != source.name) {
            continue;
          }
          final json = jsonDecode(row.normalizedJson) as Map<String, dynamic>;
          ((json['providerStates'] as Map)[source.name]['data'] as Map).remove(
            'fieldEditTimesMs',
          );
          await (repo.database.update(
            repo.database.providerSnapshotRecords,
          )..where((table) => table.snapshotId.equals(row.snapshotId))).write(
            ProviderSnapshotRecordsCompanion(
              normalizedJson: Value(jsonEncode(json)),
            ),
          );
        }
        await ingest(repo, source, [
          echo.apply(
            UserMediaPatch(score: 8),
            epoch.add(const Duration(hours: 6)),
            providerSource: source,
          ),
        ]);
        expect(
          (await repo.loadTrackingStates()).single.status,
          AniListListStatus.completed,
        );
        expect((await repo.loadTrackingStates()).single.completedAt, finish);
        expect((await repo.loadTrackingStates()).single.notes, 'Local note');
        // A genuine later status change still wins; it is not blanket protection.
        await ingest(repo, source, [
          echo.apply(
            UserMediaPatch(status: AniListListStatus.planning),
            epoch.add(const Duration(hours: 7)),
            providerSource: source,
          ),
        ]);
        expect(
          (await repo.loadTrackingStates()).single.status,
          AniListListStatus.planning,
        );
        expect((await repo.loadTrackingStates()).single.completedAt, finish);
      },
    );

    test(
      '$source canonical repair reuses a confirmed account delivery',
      () async {
        final repo = memory();
        await approve(repo, source);
        await ingest(repo, source, [sample(source: source)]);
        await edit(repo, UserMediaPatch(progress: 8), 3, targets: {source});
        final adapter = Adapter(source);
        final engine = LocalFirstSyncEngine(
          store: CanonicalTrackingSyncStore(repository: repo),
          adapters: {source: adapter},
        );
        await engine.flush();
        final original =
            (await repo.database
                    .select(repo.database.outboxDeliveryRecords)
                    .get())
                .where((row) => row.target == source.name)
                .single;
        expect(original.state, 'confirmed');
        await ingest(repo, source, [
          sample(source: source, progress: 5, hour: 2),
        ]);
        await ingest(repo, source, [
          sample(source: source, progress: 5, hour: 2),
        ]);
        final deliveries =
            (await repo.database
                    .select(repo.database.outboxDeliveryRecords)
                    .get())
                .where((row) => row.target == source.name)
                .toList();
        expect(deliveries, hasLength(1));
        expect(deliveries.single.deliveryId, original.deliveryId);
        expect(deliveries.single.state, 'pending');
        await repo.applyRemoteDeliveryLedger({
          original.deliveryId: {
            'state': 'confirmed',
            'accountId': source.name,
            'confirmedAt': epoch.toIso8601String(),
          },
        });
        expect((await repo.loadJournal()).single.tracks(source), isTrue);
        await engine.flush();
        expect(adapter.applied, hasLength(2));
        expect((await repo.loadTrackingStates()).single.progress, 8);
      },
    );

    test(
      '$source account binding and Drive confirmation tolerate an old unbound alias',
      () async {
        final repo = memory();
        await approve(repo, source);
        await ingest(repo, source, [sample(source: source)]);
        await edit(repo, UserMediaPatch(progress: 8), 3, targets: {source});
        final original =
            (await repo.database
                    .select(repo.database.outboxDeliveryRecords)
                    .get())
                .singleWhere((row) => row.target == source.name);
        await repo.database
            .into(repo.database.outboxDeliveryRecords)
            .insert(
              OutboxDeliveryRecordsCompanion.insert(
                deliveryId: 'old-unbound-alias',
                operationId: original.operationId,
                target: source.name,
                state: 'pending',
              ),
            );
        await repo.database
            .into(repo.database.outboxDeliveryRecords)
            .insert(
              OutboxDeliveryRecordsCompanion.insert(
                deliveryId: 'other-account',
                operationId: original.operationId,
                target: source.name,
                accountId: const Value('other-account'),
                state: 'pending',
              ),
            );
        await repo.updateTrackerDelivery(
          operationId: original.operationId,
          identity: (await repo.loadTrackingStates()).single.identity,
          target: source,
          accountId: source.name,
          state: 'sending',
        );
        var rows = await repo.database
            .select(repo.database.outboxDeliveryRecords)
            .get();
        expect(
          rows
              .singleWhere((row) => row.deliveryId == original.deliveryId)
              .attempts,
          1,
        );
        expect(
          rows
              .singleWhere((row) => row.deliveryId == 'old-unbound-alias')
              .state,
          'superseded',
        );
        final ledger = {
          'old-unbound-alias': {'state': 'confirmed', 'accountId': source.name},
        };
        await repo.applyRemoteDeliveryLedger(ledger);
        await repo.applyRemoteDeliveryLedger(ledger);
        rows = await repo.database
            .select(repo.database.outboxDeliveryRecords)
            .get();
        expect(
          rows
              .singleWhere((row) => row.deliveryId == original.deliveryId)
              .state,
          'confirmed',
        );
        expect(
          rows
              .singleWhere((row) => row.deliveryId == 'old-unbound-alias')
              .accountId,
          isNull,
        );
        expect(
          rows.singleWhere((row) => row.deliveryId == 'other-account').state,
          'pending',
        );
        expect(await repo.loadJournal(), isEmpty);
      },
    );
  }

  test(
    'local SQLite failure does not mark a healthy catalog as unavailable',
    () async {
      final repo = memory();
      final adapter = Adapter(TrackerSource.mal)
        ..failures = 1
        ..failure = SqliteException(
          extendedResultCode: 2067,
          message: 'local constraint',
        );
      final store = CanonicalTrackingSyncStore(repository: repo);
      await LocalFirstSyncEngine(
        store: store,
        adapters: {TrackerSource.mal: adapter},
      ).refreshAllProviderSnapshots(providerOrder: [TrackerSource.mal]);
      expect((await store.loadHealth())[TrackerSource.mal]?.lastError, isNull);
      expect(
        (await store.loadHealth())[TrackerSource.mal]?.consecutiveFailures ?? 0,
        0,
      );
    },
  );

  test(
    'newer explicit date clear imports; absent field preserves local date',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.anilist);
      await ingest(repo, TrackerSource.anilist, [
        sample().apply(
          UserMediaPatch(completedAt: epoch),
          epoch,
          providerSource: TrackerSource.anilist,
        ),
      ]);
      final localDate = epoch.add(const Duration(days: 1));
      await edit(repo, UserMediaPatch(completedAt: localDate), 1);
      await ingest(repo, TrackerSource.anilist, [
        sample(hour: 2, present: ['progress']),
      ]);
      expect((await repo.loadTrackingStates()).single.completedAt, localDate);
      await ingest(repo, TrackerSource.anilist, [
        sample(hour: 3, present: ['progress', 'completedAt']),
      ]);
      expect((await repo.loadTrackingStates()).single.completedAt, isNull);
    },
  );

  test(
    'partial list cannot delete entries or advance observed snapshots',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.anilist);
      await ingest(repo, TrackerSource.anilist, [sample()]);
      await ingest(repo, TrackerSource.anilist, [], complete: false);
      expect(await repo.loadTrackingStates(), hasLength(1));
      expect(await repo.watchConflicts().first, isEmpty);
    },
  );

  test('catalog fetch does not invent a finish date for Completed', () async {
    final repo = memory();
    await approve(repo, TrackerSource.anilist);
    await ingest(repo, TrackerSource.anilist, [
      sample().apply(
        UserMediaPatch(status: AniListListStatus.completed),
        epoch,
        providerSource: TrackerSource.anilist,
      ),
    ]);
    expect((await repo.loadTrackingStates()).single.completedAt, isNull);
  });

  test('stale provider membership cannot undo a newer deletion', () async {
    final repo = memory();
    await approve(repo, TrackerSource.anilist);
    await ingest(repo, TrackerSource.anilist, [sample()]);
    await edit(repo, UserMediaPatch(delete: true), 3);
    await ingest(repo, TrackerSource.anilist, [sample(hour: 2)]);
    expect(await repo.loadTrackingStates(), isEmpty);
  });

  test(
    'large dated changes import automatically without batch quarantine',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.anilist);
      await ingest(repo, TrackerSource.anilist, [
        for (int id = 1; id <= 40; id++) sample(id: id, progress: 10),
      ]);
      final result = await ingest(repo, TrackerSource.anilist, [
        for (int id = 1; id <= 40; id++) sample(id: id, progress: 2, hour: 2),
      ]);
      expect(result.importedChanges, 40);
      expect(result.quarantined, isFalse);
      expect(result.states.every((state) => state.progress == 2), isTrue);
      expect(await repo.watchConflicts().first, isEmpty);
    },
  );

  test(
    'explicit null clears reset defaults without clearing absent fields',
    () {
      final original = sample().apply(
        UserMediaPatch(
          notes: 'Keep until explicitly cleared',
          repeat: 2,
          progressVolumes: 4,
          priority: 8,
          private: true,
          hiddenFromStatusLists: true,
          customLists: {'A': true},
          advancedScores: {'Story': 8},
          malPriority: 2,
          malRewatchValue: 4,
          malTags: ['A'],
        ),
        epoch,
      );
      final clear = UserMediaPatch(
        fields: {
          UserMediaField.progress,
          UserMediaField.progressVolumes,
          UserMediaField.notes,
          UserMediaField.repeat,
          UserMediaField.priority,
          UserMediaField.private,
          UserMediaField.hiddenFromStatusLists,
          UserMediaField.customLists,
          UserMediaField.advancedScores,
          UserMediaField.malPriority,
          UserMediaField.malRewatchValue,
          UserMediaField.malTags,
        },
      );
      final cleared = original.apply(clear, epoch);
      expect(cleared.progress, 0);
      expect(cleared.progressVolumes, 0);
      expect(cleared.notes, '');
      expect(cleared.repeat, 0);
      expect(cleared.score, original.score);
      expect(cleared.startedAt, original.startedAt);
      for (final source in TrackerSource.values) {
        expect(providerConfirmsPatch(clear, cleared, source), isTrue);
      }
      expect(
        providerResponseConfirmsPatch(
          {
            'progress': 0,
            'notes': '',
            'repeat': 0,
            'priority': 0,
            'private': false,
            'hiddenFromStatusLists': false,
            'customLists': <String, bool>{},
            'advancedScores': <String, double>{},
          },
          clear,
          TrackerSource.anilist,
          'anime',
        ),
        isTrue,
      );
      expect(
        providerResponseConfirmsPatch(
          {
            'num_episodes_watched': 0,
            'comments': '',
            'num_times_rewatched': 0,
            'priority': 0,
            'rewatch_value': 0,
            'tags': <String>[],
          },
          clear,
          TrackerSource.mal,
          'anime',
        ),
        isTrue,
      );
    },
  );

  test(
    'first observed notes do not conflict with defaults or another field edit',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.mal);
      await ingest(repo, TrackerSource.mal, [
        sample(
          source: TrackerSource.mal,
          present: ['progress', 'score', 'startedAt'],
        ),
      ]);
      await edit(repo, UserMediaPatch(progress: 4), 1);
      await ingest(repo, TrackerSource.mal, [
        sample(source: TrackerSource.mal).apply(
          UserMediaPatch(notes: 'Previously absent catalog note'),
          epoch,
          providerSource: TrackerSource.mal,
        ),
      ]);
      final state = (await repo.loadTrackingStates()).single;
      expect(state.notes, 'Previously absent catalog note');
      expect(state.progress, 4);
      expect(state.updatedAt, epoch.add(const Duration(hours: 1)));
      expect(await repo.watchConflicts().first, isEmpty);
    },
  );

  test('queued notes cannot overwrite an unseen newer catalog note', () async {
    final repo = memory();
    await approve(repo, TrackerSource.mal);
    await ingest(repo, TrackerSource.mal, [
      sample(
        source: TrackerSource.mal,
        present: ['progress', 'score', 'startedAt'],
      ),
    ]);
    await edit(
      repo,
      UserMediaPatch(notes: 'Older local note'),
      1,
      targets: {TrackerSource.mal},
    );
    final adapter = Adapter(TrackerSource.mal);
    final engine = LocalFirstSyncEngine(
      store: CanonicalTrackingSyncStore(repository: repo),
      adapters: {TrackerSource.mal: adapter},
    );
    expect(
      await repo.unobservedDeliveryFields(
        (await repo.loadJournal()).single,
        TrackerSource.mal,
        TrackerSource.mal.name,
      ),
      contains(UserMediaField.notes),
      reason:
          (await repo.database
                  .select(repo.database.providerSnapshotRecords)
                  .get())
              .map(
                (row) =>
                    '${row.localId} ${row.accountId} ${row.normalizedJson}',
              )
              .join('\n'),
    );
    await engine.flush();
    expect(adapter.applied, isEmpty);
    expect((await repo.loadJournal()).single.patch.notes, 'Older local note');
    final remote = sample(source: TrackerSource.mal, hour: 3).apply(
      UserMediaPatch(notes: 'Newer catalog note'),
      epoch.add(const Duration(hours: 3)),
      providerSource: TrackerSource.mal,
    );
    await ingest(repo, TrackerSource.mal, [remote]);
    await engine.flush();
    expect(
      (await repo.loadTrackingStates()).single.notes,
      'Newer catalog note',
    );
    expect(adapter.applied, isEmpty);
    expect(
      await repo.loadJournal(),
      isEmpty,
      reason: jsonEncode(
        (await repo.loadJournal()).map((job) => job.toJson()).toList(),
      ),
    );
  });

  test(
    'partial snapshots keep past field observations without making them fresh',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.mal);
      UserMediaState remote(int hour) =>
          sample(source: TrackerSource.mal, hour: hour).apply(
            UserMediaPatch(notes: 'Observed catalog note'),
            epoch.add(Duration(hours: hour)),
            providerSource: TrackerSource.mal,
          );
      await ingest(repo, TrackerSource.mal, [remote(0)]);
      await edit(
        repo,
        UserMediaPatch(notes: 'Genuine local edit'),
        1,
        targets: {TrackerSource.mal},
      );
      await ingest(repo, TrackerSource.mal, [
        sample(source: TrackerSource.mal, hour: 2, present: ['progress']),
      ]);
      final adapter = Adapter(TrackerSource.mal);
      final engine = LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.mal: adapter},
      );
      await engine.flush();
      expect(adapter.applied, isEmpty);
      await ingest(repo, TrackerSource.mal, [remote(2)]);
      expect(
        (await repo.loadTrackingStates()).single.notes,
        'Genuine local edit',
        reason:
            'Unchanged notes must not acquire another field’s newer timestamp.',
      );
      await engine.flush();
      expect(adapter.applied.single.patch.notes, 'Genuine local edit');
      expect(
        await repo.loadJournal(),
        isEmpty,
        reason: jsonEncode(
          (await repo.loadJournal()).map((job) => job.toJson()).toList(),
        ),
      );
    },
  );

  test('confirmation verifies every supported field and calendar dates', () {
    final patch = UserMediaPatch(
      progress: 4,
      repeat: 2,
      priority: 8,
      completedAt: DateTime.utc(2026, 10, 1),
      notes: 'abc',
      private: true,
      advancedScores: {'Story': 8},
      customLists: {'A': true},
    );
    final desired = sample().apply(
      patch,
      epoch,
      providerSource: TrackerSource.anilist,
    );
    expect(
      providerConfirmsPatch(patch, desired, TrackerSource.anilist),
      isTrue,
    );
    for (final bad in [
      UserMediaPatch(repeat: 1),
      UserMediaPatch(priority: 0),
      UserMediaPatch(completedAt: null, fields: {UserMediaField.completedAt}),
      UserMediaPatch(notes: ''),
      UserMediaPatch(private: false),
      UserMediaPatch(advancedScores: {'Story': 1}),
      UserMediaPatch(customLists: {}),
    ]) {
      expect(
        providerConfirmsPatch(
          patch,
          desired.apply(bad, epoch, providerSource: TrackerSource.anilist),
          TrackerSource.anilist,
        ),
        isFalse,
      );
    }
  });

  test(
    'rounded scores confirm without rewriting precision and unsupported volumes stay local',
    () {
      expect(
        providerConfirmsPatch(
          UserMediaPatch(score: 8.7),
          sample(
            source: TrackerSource.mal,
          ).apply(UserMediaPatch(score: 9), epoch),
          TrackerSource.mal,
        ),
        isTrue,
      );
      expect(
        providerEntryFields(TrackerSource.mal),
        isNot(contains(UserMediaField.progressVolumes)),
      );
      expect(
        providerEntryFields(TrackerSource.mal, mediaKind: 'manga'),
        contains(UserMediaField.progressVolumes),
      );
      expect(
        providerResponseConfirmsPatch(
          {'status': 'CURRENT', 'progress': 4},
          UserMediaPatch(progress: 4, notes: 'x'),
          TrackerSource.anilist,
          'anime',
        ),
        isFalse,
      );
    },
  );

  test('many ambiguous confirmations share one list readback', () async {
    final repo = memory();
    final store = CanonicalTrackingSyncStore(repository: repo);
    await store.loadStates();
    final entries = [for (int id = 1; id <= 30; id++) sample(id: id)];
    await repo.saveTrackingStates(entries);
    await repo.saveJournal([
      for (final entry in entries)
        SyncJournalEntry(
          operationId: 'legacy-${entry.identity.localId}',
          identity: entry.identity,
          patch: UserMediaPatch(progress: 3),
          pendingTargets: const {},
          awaitingRemoteTargets: {TrackerSource.anilist},
          createdAt: epoch,
          updatedAt: epoch,
        ),
    ]);
    final adapter = Adapter(TrackerSource.anilist, entries: entries);
    await LocalFirstSyncEngine(
      store: store,
      adapters: {TrackerSource.anilist: adapter},
    ).flush();
    expect(adapter.fetches, 1);
    expect(await repo.loadJournal(), isEmpty);
    expect(adapter.applied, isEmpty);
  });

  test(
    'successful normalized mutation acknowledgment needs no list readback',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 7),
        1,
        targets: {TrackerSource.anilist},
      );
      final adapter = Adapter(TrackerSource.anilist);
      await LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.anilist: adapter},
      ).flush();
      expect(adapter.fetches, 0);
      expect(await repo.loadJournal(), isEmpty);
      expect(
        (await repo.watchActivity().first).first.deliveryStates['anilist'],
        'confirmed',
      );
    },
  );

  test(
    'stalled provider cannot block local saves or another provider delivery',
    () async {
      final repo = memory();
      for (final source in [TrackerSource.anilist, TrackerSource.mal]) {
        await approve(repo, source);
      }
      await repo.saveTrackingStates([sample()]);
      final slow = Adapter(TrackerSource.anilist)..gate = Completer<void>();
      final fast = Adapter(TrackerSource.mal);
      final sync = await coordinator(repo, {
        TrackerSource.anilist: slow,
        TrackerSource.mal: fast,
      });
      await edit(
        repo,
        UserMediaPatch(progress: 7),
        1,
        targets: {TrackerSource.anilist, TrackerSource.mal},
      );
      final running = sync.flushPending();
      try {
        await slow.entered.future.timeout(const Duration(seconds: 2));
        await fast.delivered.future.timeout(const Duration(seconds: 2));
        expect(slow.applied, isEmpty);
        await sync
            .pushEntryEdit(
              externalIds: const {'anilist': '10', 'mal': '110'},
              progress: 8,
              targets: {},
            )
            .timeout(const Duration(seconds: 2));
        expect((await repo.loadTrackingStates()).single.progress, 8);
      } finally {
        slow.gate!.complete();
        await running;
      }
    },
  );

  test(
    'stalled anime catalog cannot block another catalog manga refresh',
    () async {
      final repo = memory();
      for (final source in [TrackerSource.anilist, TrackerSource.mal]) {
        await approve(repo, source);
      }
      await repo.saveTrackingStates([sample()]);
      final slow = Adapter(TrackerSource.anilist)..gate = Completer<void>();
      final fast = Adapter(TrackerSource.mal);
      final sync = await coordinator(repo, {
        TrackerSource.anilist: slow,
        TrackerSource.mal: fast,
      });
      final running = Future.wait([
        sync.refreshAllConnectedLibraries(),
        sync.refreshAllConnectedLibraries(mediaKind: 'manga'),
      ]);
      try {
        await slow.entered.future.timeout(const Duration(seconds: 2));
        await fast.mangaEntered.future.timeout(const Duration(seconds: 2));
        expect(slow.mangaEntered.isCompleted, isFalse);
      } finally {
        slow.gate!.complete();
        await running;
      }
    },
  );

  test(
    'provider outage retries and catches up automatically without another edit',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.mal);
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 7),
        1,
        targets: {TrackerSource.mal},
      );
      final adapter = Adapter(TrackerSource.mal)..failures = 1;
      final sync = await coordinator(repo, {TrackerSource.mal: adapter});
      await sync.flushPending();
      final health = (await CanonicalTrackingSyncStore(
        repository: repo,
      ).loadHealth())[TrackerSource.mal]!;
      expect(health.nextRetryAt, isNotNull);
      await adapter.delivered.future.timeout(const Duration(seconds: 8));
      // The acknowledgment can settle immediately after the adapter returns.
      await sync.flushPending();
      expect(await repo.loadJournal(), isEmpty);
      expect(adapter.applied.single.patch.progress, 7);
      expect(adapter.fetches, 2);
    },
  );

  test(
    'coalescing keeps audit history and delivers only latest desired state',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 4),
        1,
        targets: {TrackerSource.anilist},
      );
      await edit(
        repo,
        UserMediaPatch(notes: 'Latest note'),
        2,
        targets: {TrackerSource.anilist},
      );
      await edit(
        repo,
        UserMediaPatch(progress: 6),
        3,
        targets: {TrackerSource.anilist},
      );
      final adapter = Adapter(TrackerSource.anilist);
      await LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.anilist: adapter},
      ).flush();
      expect(adapter.applied, hasLength(1));
      expect(adapter.applied.single.patch.progress, 6);
      expect(adapter.applied.single.patch.notes, 'Latest note');
      expect(await repo.watchActivity().first, hasLength(3));
    },
  );

  test(
    'orphan outbox migration restores only current fields and is idempotent',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 4),
        1,
        targets: {TrackerSource.anilist},
      );
      await edit(
        repo,
        UserMediaPatch(progress: 8, notes: 'keep'),
        2,
        targets: {TrackerSource.anilist},
      );
      await repo.saveJournal([]);
      await repo.database.customStatement(
        "DELETE FROM sync_cursor_records WHERE scope = 'migration:sync.independent.v3'",
      );
      await repo.recoverIndependentSyncBacklog();
      final jobs = await repo.loadJournal();
      expect(jobs, hasLength(1));
      expect(jobs.single.patch.progress, 8);
      expect(jobs.single.readbackBeforeWrite, isTrue);
      await repo.recoverIndependentSyncBacklog();
      expect(await repo.loadJournal(), hasLength(1));
      final history = await repo.watchActivity().first;
      expect(history.last.deliveryStates['anilist'], 'superseded');
    },
  );

  test(
    'no-op dates and zero advanced categories do not add jobs or change edit timestamps',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(advancedScores: {'Story': 0}),
        1,
        targets: {TrackerSource.anilist},
      );
      expect(await repo.loadJournal(), isEmpty);
      expect(await repo.watchActivity().first, isEmpty);
      expect((await repo.loadTrackingStates()).single.updatedAt, epoch);
    },
  );

  for (final remoteWins in [true, false]) {
    test(
      'independent Drive edits choose actual newest time (remote wins: $remoteWins)',
      () async {
        final a = memory(), b = memory();
        await a.saveTrackingStates([sample()]);
        await b.applyDriveSnapshot(await a.buildDriveSnapshot());
        await edit(a, UserMediaPatch(progress: 4), remoteWins ? 3 : 1);
        await edit(b, UserMediaPatch(progress: 7), 2);
        await b.applyDriveSegment(
          (await a.buildPendingDriveSegment())!,
          trackerTargets: const {},
        );
        expect(
          (await b.loadTrackingStates()).single.progress,
          remoteWins ? 4 : 7,
        );
        expect(await b.watchConflicts().first, isEmpty);
      },
    );
  }

  test(
    'undated proposal survives snapshot storage, deduplicates, and resolves on newer evidence',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.anilist);
      await ingest(repo, TrackerSource.anilist, [sample()]);
      await edit(repo, UserMediaPatch(progress: 8), 1);
      final unknown = UserMediaState.fromJson({
        ...sample(progress: 5).toJson(),
        'updatedAt': DateTime.fromMillisecondsSinceEpoch(
          0,
          isUtc: true,
        ).toIso8601String(),
        'providerStates': {
          'anilist': {
            'provider': 'anilist',
            'data': {
              'presentFields': ['progress'],
            },
          },
        },
      });
      await ingest(repo, TrackerSource.anilist, [unknown]);
      await ingest(repo, TrackerSource.anilist, [unknown]);
      final review = (await repo.watchConflicts().first).single;
      expect(review.title, 'Sync title 10');
      expect((review.incomingValue as Map)['reason'], contains('edit date'));
      expect((await repo.loadTrackingStates()).single.progress, 8);
      await ingest(repo, TrackerSource.anilist, [sample(progress: 5, hour: 3)]);
      expect((await repo.loadTrackingStates()).single.progress, 5);
      expect(await repo.watchConflicts().first, isEmpty);
    },
  );

  test(
    'authentication failure waits for credentials even without queued writes',
    () async {
      final repo = memory();
      await approve(repo, TrackerSource.mal);
      final adapter = Adapter(TrackerSource.mal)
        ..failures = 1
        ..failure = const TrackerAuthenticationException(TrackerSource.mal);
      final sync = await coordinator(repo, {TrackerSource.mal: adapter});
      await sync.refreshAllConnectedLibraries();
      expect(adapter.fetches, 1);
      await sync.refreshAllConnectedLibraries(force: true);
      expect(adapter.fetches, 1);
    },
  );

  test(
    'provider retry state survives account switching independently',
    () async {
      final repo = memory();
      final first = CanonicalTrackingSyncStore(
        repository: repo,
        healthAccountIds: {TrackerSource.mal: 'first'},
      );
      final second = CanonicalTrackingSyncStore(
        repository: repo,
        healthAccountIds: {TrackerSource.mal: 'second'},
      );
      final now = DateTime.now().toUtc();
      final failed = const TrackerProviderHealth(
        provider: TrackerSource.mal,
        accountId: 'first',
      ).failure(now, StateError('first account outage'));
      await first.saveProviderHealth(failed);
      expect((await second.loadHealth())[TrackerSource.mal], isNull);
      await second.saveProviderHealth(
        const TrackerProviderHealth(
          provider: TrackerSource.mal,
          accountId: 'second',
        ).success(now),
      );
      expect(
        (await first.loadHealth())[TrackerSource.mal]!.nextRetryAt,
        failed.nextRetryAt,
      );
      expect(
        (await second.loadHealth())[TrackerSource.mal]!.availability,
        TrackerProviderAvailability.healthy,
      );
    },
  );

  test(
    'persisted backoff prevents writes after worker restart and caps at five minutes',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 6),
        1,
        targets: {TrackerSource.anilist},
      );
      final store = CanonicalTrackingSyncStore(repository: repo);
      final now = DateTime.now().toUtc();
      var health = const TrackerProviderHealth(provider: TrackerSource.anilist);
      for (int i = 0; i < 15; i++) {
        health = health.failure(now, StateError('down'));
      }
      expect(health.nextRetryAt!.difference(now), const Duration(minutes: 5));
      await store.saveProviderHealth(health);
      final adapter = Adapter(TrackerSource.anilist);
      await LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.anilist: adapter},
        now: () => now,
      ).flush();
      expect(adapter.applied, isEmpty);
      expect(
        (await store.loadHealth())[TrackerSource.anilist]!.nextRetryAt,
        health.nextRetryAt,
      );
      await store.saveProviderHealth(health.success(now));
      await LocalFirstSyncEngine(
        store: store,
        adapters: {TrackerSource.anilist: adapter},
      ).flush();
      expect(adapter.applied, hasLength(1));
    },
  );

  test(
    'account switching does not send an old account queue to a new account',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 6),
        1,
        targets: {TrackerSource.anilist},
      );
      final jobs = await repo.loadJournal();
      await repo.saveJournal([
        SyncJournalEntry.fromJson({
          ...jobs.single.toJson(),
          'targetAccountIds': {'anilist': 'different-account'},
        }),
      ]);
      final adapter = Adapter(TrackerSource.anilist);
      await LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.anilist: adapter},
      ).flush();
      expect(adapter.applied, isEmpty);
      expect(await repo.loadJournal(), hasLength(1));
    },
  );

  test(
    'delivered-but-unconfirmed operation survives restart without another write',
    () async {
      final repo = memory();
      await repo.saveTrackingStates([sample()]);
      await edit(
        repo,
        UserMediaPatch(progress: 6),
        1,
        targets: {TrackerSource.anilist},
      );
      final adapter = Adapter(TrackerSource.anilist)..acknowledges = false;
      await LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.anilist: adapter},
      ).flush();
      expect((await repo.loadJournal()).single.awaitingRemoteTargets, {
        TrackerSource.anilist,
      });
      final details = (await repo.watchActivity().first).first;
      expect(details.deliveryStates['anilist'], 'delivered');
      expect(details.deliveryDetails['anilist']!.attempts, 1);
      expect(details.deliveryDetails['anilist']!.lastAttemptAt, isNotNull);
      await LocalFirstSyncEngine(
        store: CanonicalTrackingSyncStore(repository: repo),
        adapters: {TrackerSource.anilist: adapter},
      ).flush();
      expect(adapter.applied, hasLength(1));
      expect(await repo.loadJournal(), isEmpty);
    },
  );

  test(
    'exact duplicate identity repair retains history, episodes, and old Drive alias',
    () async {
      final repo = memory();
      final root = sample().withIdentity(
        const MediaIdentity(localId: 'root', anilistId: 10, malId: 110),
      );
      final shell = sample(source: TrackerSource.shikimori, progress: 7)
          .withIdentity(const MediaIdentity(localId: 'shell', shikimoriId: 210))
          .withMediaItem(
            MediaItem.fromJson({
              ...sample().mediaItem.toJson(),
              'id': 'shikimori:210',
              'title': 'Anime #210',
              'externalIds': const {'shikimori': '210'},
            }),
          );
      await repo.saveTrackingStates([root, shell]);
      final initial = await repo.loadTrackingStates();
      final savedRoot = initial.singleWhere(
        (state) => state.identity.anilistId == 10,
      );
      final savedShell = initial.singleWhere(
        (state) => state.identity.shikimoriId == 210,
      );
      final at = epoch.add(const Duration(hours: 2));
      await repo.commitTrackingMutation(
        states: [savedRoot, savedShell.apply(UserMediaPatch(progress: 8), at)],
        journal: const [],
        favorites: const [],
        identity: savedShell.identity,
        patch: UserMediaPatch(progress: 8),
        targets: const {},
        occurredAt: at,
      );
      await repo.saveEpisodeProgress(
        mediaId: shell.mediaItem.id,
        mediaItem: shell.mediaItem,
        season: 1,
        episode: 1,
        positionSeconds: 120,
        durationSeconds: 1400,
      );
      final before = (await repo.watchActivity().first).length;
      await approve(repo, TrackerSource.shikimori);
      await ingest(repo, TrackerSource.shikimori, [
        sample(source: TrackerSource.shikimori, progress: 8, hour: 2),
      ]);
      final repaired = (await repo.loadTrackingStates()).single;
      expect(repaired.identity.localId, savedRoot.identity.localId);
      expect(repaired.progress, 8);
      expect(
        (await repo.watchActivity().first).length,
        greaterThanOrEqualTo(before),
      );
      final episodes = await repo.database
          .select(repo.database.episodeStateRecords)
          .get();
      expect(episodes.single.localId, savedRoot.identity.localId);
      expect(episodes.single.positionSeconds, 120);
      expect(
        await repo.resolveOrCreateMedia(
          identity: savedShell.identity,
          mediaItem: shell.mediaItem,
        ),
        savedRoot.identity.localId,
      );
      // Saving via the old alias must still write the canonical episode key.
      await repo.saveEpisodeProgress(
        mediaId: shell.mediaItem.id,
        mediaItem: shell.mediaItem,
        season: 1,
        episode: 1,
        positionSeconds: 150,
        durationSeconds: 1400,
      );
      expect(
        await repo.database.select(repo.database.episodeStateRecords).get(),
        hasLength(1),
      );
    },
  );
}
