import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/io_compat.dart' if (dart.library.io) 'dart:io';
import '../../features/settings/presentation/settings_state.dart';

final metadataCacheStoreProvider = Provider<MetadataCacheStore>(
  (Ref ref) => MetadataCacheStore(
    enabled: ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.metadataCacheEnabled,
      ),
    ),
  ),
);

class MetadataCacheStore {
  const MetadataCacheStore({this.enabled = true});

  final bool enabled;

  static const String _prefsPrefix = 'metadata.cache.';
  static const String _directoryName = 'metadata_cache';

  Future<Map<String, dynamic>?> read(String key) async {
    if (!enabled) return null;

    try {
      final File? file = await _fileForKey(key);
      if (file != null && await file.exists()) {
        final Object? decoded = jsonDecode(await file.readAsString());
        return decoded is Map<String, dynamic> ? decoded : null;
      }
    } catch (_) {}

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString('$_prefsPrefix$key');
      if (raw == null || raw.isEmpty) return null;
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> value) async {
    if (!enabled) return;

    final String raw = jsonEncode(value);
    try {
      final File? file = await _fileForKey(key);
      if (file != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(raw, flush: true);
        return;
      }
    } catch (_) {}

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsPrefix$key', raw);
    } catch (_) {}
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
          .where((String key) => key.startsWith('$_prefsPrefix$prefix'))
          .toList(growable: false);
      for (final String key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<File?> _fileForKey(String key) async {
    final Directory? directory = await _cacheDirectory();
    if (directory == null) return null;
    return File('${directory.path}/${_safeKey(key)}.json');
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
