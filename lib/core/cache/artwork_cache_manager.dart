import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

const String miruShinArtworkCacheKey = 'mirushin_artwork_v1';
const int miruShinArtworkDefaultMaxBytes = 2048 * 1024 * 1024;
const Duration miruShinArtworkDefaultRetention = Duration(days: 30);
const int miruShinArtworkMaxObjects = 100000;
const Duration _effectivelyNeverStale = Duration(days: 36500);

/// Persistent cache shared by posters, backdrops, and the other remote artwork
/// rendered through `cached_network_image`.
///
/// `flutter_cache_manager` limits its cache by object count. MiruShin also
/// prunes least-recently-used files by their real byte size so the cache limit
/// in Settings controls disk usage, not only Flutter's decoded image memory.
class MiruShinArtworkCacheManager extends CacheManager with ImageCacheManager {
  MiruShinArtworkCacheManager._(this._policyConfig)
    : _maxCacheBytes = miruShinArtworkDefaultMaxBytes,
      _retention = miruShinArtworkDefaultRetention,
      super(_policyConfig);

  final _MutableArtworkCacheConfig _policyConfig;
  final Map<String, int> _activeKeys = <String, int>{};

  int _maxCacheBytes;
  Duration? _retention;
  Future<int> Function()? _otherCacheSizeBytes;
  Future<void>? _enforcement;
  bool _enforceAgain = false;

  int get maxCacheBytes => _maxCacheBytes;
  Duration? get retention => _retention;

  void updatePolicy({
    required int maxCacheBytes,
    required Duration? retention,
    Future<int> Function()? otherCacheSizeBytes,
  }) {
    final bool sizeProviderChanged =
        _otherCacheSizeBytes != otherCacheSizeBytes;
    _otherCacheSizeBytes = otherCacheSizeBytes;
    final int normalizedBytes = maxCacheBytes < 1 ? 1 : maxCacheBytes;
    if (_maxCacheBytes == normalizedBytes &&
        _retention == retention &&
        !sizeProviderChanged) {
      return;
    }
    _maxCacheBytes = normalizedBytes;
    _retention = retention;
    _policyConfig.stalePeriod = retention ?? _effectivelyNeverStale;
    unawaited(
      enforceCachePolicy().catchError((Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint('Artwork cache policy update failed: $error');
        }
      }),
    );
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    final String effectiveKey = key ?? url;
    _activeKeys.update(
      effectiveKey,
      (int count) => count + 1,
      ifAbsent: () => 1,
    );
    try {
      yield* super.getFileStream(
        url,
        key: key,
        headers: headers,
        withProgress: withProgress,
      );
    } finally {
      try {
        await enforceCachePolicy();
      } catch (error) {
        if (kDebugMode) debugPrint('Artwork cache cleanup failed: $error');
      } finally {
        final int remaining = (_activeKeys[effectiveKey] ?? 1) - 1;
        if (remaining <= 0) {
          _activeKeys.remove(effectiveKey);
        } else {
          _activeKeys[effectiveKey] = remaining;
        }
      }
    }
  }

  Future<int> cacheSizeBytes() async {
    await enforceCachePolicy();
    final List<_ArtworkCacheEntry> entries = await _cacheEntries();
    return entries.fold<int>(
      0,
      (int total, _ArtworkCacheEntry entry) => total + entry.length,
    );
  }

  @override
  Future<void> emptyCache() async {
    final List<_ArtworkCacheEntry> entries = await _cacheEntries();
    for (final _ArtworkCacheEntry entry in entries) {
      await _removeEntry(entry);
    }
    await super.emptyCache();
  }

  Future<void> enforceCachePolicy() {
    final Future<void>? current = _enforcement;
    if (current != null) {
      _enforceAgain = true;
      return current;
    }

    final Completer<void> completer = Completer<void>();
    _enforcement = completer.future;
    unawaited(() async {
      try {
        do {
          _enforceAgain = false;
          await _enforceCachePolicyNow();
        } while (_enforceAgain);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _enforcement = null;
      }
    }());
    return completer.future;
  }

  Future<void> _enforceCachePolicyNow() async {
    final List<_ArtworkCacheEntry> entries = await _cacheEntries();
    entries.sort(
      (_ArtworkCacheEntry left, _ArtworkCacheEntry right) =>
          left.lastUsed.compareTo(right.lastUsed),
    );

    int totalBytes = entries.fold<int>(
      0,
      (int total, _ArtworkCacheEntry entry) => total + entry.length,
    );
    final Set<String> removedKeys = <String>{};
    final Duration? retention = _retention;
    final DateTime staleBefore = DateTime.now().subtract(
      retention ?? Duration.zero,
    );

    if (retention != null) {
      for (final _ArtworkCacheEntry entry in entries) {
        if (!entry.lastUsed.isBefore(staleBefore) ||
            _activeKeys.containsKey(entry.object.key)) {
          continue;
        }
        await _removeEntry(entry);
        removedKeys.add(entry.object.key);
        totalBytes -= entry.length;
      }
    }

    int otherCacheBytes = 0;
    try {
      otherCacheBytes = await _otherCacheSizeBytes?.call() ?? 0;
    } catch (_) {}
    final int artworkByteLimit = otherCacheBytes >= _maxCacheBytes
        ? 0
        : _maxCacheBytes - otherCacheBytes;

    for (final _ArtworkCacheEntry entry in entries) {
      if (totalBytes <= artworkByteLimit) break;
      if (removedKeys.contains(entry.object.key) ||
          _activeKeys.containsKey(entry.object.key)) {
        continue;
      }
      await _removeEntry(entry);
      removedKeys.add(entry.object.key);
      totalBytes -= entry.length;
    }
  }

  Future<List<_ArtworkCacheEntry>> _cacheEntries() async {
    final CacheInfoRepository repository = config.repo;
    await repository.open();
    final List<CacheObject> objects = await repository.getAllObjects();
    final List<_ArtworkCacheEntry> entries = <_ArtworkCacheEntry>[];
    for (final CacheObject object in objects) {
      final dynamic file = await store.fileSystem.createFile(
        object.relativePath,
      );
      final bool exists = await file.exists();
      if (!exists) {
        if (object.id != null) await store.removeCachedFile(object);
        continue;
      }
      final int length = await file.length().catchError(
        (_) => object.length ?? 0,
      );
      entries.add(
        _ArtworkCacheEntry(
          object: object,
          length: length,
          lastUsed: object.touched ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    return entries;
  }

  Future<void> _removeEntry(_ArtworkCacheEntry entry) async {
    final dynamic file = await store.fileSystem.createFile(
      entry.object.relativePath,
    );
    if (await file.exists()) await file.delete();
    if (entry.object.id != null) await store.removeCachedFile(entry.object);
  }
}

class _ArtworkCacheEntry {
  const _ArtworkCacheEntry({
    required this.object,
    required this.length,
    required this.lastUsed,
  });

  final CacheObject object;
  final int length;
  final DateTime lastUsed;
}

class _MutableArtworkCacheConfig implements Config {
  _MutableArtworkCacheConfig._(this._delegate)
    : stalePeriod = miruShinArtworkDefaultRetention;

  factory _MutableArtworkCacheConfig.create() {
    return _MutableArtworkCacheConfig._(
      Config(
        miruShinArtworkCacheKey,
        stalePeriod: miruShinArtworkDefaultRetention,
        maxNrOfCacheObjects: miruShinArtworkMaxObjects,
      ),
    );
  }

  final Config _delegate;

  @override
  Duration stalePeriod;

  @override
  String get cacheKey => _delegate.cacheKey;

  @override
  FileService get fileService => _delegate.fileService;

  @override
  FileSystem get fileSystem => _delegate.fileSystem;

  @override
  int get maxNrOfCacheObjects => miruShinArtworkMaxObjects;

  @override
  CacheInfoRepository get repo => _delegate.repo;
}

final MiruShinArtworkCacheManager miruShinArtworkCacheManager =
    MiruShinArtworkCacheManager._(_MutableArtworkCacheConfig.create());

void configureMiruShinArtworkCache({
  int maxCacheBytes = miruShinArtworkDefaultMaxBytes,
  Duration? retention = miruShinArtworkDefaultRetention,
  Future<int> Function()? otherCacheSizeBytes,
}) {
  miruShinArtworkCacheManager.updatePolicy(
    maxCacheBytes: maxCacheBytes,
    retention: retention,
    otherCacheSizeBytes: otherCacheSizeBytes,
  );
  CachedNetworkImageProvider.defaultCacheManager = miruShinArtworkCacheManager;
}

Future<void> clearMiruShinArtworkCache() =>
    miruShinArtworkCacheManager.emptyCache();
