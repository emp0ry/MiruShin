import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/artwork_cache_manager.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pathProvider = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (MethodCall call) async {
          return Directory.systemTemp.path;
        });
  });

  setUp(() async {
    configureMiruShinArtworkCache();
    await clearMiruShinArtworkCache();
  });

  tearDown(() async {
    configureMiruShinArtworkCache();
    await clearMiruShinArtworkCache();
  });

  test('artwork cache exposes the persisted default policy', () {
    expect(miruShinArtworkCacheKey, 'mirushin_artwork_v1');
    expect(miruShinArtworkDefaultMaxBytes, 2048 * 1024 * 1024);
    expect(miruShinArtworkDefaultRetention, const Duration(days: 30));
    expect(miruShinArtworkMaxObjects, 100000);
  });

  test('artwork cache becomes the default for every cached network image', () {
    final previous = CachedNetworkImageProvider.defaultCacheManager;
    addTearDown(() {
      CachedNetworkImageProvider.defaultCacheManager = previous;
    });

    configureMiruShinArtworkCache();

    expect(
      CachedNetworkImageProvider.defaultCacheManager,
      same(miruShinArtworkCacheManager),
    );
  });

  test(
    'configured byte limit removes the least recently used artwork',
    () async {
      configureMiruShinArtworkCache(maxCacheBytes: 6, retention: null);
      await miruShinArtworkCacheManager.putFile(
        'https://example.com/old.jpg',
        Uint8List.fromList(<int>[1, 2, 3, 4]),
        key: 'old',
        fileExtension: 'jpg',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await miruShinArtworkCacheManager.putFile(
        'https://example.com/new.jpg',
        Uint8List.fromList(<int>[5, 6, 7, 8]),
        key: 'new',
        fileExtension: 'jpg',
      );

      await miruShinArtworkCacheManager.enforceCachePolicy();

      expect(await miruShinArtworkCacheManager.getFileFromCache('old'), isNull);
      expect(
        await miruShinArtworkCacheManager.getFileFromCache('new'),
        isNotNull,
      );
      expect(await miruShinArtworkCacheManager.cacheSizeBytes(), 4);
    },
  );

  test('clearing artwork cache deletes its physical files', () async {
    await miruShinArtworkCacheManager.putFile(
      'https://example.com/poster.jpg',
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      key: 'poster',
      fileExtension: 'jpg',
    );
    final FileInfo? cached = await miruShinArtworkCacheManager.getFileFromCache(
      'poster',
    );
    expect(cached, isNotNull);
    expect(await cached!.file.exists(), isTrue);

    await clearMiruShinArtworkCache();

    expect(await cached.file.exists(), isFalse);
    expect(
      await miruShinArtworkCacheManager.getFileFromCache('poster'),
      isNull,
    );
  });

  test('artwork and metadata share one total byte limit', () async {
    const int totalLimit = 12;
    const MetadataCacheStore metadataCache = MetadataCacheStore(
      maxCacheBytes: totalLimit,
    );
    await metadataCache.removeByPrefix('');
    addTearDown(() => metadataCache.removeByPrefix(''));
    await metadataCache.write('unified.details', <String, dynamic>{'v': 1});

    configureMiruShinArtworkCache(
      maxCacheBytes: totalLimit,
      retention: null,
      otherCacheSizeBytes: metadataCache.cacheSizeBytes,
    );
    await miruShinArtworkCacheManager.putFile(
      'https://example.com/old-unified.jpg',
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      key: 'old-unified',
      fileExtension: 'jpg',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await miruShinArtworkCacheManager.putFile(
      'https://example.com/new-unified.jpg',
      Uint8List.fromList(<int>[5, 6, 7, 8]),
      key: 'new-unified',
      fileExtension: 'jpg',
    );

    await miruShinArtworkCacheManager.enforceCachePolicy();

    expect(
      await miruShinArtworkCacheManager.getFileFromCache('old-unified'),
      isNull,
    );
    expect(
      await miruShinArtworkCacheManager.getFileFromCache('new-unified'),
      isNotNull,
    );
    final int totalBytes =
        await miruShinArtworkCacheManager.cacheSizeBytes() +
        await metadataCache.cacheSizeBytes();
    expect(totalBytes, lessThanOrEqualTo(totalLimit));
  });
}
