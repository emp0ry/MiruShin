import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/io_compat.dart' if (dart.library.io) 'dart:io';
import '../../../core/security/app_secure_storage.dart';

class MiruShinBackupException implements Exception {
  const MiruShinBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MiruShinBackupService {
  MiruShinBackupService({
    required SharedPreferences preferences,
    AppSecureStorage secureStorage = const AppSecureStorage(),
    Future<dynamic> Function()? supportDirectoryProvider,
  }) : _preferences = preferences,
       _secureStorage = secureStorage,
       _supportDirectoryProvider = supportDirectoryProvider;

  static const String formatName = 'mirushin-full-backup';
  static const int formatVersion = 1;
  static const List<String> includedData = <String>[
    'appSettings',
    'pageAndLibraryState',
    'playerSettingsAndStreamChoices',
    'watchWithFriendsRelayAndTrustSettings',
    'anilistUserSettings',
    'trackerAccountsSessionsAndAvatars',
    'addonsAndSourceState',
  ];
  static const String _secureFallbackPrefix = 'secureStorageFallback.';
  static const String _webSoraFilePrefix =
      'mirushin.web_file.mirushin_web/sora_addons/';
  static const List<String> _temporaryPreferencePrefixes = <String>[
    'metadata.cache.',
    'metadata.cacheTouched.',
  ];

  final SharedPreferences _preferences;
  final AppSecureStorage _secureStorage;
  final Future<dynamic> Function()? _supportDirectoryProvider;

  static Future<MiruShinBackupService> create() async {
    return MiruShinBackupService(
      preferences: await SharedPreferences.getInstance(),
    );
  }

  Future<String> createBackupJson() async {
    final Map<String, dynamic> document = <String, dynamic>{
      'format': formatName,
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'containsSecrets': true,
      'includedData': includedData,
      'preferences': _snapshotPreferences(includeInternalValues: false),
      'secureStorage': await _secureStorage.exportBackupValues(),
      'files': <String, dynamic>{'soraAddons': await _snapshotSoraFiles()},
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  Future<void> importBackupJson(String raw) async {
    final _ParsedBackup backup = _parse(raw);
    final Map<String, dynamic> previousPreferences = _snapshotPreferences(
      includeInternalValues: true,
    );
    final Map<String, String> previousSecure = await _secureStorage
        .exportBackupValues();
    final Map<String, String> previousSoraFiles = await _snapshotSoraFiles();

    try {
      await _replacePreferences(backup.preferences);
      await _secureStorage.replaceBackupValues(backup.secureStorage);
      await _replaceSoraFiles(backup.soraFiles);
    } on Object catch (error) {
      try {
        await _replacePreferences(previousPreferences);
        await _secureStorage.replaceBackupValues(previousSecure);
        await _replaceSoraFiles(previousSoraFiles);
      } on Object catch (rollbackError) {
        throw MiruShinBackupException(
          'Import failed ($error) and rollback failed ($rollbackError).',
        );
      }
      if (error is MiruShinBackupException) rethrow;
      throw MiruShinBackupException('Could not restore backup: $error');
    }
  }

  Map<String, dynamic> _snapshotPreferences({
    required bool includeInternalValues,
  }) {
    final Map<String, dynamic> values = <String, dynamic>{};
    final List<String> keys = _preferences.getKeys().toList()..sort();
    for (final String key in keys) {
      if (!includeInternalValues &&
          (key.startsWith(_secureFallbackPrefix) ||
              key.startsWith(_webSoraFilePrefix) ||
              _temporaryPreferencePrefixes.any(key.startsWith))) {
        continue;
      }
      final Object? value = _preferences.get(key);
      final Map<String, dynamic>? encoded = _encodePreference(value);
      if (encoded != null) values[key] = encoded;
    }
    return values;
  }

  Map<String, dynamic>? _encodePreference(Object? value) {
    if (value is String) {
      return <String, dynamic>{'type': 'string', 'value': value};
    }
    if (value is bool) {
      return <String, dynamic>{'type': 'bool', 'value': value};
    }
    if (value is int) {
      return <String, dynamic>{'type': 'int', 'value': value};
    }
    if (value is double) {
      return <String, dynamic>{'type': 'double', 'value': value};
    }
    if (value is List<String>) {
      return <String, dynamic>{'type': 'stringList', 'value': value};
    }
    return null;
  }

  _ParsedBackup _parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw MiruShinBackupException('Backup is not valid JSON: $error');
    }
    if (decoded is! Map) {
      throw const MiruShinBackupException('Backup root must be an object.');
    }
    final Map<String, dynamic> root = _stringMap(decoded, 'backup root');
    if (root['format'] != formatName) {
      throw const MiruShinBackupException(
        'This is not a MiruShin full-backup file.',
      );
    }
    final Object? rawVersion = root['version'];
    if (rawVersion is! int || rawVersion != formatVersion) {
      throw MiruShinBackupException(
        'Unsupported backup version: ${root['version']}.',
      );
    }

    final Map<String, dynamic> rawPreferences = _stringMap(
      root['preferences'],
      'preferences',
    );
    final Map<String, dynamic> preferences = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in rawPreferences.entries) {
      if (entry.key.isEmpty || entry.key.startsWith(_secureFallbackPrefix)) {
        throw MiruShinBackupException(
          'Backup contains an invalid preference key: ${entry.key}.',
        );
      }
      preferences[entry.key] = _validatePreference(entry.key, entry.value);
    }

    final Map<String, dynamic> rawSecure = _stringMap(
      root['secureStorage'],
      'secureStorage',
    );
    final Set<String> allowedSecure = AppSecureStorage.backupKeys.toSet();
    final Map<String, String> secure = <String, String>{};
    for (final MapEntry<String, dynamic> entry in rawSecure.entries) {
      if (!allowedSecure.contains(entry.key) || entry.value is! String) {
        throw MiruShinBackupException(
          'Backup contains an invalid secure-storage value: ${entry.key}.',
        );
      }
      final String value = entry.value as String;
      if (value.isNotEmpty) secure[entry.key] = value;
    }

    final Map<String, dynamic> files = _stringMap(root['files'], 'files');
    final Map<String, dynamic> rawSoraFiles = _stringMap(
      files['soraAddons'],
      'files.soraAddons',
    );
    final Map<String, String> soraFiles = <String, String>{};
    for (final MapEntry<String, dynamic> entry in rawSoraFiles.entries) {
      final String relative = _safeRelativePath(entry.key);
      if (soraFiles.containsKey(relative)) {
        throw MiruShinBackupException(
          'Backup contains the addon file path more than once: $relative.',
        );
      }
      if (entry.value is! String) {
        throw MiruShinBackupException(
          'Addon file $relative must contain text.',
        );
      }
      soraFiles[relative] = entry.value as String;
    }

    return _ParsedBackup(
      preferences: preferences,
      secureStorage: secure,
      soraFiles: soraFiles,
    );
  }

  Map<String, dynamic> _validatePreference(String key, Object? value) {
    final Map<String, dynamic> encoded = _stringMap(value, 'preference $key');
    final Object? rawValue = encoded['value'];
    switch (encoded['type']) {
      case 'string':
        if (rawValue is String) return encoded;
        break;
      case 'bool':
        if (rawValue is bool) return encoded;
        break;
      case 'int':
        if (rawValue is int) return encoded;
        break;
      case 'double':
        if (rawValue is num) {
          return <String, dynamic>{
            'type': 'double',
            'value': rawValue.toDouble(),
          };
        }
        break;
      case 'stringList':
        if (rawValue is List<dynamic> && rawValue.every((e) => e is String)) {
          return <String, dynamic>{
            'type': 'stringList',
            'value': rawValue.cast<String>(),
          };
        }
        break;
    }
    throw MiruShinBackupException(
      'Preference $key has an unsupported type or value.',
    );
  }

  Map<String, dynamic> _stringMap(Object? value, String label) {
    if (value is! Map) {
      throw MiruShinBackupException('$label must be an object.');
    }
    final Map<String, dynamic> result = <String, dynamic>{};
    for (final MapEntry<dynamic, dynamic> entry in value.entries) {
      if (entry.key is! String) {
        throw MiruShinBackupException('$label contains a non-string key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  Future<void> _replacePreferences(Map<String, dynamic> values) async {
    if (!await _preferences.clear()) {
      throw const MiruShinBackupException(
        'Could not clear the current preferences.',
      );
    }
    final List<String> keys = values.keys.toList()..sort();
    for (final String key in keys) {
      final Map<String, dynamic> encoded = _stringMap(
        values[key],
        'preference $key',
      );
      final Object? value = encoded['value'];
      final bool saved = switch (encoded['type']) {
        'string' => await _preferences.setString(key, value as String),
        'bool' => await _preferences.setBool(key, value as bool),
        'int' => await _preferences.setInt(key, value as int),
        'double' => await _preferences.setDouble(
          key,
          (value as num).toDouble(),
        ),
        'stringList' => await _preferences.setStringList(
          key,
          (value as List<dynamic>).cast<String>(),
        ),
        _ => false,
      };
      if (!saved) {
        throw MiruShinBackupException('Could not restore preference $key.');
      }
    }
  }

  Future<Map<String, String>> _snapshotSoraFiles() async {
    if (kIsWeb) {
      final Map<String, String> files = <String, String>{};
      for (final String key in _preferences.getKeys()) {
        if (!key.startsWith(_webSoraFilePrefix)) continue;
        final String? value = _preferences.getString(key);
        if (value == null) continue;
        files[_safeRelativePath(key.substring(_webSoraFilePrefix.length))] =
            value;
      }
      return files;
    }

    final Directory? root = await _soraRootDirectory();
    if (root == null || !await root.exists()) return <String, String>{};
    final Map<String, String> files = <String, String>{};
    await for (final FileSystemEntity entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final String relative = _safeRelativePath(
        p.relative(entity.path, from: root.path).replaceAll('\\', '/'),
      );
      files[relative] = await entity.readAsString();
    }
    return Map<String, String>.fromEntries(
      files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  Future<void> _replaceSoraFiles(Map<String, String> files) async {
    if (kIsWeb) {
      final List<String> oldKeys = _preferences
          .getKeys()
          .where((String key) => key.startsWith(_webSoraFilePrefix))
          .toList(growable: false);
      for (final String key in oldKeys) {
        await _preferences.remove(key);
      }
      for (final MapEntry<String, String> entry in files.entries) {
        await _preferences.setString(
          '$_webSoraFilePrefix${_safeRelativePath(entry.key)}',
          entry.value,
        );
      }
      return;
    }

    final Directory? root = await _soraRootDirectory();
    if (root == null) {
      if (files.isNotEmpty) {
        throw const MiruShinBackupException(
          'Application support storage is unavailable.',
        );
      }
      return;
    }
    if (await root.exists()) await root.delete(recursive: true);
    if (files.isEmpty) return;
    await root.create(recursive: true);
    for (final MapEntry<String, String> entry in files.entries) {
      final String relative = _safeRelativePath(entry.key);
      final File target = File(
        p.joinAll(<String>[root.path, ...p.posix.split(relative)]),
      );
      await target.parent.create(recursive: true);
      await target.writeAsString(entry.value, flush: true);
    }
  }

  Future<Directory?> _soraRootDirectory() async {
    try {
      final Future<dynamic> Function()? provider = _supportDirectoryProvider;
      final dynamic support = provider == null
          ? await getApplicationSupportDirectory()
          : await provider();
      final String supportPath = support.path as String;
      if (supportPath.trim().isEmpty) return null;
      return Directory(p.join(supportPath, 'sora_addons'));
    } on Object {
      return null;
    }
  }

  String _safeRelativePath(String raw) {
    final String normalized = p.posix.normalize(raw.replaceAll('\\', '/'));
    if (normalized.isEmpty ||
        normalized == '.' ||
        p.posix.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains(':')) {
      throw MiruShinBackupException('Unsafe addon file path: $raw.');
    }
    return normalized;
  }
}

class _ParsedBackup {
  const _ParsedBackup({
    required this.preferences,
    required this.secureStorage,
    required this.soraFiles,
  });

  final Map<String, dynamic> preferences;
  final Map<String, String> secureStorage;
  final Map<String, String> soraFiles;
}
