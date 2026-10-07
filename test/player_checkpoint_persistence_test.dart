import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/data/canonical_library_database_open_io.dart';
import 'package:mirushin/features/watch/domain/normalized_models.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late CanonicalLibraryDatabase database;
  late CanonicalLibraryRepository repository;
  setUp(() {
    database = CanonicalLibraryDatabase(NativeDatabase.memory());
    repository = CanonicalLibraryRepository(database);
  });
  tearDown(() => database.close());

  test('one checkpoint preserves all other legacy episode data', () async {
    await repository.saveLocalEpisodeProgress({
      'anilist:1|S1E1.0': {'positionSeconds': 100, 'completed': true},
      'tmdb:2|S2E2.0': {'positionSeconds': 60},
    });
    await repository.saveLocalEpisodeCheckpoint('tmdb:2|S2E2.0', {
      'positionSeconds': 80,
      'durationSeconds': 1400,
      'completed': false,
    });
    final values = await repository.loadLocalEpisodeProgress();
    expect(values['anilist:1|S1E1.0'], {
      'positionSeconds': 100,
      'completed': true,
    });
    expect(values['tmdb:2|S2E2.0'], {
      'positionSeconds': 80,
      'durationSeconds': 1400,
      'completed': false,
    });
  });

  test(
    'concurrent alias checkpoints are not lost to whole-history overwrites',
    () async {
      await Future.wait([
        repository.saveLocalEpisodeCheckpoint('canonical|S1E1', {
          'positionSeconds': 120,
        }),
        repository.saveLocalEpisodeCheckpoint('sora|S1E1', {
          'positionSeconds': 120,
        }),
      ]);
      expect(await repository.loadLocalEpisodeProgress(), {
        'canonical|S1E1': {'positionSeconds': 120},
        'sora|S1E1': {'positionSeconds': 120},
      });
    },
  );

  test(
    'arbitrary identity keys and clearing optional duration round-trip',
    () async {
      const key = 'source:"quoted\\id"|S1E1.0';
      await repository.saveLocalEpisodeCheckpoint(key, {
        'positionSeconds': 1,
        'durationSeconds': 1400,
      });
      await repository.saveLocalEpisodeCheckpoint(key, {
        'positionSeconds': 2,
        'durationSeconds': null,
        'completed': false,
      });
      final values = await repository.loadLocalEpisodeProgress();
      expect(values.keys, [key]);
      expect((values[key] as Map)['positionSeconds'], 2);
      expect((values[key] as Map)['durationSeconds'], isNull);
      expect((values[key] as Map)['completed'], isFalse);
    },
  );

  test(
    'omitted optional fields replace the previous checkpoint, not merge it',
    () async {
      const key = 'anilist:1|S1E1.0';
      await repository.saveLocalEpisodeCheckpoint(
        key,
        EpisodeProgress(
          positionSeconds: 1400,
          durationSeconds: 1400,
          updatedAt: DateTime.utc(2026, 10, 7),
          completed: true,
        ).toJson(),
      );
      final reset = EpisodeProgress(
        positionSeconds: 0,
        updatedAt: DateTime.utc(2026, 10, 7, 1),
      );
      await repository.saveLocalEpisodeCheckpoint(key, reset.toJson());
      final values = await repository.loadLocalEpisodeProgress();
      expect(values[key], reset.toJson());
      final restored = EpisodeProgress.fromJson(
        Map<String, dynamic>.from(values[key] as Map),
      );
      expect(restored.completed, isFalse);
      expect(restored.durationSeconds, isNull);
      expect(restored.positionSeconds, 0);
    },
  );

  test(
    'worker checkpoint preserves large history and survives reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mirushin-checkpoint-test-',
      );
      final file = File('${directory.path}/library.sqlite');
      CanonicalLibraryDatabase? workerDatabase;
      try {
        workerDatabase = CanonicalLibraryDatabase(
          canonicalLibraryNativeConnection(file),
        );
        var workerRepository = CanonicalLibraryRepository(workerDatabase);
        final history = {
          for (int episode = 0; episode < 5000; episode++)
            'source:$episode|S1E1.0': {
              'positionSeconds': episode,
              'completed': false,
            },
        };
        await workerRepository.saveLocalEpisodeProgress(history);
        await workerRepository.saveLocalEpisodeCheckpoint('source:1|S1E1.0', {
          'positionSeconds': 1234,
          'completed': true,
        });
        await workerDatabase.close();
        workerDatabase = CanonicalLibraryDatabase(
          canonicalLibraryNativeConnection(file),
        );
        workerRepository = CanonicalLibraryRepository(workerDatabase);
        final restored = await workerRepository.loadLocalEpisodeProgress();
        expect(restored.length, history.length);
        expect(restored['source:1|S1E1.0'], {
          'positionSeconds': 1234,
          'completed': true,
        });
        expect(restored['source:4999|S1E1.0'], history['source:4999|S1E1.0']);
      } finally {
        await workerDatabase?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
