import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

class SettingsPreferences {
  const SettingsPreferences(this._preferences);

  final SharedPreferences _preferences;

  static const String themeModeKey = 'settings.themeMode';
  static const String appLanguageKey = 'settings.appLanguage';
  static const String metadataLanguageKey = 'settings.metadataLanguage';
  static const String accentColorKey = 'settings.accentColor';
  static const String compactModeKey = 'settings.compactMode';
  static const String discordRpcEnabledKey = 'settings.discordRpcEnabled';
  static const String tmdbEnabledKey = 'settings.tmdbEnabled';
  static const String tmdbUseCustomKeyKey = 'settings.tmdbUseCustomKey';
  static const String tvdbEnabledKey = 'settings.tvdbEnabled';
  static const String tmdbLanguageKey = 'settings.tmdbLanguage';
  static const String tmdbRegionKey = 'settings.tmdbRegion';
  static const String cacheLimitMbKey = 'settings.cacheLimitMb';
  static const String metadataCacheEnabledKey = 'settings.metadataCacheEnabled';
  static const String anilistMobileClientIdKey =
      'settings.anilistMobileClientId';
  static const String anilistDesktopClientIdKey =
      'settings.anilistDesktopClientId';
  static const String anilistDesktopPortKey = 'settings.anilistDesktopPort';
  static const String anilistViewerIdKey = 'settings.anilistViewerId';
  static const String anilistViewerNameKey = 'settings.anilistViewerName';
  static const String anilistAvatarUrlKey = 'settings.anilistAvatarUrl';
  static const String anilistShowAdultContentKey =
      'settings.anilistShowAdultContent';
  static const String anilistTitleLanguageKey = 'settings.anilistTitleLanguage';
  static const String anilistLibraryDefaultPageKey =
      'settings.anilistLibraryDefaultPage';
  static const String anilistSavedAccountsKey = 'settings.anilistSavedAccounts';
  static const String anilistScoreFormatKey = 'settings.anilistScoreFormat';
  static const String anilistUserSettingsCacheKey =
      'settings.anilistUserSettingsCache';
  static const String soraWebProxyUrlKey = 'settings.soraWebProxyUrl';
  static const String startupPageKey = 'settings.startupPage';

  String? readThemeMode() => _preferences.getString(themeModeKey);

  String? readAppLanguage() => _preferences.getString(appLanguageKey);

  String? readMetadataLanguage() => _preferences.getString(metadataLanguageKey);

  int? readAccentColor() => _preferences.getInt(accentColorKey);

  bool readCompactMode() => _preferences.getBool(compactModeKey) ?? false;

  bool readDiscordRpcEnabled() =>
      _preferences.getBool(discordRpcEnabledKey) ?? true;

  bool readTmdbEnabled() => _preferences.getBool(tmdbEnabledKey) ?? true;

  bool readTmdbUseCustomKey() =>
      _preferences.getBool(tmdbUseCustomKeyKey) ?? false;

  bool readTvdbEnabled() => _preferences.getBool(tvdbEnabledKey) ?? false;

  Future<void> saveTvdbEnabled(bool value) =>
      _preferences.setBool(tvdbEnabledKey, value);

  String readTmdbLanguage() =>
      _preferences.getString(tmdbLanguageKey) ?? 'en-US';

  String readTmdbRegion() => _preferences.getString(tmdbRegionKey) ?? 'US';

  int readCacheLimitMb() => _preferences.getInt(cacheLimitMbKey) ?? 2048;

  bool readMetadataCacheEnabled() =>
      _preferences.getBool(metadataCacheEnabledKey) ?? true;

  String readAniListMobileClientId() =>
      _preferences.getString(anilistMobileClientIdKey) ??
      AppConstants.aniListMobileClientId;

  String readAniListDesktopClientId() =>
      _preferences.getString(anilistDesktopClientIdKey) ??
      AppConstants.aniListDesktopClientId;

  int readAniListDesktopPort() =>
      _preferences.getInt(anilistDesktopPortKey) ??
      AppConstants.aniListDesktopCallbackPort;

  int? readAniListViewerId() => _preferences.getInt(anilistViewerIdKey);

  String? readAniListViewerName() =>
      _preferences.getString(anilistViewerNameKey);

  String? readAniListAvatarUrl() => _preferences.getString(anilistAvatarUrlKey);

  bool readAniListShowAdultContent() =>
      _preferences.getBool(anilistShowAdultContentKey) ?? false;

  String readAniListTitleLanguage() =>
      _preferences.getString(anilistTitleLanguageKey) ?? 'ROMAJI';

  String? readAniListLibraryDefaultPage() =>
      _preferences.getString(anilistLibraryDefaultPageKey);

  List<Map<String, dynamic>> readAniListSavedAccounts() {
    final List<String>? list = _preferences.getStringList(
      anilistSavedAccountsKey,
    );
    if (list == null) return <Map<String, dynamic>>[];
    return list
        .map((String s) {
          try {
            final Object? decoded = jsonDecode(s);
            return decoded is Map<String, dynamic> ? decoded : null;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  String readAniListScoreFormat() =>
      _preferences.getString(anilistScoreFormatKey) ?? 'POINT_10_DECIMAL';

  String readSoraWebProxyUrl() =>
      _preferences.getString(soraWebProxyUrlKey) ??
      const String.fromEnvironment('MIRUSHIN_WEB_PROXY');

  String? readStartupPage() => _preferences.getString(startupPageKey);

  String? readAniListUserSettingsCache() =>
      _preferences.getString(anilistUserSettingsCacheKey);

  Future<void> saveThemeMode(String value) {
    return _preferences.setString(themeModeKey, value);
  }

  Future<void> saveAppLanguage(String value) {
    return _preferences.setString(appLanguageKey, value);
  }

  Future<void> saveMetadataLanguage(String? value) {
    if (value == null || value.isEmpty) {
      return _preferences.remove(metadataLanguageKey);
    }
    return _preferences.setString(metadataLanguageKey, value);
  }

  Future<void> saveAccentColor(int value) {
    return _preferences.setInt(accentColorKey, value);
  }

  Future<void> saveCompactMode(bool value) {
    return _preferences.setBool(compactModeKey, value);
  }

  Future<void> saveDiscordRpcEnabled(bool value) {
    return _preferences.setBool(discordRpcEnabledKey, value);
  }

  Future<void> saveTmdbEnabled(bool value) {
    return _preferences.setBool(tmdbEnabledKey, value);
  }

  Future<void> saveTmdbUseCustomKey(bool value) {
    return _preferences.setBool(tmdbUseCustomKeyKey, value);
  }

  Future<void> saveTmdbLanguage(String value) {
    return _preferences.setString(tmdbLanguageKey, value);
  }

  Future<void> saveTmdbRegion(String value) {
    return _preferences.setString(tmdbRegionKey, value);
  }

  Future<void> saveCacheLimitMb(int value) {
    return _preferences.setInt(cacheLimitMbKey, value);
  }

  Future<void> saveMetadataCacheEnabled(bool value) {
    return _preferences.setBool(metadataCacheEnabledKey, value);
  }

  Future<void> saveAniListMobileClientId(String value) {
    return _preferences.setString(anilistMobileClientIdKey, value.trim());
  }

  Future<void> saveAniListDesktopClientId(String value) {
    return _preferences.setString(anilistDesktopClientIdKey, value.trim());
  }

  Future<void> saveAniListDesktopPort(int value) {
    return _preferences.setInt(anilistDesktopPortKey, value);
  }

  Future<void> saveAniListShowAdultContent(bool value) =>
      _preferences.setBool(anilistShowAdultContentKey, value);

  Future<void> saveAniListTitleLanguage(String value) =>
      _preferences.setString(anilistTitleLanguageKey, value);

  Future<void> saveAniListLibraryDefaultPage(String value) =>
      _preferences.setString(anilistLibraryDefaultPageKey, value);

  Future<void> saveAniListSavedAccounts(
    List<Map<String, dynamic>> accounts,
  ) async {
    await _preferences.setStringList(
      anilistSavedAccountsKey,
      accounts.map((Map<String, dynamic> a) => jsonEncode(a)).toList(),
    );
  }

  Future<void> saveAniListScoreFormat(String value) =>
      _preferences.setString(anilistScoreFormatKey, value);

  Future<void> saveStartupPage(String value) =>
      _preferences.setString(startupPageKey, value);

  Future<void> saveSoraWebProxyUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _preferences.remove(soraWebProxyUrlKey);
    }
    return _preferences.setString(soraWebProxyUrlKey, trimmed);
  }

  Future<void> saveAniListUserSettingsCache(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _preferences.remove(anilistUserSettingsCacheKey);
    }
    return _preferences.setString(anilistUserSettingsCacheKey, value);
  }

  Future<void> saveAniListViewer({
    required int? id,
    required String? name,
    required String? avatarUrl,
  }) async {
    if (id == null) {
      await _preferences.remove(anilistViewerIdKey);
    } else {
      await _preferences.setInt(anilistViewerIdKey, id);
    }

    if (name == null || name.isEmpty) {
      await _preferences.remove(anilistViewerNameKey);
    } else {
      await _preferences.setString(anilistViewerNameKey, name);
    }

    if (avatarUrl == null || avatarUrl.isEmpty) {
      await _preferences.remove(anilistAvatarUrlKey);
    } else {
      await _preferences.setString(anilistAvatarUrlKey, avatarUrl);
    }
  }
}
