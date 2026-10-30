import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/request_cancellation_scope.dart';
import '../../../core/utils/settings_preferences.dart';
import '../../notifications/airing_notification_scheduler.dart';
import '../../settings/application/settings_state.dart';
import '../../settings/data/workspace_preferences_store.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../domain/anilist_profile_models.dart';

final aniListUserSettingsClientProvider = Provider<AniListApiClient>((ref) {
  final account = ref.watch(
    settingsProvider.select(
      (settings) => (settings.anilistViewerId, settings.anilistAccessToken),
    ),
  );
  final requests = RequestCancellationScope();
  ref.onDispose(() => requests.cancel('AniList account changed.'));
  return AniListApiClient(
    accessToken: account.$2.trim(),
    cancellationScope: requests,
  );
});

// Remote settings depend only on the account, never on cache notifications or
// unrelated local preferences. Rebuilding the local projection reuses this read.
final aniListRemoteUserSettingsProvider =
    AsyncNotifierProvider<
      AniListRemoteUserSettingsController,
      AniListUserSettings
    >(AniListRemoteUserSettingsController.new, retry: (_, _) => null);

class AniListRemoteUserSettingsController
    extends AsyncNotifier<AniListUserSettings> {
  @override
  Future<AniListUserSettings> build() =>
      ref.watch(aniListUserSettingsClientProvider).fetchUserSettings();

  void accept(AniListUserSettings settings) => state = AsyncData(settings);
}

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
    ref.watch(drivePreferencesRevisionProvider);
    ref.watch(
      settingsProvider.select(
        (settings) => (
          settings.anilistViewerId,
          settings.anilistAccessToken,
          settings.hasAniListSession,
          settings.anilistTitleLanguage,
          settings.anilistShowAdultContent,
          settings.anilistScoreFormat,
        ),
      ),
    );
    final SettingsState settings = ref.read(settingsProvider);
    final remoteSettings = settings.hasAniListSession
        ? ref.watch(aniListRemoteUserSettingsProvider.future)
        : null;
    final settingsController = ref.read(settingsProvider.notifier);
    final AniListUserSettings fallback = _fallbackFromSettings(settings);
    final SharedPreferences rawPreferences =
        await SharedPreferences.getInstance();
    final SettingsPreferences prefs = SettingsPreferences(rawPreferences);
    final WorkspacePreferencesStore workspaceStore = WorkspacePreferencesStore(
      rawPreferences,
    );
    final AniListUserSettings? cached = _decodeCache(
      workspaceStore.read(
                _workspaceId(settings),
                WorkspacePreferencesStore.userSettingsCacheKey,
              )
              as String? ??
          prefs.readAniListUserSettingsCache(),
    );

    if (!settings.hasAniListSession) {
      return cached ?? fallback;
    }

    try {
      final AniListUserSettings remote = await remoteSettings!;
      if (!ref.mounted) return cached ?? fallback;
      final AniListUserSettings local = _withLocalOverrides(
        remote,
        settings,
        localPreferences: cached ?? fallback,
      );
      await prefs.saveAniListUserSettingsCache(jsonEncode(local.toCacheJson()));
      await _saveWorkspaceCache(workspaceStore, settings, local);
      if (!ref.mounted) return local;
      settingsController.setAniListShowAdultContent(local.displayAdultContent);
      settingsController.setAniListScoreFormat(local.scoreFormat);
      return local;
    } catch (_) {
      return cached ?? fallback;
    }
  }

  Future<AniListUserSettings> save(AniListUserSettings draft) async {
    final SettingsState settings = ref.read(settingsProvider);
    final client = settings.hasAniListSession
        ? ref.read(aniListUserSettingsClientProvider)
        : null;
    final SettingsController settingsController = ref.read(
      settingsProvider.notifier,
    );
    final SharedPreferences rawPreferences =
        await SharedPreferences.getInstance();
    if (!_isCurrentAccount(settings)) return draft;
    final SettingsPreferences prefs = SettingsPreferences(rawPreferences);
    final WorkspacePreferencesStore workspaceStore = WorkspacePreferencesStore(
      rawPreferences,
    );
    final AniListUserSettings? previous = state.hasValue
        ? state.requireValue
        : null;
    if (!settings.hasAniListSession) {
      await prefs.saveAniListUserSettingsCache(jsonEncode(draft.toCacheJson()));
      await _saveWorkspaceCache(workspaceStore, settings, draft);
      if (!_isCurrentAccount(settings)) return draft;
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
        (_decodeCache(
                  workspaceStore.read(
                            _workspaceId(settings),
                            WorkspacePreferencesStore.userSettingsCacheKey,
                          )
                          as String? ??
                      prefs.readAniListUserSettingsCache(),
                ) ??
                previous ??
                draft)
            .copyWith(airingNotificationScope: draft.airingNotificationScope);
    await prefs.saveAniListUserSettingsCache(
      jsonEncode(localPreferences.toCacheJson()),
    );
    await _saveWorkspaceCache(workspaceStore, settings, localPreferences);
    state = AsyncData<AniListUserSettings>(draft);
    if (_shouldResetAiringNotifications(previous, draft)) {
      await AiringNotificationScheduler.cancelAll();
    }
    if (!_isCurrentAccount(settings)) return draft;
    final AniListUserSettings updated = await client!.updateUserSettings(draft);
    if (!_isCurrentAccount(settings)) {
      return draft;
    }
    ref.read(aniListRemoteUserSettingsProvider.notifier).accept(updated);
    final AniListUserSettings local = updated.copyWith(
      titleLanguage: draft.titleLanguage == 'RUSSIAN' ? 'RUSSIAN' : null,
      airingNotificationScope: draft.airingNotificationScope,
    );
    await prefs.saveAniListUserSettingsCache(jsonEncode(local.toCacheJson()));
    await _saveWorkspaceCache(workspaceStore, settings, local);
    if (!_isCurrentAccount(settings)) return draft;
    settingsController.setAniListTitleLanguage(local.titleLanguage);
    settingsController.setAniListShowAdultContent(local.displayAdultContent);
    settingsController.setAniListScoreFormat(local.scoreFormat);
    state = AsyncData<AniListUserSettings>(local);
    return local;
  }

  bool _isCurrentAccount(SettingsState settings) {
    if (!ref.mounted) return false;
    final current = ref.read(settingsProvider);
    return current.anilistViewerId == settings.anilistViewerId &&
        current.anilistAccessToken == settings.anilistAccessToken;
  }

  String _workspaceId(SettingsState settings) =>
      settings.anilistViewerId == null
      ? 'local'
      : 'anilist:${settings.anilistViewerId}';

  Future<void> _saveWorkspaceCache(
    WorkspacePreferencesStore store,
    SettingsState settings,
    AniListUserSettings value,
  ) async {
    final String workspaceId = _workspaceId(settings);
    final values = <String, String>{
      WorkspacePreferencesStore.userSettingsCacheKey: jsonEncode(
        value.toCacheJson(),
      ),
      WorkspacePreferencesStore.airingScopeKey:
          value.airingNotificationScope.name,
    };
    bool changed = false;
    for (final entry in values.entries) {
      if (store.read(workspaceId, entry.key) == entry.value) continue;
      await store.write(workspaceId, entry.key, entry.value);
      changed = true;
    }
    if (changed && ref.mounted) {
      ref.read(drivePreferencesRevisionProvider.notifier).changed();
    }
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
