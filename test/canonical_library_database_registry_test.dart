import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/data/canonical_library_database_open_io.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  test(
    'database shutdown registry closes each workspace idempotently',
    () async {
      final CanonicalLibraryDatabase database = CanonicalLibraryDatabase(
        NativeDatabase.memory(),
      );
      await database.customSelect('SELECT 1').get();

      final CanonicalLibraryDatabaseRegistry registry =
          CanonicalLibraryDatabaseRegistry();
      registry.register(database);
      registry.register(database);

      await registry.closeAll();
      await registry.closeAll();
      await registry.close(database);

      await expectLater(
        database.customSelect('SELECT 1').get(),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'exit waits for a database already closing on provider disposal',
    () async {
      final database = _DelayedCloseDatabase();
      final registry = CanonicalLibraryDatabaseRegistry()..register(database);
      final firstClose = registry.close(database);
      bool finished = false;
      final exit = registry.closeAll().then((_) => finished = true);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        expect(identical(registry.closeAll(), registry.closeAll()), isTrue);
        expect(database.closeCalls, 1);
      } finally {
        database.release.complete();
        await firstClose;
        await exit;
      }
      expect(finished, isTrue);
    },
  );

  test('shutdown drains all workspaces even when one close fails', () async {
    final failed = _DelayedCloseDatabase(fail: true);
    final pending = _DelayedCloseDatabase();
    final registry = CanonicalLibraryDatabaseRegistry()
      ..register(failed)
      ..register(pending);
    bool finished = false;
    final exit = registry.closeAll().then<void>(
      (_) => finished = true,
      onError: (Object error) {
        expect(error, isA<StateError>());
        finished = true;
      },
    );
    try {
      failed.release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
    } finally {
      if (!pending.release.isCompleted) pending.release.complete();
      await exit;
    }
    expect(finished, isTrue);
    expect(pending.closeCalls, 1);
  });

  test(
    'cannot reopen a closed workspace or register during shutdown',
    () async {
      final database = _DelayedCloseDatabase();
      final registry = CanonicalLibraryDatabaseRegistry()..register(database);
      final close = registry.close(database);
      registry.register(database);
      final exit = registry.closeAll();
      try {
        expect(registry.isShuttingDown, isTrue);
        expect(() => registry.register(database), throwsStateError);
        expect(database.closeCalls, 1);
      } finally {
        database.release.complete();
        await close;
        await exit;
      }
    },
  );

  test(
    'native read-pool connections are drained and closed before exit',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mirushin-exit-test-',
      );
      final database = CanonicalLibraryDatabase(
        canonicalLibraryNativeConnection(
          File('${directory.path}/library.sqlite'),
        ),
      );
      final registry = CanonicalLibraryDatabaseRegistry()..register(database);
      try {
        await database.customSelect('SELECT 1').get();
        await Future.wait(
          List.generate(20, (_) => database.customSelect('SELECT 1').get()),
        );
        final closing = registry.close(database);
        await registry.closeAll();
        await closing;
        await expectLater(
          database.customSelect('SELECT 1').get(),
          throwsStateError,
        );
      } finally {
        await registry.closeAll();
        await directory.delete(recursive: true);
      }
    },
  );
}

class _DelayedCloseDatabase extends CanonicalLibraryDatabase {
  _DelayedCloseDatabase({this.fail = false}) : super(NativeDatabase.memory());
  final bool fail;
  final release = Completer<void>();
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    await release.future;
    await super.close();
    if (fail) throw StateError('Simulated failed close');
  }
}
