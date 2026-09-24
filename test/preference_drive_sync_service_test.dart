import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/security/app_secure_storage.dart';
import 'package:mirushin/core/utils/settings_preferences.dart';
import 'package:mirushin/features/settings/data/preference_drive_sync_service.dart';
import 'package:mirushin/features/settings/data/workspace_preferences_store.dart';
import 'package:mirushin/features/settings/domain/preference_sync_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preferences segment rejects modified payload', () {
    final PreferenceReplicaSegment segment = PreferenceReplicaSegment(
      deviceId: 'a',
      revision: 1,
      createdAt: DateTime.utc(2026, 9, 24),
      values: const <String, PreferenceSyncValue>{},
      tombstones: const <String, PreferenceSyncVersion>{},
    );
    final Map<String, dynamic> wrapper = Map<String, dynamic>.from(
      jsonDecode(segment.encode()) as Map,
    );
    wrapper['payload'] = '${wrapper['payload']} changed';
    expect(
      () => PreferenceReplicaSegment.decode(jsonEncode(wrapper)),
      throwsFormatException,
    );
  });

  test(
    'API, watch, and workspace preferences round-trip with tombstones',
    () async {
      final _MemoryPreferenceCloud cloud = _MemoryPreferenceCloud();
      var clock = DateTime.utc(2026, 9, 24, 12);
      DateTime now() => clock = clock.add(const Duration(seconds: 1));

      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsPreferences.tmdbUseCustomKeyKey: true,
        SettingsPreferences.tmdbLanguageKey: 'ja-JP',
        SettingsPreferences.tmdbRegionKey: 'JP',
        SettingsPreferences.tmdbShowAdultContentKey: true,
        SettingsPreferences.tvdbEnabledKey: true,
        SettingsPreferences.soraWebProxyUrlKey: 'https://proxy.example',
        SettingsPreferences.anilistMobileClientIdKey: 'mobile-client',
        SettingsPreferences.anilistDesktopClientIdKey: 'desktop-client',
        SettingsPreferences.anilistDesktopPortKey: 7357,
        PreferenceDriveSyncService.watchConnectionKey: jsonEncode(
          <String, Object>{
            'mode': 'selfHostedRelay',
            'relayUrl': 'https://relay.example',
          },
        ),
        PreferenceDriveSyncService.trustedRelaysKey: jsonEncode(<String>[
          'https://relay.example',
        ]),
        workspacePreferenceKey('anilist:1', SettingsPreferences.appLanguageKey):
            'ru',
        workspacePreferenceKey('anilist:1', 'library.anilist.ANIME.All.sort'):
            'scoreHighest',
      });
      final SharedPreferences preferencesA =
          await SharedPreferences.getInstance();
      const AppSecureStorage secureA = AppSecureStorage();
      await secureA.writeTmdbReadAccessToken('tmdb-secret');
      await secureA.writeFanartTvApiKey('fanart-secret');
      await secureA.writeTvdbApiKey('tvdb-secret');
      await secureA.writeTvdbSubscriberPin('tvdb-pin');
      final PreferenceDriveSyncResult uploaded =
          await PreferenceDriveSyncService(
            preferences: preferencesA,
            now: now,
          ).sync(cloud: cloud, deviceId: 'device-a');
      expect(uploaded.pushedSegment, isTrue);
      expect(cloud.files, hasLength(1));

      final Map<String, Object> savedA = <String, Object>{
        for (final String key in preferencesA.getKeys())
          if (preferencesA.get(key) case final Object value) key: value,
      };

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferencesB =
          await SharedPreferences.getInstance();
      final PreferenceDriveSyncResult restored =
          await PreferenceDriveSyncService(
            preferences: preferencesB,
            now: now,
          ).sync(cloud: cloud, deviceId: 'device-b');
      expect(restored.localStateChanged, isTrue);
      expect(
        preferencesB.getString(SettingsPreferences.tmdbLanguageKey),
        'ja-JP',
      );
      expect(
        preferencesB.getString(
          workspacePreferenceKey(
            'anilist:1',
            SettingsPreferences.appLanguageKey,
          ),
        ),
        'ru',
      );
      expect(
        preferencesB.getString(PreferenceDriveSyncService.watchConnectionKey),
        contains('relay.example'),
      );
      const AppSecureStorage secureB = AppSecureStorage();
      expect(await secureB.readFanartTvApiKey(), 'fanart-secret');
      expect(await secureB.readTvdbSubscriberPin(), 'tvdb-pin');

      await secureB.writeFanartTvApiKey('');
      await PreferenceDriveSyncService(
        preferences: preferencesB,
        now: now,
      ).sync(cloud: cloud, deviceId: 'device-b');
      expect(cloud.files, hasLength(2));

      SharedPreferences.setMockInitialValues(savedA);
      final SharedPreferences restartedA =
          await SharedPreferences.getInstance();
      await PreferenceDriveSyncService(
        preferences: restartedA,
        now: now,
      ).sync(cloud: cloud, deviceId: 'device-a');
      expect(await const AppSecureStorage().readFanartTvApiKey(), isNull);
    },
  );

  test('legacy library preferences migrate once to every workspace', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'library.anilist.ANIME.All.grid': true,
      'library.anilist.ANIME.paused.formats': <Object>[],
      'library.anilist.ANIME.paused.genres': <Object>['Action', 'Drama'],
      'library.local.sort': 'titleAsc',
      SettingsPreferences.appLanguageKey: 'ja',
    });
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final WorkspacePreferencesStore store = WorkspacePreferencesStore(
      preferences,
    );
    await store.migrateLegacy(viewerIds: const <int>[1, 2]);
    expect(
      preferences.getBool(
        workspacePreferenceKey('anilist:1', 'library.anilist.ANIME.All.grid'),
      ),
      isTrue,
    );
    expect(
      preferences.getString(
        workspacePreferenceKey('anilist:2', 'library.local.sort'),
      ),
      'titleAsc',
    );
    expect(
      preferences.getStringList(
        workspacePreferenceKey(
          'anilist:1',
          'library.anilist.ANIME.paused.formats',
        ),
      ),
      isEmpty,
    );
    expect(
      preferences.getStringList(
        workspacePreferenceKey(
          'anilist:2',
          'library.anilist.ANIME.paused.genres',
        ),
      ),
      <String>['Action', 'Drama'],
    );
    expect(
      preferences.getString(
        workspacePreferenceKey('local', SettingsPreferences.appLanguageKey),
      ),
      'ja',
    );

    await preferences.setBool('library.anilist.ANIME.All.grid', false);
    await store.migrateLegacy(viewerIds: const <int>[1, 2]);
    expect(
      preferences.getBool(
        workspacePreferenceKey('anilist:1', 'library.anilist.ANIME.All.grid'),
      ),
      isTrue,
    );
  });

  test('independent fields changed on two devices merge together', () async {
    final _MemoryPreferenceCloud cloud = _MemoryPreferenceCloud();
    final DateTime changedAt = DateTime.utc(2026, 9, 24, 18);
    final PreferenceSyncVersion deviceA = PreferenceSyncVersion(
      changedAt: changedAt,
      deviceId: 'device-a',
    );
    final PreferenceSyncVersion deviceB = PreferenceSyncVersion(
      changedAt: changedAt,
      deviceId: 'device-b',
    );
    final PreferenceReplicaSegment first = PreferenceReplicaSegment(
      deviceId: 'device-a',
      revision: 1,
      createdAt: changedAt,
      values: <String, PreferenceSyncValue>{
        SettingsPreferences.tmdbRegionKey: PreferenceSyncValue(
          version: deviceA,
          value: 'JP',
        ),
      },
      tombstones: const <String, PreferenceSyncVersion>{},
    );
    final PreferenceReplicaSegment second = PreferenceReplicaSegment(
      deviceId: 'device-b',
      revision: 1,
      createdAt: changedAt,
      values: <String, PreferenceSyncValue>{
        workspacePreferenceKey(
          'anilist:7',
          SettingsPreferences.anilistTitleLanguageKey,
        ): PreferenceSyncValue(
          version: deviceB,
          value: 'RUSSIAN',
        ),
      },
      tombstones: const <String, PreferenceSyncVersion>{},
    );
    cloud.files[first.fileName] = first;
    cloud.files[second.fileName] = second;

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PreferenceDriveSyncResult result = await PreferenceDriveSyncService(
      preferences: preferences,
      now: () => changedAt.add(const Duration(minutes: 1)),
    ).sync(cloud: cloud, deviceId: 'device-c');

    expect(result.pulledSegments, 2);
    expect(preferences.getString(SettingsPreferences.tmdbRegionKey), 'JP');
    expect(
      preferences.getString(
        workspacePreferenceKey(
          'anilist:7',
          SettingsPreferences.anilistTitleLanguageKey,
        ),
      ),
      'RUSSIAN',
    );
  });
}

class _MemoryPreferenceCloud implements PreferenceCloudReplica {
  final Map<String, PreferenceReplicaSegment> files =
      <String, PreferenceReplicaSegment>{};

  @override
  Future<List<PreferenceReplicaSegment>> pullPreferenceSegments({
    required Set<String> excluding,
  }) async => files.entries
      .where(
        (MapEntry<String, PreferenceReplicaSegment> entry) =>
            !excluding.contains(entry.key),
      )
      .map((MapEntry<String, PreferenceReplicaSegment> entry) => entry.value)
      .toList(growable: false);

  @override
  Future<void> pushPreferenceSegment(PreferenceReplicaSegment segment) async {
    files.putIfAbsent(segment.fileName, () => segment);
  }
}
