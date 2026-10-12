import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
// Build-only access: use the locked package's own release and checksums, never
// accept a downloaded checksum or maintain a separate set of trusted hashes.
// ignore: implementation_imports
import 'package:sqlite3/src/hook/asset_hashes.dart';

typedef AssetDownload = Future<void> Function(Uri uri, File destination);

/// Seeds sqlite3 3.x's content-addressed shared hook cache. The normal hook
/// verifies these files again before bundling them; its integrity check remains
/// enabled. No application settings, databases or playback code are touched.
/// Run with `dart --disable-dart-dev` so `dart run` does not invoke the native
/// hook (and its downloader) before this cache has been prepared.
class SqliteAssetCache {
  SqliteAssetCache({
    required this.directory,
    AssetDownload? download,
    this.attempts = 4,
    this.retryDelay = const Duration(seconds: 2),
    void Function(String)? log,
  }) : download = download ?? downloadSqliteAsset,
       log = log ?? print {
    if (attempts < 1) throw ArgumentError.value(attempts, 'attempts');
  }

  final Directory directory;
  final AssetDownload download;
  final int attempts;
  final Duration retryDelay;
  final void Function(String) log;

  Future<File> ensure(String asset) async {
    final expected = assetNameToSha256Hash[asset];
    if (expected == null ||
        releaseTag == null ||
        !RegExp(r'^(lib)?sqlite3\.').hasMatch(asset)) {
      throw ArgumentError('No locked sqlite3 checksum for $asset');
    }
    // Matches PrebuiltSqliteLibrary.dirname and the bundled library basename in
    // the locked sqlite3 hook. The release workflows exercise the real hook.
    final extension = p.extension(asset);
    final target = File(
      p.join(
        directory.path,
        'download-${expected.substring(0, 8)}',
        extension == '.dll' ? 'sqlite3.dll' : 'libsqlite3$extension',
      ),
    );
    if (await _matches(target, expected)) {
      log('Verified cached $asset');
      return target;
    }
    await target.parent.create(recursive: true);

    for (var attempt = 1; attempt <= attempts; attempt++) {
      final temporary = File('${target.path}.tmp-$pid-$attempt');
      // Avoid reusing an expired GitHub release redirect from an HTTP cache.
      final uri = Uri.https(
        'github.com',
        '/simolus3/sqlite3.dart/releases/download/$releaseTag/$asset',
        {
          'mirushin_download':
              '${DateTime.now().microsecondsSinceEpoch}-$attempt',
        },
      );
      try {
        log('Downloading $asset (attempt $attempt/$attempts)');
        await download(uri, temporary);
        if (!await _matches(temporary, expected)) {
          throw StateError('SHA-256 validation failed for $asset');
        }
        await temporary.rename(target.path);
        log('Verified $asset');
        return target;
      } catch (error) {
        if (attempt == attempts) {
          throw StateError(
            'Could not cache verified $asset after $attempts attempts: $error',
          );
        }
        log('$asset download failed; retrying: $error');
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      await Future<void>.delayed(retryDelay);
    }
    throw StateError('Unreachable download state');
  }

  Future<bool> _matches(File file, String expected) async {
    if (!await file.exists()) return false;
    return (await file.openRead().transform(sha256).first).toString() ==
        expected;
  }
}

Future<void> downloadSqliteAsset(Uri uri, File destination) async {
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 20);
  // Close the socket on a total deadline as well as on idle reads, so a stalled
  // release server cannot leave the build indefinitely waiting for an asset.
  final deadline = Timer(
    const Duration(seconds: 60),
    () => client.close(force: true),
  );
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'MiruShin SQLite build cache',
    );
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('SQLite asset HTTP ${response.statusCode}');
    }
    await response
        .timeout(const Duration(seconds: 20))
        .pipe(destination.openWrite());
  } finally {
    deadline.cancel();
    client.close(force: true);
  }
}

Future<void> main(List<String> assets) async {
  if (assets.isEmpty) {
    stderr.writeln(
      'Usage: dart --disable-dart-dev tool/precache_sqlite_assets.dart <asset> ...',
    );
    exitCode = 64;
    return;
  }
  final cache = SqliteAssetCache(
    directory: Directory('.dart_tool/hooks_runner/shared/sqlite3/build'),
  );
  for (final asset in assets) {
    await cache.ensure(asset);
  }
}
