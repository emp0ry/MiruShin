import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

QueryExecutor openCanonicalLibraryDatabase({
  required String databaseName,
  String? legacyDatabaseName,
}) => driftDatabase(
  name: databaseName,
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);
