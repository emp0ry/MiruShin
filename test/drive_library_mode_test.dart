import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/security/app_secure_storage.dart';
import 'package:mirushin/core/utils/settings_preferences.dart';
import 'package:mirushin/features/addons/application/sora_addons_provider.dart';
import 'package:mirushin/features/addons/data/sora_addon_store.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/application/google_drive_sync_controller.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/player/application/playback_activity.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ConnectedDrive extends GoogleDriveSyncController {
  @override
  Future<GoogleDriveSyncState> build() async {
    await super.build();
    return const GoogleDriveSyncState(configured: true, connected: true);
  }
}

class _PendingDrive extends GoogleDriveSyncController {
  int builds = 0;
  final pending = Completer<GoogleDriveSyncState>();

  @override
  Future<GoogleDriveSyncState> build() {
    builds++;
    return pending.future;
  }
}

class _DriveFixture {
  final requests = <RequestOptions>[];
  final libraryEntered = Completer<void>();
  final releaseLibrary = Completer<void>();
  bool stallLibrary = false;

  Dio client() {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests.add(options);
          final path = options.uri.path;
          if (path.endsWith('/changes/startPageToken')) {
            if (!libraryEntered.isCompleted) libraryEntered.complete();
            if (stallLibrary) await releaseLibrary.future;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {'startPageToken': 'page-1'},
              ),
            );
          } else if (path.endsWith('/changes')) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {'changes': [], 'newStartPageToken': 'page-2'},
              ),
            );
          } else if (path.endsWith('/about')) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'user': {'displayName': 'Fixture'},
                },
              ),
            );
          } else if (path.endsWith('/files') && options.method == 'GET') {
            handler.resolve(
              Response(requestOptions: options, data: {'files': []}),
            );
          } else if (options.method == 'POST' || options.method == 'PATCH') {
            handler.resolve(
              Response(requestOptions: options, data: {'id': 'fixture-file'}),
            );
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                message: 'Unexpected request',
              ),
            );
          }
        },
      ),
    );
    return dio;
  }

  bool get hasLibraryRequest => requests.any((request) {
    final query = '${request.queryParameters['q'] ?? ''}';
    return request.uri.path.contains('/changes') ||
        query.contains('.manifest.') ||
        query.contains('.snapshot.');
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<
    ({
      ProviderContainer container,
      _DriveFixture fixture,
      CanonicalLibraryRepository repository,
    })
  >
  harness({bool enabled = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      SettingsPreferences.googleDriveLibrarySyncEnabledKey,
      enabled,
    );
    const storage = AppSecureStorage();
    await storage.writeGoogleDriveAccessToken('fixture-token');
    await storage.writeGoogleDriveExpiresAt(
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final database = CanonicalLibraryDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = CanonicalLibraryRepository(
      database,
      replicaNamespace: 'anilist-1',
      importsLegacyData: false,
    );
    final directory = await Directory.systemTemp.createTemp(
      'mirushin-drive-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final fixture = _DriveFixture();
    final container = ProviderContainer(
      overrides: [
        canonicalLibraryRepositoryProvider.overrideWithValue(repository),
        googleDriveDioFactoryProvider.overrideWithValue(fixture.client),
        googleDriveSyncControllerProvider.overrideWith(_ConnectedDrive.new),
        soraAddonStoreProvider.overrideWithValue(
          SoraAddonStore(supportDirectoryProvider: () async => directory),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).ready;
    await container.read(googleDriveSyncControllerProvider.future);
    return (container: container, fixture: fixture, repository: repository);
  }

  test(
    'default and upgraded devices opt out; the switch persists locally',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).ready;
      expect(
        container.read(settingsProvider).googleDriveLibrarySyncEnabled,
        isFalse,
      );
      container
          .read(settingsProvider.notifier)
          .setGoogleDriveLibrarySyncEnabled(true);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(SettingsPreferences.googleDriveLibrarySyncEnabledKey),
        isTrue,
      );
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      await restarted.read(settingsProvider.notifier).ready;
      expect(
        restarted.read(settingsProvider).googleDriveLibrarySyncEnabled,
        isTrue,
      );
    },
  );

  test(
    'manual, local and periodic-style polls never request full library while off',
    () async {
      final h = await harness();
      final drive = h.container.read(
        googleDriveSyncControllerProvider.notifier,
      );
      await h.repository.saveEpisodeProgress(
        mediaId: 'anilist:10',
        season: 1,
        episode: 1,
        positionSeconds: 100,
      );
      final fullPending = await h.repository.pendingDriveDeliveryCount();
      await drive.syncNow();
      await h.repository.saveEpisodeProgress(
        mediaId: 'anilist:10',
        season: 1,
        episode: 1,
        positionSeconds: 200,
      );
      await drive.syncNow(background: true, localChangesOnly: true);
      await drive.syncNow(background: true, remoteChangesOnly: true);
      expect(h.fixture.hasLibraryRequest, isFalse);
      expect(
        h.fixture.requests.any(
          (request) => '${request.queryParameters['q']}'.contains('.playback.'),
        ),
        isTrue,
      );
      expect(
        h.fixture.requests.any(
          (request) =>
              '${request.queryParameters['q']}'.contains('accounts.segment'),
        ),
        isTrue,
      );
      expect(
        h.fixture.requests.any(
          (request) =>
              '${request.queryParameters['q']}'.contains('preferences.segment'),
        ),
        isTrue,
      );
      expect(
        h.fixture.requests.any(
          (request) =>
              '${request.queryParameters['q']}'.contains('addons.segment'),
        ),
        isTrue,
      );
      expect(
        await h.repository.pendingDriveDeliveryCount(),
        greaterThanOrEqualTo(fullPending),
      );
      expect(
        await h.repository
            .watchPendingCloudDeliveryCount(includeLibrary: false)
            .first,
        0,
      );
      expect(
        h.container
            .read(googleDriveSyncControllerProvider)
            .requireValue
            .cloudEntryCount,
        isNull,
      );
      expect(
        h.container
            .read(googleDriveSyncControllerProvider)
            .requireValue
            .lastError,
        isNull,
      );
    },
  );

  test('startup and resume use lightweight mode', () async {
    final h = await harness();
    h.container.read(googleDriveSyncLifecycleProvider);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.container
        .read(googleDriveSyncControllerProvider.notifier)
        .syncNow();
    expect(h.fixture.requests, isNotEmpty);
    expect(h.fixture.hasLibraryRequest, isFalse);
    h.container.read(googleDriveSyncLifecycleProvider)();
  });

  test('enabled remote poll still reads the full library protocol', () async {
    final h = await harness(enabled: true);
    await h.container
        .read(googleDriveSyncControllerProvider.notifier)
        .syncNow(background: true, remoteChangesOnly: true);
    expect(h.fixture.hasLibraryRequest, isTrue);
    expect(await h.repository.driveChangePageToken(), 'page-1');
    expect(
      h.container
          .read(googleDriveSyncControllerProvider)
          .requireValue
          .lastError,
      isNull,
    );
  });

  test(
    'turning off during library networking cancels it and keeps the local queue',
    () async {
      final h = await harness(enabled: true);
      h.fixture.stallLibrary = true;
      await h.repository.saveEpisodeProgress(
        mediaId: 'anilist:10',
        season: 1,
        episode: 1,
        positionSeconds: 100,
      );
      final pending = await h.repository.pendingDriveDeliveryCount();
      final active = h.container
          .read(googleDriveSyncControllerProvider.notifier)
          .syncNow(background: true, remoteChangesOnly: true);
      await h.fixture.libraryEntered.future.timeout(const Duration(seconds: 5));
      h.container
          .read(settingsProvider.notifier)
          .setGoogleDriveLibrarySyncEnabled(false);
      h.fixture.releaseLibrary.complete();
      await active;
      await h.container
          .read(googleDriveSyncControllerProvider.notifier)
          .syncNow();
      expect(await h.repository.driveChangePageToken(), isNull);
      expect(await h.repository.pendingDriveDeliveryCount(), pending);
      expect(
        h.container
            .read(googleDriveSyncControllerProvider)
            .requireValue
            .lastError,
        isNull,
      );
    },
  );

  test(
    'catalog coordinator never initializes a stalled Drive provider while off',
    () async {
      final drive = _PendingDrive();
      final database = CanonicalLibraryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          canonicalLibraryRepositoryProvider.overrideWithValue(
            CanonicalLibraryRepository(database),
          ),
          googleDriveSyncControllerProvider.overrideWith(() => drive),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).ready;
      final snapshot = await container
          .read(trackerSyncCoordinatorProvider)
          .refreshAllConnectedLibraries()
          .timeout(const Duration(seconds: 2));
      expect(snapshot.fromCache, isTrue);
      expect(drive.builds, 0);
    },
  );

  test(
    'playback deferral also covers lightweight manual and remote requests',
    () async {
      final h = await harness();
      h.container.read(playbackActivityProvider.notifier).setActive(true);
      final drive = h.container.read(
        googleDriveSyncControllerProvider.notifier,
      );
      await drive.syncNow();
      await drive.syncNow(background: true, remoteChangesOnly: true);
      expect(h.fixture.requests, isEmpty);
      expect(
        h.container
            .read(googleDriveSyncControllerProvider)
            .requireValue
            .deferredForPlayback,
        isTrue,
      );
    },
  );
}
