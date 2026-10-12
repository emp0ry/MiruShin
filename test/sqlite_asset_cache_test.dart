import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:sqlite3/src/hook/asset_hashes.dart';

import '../tool/precache_sqlite_assets.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mirushin-sqlite-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('rejects untrusted asset names before any network request', () async {
    var downloads = 0;
    final cache = SqliteAssetCache(
      directory: directory,
      download: (_, _) async => downloads++,
      log: (_) {},
    );
    await expectLater(cache.ensure('../sqlite.dylib'), throwsArgumentError);
    expect(downloads, 0);
  });

  test(
    'bad checksum is retried, never published and temporary files removed',
    () async {
      var downloads = 0;
      final cache = SqliteAssetCache(
        directory: directory,
        attempts: 3,
        retryDelay: Duration.zero,
        download: (uri, file) async {
          downloads++;
          expect(uri.host, 'github.com');
          expect(uri.path, contains('/$releaseTag/'));
          await file.writeAsString('<html>upstream error, not SQLite</html>');
        },
        log: (_) {},
      );
      await expectLater(
        cache.ensure('libsqlite3.x64.macos.dylib'),
        throwsStateError,
      );
      expect(downloads, 3);
      expect(
        await directory.list(recursive: true).where((f) => f is File).toList(),
        isEmpty,
      );
    },
  );

  test(
    'transport errors have bounded attempts and do not replace existing cache',
    () async {
      const asset = 'libsqlite3.x64.macos.dylib';
      final digest = assetNameToSha256Hash[asset]!;
      final existing = File(
        '${directory.path}/download-${digest.substring(0, 8)}/libsqlite3.dylib',
      );
      await existing.parent.create(recursive: true);
      await existing.writeAsString('invalid old cache');
      var downloads = 0;
      final cache = SqliteAssetCache(
        directory: directory,
        attempts: 2,
        retryDelay: Duration.zero,
        download: (_, _) async {
          downloads++;
          throw const HttpException('HTTP 503');
        },
        log: (_) {},
      );
      await expectLater(cache.ensure(asset), throwsStateError);
      expect(downloads, 2);
      expect(await existing.readAsString(), 'invalid old cache');
    },
  );

  test('HTTP error bodies are not written as native libraries', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('upstream error');
      await request.response.close();
    });
    final destination = File('${directory.path}/bad-download');
    try {
      await expectLater(
        downloadSqliteAsset(
          Uri.parse('http://127.0.0.1:${server.port}/asset'),
          destination,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(await destination.exists(), isFalse);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('HTTP 200 streams the binary without transforming its bytes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = [0, 255, 4, 127, 128, 42];
    final subscription = server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });
    final destination = File('${directory.path}/download');
    try {
      await downloadSqliteAsset(
        Uri.parse('http://127.0.0.1:${server.port}/asset'),
        destination,
      );
      expect(await destination.readAsBytes(), bytes);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
