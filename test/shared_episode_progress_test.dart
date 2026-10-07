import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/application/episode_progress_provider.dart';
import 'package:mirushin/features/library/application/local_library_provider.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

const media = MediaItem(
  id: 'anilist:10',
  title: 'Shared episode test',
  originalTitle: '',
  overview: '',
  type: MediaType.anime,
  year: 2026,
  posterUrl: '',
  backdropUrl: '',
  rating: 0,
  genres: [],
  sourceProvider: 'AniList',
  statusLabel: 'FINISHED',
  episodeCount: 12,
  externalIds: {'anilist': '10', 'mal': '20', 'shikimori': '30'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  CanonicalLibraryRepository repository() {
    final database = CanonicalLibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    return CanonicalLibraryRepository(database);
  }

  Future<void> seed(CanonicalLibraryRepository repo) => repo.upsertLocalState(
    UserMediaState(
      identity: MediaIdentity.fromExternalIds(
        media.externalIds,
        mediaId: media.id,
      ),
      mediaItem: media,
      status: AniListListStatus.current,
      progress: 3,
      createdAt: DateTime.utc(2026, 10, 7),
      updatedAt: DateTime.utc(2026, 10, 7),
      source: TrackerSource.anilist,
    ),
  );

  test(
    'exact AniList/MAL/Shikimori bindings share checkpoints and UI',
    () async {
      final repo = repository();
      await seed(repo);
      await repo.saveEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 4,
        positionSeconds: 95,
        completed: true,
      );
      for (final id in ['anilist:10', 'mal:20', 'shikimori:30']) {
        final checkpoint = await repo.loadEpisodeProgress(
          mediaId: id,
          season: 1,
          episode: 4,
        );
        expect(checkpoint?.positionSeconds, 95);
        final ui = await repo.watchEpisodeProgress(id).first;
        expect(ui[(1, 4.0)]?.completed, isTrue);
      }
      expect(await repo.watchEpisodeProgress('mal:21').first, isEmpty);
    },
  );

  test('query reacts when media identity is first created', () async {
    final repo = repository();
    final initial = Completer<void>();
    final saved = Completer<void>();
    final sub = repo.watchEpisodeProgress(media.id).listen((values) {
      if (!initial.isCompleted) initial.complete();
      if (values[(1, 1.0)]?.positionSeconds == 95 && !saved.isCompleted) {
        saved.complete();
      }
    });
    addTearDown(sub.cancel);
    await initial.future.timeout(const Duration(seconds: 3));
    await repo.saveEpisodeProgress(
      mediaId: media.id,
      season: 1,
      episode: 1,
      positionSeconds: 95,
      mediaItem: media,
    );
    await saved.future.timeout(const Duration(seconds: 3));
  });

  test(
    'different anime, seasons, episodes and watch cycles never mix',
    () async {
      final repo = repository();
      for (final pair in [
        (1, 1.0, 95, 0),
        (2, 1.0, 125, 0),
        (1, 2.5, 165, 0),
        (1, 1.0, 0, 1),
      ]) {
        await repo.saveEpisodeProgress(
          mediaId: media.id,
          season: pair.$1,
          episode: pair.$2,
          positionSeconds: pair.$3,
          watchCycle: pair.$4,
        );
      }
      final ui = await repo.watchEpisodeProgress(media.id).first;
      expect(ui.keys, containsAll([(1, 1.0), (2, 1.0), (1, 2.5)]));
      expect(ui[(1, 1.0)]?.positionSeconds, 95);
      expect(
        (await repo.watchEpisodeProgress(media.id, watchCycle: 1).first)[(
              1,
              1.0,
            )]
            ?.positionSeconds,
        0,
      );
      expect(await repo.watchEpisodeProgress('anilist:11').first, isEmpty);
    },
  );

  test(
    'quarantined provider IDs are not checkpoint identity evidence',
    () async {
      final repo = repository();
      await seed(repo);
      await repo.saveEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 1,
        positionSeconds: 95,
      );
      await (repo.database.update(
        repo.database.providerBindingRecords,
      )..where((t) => t.provider.equals('mal'))).write(
        const ProviderBindingRecordsCompanion(quarantined: Value(true)),
      );
      expect(
        await repo.loadEpisodeProgress(
          mediaId: 'mal:20',
          season: 1,
          episode: 1,
        ),
        isNull,
      );
      expect(await repo.watchEpisodeProgress('mal:20').first, isEmpty);
    },
  );

  test(
    'compatibility migration never overwrites an authoritative zero/reset',
    () async {
      final repo = repository();
      await repo.saveEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 1,
        positionSeconds: 0,
      );
      await repo.saveLocalEpisodeCheckpoint(
        '${media.id}|S1E1.0',
        EpisodeProgress(
          positionSeconds: 700,
          completed: true,
          updatedAt: DateTime.now().add(const Duration(days: 1)),
        ).toJson(),
      );
      final c = ProviderContainer(
        overrides: [canonicalLibraryRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final local = c.read(localLibraryProvider.notifier);
      expect(
        (await local.loadEpisodeProgress(media.id, 1, 1))?.positionSeconds,
        0,
      );
      expect(
        (await repo.loadEpisodeProgress(
          mediaId: media.id,
          season: 1,
          episode: 1,
        ))?.completed,
        isFalse,
      );
    },
  );

  test('migration inserts missing checkpoints only once', () async {
    final repo = repository();
    await repo.saveEpisodeProgress(
      mediaId: media.id,
      season: 1,
      episode: 1,
      positionSeconds: 95,
      onlyIfMissing: true,
    );
    await repo.saveEpisodeProgress(
      mediaId: media.id,
      season: 1,
      episode: 1,
      positionSeconds: 500,
      completed: true,
      onlyIfMissing: true,
    );
    expect(
      (await repo.loadEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 1,
      ))?.positionSeconds,
      95,
    );
    expect(
      await repo.database.select(repo.database.libraryOperationRecords).get(),
      hasLength(1),
    );
  });

  test(
    'Drive restore updates UI without any source/compatibility bucket',
    () async {
      final a = repository();
      final b = repository();
      await seed(a);
      await a.saveEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 4,
        positionSeconds: 95,
        completed: true,
      );
      final c = ProviderContainer(
        overrides: [canonicalLibraryRepositoryProvider.overrideWithValue(b)],
      );
      addTearDown(c.dispose);
      final received = Completer<void>();
      final sub = c.listen(mediaEpisodeProgressProvider(media.id), (_, next) {
        if (next.value?[(1, 4.0)]?.positionSeconds == 95 &&
            !received.isCompleted) {
          received.complete();
        }
      });
      addTearDown(sub.close);
      expect(
        await c.read(mediaEpisodeProgressProvider(media.id).future),
        isEmpty,
      );
      await b.applyDriveSnapshot(await a.buildDriveSnapshot());
      await received.future.timeout(const Duration(seconds: 3));
      expect(await b.loadLocalEpisodeProgress(), isEmpty);
      final entry = (await b.loadTrackingStates()).single;
      expect(entry.status, AniListListStatus.current);
      expect(
        entry.progress,
        3,
        reason:
            'A playback-only checkpoint must not advance the aggregate library progress',
      );
      expect(entry.completedAt, isNull);
      expect(
        c
            .read(mediaEpisodeProgressProvider(media.id))
            .requireValue[(1, 4.0)]
            ?.isWatched,
        isTrue,
      );
    },
  );

  test('one account playback is not visible in another workspace', () async {
    final a = repository();
    final b = repository();
    await a.saveEpisodeProgress(
      mediaId: media.id,
      season: 1,
      episode: 1,
      positionSeconds: 95,
    );
    expect(await b.watchEpisodeProgress(media.id).first, isEmpty);
  });

  test(
    'account switch replaces UI checkpoints without showing previous account while loading',
    () async {
      final a = repository();
      final b = repository();
      await a.saveEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 1,
        positionSeconds: 95,
      );
      await b.saveEpisodeProgress(
        mediaId: media.id,
        season: 1,
        episode: 1,
        positionSeconds: 200,
      );
      final c = ProviderContainer(
        overrides: [
          canonicalLibraryRepositoryProvider.overrideWith(
            (ref) => ref.watch(_activeAccountProvider) == 'a' ? a : b,
          ),
        ],
      );
      addTearDown(c.dispose);
      final switched = Completer<void>();
      final sub = c.listen(mediaEpisodeProgressProvider(media.id), (_, next) {
        if (c.read(_activeAccountProvider) != 'b') return;
        final visible = currentEpisodeCheckpoints(next);
        expect(visible[(1, 1.0)]?.positionSeconds, isNot(95));
        if (visible[(1, 1.0)]?.positionSeconds == 200 &&
            !switched.isCompleted) {
          switched.complete();
        }
      });
      addTearDown(sub.close);
      expect(
        (await c.read(
          mediaEpisodeProgressProvider(media.id).future,
        ))[(1, 1.0)]?.positionSeconds,
        95,
      );
      c.read(_activeAccountProvider.notifier).switchTo('b');
      await switched.future.timeout(const Duration(seconds: 3));
    },
  );

  test('shared UI zero/unwatched wins over legacy source watched hints', () {
    final reset = EpisodeProgress(
      positionSeconds: 0,
      updatedAt: DateTime.now(),
    );
    final old = EpisodeProgress(
      positionSeconds: 700,
      updatedAt: DateTime.now(),
      completed: true,
    );
    final result = sharedEpisodeProgress(
      checkpoints: {(1, 1.0): reset},
      season: 1,
      episode: 1,
      compatible: old,
      legacySource: old,
    );
    expect(result, same(reset));
    expect(result?.isWatched, isFalse);
    expect(
      currentEpisodeCheckpoints(
        const AsyncError<Map<(int, double), EpisodeProgress>>(
          'Unavailable workspace',
          StackTrace.empty,
        ),
      ),
      isEmpty,
    );
    expect(
      sharedEpisodeProgress(
        checkpoints: {},
        season: 1,
        episode: 1,
        legacySource: old,
      ),
      same(old),
    );
  });
}

final _activeAccountProvider = NotifierProvider<_ActiveAccount, String>(
  _ActiveAccount.new,
);

class _ActiveAccount extends Notifier<String> {
  @override
  String build() => 'a';
  void switchTo(String account) => state = account;
}
