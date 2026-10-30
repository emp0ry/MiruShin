import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/profile/application/anilist_profile_provider.dart';
import 'package:mirushin/features/profile/application/anilist_user_settings_provider.dart';
import 'package:mirushin/features/profile/domain/anilist_profile_models.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/settings/data/workspace_preferences_store.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsController {
  @override
  SettingsState build() => SettingsState(
    anilistViewerId: 7,
    anilistAccessToken: 'test-7',
    anilistExpiresAt: DateTime.utc(2100),
  );
  void unrelatedChange() =>
      state = state.copyWith(compactMode: !state.compactMode);
  void switchAccount() =>
      state = state.copyWith(anilistViewerId: 8, anilistAccessToken: 'test-8');
}

class _Client extends AniListApiClient {
  int reads = 0;
  int writes = 0;
  Completer<AniListUserSettings>? gate;
  AniListUserSettings remote = const AniListUserSettings(
    scoreFormat: 'POINT_100',
  );
  @override
  Future<AniListUserSettings> fetchUserSettings() async {
    reads++;
    return gate == null ? remote : gate!.future;
  }

  @override
  Future<AniListUserSettings> updateUserSettings(
    AniListUserSettings settings,
  ) async {
    writes++;
    return remote = settings;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cache notifications and unchanged settings never repeat ViewerSettings',
    () async {
      final client = _Client();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          aniListUserSettingsClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      container.listen(aniListUserSettingsProvider, (_, _) {});
      await container.read(aniListUserSettingsProvider.future);
      await container.pump();
      final profileClient = container.read(aniListProfileClientProvider);
      for (int index = 0; index < 4; index++) {
        container.read(drivePreferencesRevisionProvider.notifier).changed();
        (container.read(settingsProvider.notifier) as _Settings)
            .unrelatedChange();
        await container.pump();
        await container.read(aniListUserSettingsProvider.future);
      }
      expect(client.reads, 1);
      expect(container.read(aniListProfileClientProvider), same(profileClient));
      expect(container.read(settingsProvider).anilistScoreFormat, 'POINT_100');
    },
  );

  test(
    'saved remote settings stay current after a cache reload without a new read',
    () async {
      final client = _Client();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          aniListUserSettingsClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      container.listen(aniListUserSettingsProvider, (_, _) {});
      await container.read(aniListUserSettingsProvider.future);
      await container.pump();
      final draft = const AniListUserSettings(
        titleLanguage: 'RUSSIAN',
        scoreFormat: 'POINT_5',
      );
      await container.read(aniListUserSettingsProvider.notifier).save(draft);
      await container.pump();
      container.read(drivePreferencesRevisionProvider.notifier).changed();
      await container.pump();
      final settings = await container.read(aniListUserSettingsProvider.future);
      expect(client.reads, 1);
      expect(client.writes, 1);
      expect(settings.titleLanguage, 'RUSSIAN');
      expect(settings.scoreFormat, 'POINT_5');
    },
  );

  test(
    'late settings from an old account cannot replace the new account cache',
    () async {
      final old = _Client()..gate = Completer();
      final current = _Client()
        ..remote = const AniListUserSettings(scoreFormat: 'POINT_5');
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          aniListUserSettingsClientProvider.overrideWith((ref) {
            final id = ref.watch(
              settingsProvider.select((settings) => settings.anilistViewerId),
            );
            return id == 7 ? old : current;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.listen(aniListUserSettingsProvider, (_, _) {});
      await container.pump();
      expect(old.reads, 1);
      (container.read(settingsProvider.notifier) as _Settings).switchAccount();
      await container.pump();
      expect(
        (await container.read(aniListUserSettingsProvider.future)).scoreFormat,
        'POINT_5',
      );
      old.gate!.complete(const AniListUserSettings(scoreFormat: 'POINT_100'));
      await container.pump();
      final store = WorkspacePreferencesStore(
        await SharedPreferences.getInstance(),
      );
      final cache = jsonDecode(
        store.read('anilist:8', WorkspacePreferencesStore.userSettingsCacheKey)
            as String,
      );
      expect(cache['scoreFormat'], 'POINT_5');
      expect(container.read(settingsProvider).anilistScoreFormat, 'POINT_5');
      expect(current.reads, 1);
    },
  );
}
