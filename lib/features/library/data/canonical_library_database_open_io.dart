import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'canonical_library_database_path_io.dart';

QueryExecutor openCanonicalLibraryDatabase({
  required String databaseName,
  String? legacyDatabaseName,
}) => DatabaseConnection.delayed(
  Future<DatabaseConnection>(() async {
    final Directory directory =
        await canonicalLibraryDatabaseDirectory(
              databaseName: databaseName,
              legacyDatabaseName: legacyDatabaseName,
            )
            as Directory;
    // Match drift_flutter's sandbox-safe temporary-file location.
    sqlite3.tempDirectory = (await getTemporaryDirectory()).path;
    return canonicalLibraryNativeConnection(
      File(path.join(directory.path, '$databaseName.sqlite')),
    );
  }),
);

/// Reads stay responsive while a Drive restore or provider reconciliation
/// holds the writer transaction. WAL readers see the last committed library.
DatabaseConnection canonicalLibraryNativeConnection(File file) =>
    NativeDatabase.createBackgroundConnection(
      file,
      readPool: 1,
      setup: _configureConnection,
    );

void _configureConnection(Database connection) {
  connection.execute('PRAGMA journal_mode = WAL');
  connection.execute('PRAGMA foreign_keys = ON');
}
