import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Keeps persistent databases in the app-private Application Support tree.
///
/// drift_flutter defaults to Documents, which makes database files visible as
/// user documents on some platforms. MiruShin data is application state, not a
/// document. Application Support is persistent (unlike cache) and remains
/// sandboxed for App Store, sideloaded, LiveContainer and TrollStore installs.
Future<Object> canonicalLibraryDatabaseDirectory({
  required String databaseName,
  String? legacyDatabaseName,
}) async {
  final Directory support = await getApplicationSupportDirectory();
  final Directory targetDirectory = Directory(
    path.join(support.path, 'MiruShin', 'Library'),
  );
  await targetDirectory.create(recursive: true);

  final Directory documents = await getApplicationDocumentsDirectory();
  final String sourceName = legacyDatabaseName ?? databaseName;
  final String sourceBase = path.join(documents.path, '$sourceName.sqlite');
  final String targetBase = path.join(
    targetDirectory.path,
    '$databaseName.sqlite',
  );
  await _moveDatabaseIfNeeded(sourceBase: sourceBase, targetBase: targetBase);
  return targetDirectory;
}

Future<void> _moveDatabaseIfNeeded({
  required String sourceBase,
  required String targetBase,
}) async {
  final File source = File(sourceBase);
  final File target = File(targetBase);
  if (!await source.exists()) return;

  if (await target.exists()) {
    // A previous migration may have copied the main database and crashed
    // before cleaning the old location. Only remove the stale source after the
    // destination has a valid SQLite header.
    if (await _hasSqliteHeader(target)) {
      await _deleteDatabaseFamily(sourceBase);
      return;
    }
    // A process can be killed while a cross-volume copy is still writing the
    // destination. The intact source remains authoritative in that case. Drop
    // only the invalid partial destination, then retry the migration below.
    await _deleteDatabaseFamily(targetBase);
  }

  // Move WAL/journal files first and the main database last. If the process is
  // interrupted, the old main database remains the migration marker and the
  // next launch can safely finish the move.
  for (final String suffix in <String>['-wal', '-shm', '-journal']) {
    await _moveFileIfPresent('$sourceBase$suffix', '$targetBase$suffix');
  }
  await _moveFileIfPresent(sourceBase, targetBase);
}

Future<void> _moveFileIfPresent(String sourcePath, String targetPath) async {
  final File source = File(sourcePath);
  if (!await source.exists()) return;
  final File target = File(targetPath);
  if (await target.exists()) return;
  try {
    await source.rename(targetPath);
  } on FileSystemException {
    await source.copy(targetPath);
    await source.delete();
  }
}

Future<bool> _hasSqliteHeader(File file) async {
  try {
    final List<int> bytes = await file.openRead(0, 16).first;
    return String.fromCharCodes(bytes) == 'SQLite format 3\u0000';
  } on Object {
    return false;
  }
}

Future<void> _deleteDatabaseFamily(String base) async {
  for (final String suffix in <String>['', '-wal', '-shm', '-journal']) {
    final File file = File('$base$suffix');
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // The destination is already authoritative. A locked legacy sidecar is
        // harmless and will be retried on the next launch.
      }
    }
  }
}
