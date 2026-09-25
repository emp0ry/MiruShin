import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/platform/tv_platform.dart';
import '../../../core/security/app_secure_storage.dart';
import '../../addons/application/addon_sources_provider.dart';
import '../../addons/application/sora_addons_provider.dart';
import '../../addons/data/addon_drive_sync_service.dart';
import '../../player/application/player_settings.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/application/settings_state.dart';
import '../../settings/data/account_drive_sync_service.dart';
import '../../settings/data/preference_drive_sync_service.dart';
import '../../settings/data/workspace_preferences_store.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/application/tracker_library_provider.dart';
import '../../tracking/application/tracker_sync_coordinator.dart';
import '../../tracking/domain/tracker_models.dart';
import '../../watch_party/application/watch_party_connection_settings.dart';
import '../data/google_drive_account_client.dart';
import '../data/google_drive_cloud_replica.dart';
import '../data/google_drive_native_auth.dart';
import '../data/google_drive_oauth_service.dart';
import '../domain/cloud_replica_models.dart';
import 'canonical_library_repository.dart';

const String _googleDriveLastFullSyncAtKey = 'google.drive.lastFullSyncAt.v1';

class GoogleDriveSyncState {
  const GoogleDriveSyncState({
    required this.configured,
    required this.connected,
    this.syncing = false,
    this.lastSyncAt,
    this.lastError,
    this.appliedSegments = 0,
    this.account,
    this.syncStage,
    this.progress,
    this.transferredBytes = 0,
    this.totalBytes = 0,
    this.processedItems = 0,
    this.totalItems = 0,
    this.driveUsageBytes,
    this.driveFileCount,
    this.cloudEntryCount,
    this.localEntryCount,
  });

  final bool configured;
  final bool connected;
  final bool syncing;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int appliedSegments;
  final GoogleDriveAccountProfile? account;
  final String? syncStage;
  final double? progress;
  final int transferredBytes;
  final int totalBytes;
  final int processedItems;
  final int totalItems;
  final int? driveUsageBytes;
  final int? driveFileCount;
  final int? cloudEntryCount;
  final int? localEntryCount;

  GoogleDriveSyncState copyWith({
    bool? configured,
    bool? connected,
    bool? syncing,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
    int? appliedSegments,
    GoogleDriveAccountProfile? account,
    bool clearAccount = false,
    String? syncStage,
    double? progress,
    bool clearProgress = false,
    int? transferredBytes,
    int? totalBytes,
    int? processedItems,
    int? totalItems,
    int? driveUsageBytes,
    int? driveFileCount,
    int? cloudEntryCount,
    int? localEntryCount,
  }) => GoogleDriveSyncState(
    configured: configured ?? this.configured,
    connected: connected ?? this.connected,
    syncing: syncing ?? this.syncing,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastError: clearError ? null : lastError ?? this.lastError,
    appliedSegments: appliedSegments ?? this.appliedSegments,
    account: clearAccount ? null : account ?? this.account,
    syncStage: clearProgress ? null : syncStage ?? this.syncStage,
    progress: clearProgress ? null : progress ?? this.progress,
    transferredBytes: clearProgress
        ? 0
        : transferredBytes ?? this.transferredBytes,
    totalBytes: clearProgress ? 0 : totalBytes ?? this.totalBytes,
    processedItems: clearProgress ? 0 : processedItems ?? this.processedItems,
    totalItems: clearProgress ? 0 : totalItems ?? this.totalItems,
    driveUsageBytes: driveUsageBytes ?? this.driveUsageBytes,
    driveFileCount: driveFileCount ?? this.driveFileCount,
    cloudEntryCount: cloudEntryCount ?? this.cloudEntryCount,
    localEntryCount: localEntryCount ?? this.localEntryCount,
  );
}

final googleDriveSyncControllerProvider =
    AsyncNotifierProvider<GoogleDriveSyncController, GoogleDriveSyncState>(
      GoogleDriveSyncController.new,
    );

final googleDriveSyncLifecycleProvider = Provider<void>((Ref ref) {
  Timer? localPushDebounce;
  Timer? fullSyncDebounce;
  var disposed = false;

  void scheduleLocalPush() {
    if (disposed) return;
    if (fullSyncDebounce?.isActive ?? false) return;
    localPushDebounce?.cancel();
    localPushDebounce = Timer(const Duration(seconds: 8), () {
      if (disposed) return;
      unawaited(
        ref
            .read(googleDriveSyncControllerProvider.notifier)
            .syncNow(background: true, localChangesOnly: true),
      );
    });
  }

  void scheduleFullSync() {
    if (disposed) return;
    localPushDebounce?.cancel();
    localPushDebounce = null;
    fullSyncDebounce?.cancel();
    fullSyncDebounce = Timer(const Duration(seconds: 8), () {
      if (disposed) return;
      unawaited(
        ref
            .read(googleDriveSyncControllerProvider.notifier)
            .syncNow(background: true),
      );
    });
  }

  ref.listen<AsyncValue<GoogleDriveSyncState>>(
    googleDriveSyncControllerProvider,
    (
      AsyncValue<GoogleDriveSyncState>? previous,
      AsyncValue<GoogleDriveSyncState> next,
    ) {
      final bool becameConnected =
          next.value?.connected == true && previous?.value?.connected != true;
      if (becameConnected) {
        unawaited(
          ref
              .read(googleDriveSyncControllerProvider.notifier)
              .syncNow(background: true),
        );
      }
    },
    fireImmediately: true,
  );
  ref.listen<String>(settingsProvider.select(_driveAccountFingerprint), (
    String? previous,
    String next,
  ) {
    if (previous == null || previous == next) return;
    scheduleFullSync();
  });
  ref.listen<String>(settingsProvider.select(_drivePreferenceFingerprint), (
    String? previous,
    String next,
  ) {
    if (previous == null || previous == next) return;
    scheduleFullSync();
  });
  ref.listen<int>(drivePreferencesRevisionProvider, (int? previous, int next) {
    if (previous == null || previous == next) return;
    scheduleFullSync();
  });
  ref.listen<String>(soraAddonsProvider.select(_driveAddonFingerprint), (
    String? previous,
    String next,
  ) {
    if (previous == null || previous == next) return;
    scheduleFullSync();
  });
  ref.listen<String>(
    addonSourcesProvider.select(_driveAddonSourceFingerprint),
    (String? previous, String next) {
      if (previous == null || previous == next) return;
      scheduleFullSync();
    },
  );
  ref.listen<AsyncValue<int>>(pendingDriveDeliveryCountProvider, (
    AsyncValue<int>? previous,
    AsyncValue<int> next,
  ) {
    final int pending = next.value ?? 0;
    if (pending <= 0) {
      localPushDebounce?.cancel();
      localPushDebounce = null;
      return;
    }
    scheduleLocalPush();
  }, fireImmediately: true);
  final Timer timer = Timer.periodic(const Duration(minutes: 15), (_) {
    if (disposed) return;
    unawaited(
      ref
          .read(googleDriveSyncControllerProvider.notifier)
          .syncNow(background: true),
    );
  });
  final AppLifecycleListener lifecycle = AppLifecycleListener(
    onResume: () {
      if (disposed) return;
      unawaited(
        ref
            .read(googleDriveSyncControllerProvider.notifier)
            .syncNow(background: true),
      );
    },
  );
  ref.onDispose(() {
    disposed = true;
    localPushDebounce?.cancel();
    fullSyncDebounce?.cancel();
    timer.cancel();
    lifecycle.dispose();
  });
});

String _driveAccountFingerprint(SettingsState settings) {
  final List<Map<String, dynamic>> saved =
      settings.anilistSavedAccounts
          .map((account) => account.toJson())
          .toList(growable: false)
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              ((a['viewerId'] as num?)?.toInt() ?? 0).compareTo(
                (b['viewerId'] as num?)?.toInt() ?? 0,
              ),
        );
  return jsonEncode(<String, dynamic>{
    'saved': saved,
    'active': <String, dynamic>{
      'viewerId': settings.anilistViewerId,
      'viewerName': settings.anilistViewerName,
      'avatarUrl': settings.anilistAvatarUrl,
      'accessToken': settings.anilistAccessToken,
      'expiresAt': settings.anilistExpiresAt?.toUtc().toIso8601String(),
      'primaryTrackerSource': settings.primaryTrackerSource.name,
      'mal': <String, dynamic>{
        'accessToken': settings.malAccessToken,
        'refreshToken': settings.malRefreshToken,
        'expiresAt': settings.malExpiresAt?.toUtc().toIso8601String(),
        'viewerId': settings.malViewerId,
        'viewerName': settings.malViewerName,
        'avatarUrl': settings.malAvatarUrl,
        'useCustomCredentials': settings.malUseCustomCredentials,
        'desktopClientId': settings.malCustomClientIdDesktop,
        'mobileClientId': settings.malCustomClientIdMobile,
      },
      'shikimori': <String, dynamic>{
        'accessToken': settings.shikimoriAccessToken,
        'refreshToken': settings.shikimoriRefreshToken,
        'expiresAt': settings.shikimoriExpiresAt?.toUtc().toIso8601String(),
        'viewerId': settings.shikimoriViewerId,
        'viewerName': settings.shikimoriViewerName,
        'avatarUrl': settings.shikimoriAvatarUrl,
        'useCustomCredentials': settings.shikimoriUseCustomCredentials,
        'clientId': settings.shikimoriCustomClientId,
        'clientSecret': settings.shikimoriCustomClientSecret,
      },
    },
  });
}

String _drivePreferenceFingerprint(SettingsState settings) =>
    jsonEncode(<String, Object?>{
      'tmdbUseCustomKey': settings.tmdbUseCustomKey,
      'tmdbReadAccessToken': settings.tmdbReadAccessToken,
      'fanartTvApiKey': settings.fanartTvApiKey,
      'tmdbLanguage': settings.tmdbLanguage,
      'tmdbRegion': settings.tmdbRegion,
      'tmdbShowAdultContent': settings.tmdbShowAdultContent,
      'tvdbEnabled': settings.tvdbEnabled,
      'tvdbApiKey': settings.tvdbApiKey,
      'tvdbSubscriberPin': settings.tvdbSubscriberPin,
      'soraWebProxyUrl': settings.soraWebProxyUrl,
      'anilistMobileClientId': settings.anilistMobileClientId,
      'anilistDesktopClientId': settings.anilistDesktopClientId,
      'anilistDesktopPort': settings.anilistDesktopPort,
      'viewerId': settings.anilistViewerId,
      'appLanguage': settings.appLocale?.languageCode,
      'discordRpcEnabled': settings.discordRpcEnabled,
      'titleLanguage': settings.anilistTitleLanguage,
      'defaultLibraryPage': settings.anilistLibraryDefaultPage.name,
    });

String _driveAddonFingerprint(SoraAddonsState state) {
  final List<Map<String, dynamic>> addons =
      state.installed
          .map((addon) {
            final Map<String, dynamic> value = addon.toJson();
            value.remove('installedAt');
            value.remove('updatedAt');
            value.remove('lastCheckedAt');
            value.remove('lastError');
            return value;
          })
          .toList(growable: false)
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              '${a['manifestUrl'] ?? a['id'] ?? ''}'.compareTo(
                '${b['manifestUrl'] ?? b['id'] ?? ''}',
              ),
        );
  return jsonEncode(addons);
}

String _driveAddonSourceFingerprint(AddonSourcesState state) {
  final List<Map<String, dynamic>> sources =
      state.sources.map((source) => source.toJson()).toList(growable: false)
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              '${a['url'] ?? ''}'.compareTo('${b['url'] ?? ''}'),
        );
  return jsonEncode(sources);
}

class GoogleDriveSyncController extends AsyncNotifier<GoogleDriveSyncState> {
  final AppSecureStorage _storage = const AppSecureStorage();
  Future<void>? _activeSync;
  Timer? _localCheckpointRetry;
  Timer? _fullSyncRetry;
  bool _syncAgainRequested = false;
  bool _fullSyncAgainRequested = false;
  bool _activeProgressVisible = false;
  bool _disposed = false;
  bool _shuttingDown = false;
  int _localRetryAttempt = 0;
  int _fullRetryAttempt = 0;

  @override
  Future<GoogleDriveSyncState> build() async {
    _disposed = false;
    _shuttingDown = false;
    ref.onDispose(() {
      _disposed = true;
      _shuttingDown = true;
      _syncAgainRequested = false;
      _fullSyncAgainRequested = false;
      _localCheckpointRetry?.cancel();
      _localCheckpointRetry = null;
      _fullSyncRetry?.cancel();
      _fullSyncRetry = null;
    });
    final bool configured = _googleDriveConfigured;
    bool connected;
    String? accessToken;
    if (configured && GoogleDriveNativeAuthService.isSupported) {
      try {
        final String? nativeToken = await const GoogleDriveNativeAuthService()
            .restoreAccessToken();
        accessToken = nativeToken ?? await _storedAccessToken();
        connected = accessToken != null && accessToken.isNotEmpty;
        if (nativeToken != null && nativeToken.isNotEmpty) {
          await _storeNativeAccessToken(nativeToken);
        }
      } on Object {
        connected = false;
      }
    } else {
      final String refreshToken =
          (await _storage.readGoogleDriveRefreshToken()) ?? '';
      connected = refreshToken.trim().isNotEmpty;
      accessToken = await _storedAccessToken();
    }
    GoogleDriveAccountProfile? account = await _storedAccountProfile();
    if (connected && accessToken != null && accessToken.isNotEmpty) {
      account = await _fetchAndStoreAccountProfile(
        accessToken,
        fallback: account,
      );
    }
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final DateTime? lastFullSyncAt = DateTime.tryParse(
      preferences.getString(_googleDriveLastFullSyncAtKey) ?? '',
    );
    return GoogleDriveSyncState(
      configured: configured,
      connected: connected,
      account: account,
      lastSyncAt: lastFullSyncAt,
    );
  }

  Future<void> connect(GoogleDriveTokenBundle tokens) async {
    await (await SharedPreferences.getInstance()).remove(
      _googleDriveLastFullSyncAtKey,
    );
    await _storage.writeGoogleDriveAccessToken(tokens.accessToken);
    await _storage.writeGoogleDriveRefreshToken(tokens.refreshToken);
    await _storage.writeGoogleDriveExpiresAt(tokens.expiresAt);
    final GoogleDriveAccountProfile? account =
        await _fetchAndStoreAccountProfile(tokens.accessToken);
    if (_disposed || _shuttingDown) return;
    _setState(
      (state.value ??
              GoogleDriveSyncState(
                configured: _googleDriveConfigured,
                connected: true,
              ))
          .copyWith(connected: true, account: account, clearError: true),
    );
  }

  Future<void> disconnect() async {
    _localCheckpointRetry?.cancel();
    _localCheckpointRetry = null;
    _fullSyncRetry?.cancel();
    _fullSyncRetry = null;
    _localRetryAttempt = 0;
    _fullRetryAttempt = 0;
    try {
      await const GoogleDriveNativeAuthService().signOut();
    } finally {
      await _storage.clearGoogleDriveSession();
    }
    await (await SharedPreferences.getInstance()).remove(
      _googleDriveLastFullSyncAtKey,
    );
    if (_disposed) return;
    _setState(
      GoogleDriveSyncState(
        configured: _googleDriveConfigured,
        connected: false,
      ),
    );
  }

  Future<void> syncNow({
    bool background = false,
    bool localChangesOnly = false,
  }) {
    if (_disposed || _shuttingDown) return Future<void>.value();
    if (localChangesOnly) {
      _localCheckpointRetry?.cancel();
      _localCheckpointRetry = null;
    } else {
      _fullSyncRetry?.cancel();
      _fullSyncRetry = null;
    }
    final Future<void>? active = _activeSync;
    if (active != null) {
      _syncAgainRequested = true;
      _fullSyncAgainRequested = _fullSyncAgainRequested || !localChangesOnly;
      return active;
    }
    final Future<void> next = _sync(
      background: background,
      localChangesOnly: localChangesOnly,
    );
    _activeSync = next;
    return next.whenComplete(() {
      if (!identical(_activeSync, next)) return;
      _activeSync = null;
      if (!_disposed && !_shuttingDown && _syncAgainRequested) {
        final bool runFullSync = _fullSyncAgainRequested;
        _syncAgainRequested = false;
        _fullSyncAgainRequested = false;
        unawaited(syncNow(background: true, localChangesOnly: !runFullSync));
      }
    });
  }

  /// Stops new background work and lets the current request settle before the
  /// provider tree (and its Drift isolate) is torn down by the operating
  /// system. This is deliberately bounded: process exit must never hang on a
  /// slow network request.
  Future<void> prepareForExit() async {
    if (_disposed) return;
    _shuttingDown = true;
    _syncAgainRequested = false;
    _fullSyncAgainRequested = false;
    _localCheckpointRetry?.cancel();
    _localCheckpointRetry = null;
    _fullSyncRetry?.cancel();
    _fullSyncRetry = null;
    final Future<void>? active = _activeSync;
    if (active == null) return;
    try {
      await active.timeout(const Duration(seconds: 2));
    } on Object {
      // The remaining request is guarded by [_disposed] and will be abandoned
      // safely when the ProviderContainer closes.
    }
  }

  Future<void> _sync({
    required bool background,
    required bool localChangesOnly,
  }) async {
    final GoogleDriveSyncState current =
        state.value ??
        GoogleDriveSyncState(
          configured: _googleDriveConfigured,
          connected: false,
        );
    if (!current.configured || !current.connected) return;
    _activeProgressVisible =
        !background || (!localChangesOnly && current.lastSyncAt == null);
    _setState(
      current.copyWith(
        syncing: _activeProgressVisible,
        clearError: true,
        syncStage: _activeProgressVisible ? 'Preparing secure sync…' : null,
        progress: _activeProgressVisible ? 0 : null,
        clearProgress: !_activeProgressVisible,
        transferredBytes: 0,
        totalBytes: 0,
        processedItems: 0,
        totalItems: 0,
      ),
    );
    GoogleDriveCloudReplica? activeCloud;
    String? leaseDeviceId;
    bool ownsDeliveryLease = false;
    final List<String> replicaWarnings = <String>[];
    try {
      final String? token = await _validAccessToken();
      if (_disposed || _shuttingDown) return;
      if (token == null || token.isEmpty) {
        _setState(
          current.copyWith(
            connected: false,
            syncing: false,
            lastError: 'Google Drive session expired. Connect again.',
          ),
        );
        return;
      }
      if (localChangesOnly) {
        final CanonicalLibraryRepository repository = ref.read(
          canonicalLibraryRepositoryProvider,
        );
        final GoogleDriveCloudReplica libraryCloud = GoogleDriveCloudReplica(
          accessToken: token,
          replicaNamespace: repository.replicaNamespace,
          includeLegacyLibrary: repository.importsLegacyData,
        );
        activeCloud = libraryCloud;
        leaseDeviceId = await repository.deviceId();
        if (_disposed || _shuttingDown) return;
        ownsDeliveryLease = await libraryCloud.acquireDeliveryLease(
          deviceId: leaseDeviceId,
        );
        if (_disposed || _shuttingDown) return;
        var applied = 0;
        var restoredSnapshot = false;
        DriveLibrarySnapshot? cloudSnapshot;
        if (ownsDeliveryLease) {
          cloudSnapshot = await libraryCloud.pullLibrarySnapshot();
          if (_disposed || _shuttingDown) return;
          if (cloudSnapshot != null &&
              !await repository.hasAppliedDriveSnapshot(
                cloudSnapshot.checksum,
              )) {
            await repository.applyDriveSnapshot(cloudSnapshot);
            restoredSnapshot = true;
          }
          final Set<String> processed = await repository
              .processedDriveSegmentNames();
          final List<DriveReplicaSegment> incoming = await libraryCloud
              .pullSegments(excluding: processed);
          final Set<TrackerSource> targets = _connectedTrackerTargets(
            ref.read(settingsProvider),
          );
          for (final DriveReplicaSegment segment in incoming) {
            applied += await repository.applyDriveSegment(
              segment,
              trackerTargets: targets,
            );
          }
          await repository.applyRemoteDeliveryLedger(
            await libraryCloud.readDeliveryLedger(),
          );
        }
        _setProgress(stage: 'Uploading local changes…', progress: 0.15);
        await _pushPendingLibrarySegments(repository, libraryCloud);
        if (_disposed || _shuttingDown) return;
        final DriveLibrarySnapshot outgoingSnapshot = await repository
            .buildDriveSnapshot();
        DriveReplicaUsage? usage;
        if (ownsDeliveryLease) {
          await libraryCloud.pushLibrarySnapshot(outgoingSnapshot);
          usage = await libraryCloud.readUsage();
          _localRetryAttempt = 0;
        } else {
          _scheduleLocalCheckpointRetry();
        }
        final DateTime completedAt = DateTime.now().toUtc();
        await (await SharedPreferences.getInstance()).setString(
          _googleDriveLastFullSyncAtKey,
          completedAt.toIso8601String(),
        );
        if (_disposed || _shuttingDown) return;
        if (restoredSnapshot || applied > 0) {
          ref.invalidate(trackerLocalAnimeLibraryProvider);
          ref.invalidate(trackerLocalMangaLibraryProvider);
          ref.invalidate(trackerAnimeListProvider);
          ref.invalidate(trackerMangaListProvider);
        }
        _setState(
          (state.value ?? current).copyWith(
            syncing: false,
            connected: true,
            lastSyncAt: completedAt,
            appliedSegments: applied,
            driveUsageBytes: usage?.totalBytes,
            driveFileCount: usage?.fileCount,
            cloudEntryCount: ownsDeliveryLease
                ? outgoingSnapshot.entryCount
                : cloudSnapshot?.entryCount,
            localEntryCount: outgoingSnapshot.entryCount,
            clearError: true,
            clearProgress: true,
          ),
        );
        return;
      }
      _setProgress(stage: 'Syncing accounts…', progress: 0.03);
      final GoogleDriveAccountProfile? account =
          await _fetchAndStoreAccountProfile(
            token,
            fallback: state.value?.account ?? current.account,
          );
      if (_disposed || _shuttingDown) return;
      if (account != null) {
        _setState(
          (state.value ?? current).copyWith(account: account, clearError: true),
        );
      }
      final GoogleDriveCloudReplica cloud = GoogleDriveCloudReplica(
        accessToken: token,
      );
      final CanonicalLibraryRepository initialRepository = ref.read(
        canonicalLibraryRepositoryProvider,
      );
      leaseDeviceId = await initialRepository.deviceId();
      final SettingsController settingsController = ref.read(
        settingsProvider.notifier,
      );
      await settingsController.ready;
      try {
        final AccountDriveSyncResult accountResult =
            await AccountDriveSyncService(
              preferences: await SharedPreferences.getInstance(),
            ).sync(
              cloud: cloud,
              deviceId: leaseDeviceId,
              localAccounts: settingsController.driveAniListAccounts(),
              activeViewerId: ref.read(settingsProvider).anilistViewerId,
            );
        if (accountResult.localStateChanged) {
          await settingsController.applyDriveAniListAccounts(
            accounts: accountResult.accounts,
            preferredActiveViewerId: accountResult.preferredActiveViewerId,
          );
          invalidateAniListLibraryProviders(ref.invalidate);
          ref.invalidate(trackerAnimeListProvider);
        }
      } on Object catch (error) {
        debugPrint('Google Drive account sync failed: $error');
        replicaWarnings.add('account');
      }
      _setProgress(stage: 'Syncing settings…', progress: 0.1);
      try {
        final PreferenceDriveSyncResult preferenceResult =
            await PreferenceDriveSyncService(
              preferences: await SharedPreferences.getInstance(),
            ).sync(cloud: cloud, deviceId: leaseDeviceId);
        if (preferenceResult.localStateChanged) {
          await settingsController.reloadDrivePreferences();
          ref.read(drivePreferencesRevisionProvider.notifier).changed();
          ref.invalidate(playerSettingsProvider);
          ref.invalidate(aniListUserSettingsProvider);
          ref.invalidate(watchPartyConnectionSettingsProvider);
        }
      } on Object catch (error) {
        debugPrint('Google Drive preference sync failed: $error');
        replicaWarnings.add('preferences');
      }
      final CanonicalLibraryRepository repository = ref.read(
        canonicalLibraryRepositoryProvider,
      );
      leaseDeviceId = await repository.deviceId();
      final GoogleDriveCloudReplica libraryCloud = GoogleDriveCloudReplica(
        accessToken: token,
        replicaNamespace: repository.replicaNamespace,
        includeLegacyLibrary: repository.importsLegacyData,
      );
      activeCloud = libraryCloud;
      _setProgress(stage: 'Syncing addons…', progress: 0.17);
      try {
        final AddonDriveSyncResult addonResult = await AddonDriveSyncService(
          preferences: await SharedPreferences.getInstance(),
          store: ref.read(soraAddonStoreProvider),
        ).sync(cloud: cloud, deviceId: leaseDeviceId);
        if (addonResult.localStateChanged) {
          ref.invalidate(soraJsRuntimeProvider);
          ref.invalidate(addonCatalogProvider);
          await ref.read(soraAddonsProvider.notifier).load();
          await ref.read(addonSourcesProvider.notifier).load();
        }
      } on Object catch (error) {
        // Addons are an independent replica. A bad/unreachable addon must not
        // prevent canonical library operations from reaching Drive.
        debugPrint('Google Drive addon sync failed: $error');
        replicaWarnings.add('addons');
      }
      _setProgress(stage: 'Checking Library backup…', progress: 0.23);
      final DriveLibrarySnapshot? cloudSnapshot = await libraryCloud
          .pullLibrarySnapshot(
            onProgress: (int received, int total) => _setTransferProgress(
              stage: 'Downloading Library backup…',
              transferred: received,
              total: total,
              start: 0.23,
              end: 0.48,
            ),
          );
      if (cloudSnapshot != null &&
          !await repository.hasAppliedDriveSnapshot(cloudSnapshot.checksum)) {
        await repository.applyDriveSnapshot(
          cloudSnapshot,
          onProgress: (int completed, int total) => _setItemProgress(
            stage: 'Restoring Local Library…',
            completed: completed,
            total: total,
            start: 0.48,
            end: 0.62,
          ),
        );
        ref.invalidate(trackerLocalAnimeLibraryProvider);
        ref.invalidate(trackerLocalMangaLibraryProvider);
        ref.invalidate(trackerAnimeListProvider);
        ref.invalidate(trackerMangaListProvider);
      }
      _setProgress(stage: 'Merging recent changes…', progress: 0.64);
      ownsDeliveryLease = await libraryCloud.acquireDeliveryLease(
        deviceId: leaseDeviceId,
      );
      int applied = 0;
      if (ownsDeliveryLease) {
        final Set<String> processed = await repository
            .processedDriveSegmentNames();
        final List<DriveReplicaSegment> incoming = await libraryCloud
            .pullSegments(excluding: processed);
        final Set<TrackerSource> targets = _connectedTrackerTargets(
          ref.read(settingsProvider),
        );
        for (final DriveReplicaSegment segment in incoming) {
          applied += await repository.applyDriveSegment(
            segment,
            trackerTargets: targets,
          );
        }
      }
      await repository.applyRemoteDeliveryLedger(
        await libraryCloud.readDeliveryLedger(),
      );
      _setProgress(stage: 'Uploading local changes…', progress: 0.76);
      await _pushPendingLibrarySegments(repository, libraryCloud);
      if (ownsDeliveryLease) {
        await ref.read(trackerSyncCoordinatorProvider).flushPending();
        await libraryCloud.mergeDeliveryLedger(
          await repository.confirmedTrackerDeliveryLedger(),
        );
      }
      final DriveLibrarySnapshot outgoingSnapshot = await repository
          .buildDriveSnapshot();
      if (ownsDeliveryLease) {
        await libraryCloud.pushLibrarySnapshot(
          outgoingSnapshot,
          onProgress: (int sent, int total) => _setTransferProgress(
            stage: 'Uploading Library backup…',
            transferred: sent,
            total: total,
            start: 0.8,
            end: 0.94,
          ),
        );
      }
      _setProgress(stage: 'Finishing sync…', progress: 0.96);
      final DriveReplicaUsage usage = await libraryCloud.readUsage();
      final DateTime completedAt = DateTime.now().toUtc();
      await (await SharedPreferences.getInstance()).setString(
        _googleDriveLastFullSyncAtKey,
        completedAt.toIso8601String(),
      );
      if (_disposed || _shuttingDown) return;
      if (ownsDeliveryLease) {
        _localRetryAttempt = 0;
      } else {
        // The immutable segments are already safe in Drive, but the compact
        // snapshot/count still belongs to the current lease holder. Retry the
        // checkpoint soon instead of waiting for the 15-minute periodic sync.
        _scheduleLocalCheckpointRetry();
      }
      if (replicaWarnings.isEmpty) {
        _fullRetryAttempt = 0;
      } else {
        // Accounts, preferences and addons are independent replicas. A
        // temporary failure in one must not roll back Library sync, but it
        // should retry promptly so UI preferences do not stay stale.
        _scheduleFullSyncRetry();
      }
      _setState(
        (state.value ?? current).copyWith(
          syncing: false,
          connected: true,
          lastSyncAt: completedAt,
          appliedSegments: applied,
          clearProgress: true,
          driveUsageBytes: usage.totalBytes,
          driveFileCount: usage.fileCount,
          cloudEntryCount: ownsDeliveryLease
              ? outgoingSnapshot.entryCount
              : cloudSnapshot?.entryCount,
          localEntryCount: outgoingSnapshot.entryCount,
          lastError: replicaWarnings.isEmpty
              ? null
              : 'Some data could not be synced. Please try again.',
          clearError: replicaWarnings.isEmpty,
        ),
      );
    } on Object catch (error) {
      debugPrint('Google Drive sync failed: $error');
      if (_disposed || _shuttingDown) return;
      if (localChangesOnly) {
        _scheduleLocalCheckpointRetry();
      } else {
        _scheduleFullSyncRetry();
      }
      final GoogleDriveSyncState latest = state.value ?? current;
      _setState(
        latest.copyWith(
          syncing: false,
          clearProgress: true,
          lastError: 'Google Drive sync failed. Please try again.',
        ),
      );
    } finally {
      if (ownsDeliveryLease && activeCloud != null && leaseDeviceId != null) {
        try {
          await activeCloud.releaseDeliveryLease(deviceId: leaseDeviceId);
        } on Object {
          // The short lease expires by itself. A release failure must not turn
          // a completed local/cloud sync into a destructive retry.
        }
      }
      _activeProgressVisible = false;
    }
  }

  void _setProgress({required String stage, required double progress}) {
    if (_disposed || _shuttingDown || !_activeProgressVisible) return;
    final GoogleDriveSyncState? current = state.value;
    if (current == null) return;
    _setState(
      current.copyWith(
        syncing: true,
        syncStage: stage,
        progress: progress.clamp(0.0, 1.0),
      ),
    );
  }

  void _setTransferProgress({
    required String stage,
    required int transferred,
    required int total,
    required double start,
    required double end,
  }) {
    if (_disposed || _shuttingDown || !_activeProgressVisible) return;
    final double fraction = total > 0
        ? (transferred / total).clamp(0.0, 1.0)
        : 0;
    final GoogleDriveSyncState? current = state.value;
    if (current == null) return;
    _setState(
      current.copyWith(
        syncing: true,
        syncStage: stage,
        progress: start + ((end - start) * fraction),
        transferredBytes: transferred,
        totalBytes: total > 0 ? total : 0,
        processedItems: 0,
        totalItems: 0,
      ),
    );
  }

  void _setItemProgress({
    required String stage,
    required int completed,
    required int total,
    required double start,
    required double end,
  }) {
    if (_disposed || _shuttingDown || !_activeProgressVisible) return;
    final double fraction = total > 0 ? (completed / total).clamp(0.0, 1.0) : 1;
    final GoogleDriveSyncState? current = state.value;
    if (current == null) return;
    _setState(
      current.copyWith(
        syncing: true,
        syncStage: stage,
        progress: start + ((end - start) * fraction),
        transferredBytes: 0,
        totalBytes: 0,
        processedItems: completed,
        totalItems: total,
      ),
    );
  }

  Future<void> _pushPendingLibrarySegments(
    CanonicalLibraryRepository repository,
    GoogleDriveCloudReplica cloud,
  ) async {
    DriveReplicaSegment? outgoing = await repository.buildPendingDriveSegment();
    while (outgoing != null) {
      final CloudReplicaFile file = await cloud.pushSegment(outgoing);
      await repository.markDriveSegmentDelivered(
        outgoing,
        remoteFileId: file.id,
      );
      outgoing = await repository.buildPendingDriveSegment();
    }
  }

  void _setState(GoogleDriveSyncState next) {
    if (_disposed) return;
    state = AsyncData(next);
  }

  void _scheduleLocalCheckpointRetry() {
    if (_disposed || _shuttingDown) return;
    _localCheckpointRetry?.cancel();
    final int exponent = _localRetryAttempt.clamp(0, 5);
    final Duration delay = Duration(
      seconds: (15 * (1 << exponent)).clamp(15, 300),
    );
    _localRetryAttempt += 1;
    _localCheckpointRetry = Timer(delay, () {
      _localCheckpointRetry = null;
      if (_disposed || _shuttingDown) return;
      unawaited(syncNow(background: true, localChangesOnly: true));
    });
  }

  void _scheduleFullSyncRetry() {
    if (_disposed || _shuttingDown) return;
    _fullSyncRetry?.cancel();
    final int exponent = _fullRetryAttempt.clamp(0, 5);
    final Duration delay = Duration(
      seconds: (15 * (1 << exponent)).clamp(15, 300),
    );
    _fullRetryAttempt += 1;
    _fullSyncRetry = Timer(delay, () {
      _fullSyncRetry = null;
      if (_disposed || _shuttingDown) return;
      unawaited(syncNow(background: true));
    });
  }

  Future<String?> _validAccessToken() async {
    if (GoogleDriveNativeAuthService.isSupported) {
      final String? nativeToken = await const GoogleDriveNativeAuthService()
          .restoreAccessToken();
      final String? token = nativeToken ?? await _storedAccessToken();
      if (token == null || token.isEmpty) return null;
      if (nativeToken != null && nativeToken.isNotEmpty) {
        await _storeNativeAccessToken(token);
      }
      return token;
    }
    final String? accessToken = await _storedAccessToken();
    if (accessToken != null) return accessToken;
    final String refreshToken =
        (await _storage.readGoogleDriveRefreshToken()) ?? '';
    if (refreshToken.isEmpty) return null;
    final GoogleDriveTokenBundle refreshed = await GoogleDriveOAuthService()
        .refresh(
          refreshToken: refreshToken,
          television: TvPlatform.isAndroidTv,
        );
    await connect(refreshed);
    return refreshed.accessToken;
  }

  bool get _googleDriveConfigured => TvPlatform.isAndroidTv
      ? AppConstants.googleOAuthTvConfigured
      : AppConstants.googleOAuthConfigured;

  Future<String?> _storedAccessToken() async {
    final String accessToken =
        (await _storage.readGoogleDriveAccessToken()) ?? '';
    final DateTime? expiresAt = await _storage.readGoogleDriveExpiresAt();
    if (accessToken.isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 2)),
        )) {
      return accessToken;
    }
    return null;
  }

  Future<void> _storeNativeAccessToken(String token) async {
    await _storage.writeGoogleDriveAccessToken(token);
    await _storage.writeGoogleDriveExpiresAt(
      DateTime.now().toUtc().add(const Duration(minutes: 50)),
    );
  }

  Future<GoogleDriveAccountProfile?> _storedAccountProfile() async {
    final String raw =
        (await _storage.readGoogleDriveAccountProfile())?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return GoogleDriveAccountProfile.fromStoredJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<GoogleDriveAccountProfile?> _fetchAndStoreAccountProfile(
    String accessToken, {
    GoogleDriveAccountProfile? fallback,
  }) async {
    try {
      final GoogleDriveAccountProfile account = await GoogleDriveAccountClient()
          .fetchProfile(accessToken);
      await _storage.writeGoogleDriveAccountProfile(
        jsonEncode(account.toJson()),
      );
      return account;
    } on Object {
      // Account decoration must never block local/cloud synchronization. The
      // next successful sync retries the lightweight Drive about.get call.
      return fallback;
    }
  }
}

Set<TrackerSource> _connectedTrackerTargets(SettingsState settings) =>
    <TrackerSource>{
      if (settings.hasAniListSession) TrackerSource.anilist,
      if (settings.hasMalSession) TrackerSource.mal,
      if (settings.hasShikimoriSession) TrackerSource.shikimori,
    };
