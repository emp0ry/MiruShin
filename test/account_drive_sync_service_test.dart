import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/utils/settings_preferences.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/settings/data/account_drive_sync_service.dart';
import 'package:mirushin/features/settings/domain/account_sync_models.dart';
import 'package:mirushin/features/tracking/data/oauth_token_bundle.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'account replica restores connections and propagates tombstones',
    () async {
      final _MemoryAccountCloud cloud = _MemoryAccountCloud();
      var clock = DateTime.utc(2026, 9, 24, 12);
      DateTime now() {
        clock = clock.add(const Duration(seconds: 1));
        return clock;
      }

      final AniListSavedAccount accountA = _account(
        viewerId: 1,
        name: 'Alice',
        malViewerId: 101,
        shikimoriViewerId: 201,
      );
      final AniListSavedAccount accountB = _account(
        viewerId: 2,
        name: 'Bob',
        malViewerId: 102,
        shikimoriViewerId: 202,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferencesA =
          await SharedPreferences.getInstance();
      final AccountDriveSyncResult uploaded =
          await AccountDriveSyncService(
            preferences: preferencesA,
            now: now,
          ).sync(
            cloud: cloud,
            deviceId: 'device-a',
            localAccounts: <AniListSavedAccount>[accountA, accountB],
            activeViewerId: 1,
          );
      expect(uploaded.pushedSegment, isTrue);
      expect(cloud.files, hasLength(1));

      final Map<String, Object> savedDeviceA = <String, Object>{
        for (final String key in preferencesA.getKeys())
          if (preferencesA.get(key) case final Object value) key: value,
      };

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferencesB =
          await SharedPreferences.getInstance();
      final AccountDriveSyncResult restored =
          await AccountDriveSyncService(
            preferences: preferencesB,
            now: now,
          ).sync(
            cloud: cloud,
            deviceId: 'device-b',
            localAccounts: const <AniListSavedAccount>[],
            activeViewerId: null,
          );
      expect(restored.localStateChanged, isTrue);
      expect(restored.preferredActiveViewerId, 1);
      expect(restored.accounts, hasLength(2));
      expect(
        restored.accounts
            .singleWhere((AniListSavedAccount a) => a.viewerId == 1)
            .malConnection
            .refreshToken,
        'mal-refresh-101',
      );
      expect(
        restored.accounts
            .singleWhere((AniListSavedAccount a) => a.viewerId == 2)
            .shikimoriConnection
            .accessToken,
        'shiki-access-202',
      );

      await AccountDriveSyncService(preferences: preferencesB, now: now).sync(
        cloud: cloud,
        deviceId: 'device-b',
        localAccounts: <AniListSavedAccount>[accountB],
        activeViewerId: 2,
      );
      expect(cloud.files, hasLength(2));

      SharedPreferences.setMockInitialValues(savedDeviceA);
      final SharedPreferences restartedA =
          await SharedPreferences.getInstance();
      final AccountDriveSyncResult mergedBack =
          await AccountDriveSyncService(preferences: restartedA, now: now).sync(
            cloud: cloud,
            deviceId: 'device-a',
            localAccounts: <AniListSavedAccount>[accountA, accountB],
            activeViewerId: 1,
          );
      expect(
        mergedBack.accounts.map((AniListSavedAccount a) => a.viewerId),
        <int>[2],
      );
      expect(mergedBack.preferredActiveViewerId, 2);
    },
  );

  test(
    'switching AniList account switches its MAL and Shikimori bundle',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer container = ProviderContainer(
        overrides: [
          canonicalLibraryDatabaseFactoryProvider.overrideWithValue(
            (String name) =>
                CanonicalLibraryDatabase(NativeDatabase.memory(), name),
          ),
        ],
      );
      addTearDown(container.dispose);
      final SettingsController controller = container.read(
        settingsProvider.notifier,
      );
      await controller.ready;
      final DateTime future = DateTime.now().toUtc().add(
        const Duration(days: 30),
      );

      await controller.connectAniList(
        oauth: AniListOAuthResult(accessToken: 'anilist-a', expiresAt: future),
        viewer: const AniListViewer(id: 1, name: 'Alice'),
      );
      expect(
        container.read(libraryWorkspaceScopeProvider).databaseName,
        'mirushin_canonical_library_v1',
      );
      expect(
        container.read(libraryWorkspaceScopeProvider).replicaNamespace,
        'anilist-1',
      );
      final CanonicalLibraryRepository aliceRepository = container.read(
        canonicalLibraryRepositoryProvider,
      );
      await aliceRepository.initialize();
      final LibraryWorkspaceScope aliceScopeBeforeConnections = container.read(
        libraryWorkspaceScopeProvider,
      );
      await controller.connectMal(
        tokens: OAuthTokenBundle(
          accessToken: 'mal-a',
          refreshToken: 'mal-refresh-a',
          expiresAt: future,
        ),
        viewer: const TrackerViewer(id: 101, name: 'Alice MAL'),
      );
      await controller.connectShikimori(
        tokens: OAuthTokenBundle(
          accessToken: 'shiki-a',
          refreshToken: 'shiki-refresh-a',
          expiresAt: future,
        ),
        viewer: const TrackerViewer(id: 201, name: 'Alice Shiki'),
      );
      expect(
        container.read(libraryWorkspaceScopeProvider),
        aliceScopeBeforeConnections,
        reason: 'Tracker connections must not recreate the library workspace.',
      );
      controller.setAppLocale(const Locale('ru'));
      controller.setDiscordRpcEnabled(false);
      controller.setAniListTitleLanguage('RUSSIAN');
      controller.setAniListLibraryDefaultPage(
        AniListLibraryDefaultPage.completed,
      );

      await controller.connectAniList(
        oauth: AniListOAuthResult(accessToken: 'anilist-b', expiresAt: future),
        viewer: const AniListViewer(id: 2, name: 'Bob'),
      );
      expect(
        container.read(libraryWorkspaceScopeProvider).databaseName,
        'mirushin_canonical_library_anilist_2_v1',
      );
      final CanonicalLibraryRepository bobRepository = container.read(
        canonicalLibraryRepositoryProvider,
      );
      await bobRepository.initialize();
      expect(bobRepository.database, isNot(same(aliceRepository.database)));
      expect(
        await aliceRepository.processedDriveSegmentNames(),
        isEmpty,
        reason:
            'An in-flight Drive sync must retain the previous workspace DB.',
      );
      expect(container.read(settingsProvider).hasMalSession, isFalse);
      expect(container.read(settingsProvider).hasShikimoriSession, isFalse);
      expect(container.read(settingsProvider).appLocale, isNull);
      expect(container.read(settingsProvider).discordRpcEnabled, isTrue);
      expect(container.read(settingsProvider).anilistTitleLanguage, 'ROMAJI');
      controller.setAppLocale(const Locale('ja'));
      controller.setAniListTitleLanguage('ENGLISH');
      controller.setAniListLibraryDefaultPage(AniListLibraryDefaultPage.all);
      await controller.connectMal(
        tokens: OAuthTokenBundle(
          accessToken: 'mal-b',
          refreshToken: 'mal-refresh-b',
          expiresAt: future,
        ),
        viewer: const TrackerViewer(id: 102, name: 'Bob MAL'),
      );
      await controller.connectShikimori(
        tokens: OAuthTokenBundle(
          accessToken: 'shiki-b',
          refreshToken: 'shiki-refresh-b',
          expiresAt: future,
        ),
        viewer: const TrackerViewer(id: 202, name: 'Bob Shiki'),
      );

      final AniListSavedAccount alice = container
          .read(settingsProvider)
          .anilistSavedAccounts
          .singleWhere((AniListSavedAccount account) => account.viewerId == 1);
      await controller.switchAniListAccount(alice);
      final SettingsState switched = container.read(settingsProvider);
      expect(switched.anilistViewerId, 1);
      expect(switched.malViewerId, 101);
      expect(switched.malAccessToken, 'mal-a');
      expect(switched.shikimoriViewerId, 201);
      expect(switched.shikimoriAccessToken, 'shiki-a');
      expect(switched.appLocale, const Locale('ru'));
      expect(switched.discordRpcEnabled, isFalse);
      expect(switched.anilistTitleLanguage, 'RUSSIAN');
      expect(
        switched.anilistLibraryDefaultPage,
        AniListLibraryDefaultPage.completed,
      );
      expect(
        container.read(libraryWorkspaceScopeProvider).databaseName,
        'mirushin_canonical_library_v1',
      );
      final CanonicalLibraryRepository restoredAliceRepository = container.read(
        canonicalLibraryRepositoryProvider,
      );
      expect(
        restoredAliceRepository.database,
        same(aliceRepository.database),
        reason: 'Switching back must reuse the open database by name.',
      );
      expect(await bobRepository.processedDriveSegmentNames(), isEmpty);

      final AniListSavedAccount bob = switched.anilistSavedAccounts.singleWhere(
        (AniListSavedAccount account) => account.viewerId == 2,
      );
      expect(bob.malConnection.viewerId, 102);
      expect(bob.shikimoriConnection.viewerId, 202);
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(SettingsPreferences.anilistSavedAccountsKey),
        isFalse,
      );
    },
  );
}

AniListSavedAccount _account({
  required int viewerId,
  required String name,
  required int malViewerId,
  required int shikimoriViewerId,
}) {
  return AniListSavedAccount(
    viewerId: viewerId,
    viewerName: name,
    accessToken: 'anilist-$viewerId',
    expiresAt: DateTime.utc(2027),
    malConnection: TrackerConnectionSnapshot(
      accessToken: 'mal-access-$malViewerId',
      refreshToken: 'mal-refresh-$malViewerId',
      expiresAt: DateTime.utc(2027),
      viewerId: malViewerId,
      viewerName: '$name MAL',
    ),
    shikimoriConnection: TrackerConnectionSnapshot(
      accessToken: 'shiki-access-$shikimoriViewerId',
      refreshToken: 'shiki-refresh-$shikimoriViewerId',
      expiresAt: DateTime.utc(2027),
      viewerId: shikimoriViewerId,
      viewerName: '$name Shikimori',
    ),
  );
}

class _MemoryAccountCloud implements AccountCloudReplica {
  final Map<String, String> files = <String, String>{};

  @override
  Future<List<AccountReplicaSegment>> pullAccountSegments({
    required Set<String> excluding,
  }) async => files.entries
      .where((MapEntry<String, String> entry) => !excluding.contains(entry.key))
      .map(
        (MapEntry<String, String> entry) =>
            AccountReplicaSegment.decode(entry.value),
      )
      .toList(growable: false);

  @override
  Future<void> pushAccountSegment(AccountReplicaSegment segment) async {
    files.putIfAbsent(segment.fileName, segment.encode);
  }
}
