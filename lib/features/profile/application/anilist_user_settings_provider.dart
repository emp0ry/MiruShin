import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/settings_preferences.dart';
import '../../notifications/airing_notification_scheduler.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../domain/anilist_profile_models.dart';

final aniListUserSettingsProvider =
    AsyncNotifierProvider<AniListUserSettingsController, AniListUserSettings>(
      AniListUserSettingsController.new,
    );

final aniListEffectiveTitleLanguageProvider = Provider<String>((Ref ref) {
  final String fallback = ref.watch(
    settingsProvider.select(
      (SettingsState settings) => settings.anilistTitleLanguage,
    ),
  );
  return ref
      .watch(aniListUserSettingsProvider)
      .maybeWhen(
        data: (AniListUserSettings value) => value.titleLanguage,
        orElse: () => fallback,
      );
});

final aniListEffectiveAdultContentProvider = Provider<bool>((Ref ref) {
  final bool fallback = ref.watch(
    settingsProvider.select(
      (SettingsState settings) => settings.anilistShowAdultContent,
    ),
  );
  return ref
      .watch(aniListUserSettingsProvider)
      .maybeWhen(
        data: (AniListUserSettings value) => value.displayAdultContent,
        orElse: () => fallback,
      );
});

final aniListEffectiveScoreFormatProvider = Provider<String>((Ref ref) {
  final String fallback = ref.watch(
    settingsProvider.select(
      (SettingsState settings) => settings.anilistScoreFormat,
    ),
  );
  return ref
      .watch(aniListUserSettingsProvider)
      .maybeWhen(
        data: (AniListUserSettings value) => value.scoreFormat,
        orElse: () => fallback,
      );
});

class AniListUserSettingsController extends AsyncNotifier<AniListUserSettings> {
  @override
  Future<AniListUserSettings> build() async {
    final SettingsState settings = ref.watch(settingsProvider);
    final AniListUserSettings fallback = _fallbackFromSettings(settings);
    final SettingsPreferences prefs = SettingsPreferences(
      await SharedPreferences.getInstance(),
    );
    final AniListUserSettings? cached = _decodeCache(
      prefs.readAniListUserSettingsCache(),
    );

    if (!settings.hasAniListSession) {
      return cached ?? fallback;
    }

    try {
      final AniListUserSettings remote = await _client(
        settings,
      ).fetchUserSettings();
      final AniListUserSettings local = _withLocalTitleOverride(
        remote,
        settings,
      );
      await prefs.saveAniListUserSettingsCache(
        jsonEncode(local.toCacheJson()),
      );
      return local;
    } catch (_) {
      return cached ?? fallback;
    }
  }

  Future<void> refresh() async {
    final SettingsState settings = ref.read(settingsProvider);
    final AniListUserSettings fallback = _fallbackFromSettings(settings);
    final SettingsPreferences prefs = SettingsPreferences(
      await SharedPreferences.getInstance(),
    );
    if (!settings.hasAniListSession) {
      state = AsyncData<AniListUserSettings>(
        _decodeCache(prefs.readAniListUserSettingsCache()) ?? fallback,
      );
      return;
    }

    state = await AsyncValue.guard(() async {
      final AniListUserSettings remote = await _client(
        settings,
      ).fetchUserSettings();
      final AniListUserSettings local = _withLocalTitleOverride(
        remote,
        settings,
      );
      await prefs.saveAniListUserSettingsCache(
        jsonEncode(local.toCacheJson()),
      );
      return local;
    });
  }

  Future<AniListUserSettings> save(AniListUserSettings draft) async {
    final SettingsState settings = ref.read(settingsProvider);
    final SettingsController settingsController = ref.read(
      settingsProvider.notifier,
    );
    final SettingsPreferences prefs = SettingsPreferences(
      await SharedPreferences.getInstance(),
    );
    if (!settings.hasAniListSession) {
      await prefs.saveAniListUserSettingsCache(jsonEncode(draft.toCacheJson()));
      settingsController.setAniListTitleLanguage(draft.titleLanguage);
      settingsController.setAniListShowAdultContent(draft.displayAdultContent);
      settingsController.setAniListScoreFormat(draft.scoreFormat);
      if (!draft.airingNotifications) {
        await AiringNotificationScheduler.cancelAll();
      }
      state = AsyncData<AniListUserSettings>(draft);
      return draft;
    }

    state = AsyncData<AniListUserSettings>(draft);
    final AniListUserSettings updated = await _client(
      settings,
    ).updateUserSettings(draft);
    final AniListUserSettings local = draft.titleLanguage == 'RUSSIAN'
        ? updated.copyWith(titleLanguage: 'RUSSIAN')
        : updated;
    await prefs.saveAniListUserSettingsCache(jsonEncode(local.toCacheJson()));
    settingsController.setAniListTitleLanguage(local.titleLanguage);
    settingsController.setAniListShowAdultContent(local.displayAdultContent);
    settingsController.setAniListScoreFormat(local.scoreFormat);
    if (!local.airingNotifications) {
      await AiringNotificationScheduler.cancelAll();
    }
    state = AsyncData<AniListUserSettings>(local);
    return local;
  }

  AniListApiClient _client(SettingsState settings) {
    return AniListApiClient(accessToken: settings.anilistAccessToken.trim());
  }

  AniListUserSettings? _decodeCache(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? AniListUserSettings.fromCacheJson(decoded)
          : null;
    } catch (_) {
      return null;
    }
  }

  AniListUserSettings _fallbackFromSettings(SettingsState settings) {
    return AniListUserSettings(
      titleLanguage: settings.anilistTitleLanguage,
      displayAdultContent: settings.anilistShowAdultContent,
      scoreFormat: settings.anilistScoreFormat,
    );
  }

  AniListUserSettings _withLocalTitleOverride(
    AniListUserSettings remote,
    SettingsState settings,
  ) {
    if (settings.anilistTitleLanguage == 'RUSSIAN') {
      return remote.copyWith(titleLanguage: 'RUSSIAN');
    }
    return remote;
  }
}
