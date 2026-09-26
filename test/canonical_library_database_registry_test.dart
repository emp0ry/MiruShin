import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';

void main() {
  test('database shutdown registry closes each workspace idempotently', () async {
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
  });
}
