import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSecureStorage {
  const AppSecureStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static const String tmdbReadAccessTokenKey = 'tmdb.readAccessToken';
  static const String tvdbApiKeyKey = 'tvdb.apiKey';
  static const String tvdbSubscriberPinKey = 'tvdb.subscriberPin';
  static const String anilistAccessTokenKey = 'anilist.accessToken';
  static const String anilistExpiresAtKey = 'anilist.expiresAt';
  static const String _fallbackPrefix = 'secureStorageFallback.';

  Future<String?> readTmdbReadAccessToken() {
    return _read(tmdbReadAccessTokenKey);
  }

  Future<void> writeTmdbReadAccessToken(String token) {
    return _writeOrDelete(tmdbReadAccessTokenKey, token);
  }

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
