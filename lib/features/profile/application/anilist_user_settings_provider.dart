import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/settings_preferences.dart';
import '../../notifications/airing_notification_scheduler.dart';
import '../../settings/application/settings_state.dart';
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
      final AniListUserSettings local = _withLocalOverrides(
        remote,
        settings,
        localPreferences: cached ?? fallback,
      );
      await prefs.saveAniListUserSettingsCache(jsonEncode(local.toCacheJson()));
      return local;
    } catch (_) {
      return cached ?? fallback;
    }
  }

  Future<AniListUserSettings> save(AniListUserSettings draft) async {
    final SettingsState settings = ref.read(settingsProvider);
    final SettingsController settingsController = ref.read(
      settingsProvider.notifier,
    );
    final SettingsPreferences prefs = SettingsPreferences(
      await SharedPreferences.getInstance(),
    );
    final AniListUserSettings? previous = state.hasValue
        ? state.requireValue
        : null;
    if (!settings.hasAniListSession) {
      await prefs.saveAniListUserSettingsCache(jsonEncode(draft.toCacheJson()));
      settingsController.setAniListTitleLanguage(draft.titleLanguage);
      settingsController.setAniListShowAdultContent(draft.displayAdultContent);
      settingsController.setAniListScoreFormat(draft.scoreFormat);
      if (_shouldResetAiringNotifications(previous, draft)) {
        await AiringNotificationScheduler.cancelAll();
      }
      state = AsyncData<AniListUserSettings>(draft);
      return draft;
    }

    final AniListUserSettings localPreferences =
        (_decodeCache(prefs.readAniListUserSettingsCache()) ??
                previous ??
                draft)
            .copyWith(airingNotificationScope: draft.airingNotificationScope);
    await prefs.saveAniListUserSettingsCache(
      jsonEncode(localPreferences.toCacheJson()),
    );
    state = AsyncData<AniListUserSettings>(draft);
    if (_shouldResetAiringNotifications(previous, draft)) {
      await AiringNotificationScheduler.cancelAll();
    }
    final AniListUserSettings updated = await _client(
      settings,
    ).updateUserSettings(draft);
    final AniListUserSettings local = updated.copyWith(
      titleLanguage: draft.titleLanguage == 'RUSSIAN' ? 'RUSSIAN' : null,
      airingNotificationScope: draft.airingNotificationScope,
    );
    await prefs.saveAniListUserSettingsCache(jsonEncode(local.toCacheJson()));
    settingsController.setAniListTitleLanguage(local.titleLanguage);
    settingsController.setAniListShowAdultContent(local.displayAdultContent);
    settingsController.setAniListScoreFormat(local.scoreFormat);
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

  AniListUserSettings _withLocalOverrides(
    AniListUserSettings remote,
    SettingsState settings, {
    required AniListUserSettings localPreferences,
  }) {
    return remote.copyWith(
      titleLanguage: settings.anilistTitleLanguage == 'RUSSIAN'
          ? 'RUSSIAN'
          : null,
      airingNotificationScope: localPreferences.airingNotificationScope,
    );
  }

  bool _shouldResetAiringNotifications(
    AniListUserSettings? previous,
    AniListUserSettings next,
  ) {
    if (!next.airingNotifications) return true;
    if (previous == null) return false;
    return previous.airingNotifications != next.airingNotifications ||
        previous.airingNotificationScope != next.airingNotificationScope;
  }
}
