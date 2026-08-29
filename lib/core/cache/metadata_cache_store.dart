import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/io_compat.dart' if (dart.library.io) 'dart:io';

class MetadataCacheStore {
  const MetadataCacheStore({
    this.maxAge,
    this.maxCacheBytes,
    this.onSizeChanged,
    DateTime? nowForTesting,
  }) : _nowForTesting = nowForTesting;

  final Duration? maxAge;
  final int? maxCacheBytes;
  final Future<void> Function()? onSizeChanged;
  final DateTime? _nowForTesting;

  static const String _prefsPrefix = 'metadata.cache.';
  static const String _prefsTouchedPrefix = 'metadata.cacheTouched.';
  static const String _directoryName = 'metadata_cache';

  Future<Map<String, dynamic>?> read(String key) async {
    try {
      final File? file = await _fileForKey(key);
      if (file != null && await file.exists()) {
        final DateTime touched = await file.lastModified();
        if (_isExpired(touched)) {
          await file.delete();
          await _removePreferencesEntry(key);
          return null;
        }
        final Object? decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic>) return null;
        try {
          await file.setLastModified(_now());
        } catch (_) {}
        return decoded;
      }
    } catch (_) {}

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString('$_prefsPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final int? touchedMilliseconds = prefs.getInt('$_prefsTouchedPrefix$key');
      if (touchedMilliseconds != null &&
          _isExpired(
            DateTime.fromMillisecondsSinceEpoch(touchedMilliseconds),
          )) {
        await prefs.remove('$_prefsPrefix$key');
        await prefs.remove('$_prefsTouchedPrefix$key');
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      await prefs.setInt(
        '$_prefsTouchedPrefix$key',
        _now().millisecondsSinceEpoch,
      );
      return decoded;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> value) async {
    final String raw = jsonEncode(value);
    bool wroteFile = false;
    try {
      final File? file = await _fileForKey(key);
      if (file != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(raw, flush: true);
        try {
          await file.setLastModified(_now());
        } catch (_) {}
        wroteFile = true;
      }
    } catch (_) {}
    if (wroteFile) {
      await _afterWrite();
      return;
    }

    bool wrotePreferences = false;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$key', raw);
      await prefs.setInt(
        '$_prefsTouchedPrefix$key',
        _now().millisecondsSinceEpoch,
      );
      wrotePreferences = true;
    } catch (_) {}
    if (wrotePreferences) await _afterWrite();
  }

  Future<void> removeByPrefix(String prefix) async {
    try {
      final Directory? directory = await _cacheDirectory();
      if (directory != null && await directory.exists()) {
        await for (final FileSystemEntity entity in directory.list()) {
          if (entity is File &&
              entity.uri.pathSegments.last.startsWith(prefix)) {
            await entity.delete().catchError((_) => entity);
          }
        }
      }
    } catch (_) {}

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> keys = prefs
          .getKeys()
          .where(
            (String key) =>
                key.startsWith('$_prefsPrefix$prefix') ||
                key.startsWith('$_prefsTouchedPrefix$prefix'),
          )
          .toList(growable: false);
      for (final String key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<int> cacheSizeBytes() async {
    final List<_MetadataCacheEntry> entries = await _cacheEntries();
    return entries.fold<int>(
      0,
      (int total, _MetadataCacheEntry entry) => total + entry.length,
    );
  }

  Future<void> enforceCachePolicy() async {
    final List<_MetadataCacheEntry> entries = await _cacheEntries()
      ..sort(
        (_MetadataCacheEntry left, _MetadataCacheEntry right) =>
            left.lastUsed.compareTo(right.lastUsed),
      );
    int totalBytes = entries.fold<int>(
      0,
      (int total, _MetadataCacheEntry entry) => total + entry.length,
    );
    final Set<_MetadataCacheEntry> removed = <_MetadataCacheEntry>{};

    for (final _MetadataCacheEntry entry in entries) {
      if (!_isExpired(entry.lastUsed)) continue;
      await entry.remove();
      removed.add(entry);
      totalBytes -= entry.length;
    }

    final int? byteLimit = maxCacheBytes;
    if (byteLimit == null) return;
    for (final _MetadataCacheEntry entry in entries) {
      if (totalBytes <= byteLimit) break;
      if (removed.contains(entry)) continue;
      await entry.remove();
      totalBytes -= entry.length;
    }
  }

  Future<void> pruneExpired() => enforceCachePolicy();

  Future<List<_MetadataCacheEntry>> _cacheEntries() async {
    final List<_MetadataCacheEntry> entries = <_MetadataCacheEntry>[];
    try {
      final Directory? directory = await _cacheDirectory();
      if (directory != null && await directory.exists()) {
        await for (final FileSystemEntity entity in directory.list()) {
          if (entity is! File) continue;
          final File file = entity;
          entries.add(
            _MetadataCacheEntry(
              length: await file.length(),
              lastUsed: await file.lastModified(),
              remove: () async {
                if (await file.exists()) await file.delete();
              },
            ),
          );
        }
      }
    } catch (_) {}

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> valueKeys = prefs
          .getKeys()
          .where((String key) => key.startsWith(_prefsPrefix))
          .toList(growable: false);
      for (final String valueKey in valueKeys) {
        final String? raw = prefs.getString(valueKey);
        if (raw == null) continue;
        final String key = valueKey.substring(_prefsPrefix.length);
        final String touchedKey = '$_prefsTouchedPrefix$key';
        final int? touchedMilliseconds = prefs.getInt(touchedKey);
        entries.add(
          _MetadataCacheEntry(
            length: utf8.encode(raw).length,
            lastUsed: touchedMilliseconds == null
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : DateTime.fromMillisecondsSinceEpoch(touchedMilliseconds),
            remove: () async {
              await prefs.remove(valueKey);
              await prefs.remove(touchedKey);
            },
          ),
        );
      }
    } catch (_) {}
    return entries;
  }

  Future<void> _afterWrite() async {
    try {
      await enforceCachePolicy();
    } catch (_) {}
    try {
      await onSizeChanged?.call();
    } catch (_) {}
  }

  Future<File?> _fileForKey(String key) async {
    final Directory? directory = await _cacheDirectory();
    if (directory == null) return null;
    return File('${directory.path}/${_safeKey(key)}.json');
  }

  DateTime _now() => _nowForTesting ?? DateTime.now();

  bool _isExpired(DateTime touched) {
    final Duration? age = maxAge;
    return age != null && !touched.add(age).isAfter(_now());
  }

  Future<void> _removePreferencesEntry(String key) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsPrefix$key');
      await prefs.remove('$_prefsTouchedPrefix$key');
    } catch (_) {}
  }

  Future<Directory?> _cacheDirectory() async {
    if (kIsWeb) return null;
    try {
      final dynamic base = await getApplicationSupportDirectory();
      return Directory('${base.path}/$_directoryName');
    } catch (_) {
      try {
        final dynamic base = await getTemporaryDirectory();
        return Directory('${base.path}/$_directoryName');
      } catch (_) {
        return null;
      }
    }
  }

  String _safeKey(String key) {
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }
}

class _MetadataCacheEntry {
  const _MetadataCacheEntry({
    required this.length,
    required this.lastUsed,
    required this.remove,
  });

  final int length;
  final DateTime lastUsed;
  final Future<void> Function() remove;
}
