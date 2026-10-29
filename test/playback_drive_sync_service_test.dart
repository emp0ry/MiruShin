import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/data/playback_drive_sync_service.dart';
import 'package:mirushin/features/library/domain/canonical_library_models.dart';
import 'package:mirushin/features/library/domain/playback_sync_models.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

const media = MediaItem(
  id: 'anilist:10',
  title: 'Must not travel in playback',
  originalTitle: '',
  overview: 'Large catalog metadata must stay out',
  type: MediaType.anime,
  year: 2026,
  posterUrl: 'https://example.com/poster.jpg',
  backdropUrl: '',
  rating: 0,
  genres: [],
  sourceProvider: 'AniList',
  statusLabel: '',
  externalIds: {'anilist': '10', 'mal': '20', 'shikimori': '30'},
);

class MemoryPlaybackCloud implements PlaybackCloudReplica {
  final files = <String, PlaybackReplicaSnapshot>{};
  int uploads = 0;
  bool failPush = false;
  Future<void> Function()? beforeUpload;

  @override
  Future<PlaybackCloudRead> pullPlaybackSnapshots({
    required Map<String, String> excluding,
  }) async => PlaybackCloudRead(
    snapshots: [
      for (final snapshot in files.values)
        if (excluding[snapshot.fileName] != snapshot.checksum)
          PlaybackReplicaSnapshot.decode(snapshot.encode()),
    ],
    fileNames: files.keys.toSet(),
  );

  @override
  Future<void> pushPlaybackSnapshot(PlaybackReplicaSnapshot snapshot) async {
    await beforeUpload?.call();
    if (failPush) throw StateError('offline');
    uploads++;
    files[snapshot.fileName] = PlaybackReplicaSnapshot.decode(
      snapshot.encode(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  CanonicalLibraryRepository repository({String namespace = 'anilist-1'}) {
    final database = CanonicalLibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    return CanonicalLibraryRepository(database, replicaNamespace: namespace);
  }

  Future<void> save(
    CanonicalLibraryRepository repo,
    int position,
    int seconds, {
    int cycle = 0,
    bool completed = false,
  }) => repo.saveEpisodeProgress(
    mediaId: media.id,
    mediaItem: media,
    season: 1,
    episode: 2.5,
    positionSeconds: position,
    durationSeconds: 1400,
    completed: completed,
    watchCycle: cycle,
    occurredAt: DateTime.utc(2026, 10, 1).add(Duration(seconds: seconds)),
  );

  Future<void> sync(
    CanonicalLibraryRepository repo,
    MemoryPlaybackCloud cloud,
  ) => PlaybackDriveSyncService(
    repository: repo,
  ).sync(cloud: cloud, requireActive: () {});

  test(
    'two devices exchange positions and choices without library, metadata, or tracker work',
    () async {
      final a = repository();
      final b = repository();
      final cloud = MemoryPlaybackCloud();
      await save(a, 120, 1);
      await a.saveStreamPreference(
        identity: MediaIdentity.fromExternalIds(
          media.externalIds,
          mediaId: media.id,
        ),
        mediaItem: media,
        preference: const CanonicalStreamPreference(
          addonId: 'addon',
          sourceId: 'source',
          serverId: 'server',
          serverTitle: 'Server',
          voiceoverId: 'dub',
          voiceoverTitle: 'Dub',
          qualityId: '1080',
          qualityLabel: '1080p',
        ),
      );
      final fullPending = await a.pendingDriveDeliveryCount();
      await sync(a, cloud);
      await sync(b, cloud);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: 'mal:20',
          season: 1,
          episode: 2.5,
        ))?.positionSeconds,
        120,
      );
      expect(
        (await b.loadStreamPreference(mediaId: 'shikimori:30'))?.voiceoverId,
        'dub',
      );
      expect(
        (await b.loadStreamPreference(mediaId: media.id))?.qualityLabel,
        '1080p',
      );
      expect(await b.activeLibraryEntryCount(), 0);
      expect(await b.loadJournal(), isEmpty);
      expect(
        await b.database.select(b.database.libraryOperationRecords).get(),
        isEmpty,
      );
      expect(await b.pendingDriveDeliveryCount(), 0);
      expect(await a.pendingDriveDeliveryCount(), fullPending);
      expect(await a.pendingPlaybackDeliveryIds(), isEmpty);
      expect(await a.confirmedTrackerDeliveryLedger(), isEmpty);
      final raw = cloud.files.values.first.encode();
      for (final forbidden in [
        media.title,
        media.overview,
        media.posterUrl,
        'libraryEntries',
        'operations',
        'providerSnapshots',
      ]) {
        expect(raw, isNot(contains(forbidden)));
      }
      final uploads = cloud.uploads;
      await sync(a, cloud);
      await sync(b, cloud);
      expect(
        cloud.uploads,
        uploads,
        reason: 'Remote applies must not echo into uploads.',
      );
    },
  );

  test(
    'rewind, explicit zero, fractional episode and rewatch cycles survive restart',
    () async {
      final a = repository();
      final b = repository();
      final cloud = MemoryPlaybackCloud();
      await save(a, 900, 1, completed: true);
      await sync(a, cloud);
      await sync(b, cloud);
      await save(b, 0, 2);
      await sync(b, cloud);
      await sync(a, cloud);
      expect(
        (await a.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 2.5,
        ))?.positionSeconds,
        0,
      );
      expect(
        (await a.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 2.5,
        ))?.completed,
        isFalse,
      );
      await save(a, 45, 3, cycle: 1);
      await sync(a, cloud);
      final restartedB = CanonicalLibraryRepository(
        b.database,
        replicaNamespace: 'anilist-1',
      );
      await sync(restartedB, cloud);
      expect(
        (await b.watchEpisodeProgress(media.id, watchCycle: 1).first)[(1, 2.5)]
            ?.positionSeconds,
        45,
      );
      expect(
        (await b.watchEpisodeProgress(media.id).first)[(1, 2.5)]
            ?.positionSeconds,
        0,
      );
      expect(
        cloud.files.length,
        2,
        reason: 'One replaceable file per device, including after restart.',
      );
    },
  );

  test(
    'latest actual edit wins regardless of compact file iteration order',
    () async {
      final a = repository();
      final b = repository();
      final c = repository();
      await save(a, 900, 1);
      await b.applyPlaybackSnapshot(await a.buildPlaybackSnapshot());
      await save(a, 1200, 2);
      await save(b, 40, 3);
      await c.applyPlaybackSnapshot(await b.buildPlaybackSnapshot());
      await c.applyPlaybackSnapshot(await a.buildPlaybackSnapshot());
      expect(
        (await c.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 2.5,
        ))?.positionSeconds,
        40,
      );
      await c.applyPlaybackSnapshot(await b.buildPlaybackSnapshot());
      expect(await c.watchConflicts().first, isEmpty);
    },
  );

  test(
    'same-time causal reset applies, same-time independent edits create one conflict',
    () async {
      final a = repository();
      final b = repository();
      await save(a, 900, 1);
      await b.applyPlaybackSnapshot(await a.buildPlaybackSnapshot());
      await save(b, 0, 1);
      await a.applyPlaybackSnapshot(await b.buildPlaybackSnapshot());
      expect(
        (await a.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 2.5,
        ))?.positionSeconds,
        0,
      );
      await save(a, 300, 5);
      await save(b, 500, 5);
      final incoming = await b.buildPlaybackSnapshot();
      await a.applyPlaybackSnapshot(incoming);
      await a.applyPlaybackSnapshot(incoming);
      expect(await a.watchConflicts().first, hasLength(1));
      await b.applyPlaybackSnapshot(await a.buildPlaybackSnapshot());
      expect(await b.watchConflicts().first, hasLength(1));
      final conflict = (await a.watchConflicts().first).single;
      await a.resolveConflict(
        conflictId: conflict.conflictId,
        takeIncoming: false,
        trackerTargets: {},
      );
      await b.applyPlaybackSnapshot(await a.buildPlaybackSnapshot());
      expect(await b.watchConflicts().first, isEmpty);
    },
  );

  test(
    'sub-checkpoint position updates are replicated with their actual time',
    () async {
      final a = repository();
      final b = repository();
      final cloud = MemoryPlaybackCloud();
      await save(a, 100, 1);
      await sync(a, cloud);
      await sync(b, cloud);
      await save(a, 105, 2); // Does not create a new historical operation.
      await sync(a, cloud);
      await sync(b, cloud);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 2.5,
        ))?.positionSeconds,
        105,
      );
      expect(await b.watchConflicts().first, isEmpty);
    },
  );

  test(
    'upload failure and a save during upload never acknowledge unsent edits',
    () async {
      final a = repository();
      final cloud = MemoryPlaybackCloud()..failPush = true;
      await save(a, 100, 1);
      await expectLater(sync(a, cloud), throwsStateError);
      expect(await a.pendingPlaybackDeliveryIds(), isNotEmpty);
      cloud.failPush = false;
      cloud.beforeUpload = () => save(a, 400, 3);
      await sync(a, cloud);
      expect(await a.pendingPlaybackDeliveryIds(), isNotEmpty);
      cloud.beforeUpload = null;
      await sync(a, cloud);
      expect(await a.pendingPlaybackDeliveryIds(), isEmpty);
      expect(cloud.files.values.single.episodes.single['positionSeconds'], 400);
    },
  );

  test(
    'cancellation prevents applying or acknowledging late remote results',
    () async {
      final a = repository();
      final b = repository();
      final cloud = MemoryPlaybackCloud();
      await save(a, 100, 1);
      await sync(a, cloud);
      await expectLater(
        PlaybackDriveSyncService(repository: b).sync(
          cloud: cloud,
          requireActive: () => throw StateError('workspace switched'),
        ),
        throwsStateError,
      );
      expect(
        await b.database.select(b.database.episodeStateRecords).get(),
        isEmpty,
      );
      expect(await b.processedPlaybackChecksums(), isEmpty);
    },
  );

  test(
    'different account namespaces are rejected without creating any records',
    () async {
      final a = repository();
      final b = repository(namespace: 'anilist-2');
      await save(a, 100, 1);
      await expectLater(
        b.applyPlaybackSnapshot(await a.buildPlaybackSnapshot()),
        throwsStateError,
      );
      expect(
        await b.database.select(b.database.canonicalMediaRecords).get(),
        isEmpty,
      );
    },
  );

  test(
    'reconnecting to an empty Google account seeds current positions again',
    () async {
      final a = repository();
      final cloud = MemoryPlaybackCloud();
      await save(a, 100, 1);
      await sync(a, cloud);
      expect(await a.pendingPlaybackDeliveryIds(), isEmpty);
      final otherGoogleAccount = MemoryPlaybackCloud();
      await sync(a, otherGoogleAccount);
      expect(
        otherGoogleAccount
            .files
            .values
            .single
            .episodes
            .single['positionSeconds'],
        100,
      );
      await sync(a, otherGoogleAccount);
      expect(otherGoogleAccount.uploads, 1);
    },
  );

  test(
    'existing local history seeds compact format without altering edit times',
    () async {
      final a = repository();
      final cloud = MemoryPlaybackCloud();
      await save(a, 100, 1);
      await a.database.customStatement(
        "DELETE FROM outbox_delivery_records WHERE target = 'drive.playback'",
      );
      await sync(a, cloud);
      final snapshot = cloud.files.values.single;
      expect(
        snapshot.episodes.single['updatedAtMs'],
        DateTime.utc(2026, 10, 1, 0, 0, 1).millisecondsSinceEpoch,
      );
      expect(cloud.uploads, 1);
    },
  );

  test(
    'old full backup restores membership after compact sync without regressing newer playback',
    () async {
      final a = repository();
      final b = repository();
      final c = repository();
      await a.saveTrackingStates([
        UserMediaState(
          identity: MediaIdentity.fromExternalIds(
            media.externalIds,
            mediaId: media.id,
          ),
          mediaItem: media,
          status: AniListListStatus.current,
          progress: 1,
          source: TrackerSource.anilist,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ]);
      await save(a, 100, 1);
      final oldBackup = await a.buildDriveSnapshot();
      await c.applyPlaybackSnapshot(await a.buildPlaybackSnapshot());
      await save(c, 500, 3);
      await b.applyPlaybackSnapshot(await c.buildPlaybackSnapshot());
      expect(await b.activeLibraryEntryCount(), 0);
      final result = await b.applyDriveSnapshot(oldBackup);
      expect(result.localEntryCount, 1);
      expect(
        (await b.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 2.5,
        ))?.positionSeconds,
        500,
      );
      expect(
        await b.database.select(b.database.canonicalMediaRecords).get(),
        hasLength(1),
      );
    },
  );

  test(
    'turning off during full snapshot application rolls back the transaction',
    () async {
      final a = repository();
      final b = repository();
      await a.saveTrackingStates([
        UserMediaState(
          identity: MediaIdentity.fromExternalIds(
            media.externalIds,
            mediaId: media.id,
          ),
          mediaItem: media,
          status: AniListListStatus.current,
          progress: 1,
          source: TrackerSource.anilist,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ]);
      final snapshot = await a.buildDriveSnapshot();
      var checks = 0;
      await expectLater(
        b.applyDriveSnapshot(
          snapshot,
          requireActive: () {
            if (++checks == 2) throw StateError('mode disabled');
          },
        ),
        throwsStateError,
      );
      expect(await b.activeLibraryEntryCount(), 0);
      expect(
        await b.database.select(b.database.canonicalMediaRecords).get(),
        isEmpty,
      );
      expect(await b.appliedDriveSnapshotChecksum(), isNull);
    },
  );

  test(
    'large unrelated library and audit history do not increase compact payload',
    () async {
      final a = repository();
      await save(a, 100, 1);
      final before = (await a.buildPlaybackSnapshot()).encode();
      final states = List.generate(
        500,
        (i) => UserMediaState(
          identity: MediaIdentity(localId: 'catalog:$i', anilistId: i + 1000),
          mediaItem: MediaItem.fromJson({
            ...media.toJson(),
            'id': 'anilist:${i + 1000}',
            'externalIds': {'anilist': '${i + 1000}'},
            'title': 'Catalog $i',
            'overview': 'metadata' * 300,
          }),
          status: AniListListStatus.planning,
          progress: 0,
          source: TrackerSource.anilist,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      await a.saveTrackingStates(states);
      final watchedId =
          (await a.buildPlaybackSnapshot()).episodes.single['localId']
              as String;
      for (var i = 0; i < 500; i++) {
        await a.appendOperation(
          LibraryOperationDraft(
            localId: watchedId,
            originKind: LibraryOriginKind.user,
            intent: LibraryMutationIntent.edit,
            fields: {'notes'},
            before: {},
            after: {'notes': 'history' * 300},
            targets: {},
            occurredAt: DateTime.utc(2026),
          ),
        );
      }
      expect((await a.buildPlaybackSnapshot()).encode(), before);
      expect(utf8.encode(before).length, lessThan(3000));
    },
  );
}
