import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/env/env.dart';
import '../../../core/security/app_secure_storage.dart';
import '../../../core/utils/settings_preferences.dart';
import '../../../shared/models/anilist_models.dart';
import '../../tracking/data/mal_oauth_service.dart';
import '../../tracking/data/oauth_token_bundle.dart';
import '../../tracking/data/shikimori_oauth_service.dart';
import '../../tracking/domain/tracker_models.dart';
import '../data/workspace_preferences_store.dart';

final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

/// Whether the running build targets a mobile platform. Matches the definition
/// used by the tracker login flow so MAL client-id selection (desktop vs mobile
/// app) is consistent between login and token refresh.
bool get _isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

enum AppThemeMode { system, dark, light, oled }

enum CacheRetention {
  oneWeek(Duration(days: 7), '1 Week'),
  oneMonth(Duration(days: 30), '1 Month'),
  threeMonths(Duration(days: 90), '3 Months'),
  never(null, 'Never expire');

  const CacheRetention(this.duration, this.labelKey);

  final Duration? duration;
  final String labelKey;

  static CacheRetention fromName(String? name) {
    return CacheRetention.values.firstWhere(
      (CacheRetention retention) => retention.name == name,
      orElse: () => CacheRetention.oneMonth,
    );
  }
}

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
    this.fanartTvApiKey = '',
    this.tmdbLanguage = 'en-US',
    this.tmdbRegion = 'US',
    this.tmdbShowAdultContent = false,
    this.cacheLimitMb = 2048,
    this.cacheRetention = CacheRetention.oneMonth,
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
    this.canonicalLibraryOwnerAniListId,
    this.anilistScoreFormat = 'POINT_10_DECIMAL',
    this.soraWebProxyUrl = const String.fromEnvironment('MIRUSHIN_WEB_PROXY'),
    this.startupPage = AppStartupPage.board,
    this.primaryTrackerSource = TrackerSource.anilist,
    this.malAccessToken = '',
    this.malRefreshToken = '',
    this.malExpiresAt,
    this.malViewerId,
    this.malViewerName,
    this.malAvatarUrl,
    this.malUseCustomCredentials = false,
    this.malCustomClientIdDesktop = '',
    this.malCustomClientIdMobile = '',
    this.shikimoriAccessToken = '',
    this.shikimoriRefreshToken = '',
    this.shikimoriExpiresAt,
    this.shikimoriViewerId,
    this.shikimoriViewerName,
    this.shikimoriAvatarUrl,
    this.shikimoriUseCustomCredentials = false,
    this.shikimoriCustomClientId = '',
    this.shikimoriCustomClientSecret = '',
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
  final String fanartTvApiKey;
  final String tmdbLanguage;
  final String tmdbRegion;
  final bool tmdbShowAdultContent;
  final int cacheLimitMb;
  final CacheRetention cacheRetention;
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
  final int? canonicalLibraryOwnerAniListId;
  final String anilistScoreFormat;
  final String soraWebProxyUrl;
  final AppStartupPage startupPage;

  /// The tracker whose library feeds the in-app Library view.
  final TrackerSource primaryTrackerSource;

  // MyAnimeList session + credentials.
  final String malAccessToken;
  final String malRefreshToken;
  final DateTime? malExpiresAt;
  final int? malViewerId;
  final String? malViewerName;
  final String? malAvatarUrl;
  final bool malUseCustomCredentials;
  final String malCustomClientIdDesktop;
  final String malCustomClientIdMobile;

  // Shikimori session + credentials.
  final String shikimoriAccessToken;
  final String shikimoriRefreshToken;
  final DateTime? shikimoriExpiresAt;
  final int? shikimoriViewerId;
  final String? shikimoriViewerName;
  final String? shikimoriAvatarUrl;
  final bool shikimoriUseCustomCredentials;
  final String shikimoriCustomClientId;
  final String shikimoriCustomClientSecret;

  /// The MAL client id used for OAuth. MAL client ids are not bundled in public
  /// builds, so users must enable custom credentials and provide their own.
  String effectiveMalClientId({required bool isMobile}) {
    if (malUseCustomCredentials) {
      return (isMobile ? malCustomClientIdMobile : malCustomClientIdDesktop)
          .trim();
    }
    return '';
  }

  String get effectiveShikimoriClientId {
    if (shikimoriUseCustomCredentials) return shikimoriCustomClientId.trim();
    return '';
  }

  String get effectiveShikimoriClientSecret {
    if (shikimoriUseCustomCredentials) {
      return shikimoriCustomClientSecret.trim();
    }
    return '';
  }

  bool get hasMalSession {
    return malAccessToken.trim().isNotEmpty && malViewerId != null;
  }

  bool get hasShikimoriSession {
    return shikimoriAccessToken.trim().isNotEmpty && shikimoriViewerId != null;
  }

  bool get malConfigured =>
      !malUseCustomCredentials ||
      effectiveMalClientId(isMobile: false).isNotEmpty ||
      effectiveMalClientId(isMobile: true).isNotEmpty;

  bool get shikimoriConfigured =>
      !shikimoriUseCustomCredentials ||
      (effectiveShikimoriClientId.isNotEmpty &&
          effectiveShikimoriClientSecret.isNotEmpty);

  /// Deterministic presentation source for legacy UI paths. Local Library is
  /// canonical and every connected tracker is reconciled independently, so
  /// the old user-selected preferred tracker no longer affects sync.
  TrackerSource get effectivePrimaryTrackerSource {
    bool connected(TrackerSource source) {
      return switch (source) {
        TrackerSource.anilist => hasAniListSession,
        TrackerSource.mal => hasMalSession,
        TrackerSource.shikimori => hasShikimoriSession,
      };
    }

    for (final TrackerSource source in TrackerSource.values) {
      if (connected(source)) return source;
    }
    return TrackerSource.anilist;
  }

  /// The token actually used for TMDB requests: the user's custom token when
  /// [tmdbUseCustomKey] is enabled, otherwise the bundled default key.
  String get effectiveTmdbReadAccessToken {
    if (tmdbUseCustomKey) {
      return tmdbReadAccessToken.trim();
    }
    return Env.tmdbReadAccessToken.trim();
  }

  bool get hasTmdbToken => effectiveTmdbReadAccessToken.isNotEmpty;

  /// The user-provided Fanart.tv key, falling back to an optional build-time
  /// key for private builds. Public MiruShin builds leave that fallback empty.
  String get effectiveFanartTvApiKey {
    final String customKey = fanartTvApiKey.trim();
    return customKey.isNotEmpty ? customKey : Env.fanartTvApiKey.trim();
  }

  bool get hasFanartTvApiKey => effectiveFanartTvApiKey.isNotEmpty;

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
    String? fanartTvApiKey,
    String? tmdbLanguage,
    String? tmdbRegion,
    bool? tmdbShowAdultContent,
    int? cacheLimitMb,
    CacheRetention? cacheRetention,
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
    int? canonicalLibraryOwnerAniListId,
    String? anilistScoreFormat,
    String? soraWebProxyUrl,
    AppStartupPage? startupPage,
    TrackerSource? primaryTrackerSource,
    String? malAccessToken,
    String? malRefreshToken,
    DateTime? malExpiresAt,
    int? malViewerId,
    String? malViewerName,
    String? malAvatarUrl,
    bool? malUseCustomCredentials,
    String? malCustomClientIdDesktop,
    String? malCustomClientIdMobile,
    String? shikimoriAccessToken,
    String? shikimoriRefreshToken,
    DateTime? shikimoriExpiresAt,
    int? shikimoriViewerId,
    String? shikimoriViewerName,
    String? shikimoriAvatarUrl,
    bool? shikimoriUseCustomCredentials,
    String? shikimoriCustomClientId,
    String? shikimoriCustomClientSecret,
    bool clearAppLocale = false,
    bool clearMetadataLocale = false,
    bool clearAniListSession = false,
    bool clearMalSession = false,
    bool clearShikimoriSession = false,
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
      fanartTvApiKey: fanartTvApiKey ?? this.fanartTvApiKey,
      tmdbLanguage: tmdbLanguage ?? this.tmdbLanguage,
      tmdbRegion: tmdbRegion ?? this.tmdbRegion,
      tmdbShowAdultContent: tmdbShowAdultContent ?? this.tmdbShowAdultContent,
      cacheLimitMb: cacheLimitMb ?? this.cacheLimitMb,
      cacheRetention: cacheRetention ?? this.cacheRetention,
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
      canonicalLibraryOwnerAniListId:
          canonicalLibraryOwnerAniListId ?? this.canonicalLibraryOwnerAniListId,
      anilistScoreFormat: anilistScoreFormat ?? this.anilistScoreFormat,
      soraWebProxyUrl: soraWebProxyUrl ?? this.soraWebProxyUrl,
      startupPage: startupPage ?? this.startupPage,
      primaryTrackerSource: primaryTrackerSource ?? this.primaryTrackerSource,
      malAccessToken: clearMalSession
          ? ''
          : malAccessToken ?? this.malAccessToken,
      malRefreshToken: clearMalSession
          ? ''
          : malRefreshToken ?? this.malRefreshToken,
      malExpiresAt: clearMalSession ? null : malExpiresAt ?? this.malExpiresAt,
      malViewerId: clearMalSession ? null : malViewerId ?? this.malViewerId,
      malViewerName: clearMalSession
          ? null
          : malViewerName ?? this.malViewerName,
      malAvatarUrl: clearMalSession ? null : malAvatarUrl ?? this.malAvatarUrl,
      malUseCustomCredentials:
          malUseCustomCredentials ?? this.malUseCustomCredentials,
      malCustomClientIdDesktop:
          malCustomClientIdDesktop ?? this.malCustomClientIdDesktop,
      malCustomClientIdMobile:
          malCustomClientIdMobile ?? this.malCustomClientIdMobile,
      shikimoriAccessToken: clearShikimoriSession
          ? ''
          : shikimoriAccessToken ?? this.shikimoriAccessToken,
      shikimoriRefreshToken: clearShikimoriSession
          ? ''
          : shikimoriRefreshToken ?? this.shikimoriRefreshToken,
      shikimoriExpiresAt: clearShikimoriSession
          ? null
          : shikimoriExpiresAt ?? this.shikimoriExpiresAt,
      shikimoriViewerId: clearShikimoriSession
          ? null
          : shikimoriViewerId ?? this.shikimoriViewerId,
      shikimoriViewerName: clearShikimoriSession
          ? null
          : shikimoriViewerName ?? this.shikimoriViewerName,
      shikimoriAvatarUrl: clearShikimoriSession
          ? null
          : shikimoriAvatarUrl ?? this.shikimoriAvatarUrl,
      shikimoriUseCustomCredentials:
          shikimoriUseCustomCredentials ?? this.shikimoriUseCustomCredentials,
      shikimoriCustomClientId:
          shikimoriCustomClientId ?? this.shikimoriCustomClientId,
      shikimoriCustomClientSecret:
          shikimoriCustomClientSecret ?? this.shikimoriCustomClientSecret,
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
  final Completer<void> _persistedReady = Completer<void>();
  SettingsPreferences? _preferences;
  bool _loadingPersisted = false;

  Future<void> get ready => _persistedReady.future;

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

  Future<List<AniListSavedAccount>> _readSavedAniListAccounts(
    SettingsPreferences preferences,
  ) async {
    final List<AniListSavedAccount> legacy = preferences
        .readAniListSavedAccounts()
        .map(AniListSavedAccount.fromJson)
        .where((AniListSavedAccount account) => account.viewerId > 0)
        .toList(growable: false);
    final String secureRaw =
        (await _secureStorage.readTrackerAccountWorkspaces()) ?? '';
    List<AniListSavedAccount> secure = <AniListSavedAccount>[];
    if (secureRaw.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(secureRaw);
        if (decoded is List) {
          secure = decoded
              .whereType<Map>()
              .map(
                (Map<dynamic, dynamic> value) => AniListSavedAccount.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .where((AniListSavedAccount account) => account.viewerId > 0)
              .toList(growable: false);
        }
      } on Object {
        // Fall back to the legacy copy below and rewrite a valid secure value.
      }
    }
    final List<AniListSavedAccount> result = secure.isNotEmpty
        ? secure
        : legacy;
    if (legacy.isNotEmpty || (secureRaw.isNotEmpty && secure.isEmpty)) {
      await _persistSavedAniListAccounts(result, preferences: preferences);
      await preferences.clearAniListSavedAccounts();
    }
    return result;
  }

  Future<void> _persistSavedAniListAccounts(
    List<AniListSavedAccount> accounts, {
    SettingsPreferences? preferences,
  }) async {
    await _secureStorage.writeTrackerAccountWorkspaces(
      jsonEncode(
        accounts
            .map((AniListSavedAccount account) => account.toJson())
            .toList(growable: false),
      ),
    );
    await (preferences ?? await _prefs()).clearAniListSavedAccounts();
  }

  Future<void> _loadPersisted() async {
    try {
      final SettingsPreferences preferences = await _prefs();
      final String? themeModeName = preferences.readThemeMode();
      String? appLanguage = preferences.readAppLanguage();
      final String? metadataLanguage = preferences.readMetadataLanguage();
      final int? accentColor = preferences.readAccentColor();
      final String? tmdbToken = await _secureStorage.readTmdbReadAccessToken();
      final String? fanartTvApiKey = await _secureStorage.readFanartTvApiKey();
      final String? tvdbApiKey = await _secureStorage.readTvdbApiKey();
      final String? tvdbSubscriberPin = await _secureStorage
          .readTvdbSubscriberPin();
      final String? aniListToken = await _secureStorage
          .readAniListAccessToken();
      final DateTime? aniListExpiresAt = await _secureStorage
          .readAniListExpiresAt();
      final int? aniListViewerId = preferences.readAniListViewerId();
      int? canonicalLibraryOwnerAniListId = preferences
          .readCanonicalLibraryOwnerAniListId();
      if (canonicalLibraryOwnerAniListId == null && aniListViewerId != null) {
        canonicalLibraryOwnerAniListId = aniListViewerId;
        await preferences.saveCanonicalLibraryOwnerAniListId(aniListViewerId);
      }
      final String? malToken = await _secureStorage.readMalAccessToken();
      final String? malRefresh = await _secureStorage.readMalRefreshToken();
      final DateTime? malExpiresAt = await _secureStorage.readMalExpiresAt();
      final String? shikimoriToken = await _secureStorage
          .readShikimoriAccessToken();
      final String? shikimoriRefresh = await _secureStorage
          .readShikimoriRefreshToken();
      final DateTime? shikimoriExpiresAt = await _secureStorage
          .readShikimoriExpiresAt();
      String shikimoriCustomClientSecret =
          (await _secureStorage.readShikimoriCustomClientSecret()) ?? '';
      final String legacyShikimoriCustomClientSecret = preferences
          .readShikimoriCustomClientSecret()
          .trim();
      if (shikimoriCustomClientSecret.isEmpty &&
          legacyShikimoriCustomClientSecret.isNotEmpty) {
        shikimoriCustomClientSecret = legacyShikimoriCustomClientSecret;
        await _secureStorage.writeShikimoriCustomClientSecret(
          legacyShikimoriCustomClientSecret,
        );
        await preferences.clearShikimoriCustomClientSecret();
      }
      final Locale? legacyAppLocale =
          SettingsState._supportedLocaleFromLanguage(appLanguage);
      final Locale? metadataLocale = SettingsState._supportedLocaleFromLanguage(
        metadataLanguage,
      );
      if (appLanguage != null && legacyAppLocale == null) {
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
      final List<AniListSavedAccount> savedAniListAccounts =
          await _readSavedAniListAccounts(preferences);
      final SharedPreferences rawPreferences =
          await SharedPreferences.getInstance();
      final WorkspacePreferencesStore workspaceStore =
          WorkspacePreferencesStore(rawPreferences);
      await workspaceStore.migrateLegacy(
        viewerIds: <int>{
          ...savedAniListAccounts.map(
            (AniListSavedAccount account) => account.viewerId,
          ),
          ?aniListViewerId,
        },
      );
      final String workspaceId = _workspaceIdFor(aniListViewerId);
      appLanguage =
          workspaceStore.read(workspaceId, SettingsPreferences.appLanguageKey)
              as String? ??
          appLanguage;
      final Locale? appLocale = SettingsState._supportedLocaleFromLanguage(
        appLanguage,
      );
      final bool workspaceDiscord =
          workspaceStore.read(
                workspaceId,
                SettingsPreferences.discordRpcEnabledKey,
              )
              as bool? ??
          preferences.readDiscordRpcEnabled();
      final String workspaceTitleLanguage =
          workspaceStore.read(
                workspaceId,
                SettingsPreferences.anilistTitleLanguageKey,
              )
              as String? ??
          preferences.readAniListTitleLanguage();
      final String? workspaceDefaultPage =
          workspaceStore.read(
                workspaceId,
                SettingsPreferences.anilistLibraryDefaultPageKey,
              )
              as String? ??
          preferences.readAniListLibraryDefaultPage();
      if (!ref.mounted) return;

      state = state.copyWith(
        themeMode: _themeModeFromName(themeModeName),
        appLocale: appLocale,
        accentColor: accentColor == null ? null : Color(accentColor),
        compactMode: preferences.readCompactMode(),
        compactCards: preferences.readCompactCards(),
        discordRpcEnabled: workspaceDiscord,
        tmdbUseCustomKey: preferences.readTmdbUseCustomKey(),
        tmdbReadAccessToken: tmdbToken ?? '',
        fanartTvApiKey: fanartTvApiKey ?? '',
        tmdbLanguage: tmdbLanguage,
        metadataLocale: metadataLocale,
        tmdbRegion: preferences.readTmdbRegion(),
        tmdbShowAdultContent: preferences.readTmdbShowAdultContent(),
        cacheLimitMb: preferences.readCacheLimitMb(),
        cacheRetention: CacheRetention.fromName(
          preferences.readCacheRetention(),
        ),
        anilistMobileClientId: preferences.readAniListMobileClientId(),
        anilistDesktopClientId: preferences.readAniListDesktopClientId(),
        anilistDesktopPort: preferences.readAniListDesktopPort(),
        anilistAccessToken: aniListToken ?? '',
        anilistExpiresAt: aniListExpiresAt,
        anilistViewerId: aniListViewerId,
        anilistViewerName: preferences.readAniListViewerName(),
        anilistAvatarUrl: preferences.readAniListAvatarUrl(),
        tvdbEnabled: preferences.readTvdbEnabled(),
        tvdbApiKey: tvdbApiKey ?? '',
        tvdbSubscriberPin: tvdbSubscriberPin ?? '',
        anilistShowAdultContent: preferences.readAniListShowAdultContent(),
        anilistTitleLanguage: workspaceTitleLanguage,
        anilistLibraryDefaultPage: AniListLibraryDefaultPage.fromName(
          workspaceDefaultPage,
        ),
        anilistSavedAccounts: savedAniListAccounts,
        canonicalLibraryOwnerAniListId: canonicalLibraryOwnerAniListId,
        anilistScoreFormat: preferences.readAniListScoreFormat(),
        soraWebProxyUrl: preferences.readSoraWebProxyUrl(),
        startupPage: AppStartupPage.fromName(preferences.readStartupPage()),
        primaryTrackerSource: TrackerSource.fromName(
          preferences.readPrimaryTrackerSource(),
        ),
        malAccessToken: malToken ?? '',
        malRefreshToken: malRefresh ?? '',
        malExpiresAt: malExpiresAt,
        malViewerId: preferences.readMalViewerId(),
        malViewerName: preferences.readMalViewerName(),
        malAvatarUrl: preferences.readMalAvatarUrl(),
        malUseCustomCredentials: preferences.readMalUseCustomCredentials(),
        malCustomClientIdDesktop: preferences.readMalCustomClientIdDesktop(),
        malCustomClientIdMobile: preferences.readMalCustomClientIdMobile(),
        shikimoriAccessToken: shikimoriToken ?? '',
        shikimoriRefreshToken: shikimoriRefresh ?? '',
        shikimoriExpiresAt: shikimoriExpiresAt,
        shikimoriViewerId: preferences.readShikimoriViewerId(),
        shikimoriViewerName: preferences.readShikimoriViewerName(),
        shikimoriAvatarUrl: preferences.readShikimoriAvatarUrl(),
        shikimoriUseCustomCredentials: preferences
            .readShikimoriUseCustomCredentials(),
        shikimoriCustomClientId: preferences.readShikimoriCustomClientId(),
        shikimoriCustomClientSecret: shikimoriCustomClientSecret,
      );
    } finally {
      if (!_persistedReady.isCompleted) _persistedReady.complete();
    }
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
    unawaited(
      _saveWorkspaceValue(
        SettingsPreferences.appLanguageKey,
        locale?.languageCode,
      ),
    );
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
    unawaited(
      _saveWorkspaceValue(SettingsPreferences.discordRpcEnabledKey, value),
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

  void setFanartTvApiKey(String value) {
    state = state.copyWith(fanartTvApiKey: value.trim());
    unawaited(_secureStorage.writeFanartTvApiKey(value));
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

  void setCacheRetention(CacheRetention value) {
    state = state.copyWith(cacheRetention: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveCacheRetention(value.name),
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
    unawaited(
      _saveWorkspaceValue(SettingsPreferences.anilistTitleLanguageKey, value),
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
    unawaited(
      _saveWorkspaceValue(
        SettingsPreferences.anilistLibraryDefaultPageKey,
        value.name,
      ),
    );
  }

  void setAniListScoreFormat(String value) {
    final String normalized = value == 'SMILEY' ? 'POINT_3' : value;
    state = state.copyWith(anilistScoreFormat: normalized);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveAniListScoreFormat(normalized),
      ),
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
    await _persistSavedAniListAccounts(existing);
  }

  Future<void> removeAniListAccount(int viewerId) async {
    final List<AniListSavedAccount> updated = state.anilistSavedAccounts
        .where((AniListSavedAccount a) => a.viewerId != viewerId)
        .toList(growable: false);
    state = state.copyWith(anilistSavedAccounts: updated);
    await _persistSavedAniListAccounts(updated);
  }

  Future<void> switchAniListAccount(AniListSavedAccount account) async {
    await _captureWorkspaceProfile();
    // Save current active account to the saved list before switching.
    if (state.anilistViewerId != null &&
        state.anilistAccessToken.trim().isNotEmpty) {
      await saveAniListAccount(_activeAniListAccount());
    }
    // Remove target account from saved list (it's becoming active).
    await removeAniListAccount(account.viewerId);
    await _activateAniListAccount(account);
  }

  Future<void> connectAniList({
    required AniListOAuthResult oauth,
    required AniListViewer viewer,
  }) async {
    await _captureWorkspaceProfile();
    AniListSavedAccount? restoredWorkspace;
    if (state.anilistViewerId == viewer.id) {
      restoredWorkspace = _activeAniListAccount();
    } else {
      for (final AniListSavedAccount account in state.anilistSavedAccounts) {
        if (account.viewerId == viewer.id) {
          restoredWorkspace = account;
          break;
        }
      }
    }
    // If a different account is currently active, save it to the list.
    if (state.anilistViewerId != null &&
        state.anilistAccessToken.trim().isNotEmpty &&
        state.anilistViewerId != viewer.id) {
      await saveAniListAccount(_activeAniListAccount());
    }
    await removeAniListAccount(viewer.id);
    await _activateAniListAccount(
      AniListSavedAccount(
        viewerId: viewer.id,
        viewerName: viewer.name,
        avatarUrl: viewer.avatarUrl,
        accessToken: oauth.accessToken,
        expiresAt: oauth.expiresAt,
        malConnection:
            restoredWorkspace?.malConnection ??
            const TrackerConnectionSnapshot(),
        shikimoriConnection:
            restoredWorkspace?.shikimoriConnection ??
            const TrackerConnectionSnapshot(),
        primaryTrackerSource:
            restoredWorkspace?.primaryTrackerSource ??
            TrackerSource.anilist.name,
      ),
    );
  }

  Future<void> disconnectAniList() async {
    await _captureWorkspaceProfile();
    state = state.copyWith(
      clearAniListSession: true,
      clearMalSession: true,
      clearShikimoriSession: true,
      primaryTrackerSource: TrackerSource.anilist,
      malUseCustomCredentials: false,
      malCustomClientIdDesktop: '',
      malCustomClientIdMobile: '',
      shikimoriUseCustomCredentials: false,
      shikimoriCustomClientId: '',
      shikimoriCustomClientSecret: '',
    );
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.clearAniListSession();
    await _secureStorage.clearMalSession();
    await _secureStorage.clearShikimoriSession();
    await _secureStorage.writeShikimoriCustomClientSecret('');
    await preferences.saveAniListViewer(id: null, name: null, avatarUrl: null);
    await preferences.saveMalViewer(id: null, name: null, avatarUrl: null);
    await preferences.saveShikimoriViewer(
      id: null,
      name: null,
      avatarUrl: null,
    );
    await preferences.savePrimaryTrackerSource(TrackerSource.anilist.name);
    await preferences.saveMalUseCustomCredentials(false);
    await preferences.saveMalCustomClientIdDesktop('');
    await preferences.saveMalCustomClientIdMobile('');
    await preferences.saveShikimoriUseCustomCredentials(false);
    await preferences.saveShikimoriCustomClientId('');
    await _applyWorkspaceProfile('local');
  }

  List<AniListSavedAccount> driveAniListAccounts() {
    final Map<int, AniListSavedAccount> accounts = <int, AniListSavedAccount>{
      for (final AniListSavedAccount account in state.anilistSavedAccounts)
        account.viewerId: account,
    };
    if (state.anilistViewerId != null &&
        state.anilistAccessToken.trim().isNotEmpty) {
      accounts[state.anilistViewerId!] = _activeAniListAccount();
    }
    return accounts.values.toList(growable: false)..sort(
      (AniListSavedAccount a, AniListSavedAccount b) =>
          a.viewerId.compareTo(b.viewerId),
    );
  }

  Future<void> applyDriveAniListAccounts({
    required List<AniListSavedAccount> accounts,
    required int? preferredActiveViewerId,
  }) async {
    await ready;
    final Map<int, AniListSavedAccount> byId = <int, AniListSavedAccount>{
      for (final AniListSavedAccount account in accounts)
        account.viewerId: account,
    };
    int? activeId = state.anilistViewerId;
    AniListSavedAccount? active = activeId == null ? null : byId[activeId];
    if (activeId != null && active == null && state.hasAniListSession) {
      await disconnectAniList();
      activeId = null;
    }
    if (active == null && !state.hasAniListSession) {
      if (preferredActiveViewerId != null) {
        active = byId[preferredActiveViewerId];
      }
      if (active == null || !active.isValid) {
        for (final AniListSavedAccount candidate in byId.values) {
          if (candidate.isValid) {
            active = candidate;
            break;
          }
        }
      }
      if (active != null && active.isValid) activeId = active.viewerId;
    }
    if (active != null && activeId == active.viewerId) {
      await _activateAniListAccount(active);
    }
    final List<AniListSavedAccount> saved =
        byId.values
            .where(
              (AniListSavedAccount account) => account.viewerId != activeId,
            )
            .toList(growable: false)
          ..sort(
            (AniListSavedAccount a, AniListSavedAccount b) =>
                a.viewerId.compareTo(b.viewerId),
          );
    state = state.copyWith(anilistSavedAccounts: saved);
    await _persistSavedAniListAccounts(saved);
  }

  AniListSavedAccount _activeAniListAccount() {
    return AniListSavedAccount(
      viewerId: state.anilistViewerId!,
      viewerName: state.anilistViewerName ?? 'AniList User',
      avatarUrl: state.anilistAvatarUrl,
      accessToken: state.anilistAccessToken,
      expiresAt: state.anilistExpiresAt ?? DateTime.now(),
      malConnection: TrackerConnectionSnapshot(
        accessToken: state.malAccessToken,
        refreshToken: state.malRefreshToken,
        expiresAt: state.malExpiresAt,
        viewerId: state.malViewerId,
        viewerName: state.malViewerName,
        avatarUrl: state.malAvatarUrl,
        useCustomCredentials: state.malUseCustomCredentials,
        desktopClientId: state.malCustomClientIdDesktop,
        mobileClientId: state.malCustomClientIdMobile,
      ),
      shikimoriConnection: TrackerConnectionSnapshot(
        accessToken: state.shikimoriAccessToken,
        refreshToken: state.shikimoriRefreshToken,
        expiresAt: state.shikimoriExpiresAt,
        viewerId: state.shikimoriViewerId,
        viewerName: state.shikimoriViewerName,
        avatarUrl: state.shikimoriAvatarUrl,
        useCustomCredentials: state.shikimoriUseCustomCredentials,
        clientId: state.shikimoriCustomClientId,
        clientSecret: state.shikimoriCustomClientSecret,
      ),
      primaryTrackerSource: state.primaryTrackerSource.name,
    );
  }

  Future<void> _activateAniListAccount(AniListSavedAccount account) async {
    final TrackerConnectionSnapshot mal = account.malConnection;
    final TrackerConnectionSnapshot shikimori = account.shikimoriConnection;
    final TrackerSource primary = TrackerSource.fromName(
      account.primaryTrackerSource,
    );
    final SettingsPreferences preferences = await _prefs();
    final int ownerId =
        state.canonicalLibraryOwnerAniListId ?? account.viewerId;
    if (state.canonicalLibraryOwnerAniListId == null) {
      await preferences.saveCanonicalLibraryOwnerAniListId(ownerId);
    }
    state = state.copyWith(
      anilistAccessToken: account.accessToken,
      anilistExpiresAt: account.expiresAt,
      anilistViewerId: account.viewerId,
      anilistViewerName: account.viewerName,
      anilistAvatarUrl: account.avatarUrl,
      malAccessToken: mal.accessToken,
      malRefreshToken: mal.refreshToken,
      malExpiresAt: mal.expiresAt,
      malViewerId: mal.viewerId,
      malViewerName: mal.viewerName,
      malAvatarUrl: mal.avatarUrl,
      clearMalSession: !mal.hasSession,
      malUseCustomCredentials: mal.useCustomCredentials,
      malCustomClientIdDesktop: mal.desktopClientId,
      malCustomClientIdMobile: mal.mobileClientId,
      shikimoriAccessToken: shikimori.accessToken,
      shikimoriRefreshToken: shikimori.refreshToken,
      shikimoriExpiresAt: shikimori.expiresAt,
      shikimoriViewerId: shikimori.viewerId,
      shikimoriViewerName: shikimori.viewerName,
      shikimoriAvatarUrl: shikimori.avatarUrl,
      clearShikimoriSession: !shikimori.hasSession,
      shikimoriUseCustomCredentials: shikimori.useCustomCredentials,
      shikimoriCustomClientId: shikimori.clientId,
      shikimoriCustomClientSecret: shikimori.clientSecret,
      primaryTrackerSource: primary,
      canonicalLibraryOwnerAniListId: ownerId,
    );

    await _secureStorage.writeAniListAccessToken(account.accessToken);
    await _secureStorage.writeAniListExpiresAt(account.expiresAt);
    await preferences.saveAniListViewer(
      id: account.viewerId,
      name: account.viewerName,
      avatarUrl: account.avatarUrl,
    );
    await _secureStorage.writeMalAccessToken(mal.accessToken);
    await _secureStorage.writeMalRefreshToken(mal.refreshToken);
    await _secureStorage.writeMalExpiresAt(mal.expiresAt);
    await preferences.saveMalViewer(
      id: mal.viewerId,
      name: mal.viewerName,
      avatarUrl: mal.avatarUrl,
    );
    await preferences.saveMalUseCustomCredentials(mal.useCustomCredentials);
    await preferences.saveMalCustomClientIdDesktop(mal.desktopClientId);
    await preferences.saveMalCustomClientIdMobile(mal.mobileClientId);
    await _secureStorage.writeShikimoriAccessToken(shikimori.accessToken);
    await _secureStorage.writeShikimoriRefreshToken(shikimori.refreshToken);
    await _secureStorage.writeShikimoriExpiresAt(shikimori.expiresAt);
    await preferences.saveShikimoriViewer(
      id: shikimori.viewerId,
      name: shikimori.viewerName,
      avatarUrl: shikimori.avatarUrl,
    );
    await preferences.saveShikimoriUseCustomCredentials(
      shikimori.useCustomCredentials,
    );
    await preferences.saveShikimoriCustomClientId(shikimori.clientId);
    await _secureStorage.writeShikimoriCustomClientSecret(
      shikimori.clientSecret,
    );
    await preferences.clearShikimoriCustomClientSecret();
    await preferences.savePrimaryTrackerSource(primary.name);
    await _applyWorkspaceProfile(_workspaceIdFor(account.viewerId));
  }

  // Tracker primary source + custom credentials

  void setPrimaryTrackerSource(TrackerSource value) {
    state = state.copyWith(primaryTrackerSource: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) =>
            prefs.savePrimaryTrackerSource(value.name),
      ),
    );
  }

  void setMalUseCustomCredentials(bool value) {
    state = state.copyWith(malUseCustomCredentials: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveMalUseCustomCredentials(value),
      ),
    );
  }

  void setMalCustomClientIdDesktop(String value) {
    state = state.copyWith(malCustomClientIdDesktop: value.trim());
    unawaited(
      _save(
        (SettingsPreferences prefs) =>
            prefs.saveMalCustomClientIdDesktop(value),
      ),
    );
  }

  void setMalCustomClientIdMobile(String value) {
    state = state.copyWith(malCustomClientIdMobile: value.trim());
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveMalCustomClientIdMobile(value),
      ),
    );
  }

  void setShikimoriUseCustomCredentials(bool value) {
    state = state.copyWith(shikimoriUseCustomCredentials: value);
    unawaited(
      _save(
        (SettingsPreferences prefs) =>
            prefs.saveShikimoriUseCustomCredentials(value),
      ),
    );
  }

  void setShikimoriCustomClientId(String value) {
    state = state.copyWith(shikimoriCustomClientId: value.trim());
    unawaited(
      _save(
        (SettingsPreferences prefs) => prefs.saveShikimoriCustomClientId(value),
      ),
    );
  }

  void setShikimoriCustomClientSecret(String value) {
    state = state.copyWith(shikimoriCustomClientSecret: value.trim());
    unawaited(
      _secureStorage.writeShikimoriCustomClientSecret(value).then((_) async {
        final SettingsPreferences preferences = await _prefs();
        await preferences.clearShikimoriCustomClientSecret();
      }),
    );
  }

  // MyAnimeList session

  Future<void> connectMal({
    required OAuthTokenBundle tokens,
    required TrackerViewer viewer,
  }) async {
    state = state.copyWith(
      malAccessToken: tokens.accessToken,
      malRefreshToken: tokens.refreshToken,
      malExpiresAt: tokens.expiresAt,
      malViewerId: viewer.id,
      malViewerName: viewer.name,
      malAvatarUrl: viewer.avatarUrl,
    );
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.writeMalAccessToken(tokens.accessToken);
    await _secureStorage.writeMalRefreshToken(tokens.refreshToken);
    await _secureStorage.writeMalExpiresAt(tokens.expiresAt);
    await preferences.saveMalViewer(
      id: viewer.id,
      name: viewer.name,
      avatarUrl: viewer.avatarUrl,
    );
  }

  Future<void> disconnectMal() async {
    state = state.copyWith(clearMalSession: true);
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.clearMalSession();
    await preferences.saveMalViewer(id: null, name: null, avatarUrl: null);
  }

  /// Refreshes the MAL access token using the stored refresh token, persisting
  /// the new tokens. Returns the fresh access token, or null on failure.
  Future<String?> refreshMalToken() async {
    final String refresh = state.malRefreshToken.trim();
    // A MAL refresh token can only be refreshed with the client id of the app
    // that issued it. A given build only ever logs in via one platform's app,
    // so the current platform selects the matching client id.
    final String clientId = state.effectiveMalClientId(
      isMobile: _isMobilePlatform,
    );
    if (state.malUseCustomCredentials && clientId.isEmpty) return null;
    if (refresh.isEmpty) return null;
    try {
      final OAuthTokenBundle tokens = await MalOAuthService().refresh(
        clientId: clientId,
        refreshToken: refresh,
        isMobile: _isMobilePlatform,
      );
      state = state.copyWith(
        malAccessToken: tokens.accessToken,
        malRefreshToken: tokens.refreshToken.isEmpty
            ? state.malRefreshToken
            : tokens.refreshToken,
        malExpiresAt: tokens.expiresAt,
      );
      await _secureStorage.writeMalAccessToken(tokens.accessToken);
      if (tokens.refreshToken.isNotEmpty) {
        await _secureStorage.writeMalRefreshToken(tokens.refreshToken);
      }
      await _secureStorage.writeMalExpiresAt(tokens.expiresAt);
      return tokens.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Returns a non-expired MAL access token, refreshing proactively if needed.
  Future<String?> validMalAccessToken() async {
    if (!state.hasMalSession) return null;
    final DateTime? expiresAt = state.malExpiresAt;
    if (expiresAt != null && expiresAt.isAfter(DateTime.now())) {
      return state.malAccessToken.trim();
    }
    return refreshMalToken();
  }

  // Shikimori session

  Future<void> connectShikimori({
    required OAuthTokenBundle tokens,
    required TrackerViewer viewer,
  }) async {
    state = state.copyWith(
      shikimoriAccessToken: tokens.accessToken,
      shikimoriRefreshToken: tokens.refreshToken,
      shikimoriExpiresAt: tokens.expiresAt,
      shikimoriViewerId: viewer.id,
      shikimoriViewerName: viewer.name,
      shikimoriAvatarUrl: viewer.avatarUrl,
    );
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.writeShikimoriAccessToken(tokens.accessToken);
    await _secureStorage.writeShikimoriRefreshToken(tokens.refreshToken);
    await _secureStorage.writeShikimoriExpiresAt(tokens.expiresAt);
    await preferences.saveShikimoriViewer(
      id: viewer.id,
      name: viewer.name,
      avatarUrl: viewer.avatarUrl,
    );
  }

  Future<void> disconnectShikimori() async {
    state = state.copyWith(clearShikimoriSession: true);
    final SettingsPreferences preferences = await _prefs();
    await _secureStorage.clearShikimoriSession();
    await preferences.saveShikimoriViewer(
      id: null,
      name: null,
      avatarUrl: null,
    );
  }

  Future<String?> refreshShikimoriToken() async {
    final String refresh = state.shikimoriRefreshToken.trim();
    final String clientId = state.effectiveShikimoriClientId;
    final String clientSecret = state.effectiveShikimoriClientSecret;
    if (refresh.isEmpty || !state.shikimoriConfigured) {
      return null;
    }
    try {
      final OAuthTokenBundle tokens = await ShikimoriOAuthService().refresh(
        clientId: clientId,
        clientSecret: clientSecret,
        refreshToken: refresh,
      );
      state = state.copyWith(
        shikimoriAccessToken: tokens.accessToken,
        shikimoriRefreshToken: tokens.refreshToken.isEmpty
            ? state.shikimoriRefreshToken
            : tokens.refreshToken,
        shikimoriExpiresAt: tokens.expiresAt,
      );
      await _secureStorage.writeShikimoriAccessToken(tokens.accessToken);
      if (tokens.refreshToken.isNotEmpty) {
        await _secureStorage.writeShikimoriRefreshToken(tokens.refreshToken);
      }
      await _secureStorage.writeShikimoriExpiresAt(tokens.expiresAt);
      return tokens.accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<String?> validShikimoriAccessToken() async {
    if (!state.hasShikimoriSession) return null;
    final DateTime? expiresAt = state.shikimoriExpiresAt;
    if (expiresAt != null && expiresAt.isAfter(DateTime.now())) {
      return state.shikimoriAccessToken.trim();
    }
    return refreshShikimoriToken();
  }

  Future<void> _save(
    Future<void> Function(SettingsPreferences preferences) save,
  ) async {
    await save(await _prefs());
  }

  String _workspaceIdFor(int? viewerId) =>
      viewerId == null ? 'local' : 'anilist:$viewerId';

  Future<void> _saveWorkspaceValue(String key, Object? value) async {
    final SharedPreferences raw = await SharedPreferences.getInstance();
    await WorkspacePreferencesStore(
      raw,
    ).write(_workspaceIdFor(state.anilistViewerId), key, value);
    if (ref.mounted) {
      ref.read(drivePreferencesRevisionProvider.notifier).changed();
    }
  }

  Future<void> _captureWorkspaceProfile() async {
    final SharedPreferences raw = await SharedPreferences.getInstance();
    await WorkspacePreferencesStore(raw).captureActiveProfile(
      workspaceId: _workspaceIdFor(state.anilistViewerId),
      appLanguage: state.appLocale?.languageCode,
      discordRpcEnabled: state.discordRpcEnabled,
      titleLanguage: state.anilistTitleLanguage,
      defaultLibraryPage: state.anilistLibraryDefaultPage.name,
    );
  }

  Future<void> _applyWorkspaceProfile(String workspaceId) async {
    final SharedPreferences raw = await SharedPreferences.getInstance();
    final WorkspacePreferencesStore store = WorkspacePreferencesStore(raw);
    final String? language =
        store.read(workspaceId, SettingsPreferences.appLanguageKey) as String?;
    final bool discord =
        store.read(workspaceId, SettingsPreferences.discordRpcEnabledKey)
            as bool? ??
        true;
    final String titleLanguage =
        store.read(workspaceId, SettingsPreferences.anilistTitleLanguageKey)
            as String? ??
        'ROMAJI';
    final AniListLibraryDefaultPage defaultPage =
        AniListLibraryDefaultPage.fromName(
          store.read(
                workspaceId,
                SettingsPreferences.anilistLibraryDefaultPageKey,
              )
              as String?,
        );
    final Locale? locale = SettingsState._supportedLocaleFromLanguage(language);
    state = state.copyWith(
      appLocale: locale,
      clearAppLocale: locale == null,
      discordRpcEnabled: discord,
      anilistTitleLanguage: titleLanguage,
      anilistLibraryDefaultPage: defaultPage,
    );
    if (language == null) {
      await raw.remove(SettingsPreferences.appLanguageKey);
    } else {
      await raw.setString(SettingsPreferences.appLanguageKey, language);
    }
    await raw.setBool(SettingsPreferences.discordRpcEnabledKey, discord);
    await raw.setString(
      SettingsPreferences.anilistTitleLanguageKey,
      titleLanguage,
    );
    await raw.setString(
      SettingsPreferences.anilistLibraryDefaultPageKey,
      defaultPage.name,
    );
    if (ref.mounted) {
      ref.read(drivePreferencesRevisionProvider.notifier).changed();
    }
  }

  Future<void> reloadDrivePreferences() async {
    await ready;
    final SettingsPreferences preferences = await _prefs();
    state = state.copyWith(
      tmdbUseCustomKey: preferences.readTmdbUseCustomKey(),
      tmdbReadAccessToken:
          (await _secureStorage.readTmdbReadAccessToken()) ?? '',
      fanartTvApiKey: (await _secureStorage.readFanartTvApiKey()) ?? '',
      tmdbLanguage: preferences.readTmdbLanguage(),
      tmdbRegion: preferences.readTmdbRegion(),
      tmdbShowAdultContent: preferences.readTmdbShowAdultContent(),
      tvdbEnabled: preferences.readTvdbEnabled(),
      tvdbApiKey: (await _secureStorage.readTvdbApiKey()) ?? '',
      tvdbSubscriberPin: (await _secureStorage.readTvdbSubscriberPin()) ?? '',
      soraWebProxyUrl: preferences.readSoraWebProxyUrl(),
      anilistMobileClientId: preferences.readAniListMobileClientId(),
      anilistDesktopClientId: preferences.readAniListDesktopClientId(),
      anilistDesktopPort: preferences.readAniListDesktopPort(),
    );
    await _applyWorkspaceProfile(_workspaceIdFor(state.anilistViewerId));
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
