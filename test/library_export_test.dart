import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/domain/library_export_snapshot.dart';
import 'package:mirushin/features/profile/application/anilist_profile_export.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

MediaItem media({bool manga = false, String title = 'Saved & offline'}) =>
    MediaItem(
      id: 'anilist:1',
      title: title,
      originalTitle: '',
      overview: '',
      type: manga ? MediaType.manga : MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 8,
      genres: const [],
      sourceProvider: 'AniList',
      externalIds: {if (manga) 'volumes': '12'},
      episodeCount: manga ? 100 : 24,
      statusLabel: 'FINISHED',
    );

LibraryExportEntry entry({
  String id = 'one',
  bool manga = false,
  Map<String, int> ids = const {'mal': 2, 'shikimori': 300},
  AniListListStatus status = AniListListStatus.completed,
}) => LibraryExportEntry(
  localId: id,
  mediaItem: media(manga: manga),
  status: status,
  progress: 24,
  progressVolumes: 7,
  totalVolumes: 12,
  repeat: 3,
  scoreRaw: 85,
  startedAt: const LibraryExportDate(year: 2026, month: 9),
  completedAt: const LibraryExportDate(year: 2026, month: 10, day: 1),
  notes: 'Notes ]]> & <test>',
  providerIds: ids,
);

LibraryExportPayload? export(
  List<LibraryExportEntry> entries, {
  bool anime = true,
  LibraryExportTarget target = LibraryExportTarget.myAnimeList,
}) => buildLibraryExportPayload(
  snapshot: LibraryExportSnapshot(workspaceId: 'local', entries: entries),
  username: 'User & partner',
  anime: anime,
  target: target,
  generatedAt: DateTime.utc(2026, 10, 11),
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'SQLite export preserves fuzzy dates but not over an explicit local edit',
    () async {
      final database = CanonicalLibraryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = CanonicalLibraryRepository(database);
      final state = UserMediaState(
        identity: const MediaIdentity(
          localId: 'date-test',
          anilistId: 1,
          malId: 2,
        ),
        mediaItem: media(),
        status: AniListListStatus.current,
        progress: 2,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 10),
        source: TrackerSource.anilist,
        startedAt: DateTime(2026, 1, 1),
        providerStates: {
          TrackerSource.anilist: ProviderUserMediaState(
            provider: TrackerSource.anilist,
            data: const {
              'startedAtFuzzy': {'year': 2026, 'month': null, 'day': null},
            },
          ),
        },
      );
      await repository.saveTrackingStates([state]);
      expect(
        (await repository.buildExportSnapshot())
            .entries
            .single
            .startedAt
            .malDate,
        '2026-00-00',
      );
      final stored = (await repository.loadTrackingStates()).single;
      await repository.commitTrackingMutation(
        states: [stored],
        journal: [],
        favorites: [],
        identity: stored.identity,
        patch: UserMediaPatch(startedAt: DateTime(2026, 1, 2)),
        targets: {},
        occurredAt: DateTime.utc(2026, 10, 11),
      );
      expect(
        (await repository.buildExportSnapshot())
            .entries
            .single
            .startedAt
            .malDate,
        '2026-01-02',
      );
    },
  );

  test(
    'offline XML uses only saved MAL identity and preserves tracking data',
    () {
      final xml = utf8.decode(export([entry()])!.bytes);
      expect(xml, contains('<series_animedb_id>2</series_animedb_id>'));
      expect(xml, contains('<my_watched_episodes>24</my_watched_episodes>'));
      expect(xml, contains('<my_score>9</my_score>'));
      expect(xml, contains('<my_start_date>2026-09-00</my_start_date>'));
      expect(xml, contains('<my_finish_date>2026-10-01</my_finish_date>'));
      expect(xml, contains('<my_times_watched>3</my_times_watched>'));
      expect(xml, contains('User &amp; partner'));
      expect(xml, contains(']]]]><![CDATA[>'));
    },
  );

  test('manga volumes, chapters and re-read counts are not zeroed', () {
    final xml = utf8.decode(
      export([
        entry(manga: true, status: AniListListStatus.repeating),
      ], anime: false)!.bytes,
    );
    expect(xml, contains('<my_read_volumes>7</my_read_volumes>'));
    expect(xml, contains('<series_volumes>12</series_volumes>'));
    expect(xml, contains('<my_read_chapters>24</my_read_chapters>'));
    expect(xml, contains('<my_times_read>3</my_times_read>'));
    expect(xml, contains('<user_total_reading>1</user_total_reading>'));
  });

  test('Shikimori target_id is NOT the MAL ID', () {
    final data =
        jsonDecode(
              utf8.decode(
                export(
                  [entry(manga: true)],
                  anime: false,
                  target: LibraryExportTarget.shikimori,
                )!.bytes,
              ),
            )
            as List;
    expect(data.single['target_id'], 300);
    expect(data.single['target_type'], 'Manga');
    expect(data.single['volumes'], 7);
    expect(data.single['chapters'], 24);
    expect(data.single['score'], 9);
    expect(data.single['rewatches'], 3);
    expect(data.single['text'], 'Notes ]]> & <test>');
  });

  test('deduplicates local entries and counts only exported entries', () {
    final valid = entry();
    final result = export([valid, valid, entry(id: 'missing', ids: {})])!;
    expect(result.skippedCount, 1);
    expect(result.skippedTitles, ['Saved & offline']);
    expect(
      utf8.decode(result.bytes),
      contains('<user_total_anime>1</user_total_anime>'),
    );
    expect(RegExp('<anime>').allMatches(utf8.decode(result.bytes)).length, 1);
  });

  test('ambiguous provider identity is skipped rather than writing twice', () {
    expect(export([entry(id: 'a'), entry(id: 'b')]), isNull);
    expect(
      export([
        entry(ids: {'mal': 2}),
      ], target: LibraryExportTarget.shikimori),
      isNull,
    );
    expect(export([entry(ids: {})]), isNull);
    expect(export([]), isNull);
  });

  test(
    'all five score representations use canonical raw without changing it',
    () {
      for (final raw in [35, 60, 85, 87, 100]) {
        final value = LibraryExportEntry(
          localId: '$raw',
          mediaItem: media(),
          status: AniListListStatus.current,
          progress: 2,
          scoreRaw: raw,
          providerIds: const {'mal': 2},
        );
        expect(
          utf8.decode(export([value])!.bytes),
          contains('<my_score>${(raw / 10).round()}</my_score>'),
        );
        expect(value.scoreRaw, raw);
      }
    },
  );

  test(
    'SQLite snapshot isolates workspaces, includes pending edits, skips tombstones/quarantine',
    () async {
      final dbA = CanonicalLibraryDatabase(NativeDatabase.memory());
      final dbB = CanonicalLibraryDatabase(NativeDatabase.memory());
      final a = CanonicalLibraryRepository(dbA, workspaceId: 'anilist:1');
      final b = CanonicalLibraryRepository(dbB, workspaceId: 'anilist:2');
      addTearDown(dbA.close);
      addTearDown(dbB.close);
      final now = DateTime.utc(2026, 10, 11);
      UserMediaState state(String id, int mal, int progress) => UserMediaState(
        identity: MediaIdentity(
          localId: id,
          kind: 'manga',
          malId: mal,
          shikimoriId: mal + 100,
        ),
        mediaItem: MediaItem.fromJson({
          ...media(manga: true).toJson(),
          'id': 'mal:manga:$mal',
        }),
        status: AniListListStatus.current,
        progress: progress,
        progressVolumes: 7,
        repeat: 2,
        score: 8.5,
        source: TrackerSource.mal,
        createdAt: now,
        updatedAt: now,
      );
      await a.saveTrackingStates([state('a', 2, 24), state('deleted', 3, 10)]);
      await b.saveTrackingStates([state('b', 9, 1)]);
      final existing = await a.loadTrackingStates();
      await a.removeLocalState(
        existing.firstWhere((s) => s.identity.malId == 3).identity,
      );
      await (dbA.update(
        dbA.providerBindingRecords,
      )..where((t) => t.provider.equals('shikimori'))).write(
        const ProviderBindingRecordsCompanion(quarantined: Value(true)),
      );
      final snapshot = await a.buildExportSnapshot();
      expect(snapshot.workspaceId, 'anilist:1');
      expect(snapshot.entries.length, 1);
      expect(snapshot.entries.single.progress, 24);
      expect(snapshot.entries.single.progressVolumes, 7);
      expect(snapshot.entries.single.totalVolumes, 12);
      expect(snapshot.entries.single.providerIds['mal'], 2);
      expect(
        snapshot.entries.single.providerIds.containsKey('shikimori'),
        isFalse,
      );
      expect(() => snapshot.entries.clear(), throwsUnsupportedError);
      expect((await b.buildExportSnapshot()).entries.single.progress, 1);
      expect(await a.pendingDriveDeliveryCount(), greaterThan(0));
    },
  );
}
