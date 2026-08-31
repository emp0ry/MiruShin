import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSecureStorage {
  const AppSecureStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static const String tmdbReadAccessTokenKey = 'tmdb.readAccessToken';
  static const String fanartTvApiKeyKey = 'fanartTv.apiKey';
  static const String tvdbApiKeyKey = 'tvdb.apiKey';
  static const String tvdbSubscriberPinKey = 'tvdb.subscriberPin';
  static const String anilistAccessTokenKey = 'anilist.accessToken';
  static const String anilistExpiresAtKey = 'anilist.expiresAt';
  static const String malAccessTokenKey = 'mal.accessToken';
  static const String malRefreshTokenKey = 'mal.refreshToken';
  static const String malExpiresAtKey = 'mal.expiresAt';
  static const String shikimoriAccessTokenKey = 'shikimori.accessToken';
  static const String shikimoriRefreshTokenKey = 'shikimori.refreshToken';
  static const String shikimoriExpiresAtKey = 'shikimori.expiresAt';
  static const String shikimoriCustomClientSecretKey =
      'shikimori.customClientSecret';
  static const String _fallbackPrefix = 'secureStorageFallback.';

  /// Every secret that belongs in a portable MiruShin backup. Keep this list
  /// explicit so a backup cannot read or restore unrelated platform secrets.
  static const List<String> backupKeys = <String>[
    tmdbReadAccessTokenKey,
    fanartTvApiKeyKey,
    tvdbApiKeyKey,
    tvdbSubscriberPinKey,
    anilistAccessTokenKey,
    anilistExpiresAtKey,
    malAccessTokenKey,
    malRefreshTokenKey,
    malExpiresAtKey,
    shikimoriAccessTokenKey,
    shikimoriRefreshTokenKey,
    shikimoriExpiresAtKey,
    shikimoriCustomClientSecretKey,
  ];

  Future<Map<String, String>> exportBackupValues() async {
    final Map<String, String> values = <String, String>{};
    for (final String key in backupKeys) {
      final String? value = await _read(key);
      if (value != null && value.isNotEmpty) values[key] = value;
    }
    return values;
  }

  /// Replaces every MiruShin-owned secure value with [values]. Callers are
  /// expected to warn that these credentials are stored in the backup file.
  Future<void> replaceBackupValues(Map<String, String> values) async {
    final Set<String> allowed = backupKeys.toSet();
    String? unsupported;
    for (final String key in values.keys) {
      if (!allowed.contains(key)) {
        unsupported = key;
        break;
      }
    }
    if (unsupported != null) {
      throw ArgumentError.value(unsupported, 'key', 'Unsupported secure key');
    }
    for (final String key in backupKeys) {
      await _delete(key);
    }
    for (final MapEntry<String, String> entry in values.entries) {
      if (entry.value.isNotEmpty) await _write(entry.key, entry.value);
    }
  }

  Future<String?> readTmdbReadAccessToken() {
    return _read(tmdbReadAccessTokenKey);
  }

  Future<void> writeTmdbReadAccessToken(String token) {
    return _writeOrDelete(tmdbReadAccessTokenKey, token);
  }

  Future<String?> readFanartTvApiKey() => _read(fanartTvApiKeyKey);

  Future<void> writeFanartTvApiKey(String key) =>
      _writeOrDelete(fanartTvApiKeyKey, key);

  Future<String?> readTvdbApiKey() => _read(tvdbApiKeyKey);

  Future<void> writeTvdbApiKey(String key) =>
      _writeOrDelete(tvdbApiKeyKey, key);

  Future<String?> readTvdbSubscriberPin() => _read(tvdbSubscriberPinKey);

  Future<void> writeTvdbSubscriberPin(String pin) =>
      _writeOrDelete(tvdbSubscriberPinKey, pin);

  Future<String?> readAniListAccessToken() {
    return _read(anilistAccessTokenKey);
  }

  Future<void> writeAniListAccessToken(String token) {
    return _writeOrDelete(anilistAccessTokenKey, token);
  }

  Future<DateTime?> readAniListExpiresAt() async {
    final String? value = await _read(anilistExpiresAtKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> writeAniListExpiresAt(DateTime? value) {
    return value == null
        ? _delete(anilistExpiresAtKey)
        : _write(anilistExpiresAtKey, value.toIso8601String());
  }

  Future<void> clearAniListSession() async {
    await _delete(anilistAccessTokenKey);
    await _delete(anilistExpiresAtKey);
  }

  // MyAnimeList

  Future<String?> readMalAccessToken() => _read(malAccessTokenKey);

  Future<void> writeMalAccessToken(String token) =>
      _writeOrDelete(malAccessTokenKey, token);

  Future<String?> readMalRefreshToken() => _read(malRefreshTokenKey);

  Future<void> writeMalRefreshToken(String token) =>
      _writeOrDelete(malRefreshTokenKey, token);

  Future<DateTime?> readMalExpiresAt() async {
    final String? value = await _read(malExpiresAtKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> writeMalExpiresAt(DateTime? value) {
    return value == null
        ? _delete(malExpiresAtKey)
        : _write(malExpiresAtKey, value.toIso8601String());
  }

  Future<void> clearMalSession() async {
    await _delete(malAccessTokenKey);
    await _delete(malRefreshTokenKey);
    await _delete(malExpiresAtKey);
  }

  // Shikimori

  Future<String?> readShikimoriAccessToken() => _read(shikimoriAccessTokenKey);

  Future<void> writeShikimoriAccessToken(String token) =>
      _writeOrDelete(shikimoriAccessTokenKey, token);

  Future<String?> readShikimoriRefreshToken() =>
      _read(shikimoriRefreshTokenKey);

  Future<void> writeShikimoriRefreshToken(String token) =>
      _writeOrDelete(shikimoriRefreshTokenKey, token);

  Future<DateTime?> readShikimoriExpiresAt() async {
    final String? value = await _read(shikimoriExpiresAtKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> writeShikimoriExpiresAt(DateTime? value) {
    return value == null
        ? _delete(shikimoriExpiresAtKey)
        : _write(shikimoriExpiresAtKey, value.toIso8601String());
  }

  Future<void> clearShikimoriSession() async {
    await _delete(shikimoriAccessTokenKey);
    await _delete(shikimoriRefreshTokenKey);
    await _delete(shikimoriExpiresAtKey);
  }

  Future<String?> readShikimoriCustomClientSecret() =>
      _read(shikimoriCustomClientSecretKey);

  Future<void> writeShikimoriCustomClientSecret(String secret) =>
      _writeOrDelete(shikimoriCustomClientSecretKey, secret);

  Future<void> _writeOrDelete(String key, String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _delete(key);
    }
    return _write(key, trimmed);
  }

  Future<String?> _read(String key) async {
    try {
      final String? value = await _storage.read(key: key);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    } on PlatformException {
      // macOS can report missing Keychain entitlement in debug builds.
    } catch (_) {
      // Keep app startup resilient if a platform storage backend is unavailable.
    }

    final SharedPreferences preferences = await SharedPreferences.getInstance();
    return preferences.getString('$_fallbackPrefix$key');
  }

  Future<void> _write(String key, String value) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    try {
      await _storage.write(key: key, value: value);
      await preferences.remove('$_fallbackPrefix$key');
    } on PlatformException {
      await preferences.setString('$_fallbackPrefix$key', value);
    } catch (_) {
      await preferences.setString('$_fallbackPrefix$key', value);
    }
  }

  Future<void> _delete(String key) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_fallbackPrefix$key');
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      // Fallback copy is already removed.
    } catch (_) {
      // Fallback copy is already removed.
    }
  }
}
