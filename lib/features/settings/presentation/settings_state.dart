import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/env/env.dart';
import '../../../core/security/app_secure_storage.dart';
import '../../../core/utils/settings_preferences.dart';
import '../../../shared/models/anilist_models.dart';

final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

enum AppThemeMode { system, dark, light, oled }

enum AppStartupPage {
  board('/board', 'Board'),
  discovery('/discovery', 'Discovery'),
  library('/library', 'Library'),
  calendar('/calendar', 'Calendar'),
  addons('/addons', 'Addons');

  const AppStartupPage(this.route, this.label);

  final String route;
  final String label;

  static AppStartupPage fromName(String? name) {
    return AppStartupPage.values.firstWhere(
      (AppStartupPage p) => p.name == name,
      orElse: () => AppStartupPage.board,
    );
  }
}

enum AniListLibraryDefaultPage {
  all(null, 'All'),
  current(AniListListStatus.current, 'Watching'),
  planning(AniListListStatus.planning, 'Planning'),
  completed(AniListListStatus.completed, 'Completed'),
  dropped(AniListListStatus.dropped, 'Dropped'),
  paused(AniListListStatus.paused, 'Paused'),
  repeating(AniListListStatus.repeating, 'Repeating');

  const AniListLibraryDefaultPage(this.status, this.labelKey);

  final AniListListStatus? status;
  final String labelKey;

  static AniListLibraryDefaultPage fromName(String? name) {
    return AniListLibraryDefaultPage.values.firstWhere(
      (AniListLibraryDefaultPage page) => page.name == name,
      orElse: () => AniListLibraryDefaultPage.all,
    );
  }
}

extension AppThemeModeLabel on AppThemeMode {
  String get labelKey {
    return switch (this) {
      AppThemeMode.system => 'System',
      AppThemeMode.dark => 'Dark',
      AppThemeMode.light => 'Light',
      AppThemeMode.oled => 'OLED',
    };
  }

  ThemeMode get materialThemeMode {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.oled => ThemeMode.dark,
    };
  }

  IconData get icon {
    return switch (this) {
      AppThemeMode.system => Icons.devices_rounded,
      AppThemeMode.dark => Icons.dark_mode_rounded,
      AppThemeMode.light => Icons.light_mode_rounded,
      AppThemeMode.oled => Icons.brightness_2_rounded,
    };
  }
}

class SettingsState {
  const SettingsState({
    this.themeMode = AppThemeMode.system,
    this.appLocale,
    this.metadataLocale,
    this.accentColor = AppColors.accentPurple,
    this.compactMode = false,
    this.compactCards = false,
    this.discordRpcEnabled = true,
    this.tmdbUseCustomKey = false,
    this.tmdbReadAccessToken = '',
    this.tmdbLanguage = 'en-US',
    this.tmdbRegion = 'US',
    this.tmdbShowAdultContent = false,
    this.cacheLimitMb = 2048,
    this.metadataCacheEnabled = true,
    this.anilistMobileClientId = AppConstants.aniListMobileClientId,
    this.anilistDesktopClientId = AppConstants.aniListDesktopClientId,
    this.anilistDesktopPort = AppConstants.aniListDesktopCallbackPort,
    this.anilistAccessToken = '',
    this.anilistExpiresAt,
    this.anilistViewerId,
    this.anilistViewerName,
    this.anilistAvatarUrl,
    this.tvdbEnabled = false,
    this.tvdbApiKey = '',
    this.tvdbSubscriberPin = '',
    this.anilistShowAdultContent = false,
    this.anilistTitleLanguage = 'ROMAJI',
    this.anilistLibraryDefaultPage = AniListLibraryDefaultPage.all,
    this.anilistSavedAccounts = const <AniListSavedAccount>[],
    this.anilistScoreFormat = 'POINT_10_DECIMAL',
    this.soraWebProxyUrl = const String.fromEnvironment('MIRUSHIN_WEB_PROXY'),
    this.startupPage = AppStartupPage.board,
  });

  final AppThemeMode themeMode;
  final Locale? appLocale;
  final Locale? metadataLocale;
  final Color accentColor;
  final bool compactMode;
  final bool compactCards;
  final bool discordRpcEnabled;

  /// When `true`, [tmdbReadAccessToken] (the user's own key) is used. When
  /// `false`, the bundled default key from [Env.tmdbReadAccessToken] is used.
  final bool tmdbUseCustomKey;
  final String tmdbReadAccessToken;
  final String tmdbLanguage;
  final String tmdbRegion;
  final bool tmdbShowAdultContent;
  final int cacheLimitMb;
  final bool metadataCacheEnabled;
  final String anilistMobileClientId;
  final String anilistDesktopClientId;
  final int anilistDesktopPort;
  final String anilistAccessToken;
  final DateTime? anilistExpiresAt;
  final int? anilistViewerId;
  final String? anilistViewerName;
  final String? anilistAvatarUrl;
  final bool tvdbEnabled;
  final String tvdbApiKey;
  final String tvdbSubscriberPin;
  final bool anilistShowAdultContent;
  final String anilistTitleLanguage;
  final AniListLibraryDefaultPage anilistLibraryDefaultPage;
  final List<AniListSavedAccount> anilistSavedAccounts;
  final String anilistScoreFormat;
  final String soraWebProxyUrl;
  final AppStartupPage startupPage;

  /// The token actually used for TMDB requests: the user's custom token when
  /// [tmdbUseCustomKey] is enabled, otherwise the bundled default key.
  String get effectiveTmdbReadAccessToken {
    if (tmdbUseCustomKey) {
      return tmdbReadAccessToken.trim();
    }
    return Env.tmdbReadAccessToken.trim();
  }

  bool get hasTmdbToken => effectiveTmdbReadAccessToken.isNotEmpty;

  bool get hasTvdbApiKey => tvdbApiKey.trim().isNotEmpty;

  String get effectiveTvdbLanguage {
    final Locale? locale = metadataLocale;
    if (locale != null) {
      return switch (locale.languageCode) {
        'ru' => 'rus',
        'ja' => 'jpn',
        'zh' => 'zho',
        'fr' => 'fra',
        'de' => 'deu',
        'es' => 'spa',
        'pt' => 'por',
        'it' => 'ita',
        'ko' => 'kor',
        _ => 'eng',
      };
    }
    return 'eng';
  }

  String get effectiveTmdbLanguage {
    final String value = tmdbLanguage.trim();
    return value.isEmpty ? _defaultTmdbLanguage() : value;
  }

  bool get hasAniListSession {
    final DateTime? expiration = anilistExpiresAt;
    return anilistAccessToken.trim().isNotEmpty &&
        expiration != null &&
        expiration.isAfter(DateTime.now());
  }

  SettingsState copyWith({
    AppThemeMode? themeMode,
    Locale? appLocale,
    Locale? metadataLocale,
    Color? accentColor,
    bool? compactMode,
    bool? compactCards,
    bool? discordRpcEnabled,
    bool? tmdbUseCustomKey,
    String? tmdbReadAccessToken,
    String? tmdbLanguage,
    String? tmdbRegion,
    bool? tmdbShowAdultContent,
    int? cacheLimitMb,
    bool? metadataCacheEnabled,
    String? anilistMobileClientId,
    String? anilistDesktopClientId,
    int? anilistDesktopPort,
    String? anilistAccessToken,
    DateTime? anilistExpiresAt,
    int? anilistViewerId,
    String? anilistViewerName,
    String? anilistAvatarUrl,
    bool? tvdbEnabled,
    String? tvdbApiKey,
    String? tvdbSubscriberPin,
    bool? anilistShowAdultContent,
    String? anilistTitleLanguage,
    AniListLibraryDefaultPage? anilistLibraryDefaultPage,
    List<AniListSavedAccount>? anilistSavedAccounts,
    String? anilistScoreFormat,
    String? soraWebProxyUrl,
    AppStartupPage? startupPage,
    bool clearAppLocale = false,
    bool clearMetadataLocale = false,
    bool clearAniListSession = false,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      appLocale: clearAppLocale ? null : appLocale ?? this.appLocale,
      metadataLocale: clearMetadataLocale
          ? null
          : metadataLocale ?? this.metadataLocale,
      accentColor: accentColor ?? this.accentColor,
      compactMode: compactMode ?? this.compactMode,
      compactCards: compactCards ?? this.compactCards,
      discordRpcEnabled: discordRpcEnabled ?? this.discordRpcEnabled,
      tmdbUseCustomKey: tmdbUseCustomKey ?? this.tmdbUseCustomKey,
      tmdbReadAccessToken: tmdbReadAccessToken ?? this.tmdbReadAccessToken,
      tmdbLanguage: tmdbLanguage ?? this.tmdbLanguage,
      tmdbRegion: tmdbRegion ?? this.tmdbRegion,
      tmdbShowAdultContent: tmdbShowAdultContent ?? this.tmdbShowAdultContent,
      cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
      metadataCacheEnabled: metadataCacheEnabled ?? this.metadataCacheEnabled,
      anilistMobileClientId:
          anilistMobileClientId ?? this.anilistMobileClientId,
      anilistDesktopClientId:
          anilistDesktopClientId ?? this.anilistDesktopClientId,
      anilistDesktopPort: anilistDesktopPort ?? this.anilistDesktopPort,
      anilistAccessToken: clearAniListSession
          ? ''
          : anilistAccessToken ?? this.anilistAccessToken,
      anilistExpiresAt: clearAniListSession
          ? null
          : anilistExpiresAt ?? this.anilistExpiresAt,
      anilistViewerId: clearAniListSession
          ? null
          : anilistViewerId ?? this.anilistViewerId,
      anilistViewerName: clearAniListSession
          ? null
          : anilistViewerName ?? this.anilistViewerName,
      anilistAvatarUrl: clearAniListSession
          ? null
          : anilistAvatarUrl ?? this.anilistAvatarUrl,
      tvdbEnabled: tvdbEnabled ?? this.tvdbEnabled,
      tvdbApiKey: tvdbApiKey ?? this.tvdbApiKey,
      tvdbSubscriberPin: tvdbSubscriberPin ?? this.tvdbSubscriberPin,
      anilistShowAdultContent:
          anilistShowAdultContent ?? this.anilistShowAdultContent,
      anilistTitleLanguage: anilistTitleLanguage ?? this.anilistTitleLanguage,
      anilistLibraryDefaultPage:
          anilistLibraryDefaultPage ?? this.anilistLibraryDefaultPage,
      anilistSavedAccounts: anilistSavedAccounts ?? this.anilistSavedAccounts,
      anilistScoreFormat: anilistScoreFormat ?? this.anilistScoreFormat,
      soraWebProxyUrl: soraWebProxyUrl ?? this.soraWebProxyUrl,
      startupPage: startupPage ?? this.startupPage,
    );
  }

  static String _tmdbLanguageForLocale(Locale locale) {
    return switch (locale.languageCode) {
      'ru' => 'ru-RU',
      'ja' => 'ja-JP',
      _ => 'en-US',
    };
  }

  static String _defaultTmdbLanguage() {
    final Locale? locale = _supportedSystemLocale();
    return locale == null ? 'en-US' : _tmdbLanguageForLocale(locale);
  }

  static Locale? _supportedSystemLocale() {
    final List<Locale> locales =
        WidgetsBinding.instance.platformDispatcher.locales;
    for (final Locale locale in locales) {
      if (locale.languageCode == 'en' ||
          locale.languageCode == 'ru' ||
          locale.languageCode == 'ja') {
        return Locale(locale.languageCode);
      }
    }
    return null;
  }

  static String _tmdbLanguageForMetadataState({
    required Locale? metadataLocale,
    String? fallback,
  }) {
    final Locale? locale = metadataLocale;
    if (locale != null) {
      return _tmdbLanguageForLocale(locale);
    }
    final String value = fallback?.trim() ?? '';
    return value.isEmpty ? 'en-US' : value;
  }

  static Locale? localeFromTmdbLanguage(String value) {
    final String language = value.split('-').first.toLowerCase();
    return switch (language) {
      'ru' => const Locale('ru'),
      'ja' => const Locale('ja'),
      'en' => const Locale('en'),
      _ => null,
    };
  }

  static Locale? _supportedLocaleFromLanguage(String? value) {
    final String language = value?.trim().split('-').first.toLowerCase() ?? '';
    return switch (language) {
      'en' => const Locale('en'),
      'ru' => const Locale('ru'),
      'ja' => const Locale('ja'),
      _ => null,
    };
  }
}

class SettingsController extends Notifier<SettingsState> {
  final AppSecureStorage _secureStorage = const AppSecureStorage();
  SettingsPreferences? _preferences;
  bool _loadingPersisted = false;

  @override
  SettingsState build() {
    if (!_loadingPersisted) {
      _loadingPersisted = true;
      unawaited(_loadPersisted());
    }
    return const SettingsState();
  }

  Future<SettingsPreferences> _prefs() async {
    return _preferences ??= SettingsPreferences(
      await SharedPreferences.getInstance(),
    );
  }

  Future<void> _loadPersisted() async {
    final SettingsPreferences preferences = await _prefs();
    final String? themeModeName = preferences.readThemeMode();
    final String? appLanguage = preferences.readAppLanguage();
    final String? metadataLanguage = preferences.readMetadataLanguage();
    final int? accentColor = preferences.readAccentColor();
    final String? tmdbToken = await _secureStorage.readTmdbReadAccessToken();
    final String? tvdbApiKey = await _secureStorage.readTvdbApiKey();
    final String? tvdbSubscriberPin = await _secureStorage
        .readTvdbSubscriberPin();
    final String? aniListToken = await _secureStorage.readAniListAccessToken();
    final DateTime? aniListExpiresAt = await _secureStorage
        .readAniListExpiresAt();
    final Locale? appLocale = SettingsState._supportedLocaleFromLanguage(
      appLanguage,
    );
    final Locale? metadataLocale = SettingsState._supportedLocaleFromLanguage(
      metadataLanguage,
    );
    if (appLanguage != null && appLocale == null) {
      final SharedPreferences raw = await SharedPreferences.getInstance();
      await raw.remove(SettingsPreferences.appLanguageKey);
    }
    if (metadataLanguage != null && metadataLocale == null) {
      await preferences.saveMetadataLanguage(null);
    }
    final String tmdbLanguage = SettingsState._tmdbLanguageForMetadataState(
      metadataLocale: metadataLocale,
      fallback: preferences.readTmdbLanguage(),
    );

    state = state.copyWith(
      themeMode: _themeModeFromName(themeModeName),
      appLocale: appLocale,
      accentColor: accentColor == null ? null : Color(accentColor),
      compactMode: preferences.readCompactMode(),
      compactCards: preferences.readCompactCards(),
      discordRpcEnabled: preferences.readDiscordRpcEnabled(),
      tmdbUseCustomKey: preferences.readTmdbUseCustomKey(),
      tmdbReadAccessToken: tmdbToken ?? '',
      tmdbLanguage: tmdbLanguage,
      metadataLocale: metadataLocale,
      tmdbRegion: preferences.readTmdbRegion(),
      tmdbShowAdultContent: preferences.readTmdbShowAdultContent(),
      cacheLimitMb: preferences.readCacheLimitMb(),
      metadataCacheEnabled: preferences.readMetadataCacheEnabled(),
      anilistMobileClientId: preferences.readAniListMobileClientId(),
      anilistDesktopClientId: preferences.readAniListDesktopClientId(),
      anilistDesktopPort: preferences.readAniListDesktopPort(),
      anilistAccessToken: aniListToken ?? '',
      anilistExpiresAt: aniListExpiresAt,
      anilistViewerId: preferences.readAniListViewerId(),
      anilistViewerName: preferences.readAniListViewerName(),
      anilistAvatarUrl: preferences.readAniListAvatarUrl(),
      tvdbEnabled: preferences.readTvdbEnabled(),
      tvdbApiKey: tvdbApiKey ?? '',
      tvdbSubscriberPin: tvdbSubscriberPin ?? '',
      anilistShowAdultContent: preferences.readAniListShowAdultContent(),
      anilistTitleLanguage: preferences.readAniListTitleLanguage(),
      anilistLibraryDefaultPage: AniListLibraryDefaultPage.fromName(
        preferences.readAniListLibraryDefaultPage(),
      ),
      anilistSavedAccounts: preferences
          .readAniListSavedAccounts()
          .map(AniListSavedAccount.fromJson)
          .toList(growable: false),
      anilistScoreFormat: preferences.readAniListScoreFormat(),
      soraWebProxyUrl: preferences.readSoraWebProxyUrl(),
      startupPage: AppStartupPage.fromName(preferences.readStartupPage()),
    );
  }

  void setThemeMode(AppThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveThemeMode(mode.name)),
    );
  }

  void setAppLocale(Locale? locale) {
    state = state.copyWith(appLocale: locale, clearAppLocale: locale == null);
    if (locale == null) {
      unawaited(
        _save((SettingsPreferences prefs) async {
          final SharedPreferences raw = await SharedPreferences.getInstance();
          await raw.remove(SettingsPreferences.appLanguageKey);
        }),
      );
    } else {
      unawaited(
        _save(
          (SettingsPreferences prefs) =>
              prefs.saveAppLanguage(locale.languageCode),
        ),
      );
    }
  }

  void setMetadataLocale(Locale? locale) {
    final String language = locale != null
        ? SettingsState._tmdbLanguageForLocale(locale)
        : SettingsState._defaultTmdbLanguage();
    state = state.copyWith(
      metadataLocale: locale,
      clearMetadataLocale: locale == null,
      tmdbLanguage: language,
    );
    unawaited(
      _save((SettingsPreferences prefs) async {
        await prefs.saveMetadataLanguage(locale?.languageCode);
        await prefs.saveTmdbLanguage(language);
      }),
    );
  }

  void setAccentColor(Color color) {
    state = state.copyWith(accentColor: color);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveAccentColor(color.toARGB32()),
      ),
    );
  }

  void setCompactMode(bool value) {
    state = state.copyWith(compactMode: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveCompactMode(value)),
    );
  }

  void setCompactCards(bool value) {
    state = state.copyWith(compactCards: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveCompactCards(value)),
    );
  }

  void setDiscordRpcEnabled(bool value) {
    state = state.copyWith(discordRpcEnabled: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveDiscordRpcEnabled(value)),
    );
  }

  void setTmdbUseCustomKey(bool value) {
    state = state.copyWith(tmdbUseCustomKey: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveTmdbUseCustomKey(value)),
    );
  }

  void setTvdbEnabled(bool value) {
    state = state.copyWith(tvdbEnabled: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveTvdbEnabled(value)),
    );
  }

  void setTvdbApiKey(String value) {
    state = state.copyWith(tvdbApiKey: value.trim());
    unawaited(_secureStorage.writeTvdbApiKey(value));
  }

  void setTvdbSubscriberPin(String value) {
    state = state.copyWith(tvdbSubscriberPin: value.trim());
    unawaited(_secureStorage.writeTvdbSubscriberPin(value));
  }

  void setTmdbReadAccessToken(String token) {
    state = state.copyWith(tmdbReadAccessToken: token.trim());
    unawaited(_secureStorage.writeTmdbReadAccessToken(token));
  }

  void setTmdbLanguage(String value) {
    final String language = value.trim().isEmpty ? 'en-US' : value.trim();
    final Locale? locale = SettingsState.localeFromTmdbLanguage(language);
    state = state.copyWith(
      tmdbLanguage: language,
      metadataLocale: locale,
      clearMetadataLocale: locale == null,
    );
    unawaited(
      _save((SettingsPreferences prefs) async {
        await prefs.saveMetadataLanguage(locale?.languageCode);
        await prefs.saveTmdbLanguage(language);
      }),
    );
  }

  void setTmdbRegion(String value) {
    state = state.copyWith(tmdbRegion: value.trim().toUpperCase());
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveTmdbRegion(value)),
    );
  }

  void setTmdbShowAdultContent(bool value) {
    state = state.copyWith(tmdbShowAdultContent: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveTmdbShowAdultContent(value),
      ),
    );
  }

  void setCacheLimitMb(int value) {
    final int normalized = value.clamp(256, 8192).toInt();
    state = state.copyWith(cacheLimitMb: normalized);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveCacheLimitMb(normalized)),
    );
  }

  void setMetadataCacheEnabled(bool value) {
    state = state.copyWith(metadataCacheEnabled: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveMetadataCacheEnabled(value),
      ),
    );
  }

  void setAniListMobileClientId(String value) {
    state = state.copyWith(anilistMobileClientId: value.trim());
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveAniListMobileClientId(value),
      ),
    );
  }

  void setAniListDesktopClientId(String value) {
    state = state.copyWith(anilistDesktopClientId: value.trim());
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveAniListDesktopClientId(value),
      ),
    );
  }

  void setAniListDesktopPort(int value) {
    state = state.copyWith(anilistDesktopPort: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveAniListDesktopPort(value)),
    );
  }

  void setAniListShowAdultContent(bool value) {
    state = state.copyWith(anilistShowAdultContent: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveAniListShowAdultContent(value),
      ),
    );
  }

  void setAniListTitleLanguage(String value) {
    state = state.copyWith(anilistTitleLanguage: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveAniListTitleLanguage(value),
      ),
    );
  }

  void setAniListLibraryDefaultPage(AniListLibraryDefaultPage value) {
    state = state.copyWith(anilistLibraryDefaultPage: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) =>
            prefs.saveAniListLibraryDefaultPage(value.name),
      ),
    );
  }

  void setAniListScoreFormat(String value) {
    state = state.copyWith(anilistScoreFormat: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveAniListScoreFormat(value)),
    );
  }

  void setStartupPage(AppStartupPage value) {
    state = state.copyWith(startupPage: value);
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveStartupPage(value.name)),
    );
  }

  void setSoraWebProxyUrl(String value) {
    state = state.copyWith(soraWebProxyUrl: value.trim());
    unawaited(
      _save((SettingsPreferences prefs) => prefs.saveSoraWebProxyUrl(value)),
    );
  }

  Future<void> saveAniListAccount(AniListSavedAccount account) async {
    final List<AniListSavedAccount> existing = List<AniListSavedAccount>.from(
      state.anilistSavedAccounts,
    );
    existing.removeWhere(
      (AniListSavedAccount a) => a.viewerId == account.viewerId,
    );
    existing.add(account);
    state = state.copyWith(anilistSavedAccounts: existing);
    final SettingsPreferences preferences = await _prefs();
    await preferences.saveAniListSavedAccounts(
      existing.map((AniListSavedAccount a) => a.toJson()).toList(),
    );
  }

  Future<void> removeAniListAccount(int viewerId) async {
    final List<AniListSavedAccount> updated = state.anilistSavedAccounts
        .where((AniListSavedAccount a) => a.viewerId != viewerId)
        .toList(growable: false);
    state = state.copyWith(anilistSavedAccounts: updated);
    final SettingsPreferences preferences = await _prefs();
    await preferences.saveAniListSavedAccounts(
      updated.map((AniListSavedAccount a) => a.toJson()).toList(),
    );
  }

  Future<void> switchAniListAccount(AniListSavedAccount account) async {
    // Save current active account to the saved list before switching.
    if (state.hasAniListSession && state.anilistViewerId != null) {
      final AniListSavedAccount current = AniListSavedAccount(
        viewerId: state.anilistViewerId!,
        viewerName: state.anilistViewerName ?? 'AniList User',
        avatarUrl: state.anilistAvatarUrl,
        accessToken: state.anilistAccessToken,
        expiresAt: state.anilistExpiresAt ?? DateTime.now(),
      );
      await saveAniListAccount(current);
    }
    // Remove target account from saved list (it's becoming active).
    await removeAniListAccount(account.viewerId);
    // Activate the selected account.
    state = state.copyWith(
      anilistAccessToken: account.accessToken,
      anilistExpiresAt: account.expiresAt,
      anilistViewerId: account.viewerId,
      anilistViewerName: account.viewerName,
      anilistAvatarUrl: account.avatarUrl,
    );
    await _secureStorage.writeAniListAccessToken(account.accessToken);
    await _secureStorage.writeAniListExpiresAt(account.expiresAt);
    final SettingsPreferences preferences = await _prefs();
    await preferences.saveAniListViewer(
      id: account.viewerId,
      name: account.viewerName,
      avatarUrl: account.avatarUrl,
    );
  }

  Future<void> connectAniList({
    required AniListOAuthResult oauth,
    required AniListViewer viewer,
  }) async {
    // If a different account is currently active, save it to the list.
    if (state.hasAniListSession &&
        state.anilistViewerId != null &&
        state.anilistViewerId != viewer.id) {
      final AniListSavedAccount current = AniListSavedAccount(
        viewerId: state.anilistViewerId!,
        viewerName: state.anilistViewerName ?? 'AniList User',
        avatarUrl: state.anilistAvatarUrl,
        accessToken: state.anilistAccessToken,
        expiresAt: state.anilistExpiresAt ?? DateTime.now(),
      );
      await saveAniListAccount(current);
    }
    state = state.copyWith(
      anilistAccessToken: oauth.accessToken,
      anilistExpiresAt: oauth.expiresAt,
      anilistViewerId: viewer.id,
      anilistViewerName: viewer.name,
      anilistAvatarUrl: viewer.avatarUrl,
    );
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.writeAniListAccessToken(oauth.accessToken);
    await _secureStorage.writeAniListExpiresAt(oauth.expiresAt);
    await preferences.saveAniListViewer(
      id: viewer.id,
      name: viewer.name,
      avatarUrl: viewer.avatarUrl,
    );
  }

  Future<void> disconnectAniList() async {
    state = state.copyWith(clearAniListSession: true);
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.clearAniListSession();
    await preferences.saveAniListViewer(id: null, name: null, avatarUrl: null);
  }

  Future<void> _save(
    Future<void> Function(SettingsPreferences preferences) save,
  ) async {
    await save(await _prefs());
  }

  AppThemeMode _themeModeFromName(String? name) {
    return AppThemeMode.values.firstWhere(
      (AppThemeMode mode) => mode.name == name,
      orElse: () {
        return switch (name) {
          'dark' => AppThemeMode.dark,
          'light' => AppThemeMode.light,
          _ => AppThemeMode.system,
        };
      },
    );
  }
}
