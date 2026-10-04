import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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
const Duration _trackerDeliveryPullFreshness = Duration(seconds: 5);

class GoogleDriveSyncState {
  const GoogleDriveSyncState({
    required this.configured,
    required this.connected,
    this.syncing = false,
    this.checking = false,
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

  /// A quiet background pull is in progress; unlike a manual sync it does not
  /// show a persistent progress bar or disable the Sync now button.
  final bool checking;
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
    bool? checking,
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
    checking: checking ?? this.checking,
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
        if (previous == null) {
          // Let the first frame, local database and cached Board render before
          // a potentially large Drive restore starts on mobile hardware.
          fullSyncDebounce?.cancel();
          fullSyncDebounce = Timer(const Duration(seconds: 2), () {
            if (disposed) return;
            unawaited(
              ref
                  .read(googleDriveSyncControllerProvider.notifier)
                  .syncNow(background: true),
            );
          });
        } else {
          unawaited(
            ref
                .read(googleDriveSyncControllerProvider.notifier)
                .syncNow(background: true),
          );
        }
      }
    },
    fireImmediately: true,
  );
  ref.listen<String>(settingsProvider.select(_driveAccountFingerprint), (
    String? previous,
    String next,
  ) {
    if (previous == null || previous == next) return;
    if (ref
        .read(googleDriveSyncControllerProvider.notifier)
        .isApplyingRemoteChanges) {
      return;
    }
    scheduleFullSync();
  });
  ref.listen<String>(settingsProvider.select(_drivePreferenceFingerprint), (
    String? previous,
    String next,
  ) {
    if (previous == null || previous == next) return;
    if (ref
        .read(googleDriveSyncControllerProvider.notifier)
        .isApplyingRemoteChanges) {
      return;
    }
    scheduleFullSync();
  });
  ref.listen<int>(drivePreferencesRevisionProvider, (int? previous, int next) {
    if (previous == null || previous == next) return;
    if (ref
        .read(googleDriveSyncControllerProvider.notifier)
        .isApplyingRemoteChanges) {
      return;
    }
    scheduleFullSync();
  });
  ref.listen<String>(soraAddonsProvider.select(_driveAddonFingerprint), (
    String? previous,
    String next,
  ) {
    if (previous == null || previous == next) return;
    if (ref
        .read(googleDriveSyncControllerProvider.notifier)
        .isApplyingRemoteChanges) {
      return;
    }
    scheduleFullSync();
  });
  ref.listen<String>(
    addonSourcesProvider.select(_driveAddonSourceFingerprint),
    (String? previous, String next) {
      if (previous == null || previous == next) return;
      if (ref
          .read(googleDriveSyncControllerProvider.notifier)
          .isApplyingRemoteChanges) {
        return;
      }
      scheduleFullSync();
    },
  );
  ref.listen<AsyncValue<int>>(pendingDriveDeliveryCountProvider, (
    AsyncValue<int>? previous,
    AsyncValue<int> next,
  ) {
    final int pending = next.value ?? 0;
    final int previousPending = previous?.value ?? 0;
    if (pending <= 0) {
      localPushDebounce?.cancel();
      localPushDebounce = null;
      return;
    }
    // Confirming a delivered batch decreases this count. Treating that DB
    // write as a new local mutation schedules Drive again from inside its own
    // sync and creates a self-sustaining loop for large libraries.
    if (previous != null && pending <= previousPending) return;
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

String _replicaWarningCode(List<String> warnings) =>
    'drive.partialSync:${warnings.toSet().join(',')}';

class GoogleDriveSyncController extends AsyncNotifier<GoogleDriveSyncState> {
  static const int _maximumAutomaticRetries = 3;

  final AppSecureStorage _storage = const AppSecureStorage();
  Future<void>? _activeSync;
  bool _activeSyncIsFull = false;
  CancelToken? _activeCancelToken;
  Timer? _localCheckpointRetry;
  Timer? _fullSyncRetry;
  bool _syncAgainRequested = false;
  bool _fullSyncAgainRequested = false;
  bool _runningCoalescedFollowUp = false;
  bool _activeProgressVisible = false;
  bool _applyingRemoteChanges = false;
  bool _cloudDataDeletionActive = false;
  bool _disposed = false;
  bool _shuttingDown = false;
  bool _accountsRestored = false;
  final Set<String> _pulledLibraryWorkspaces = <String>{};
  final Map<String, DateTime> _lastLibraryPullAt = <String, DateTime>{};
  final Set<String> _trackerOutboxResumedWorkspaces = <String>{};
  int _localRetryAttempt = 0;
  int _fullRetryAttempt = 0;

  bool get isApplyingRemoteChanges => _applyingRemoteChanges;

  @override
  Future<GoogleDriveSyncState> build() async {
    _disposed = false;
    _shuttingDown = false;
    _accountsRestored = false;
    _pulledLibraryWorkspaces.clear();
    _lastLibraryPullAt.clear();
    _trackerOutboxResumedWorkspaces.clear();
    ref.onDispose(() {
      _disposed = true;
      _shuttingDown = true;
      _syncAgainRequested = false;
      _fullSyncAgainRequested = false;
      _activeCancelToken?.cancel('Google Drive controller disposed.');
      _activeCancelToken = null;
      _localCheckpointRetry?.cancel();
      _localCheckpointRetry = null;
      _fullSyncRetry?.cancel();
      _fullSyncRetry = null;
    });
    final bool configured = _googleDriveConfigured;
    bool connected;
    String? accessToken;
    if (configured && GoogleDriveNativeAuthService.isSupported) {
      final String? storedToken = await _storedAccessToken();
      final String refreshToken =
          (await _storage.readGoogleDriveRefreshToken()) ?? '';
      accessToken = storedToken;
      connected = storedToken != null || refreshToken.trim().isNotEmpty;
      if (!connected) {
        try {
          final String? nativeToken = await const GoogleDriveNativeAuthService()
              .restoreAccessToken()
              .timeout(const Duration(seconds: 4));
          accessToken = nativeToken ?? accessToken;
          connected = connected || (nativeToken?.isNotEmpty ?? false);
          if (nativeToken != null && nativeToken.isNotEmpty) {
            await _storeNativeAccessToken(nativeToken);
          }
        } on Object {
          // Resigned and containerized iOS builds may not be able to restore the
          // native Google SDK session. Keep the Worker/device-flow refresh token
          // usable instead of falsely disconnecting the account and hiding its
          // persistent Drive outbox.
        }
      }
    } else {
      final String refreshToken =
          (await _storage.readGoogleDriveRefreshToken()) ?? '';
      connected = refreshToken.trim().isNotEmpty;
      accessToken = await _storedAccessToken();
    }
    final GoogleDriveAccountProfile? account = await _storedAccountProfile();
    if (connected && accessToken != null && accessToken.isNotEmpty) {
      // Account artwork is optional. Waiting for Google's /about endpoint
      // here prevented the connected state (and startup Library pull) from
      // being published on a slow or blocked network.
      unawaited(_refreshAccountProfile(accessToken, fallback: account));
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
    _accountsRestored = false;
    _pulledLibraryWorkspaces.clear();
    _lastLibraryPullAt.clear();
    _trackerOutboxResumedWorkspaces.clear();
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
    _accountsRestored = false;
    _pulledLibraryWorkspaces.clear();
    _lastLibraryPullAt.clear();
    _trackerOutboxResumedWorkspaces.clear();
    _localCheckpointRetry?.cancel();
    _localCheckpointRetry = null;
    _fullSyncRetry?.cancel();
    _fullSyncRetry = null;
    _localRetryAttempt = 0;
    _fullRetryAttempt = 0;
    try {
      await const GoogleDriveNativeAuthService().signOut();
    } on Object catch (error) {
      // Native sign-out can be unavailable in a re-signed/containerized iOS
      // build. Removing MiruShin's device-local session must still succeed.
      debugPrint('Native Google sign-out was unavailable: $error');
    }
    await _storage.clearGoogleDriveSession();
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
    bool remoteChangesOnly = false,
    bool automaticRetry = false,
  }) {
    if (_disposed || _shuttingDown || _cloudDataDeletionActive) {
      return Future<void>.value();
    }
    if (remoteChangesOnly) {
      // A running full or local checkpoint already pulls this workspace.
    } else if (localChangesOnly) {
      _localCheckpointRetry?.cancel();
      _localCheckpointRetry = null;
      if (!automaticRetry) _localRetryAttempt = 0;
    } else {
      _fullSyncRetry?.cancel();
      _fullSyncRetry = null;
      if (!automaticRetry) _fullRetryAttempt = 0;
    }
    final Future<void>? active = _activeSync;
    if (active != null) {
      if (remoteChangesOnly && background) return active;
      if (background &&
          !localChangesOnly &&
          !remoteChangesOnly &&
          _activeSyncIsFull) {
        return active;
      }
      if (!background) {
        _activeProgressVisible = true;
        final GoogleDriveSyncState? current = state.value;
        if (current != null) {
          _setState(
            current.copyWith(
              syncing: true,
              syncStage: current.syncStage ?? 'Finishing current sync…',
            ),
          );
        }
        // A manual request always performs a fresh full pass after the active
        // background checkpoint. The button therefore never appears to do
        // nothing merely because the eight-second debounce fired first.
        return active.then((_) async {
          if (_disposed || _shuttingDown) return;
          await syncNow(background: false);
        });
      }
      if (_runningCoalescedFollowUp) return active;
      _syncAgainRequested = true;
      _fullSyncAgainRequested = _fullSyncAgainRequested || !localChangesOnly;
      return active;
    }
    final CancelToken cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    final Future<void> next = _sync(
      background: background,
      localChangesOnly: localChangesOnly,
      remoteChangesOnly: remoteChangesOnly,
      cancelToken: cancelToken,
    );
    _activeSyncIsFull = !localChangesOnly && !remoteChangesOnly;
    _activeSync = next;
    return next.whenComplete(() {
      if (!identical(_activeSync, next)) return;
      _activeSync = null;
      _activeSyncIsFull = false;
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
      if (!_disposed && !_shuttingDown && _syncAgainRequested) {
        final bool runFullSync = _fullSyncAgainRequested;
        _syncAgainRequested = false;
        _fullSyncAgainRequested = false;
        _runningCoalescedFollowUp = true;
        unawaited(
          syncNow(
            background: true,
            localChangesOnly: !runFullSync,
          ).whenComplete(() => _runningCoalescedFollowUp = false),
        );
      }
    });
  }

  /// A provider import must not run against the pre-Drive state of this
  /// workspace. A failed first pull leaves the provider queue untouched.
  Future<bool> syncBeforeTrackerReconciliation() async {
    final bool driveWasConnected = state.value?.connected == true;
    final Future<void>? active = _activeSync;
    if (active != null && !_activeSyncIsFull) {
      await active;
    }
    await syncNow(background: true);
    final GoogleDriveSyncState? current = state.value;
    if (current == null) return false;
    if (!current.connected) return !driveWasConnected;
    final String workspace = ref
        .read(canonicalLibraryRepositoryProvider)
        .replicaNamespace;
    if (_accountsRestored && _pulledLibraryWorkspaces.contains(workspace)) {
      return true;
    }
    return ensureWorkspaceReadyForTrackerDelivery(workspace);
  }

  /// Local writes never wait for Drive. Outbound tracker writes do wait for
  /// the first successful pull of their own AniList workspace, so an offline
  /// Device B cannot publish stale progress before seeing Device A's changes.
  Future<bool> ensureWorkspaceReadyForTrackerDelivery(
    String replicaNamespace,
  ) async {
    final GoogleDriveSyncState? current = state.value;
    if (current == null) return false;
    if (!current.configured) return true;
    if (!current.connected) {
      // A deliberate disconnect releases the tracker queue, but an expired
      // Drive session must not make a stale device publish its old state.
      return current.lastError == null;
    }
    if (_accountsRestored && _libraryPullIsFresh(replicaNamespace)) {
      return true;
    }
    for (var attempt = 0; attempt < 2; attempt += 1) {
      await syncNow(background: true, remoteChangesOnly: _accountsRestored);
      if (_accountsRestored && _libraryPullIsFresh(replicaNamespace)) {
        return true;
      }
      if (_disposed ||
          _shuttingDown ||
          ref.read(canonicalLibraryRepositoryProvider).replicaNamespace !=
              replicaNamespace) {
        return false;
      }
    }
    return false;
  }

  /// Stops new background work and lets the current request settle before the
  /// provider tree (and its Drift isolate) is torn down by the operating
  /// system. Drive HTTP work is cancelled first, so awaiting here is both
  /// bounded and safer than allowing SQLite to close under an active sync.
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
    _activeCancelToken?.cancel('MiruShin is closing.');
    try {
      await active;
    } on Object {
      // Shutdown continues after the active operation has unwound its finally
      // blocks. Its user-facing error state is intentionally irrelevant here.
    }
  }

  Future<int> deleteCloudDataAndDisconnect() async {
    _cloudDataDeletionActive = true;
    _syncAgainRequested = false;
    _fullSyncAgainRequested = false;
    _localCheckpointRetry?.cancel();
    _fullSyncRetry?.cancel();
    final Future<void>? active = _activeSync;
    try {
      if (active != null) await active;
      final String? token = await _validAccessToken();
      if (token == null || token.isEmpty) {
        throw StateError('Google Drive session expired. Connect again.');
      }
      _activeProgressVisible = true;
      final GoogleDriveSyncState current =
          state.value ??
          GoogleDriveSyncState(
            configured: _googleDriveConfigured,
            connected: true,
          );
      _setState(
        current.copyWith(
          syncing: true,
          syncStage: 'Deleting MiruShin data from Drive…',
          progress: 0,
          clearError: true,
        ),
      );
      final int deleted = await GoogleDriveCloudReplica(accessToken: token)
          .deleteAllMiruShinData(
            onProgress: (int completed, int total) {
              _setItemProgress(
                stage: 'Deleting MiruShin data from Drive…',
                completed: completed,
                total: total,
                start: 0,
                end: 1,
              );
            },
          );
      await disconnect();
      return deleted;
    } catch (error) {
      final GoogleDriveSyncState current =
          state.value ??
          GoogleDriveSyncState(
            configured: _googleDriveConfigured,
            connected: true,
          );
      _setState(
        current.copyWith(
          syncing: false,
          clearProgress: true,
          lastError: 'Could not delete MiruShin data from Google Drive.',
        ),
      );
      rethrow;
    } finally {
      _activeProgressVisible = false;
      _cloudDataDeletionActive = false;
    }
  }

  Future<void> _sync({
    required bool background,
    required bool localChangesOnly,
    required bool remoteChangesOnly,
    required CancelToken cancelToken,
  }) async {
    final GoogleDriveSyncState current =
        state.value ??
        GoogleDriveSyncState(
          configured: _googleDriveConfigured,
          connected: false,
        );
    if (!current.configured || !current.connected) return;
    if (localChangesOnly && !remoteChangesOnly) {
      try {
        final int pending = await ref
            .read(canonicalLibraryRepositoryProvider)
            .pendingDriveDeliveryCount();
        if (pending <= 0) {
          _localRetryAttempt = 0;
          return;
        }
      } on Object catch (error) {
        if (_disposed || _shuttingDown) return;
        debugPrint('Could not inspect pending Google Drive work: $error');
        _scheduleLocalCheckpointRetry();
        return;
      }
    }
    _activeProgressVisible =
        !background ||
        (!localChangesOnly && !remoteChangesOnly && current.lastSyncAt == null);
    _setState(
      current.copyWith(
        syncing: _activeProgressVisible,
        checking: !_activeProgressVisible && !localChangesOnly,
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
      final String? token = await _validAccessToken(cancelToken: cancelToken);
      if (_disposed || _shuttingDown) return;
      if (token == null || token.isEmpty) {
        _setState(
          current.copyWith(
            connected: false,
            syncing: false,
            checking: false,
            lastError: 'Google Drive session expired. Connect again.',
          ),
        );
        return;
      }
      if (localChangesOnly || remoteChangesOnly) {
        final CanonicalLibraryRepository repository = ref.read(
          canonicalLibraryRepositoryProvider,
        );
        final GoogleDriveCloudReplica libraryCloud = GoogleDriveCloudReplica(
          accessToken: token,
          replicaNamespace: repository.replicaNamespace,
          includeLegacyLibrary: repository.importsLegacyData,
          cancelToken: cancelToken,
        );
        activeCloud = libraryCloud;
        leaseDeviceId = await repository.deviceId();
        if (_disposed || _shuttingDown) return;
        var applied = 0;
        var restoredSnapshot = false;
        final Set<TrackerSource> targets = _connectedTrackerTargets(
          ref.read(settingsProvider),
        );
        // Every device is a reader. The lease protects tracker delivery and
        // compact checkpoint publication only; it must never hide remote
        // library operations from another phone/desktop.
        final String? appliedSnapshotChecksum = await repository
            .appliedDriveSnapshotChecksum();
        final DriveLibraryChanges changes = await libraryCloud
            .pullLibraryChanges(
              excluding: await repository.processedDriveSegmentNames(),
              pageToken: await repository.driveChangePageToken(),
            );
        final DriveLibrarySnapshot? cloudSnapshot =
            changes.manifestChanged || appliedSnapshotChecksum == null
            ? await libraryCloud.pullLibrarySnapshot(
                excludingChecksum: appliedSnapshotChecksum,
                manifestFileId: changes.manifestFileId,
                snapshotFileId: changes.snapshotFileId,
              )
            : null;
        if (_disposed || _shuttingDown) return;
        if (cloudSnapshot != null &&
            !await repository.hasAppliedDriveSnapshot(cloudSnapshot.checksum)) {
          await repository.applyDriveSnapshot(
            cloudSnapshot,
            trackerTargets: targets,
          );
          restoredSnapshot = true;
        }
        for (final DriveReplicaSegment segment in changes.segments) {
          applied += await repository.applyDriveSegment(
            segment,
            trackerTargets: targets,
          );
        }
        await repository.saveDriveChangePageToken(changes.nextPageToken);
        if (changes.manifestChanged) {
          await repository.applyRemoteDeliveryLedger(
            await libraryCloud.readDeliveryLedger(
              manifestFileId: changes.manifestFileId,
            ),
          );
        }
        _markLibraryPulled(repository.replicaNamespace);
        if (remoteChangesOnly) {
          if (restoredSnapshot || applied > 0) {
            ref.invalidate(trackerLocalAnimeLibraryProvider);
            ref.invalidate(trackerLocalMangaLibraryProvider);
            ref.invalidate(trackerAnimeListProvider);
            ref.invalidate(trackerMangaListProvider);
          }
          _setState(
            (state.value ?? current).copyWith(
              syncing: false,
              checking: false,
              connected: true,
              lastSyncAt: DateTime.now().toUtc(),
              appliedSegments: applied,
              clearError: true,
              clearProgress: true,
            ),
          );
          return;
        }
        _setProgress(stage: 'Uploading local changes…', progress: 0.15);
        final bool moreLocalChanges = await _pushPendingLibrarySegments(
          repository,
          libraryCloud,
          progressStart: 0.15,
          progressEnd: 0.68,
        );
        if (_disposed || _shuttingDown) return;
        // Immutable segments already make the change available to other
        // devices. Rebuilding the entire Library here made every playback
        // checkpoint serialize years of history on the UI isolate. A full
        // sync publishes the compact backup later, using a durable watermark.
        _setProgress(stage: 'Finishing sync…', progress: 0.96);
        if (moreLocalChanges) {
          _scheduleLocalCheckpointRetry();
        } else {
          _localRetryAttempt = 0;
        }
        final int localEntryCount = await repository.activeLibraryEntryCount();
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
            checking: false,
            connected: true,
            lastSyncAt: completedAt,
            appliedSegments: applied,
            cloudEntryCount: moreLocalChanges
                ? cloudSnapshot?.entryCount
                : localEntryCount,
            localEntryCount: localEntryCount,
            clearError: true,
            clearProgress: true,
          ),
        );
        return;
      }
      _setProgress(stage: 'Syncing accounts…', progress: 0.03);
      unawaited(
        _refreshAccountProfile(
          token,
          fallback: state.value?.account ?? current.account,
          cancelToken: cancelToken,
        ),
      );
      final GoogleDriveCloudReplica cloud = GoogleDriveCloudReplica(
        accessToken: token,
        cancelToken: cancelToken,
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
          _applyingRemoteChanges = true;
          try {
            await settingsController.applyDriveAniListAccounts(
              accounts: accountResult.accounts,
              preferredActiveViewerId: accountResult.preferredActiveViewerId,
            );
            invalidateAniListLibraryProviders(ref.invalidate);
            ref.invalidate(trackerAnimeListProvider);
          } finally {
            _applyingRemoteChanges = false;
          }
        }
        _accountsRestored = true;
      } on Object catch (error) {
        if (_isCancelled(error)) rethrow;
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
          _applyingRemoteChanges = true;
          try {
            await settingsController.reloadDrivePreferences();
            ref.read(drivePreferencesRevisionProvider.notifier).changed();
            ref.invalidate(playerSettingsProvider);
            ref.invalidate(aniListUserSettingsProvider);
            ref.invalidate(watchPartyConnectionSettingsProvider);
          } finally {
            _applyingRemoteChanges = false;
          }
        }
      } on Object catch (error) {
        if (_isCancelled(error)) rethrow;
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
        cancelToken: cancelToken,
      );
      activeCloud = libraryCloud;
      _setProgress(stage: 'Checking Library changes…', progress: 0.23);
      final Set<TrackerSource> targets = _connectedTrackerTargets(
        ref.read(settingsProvider),
      );
      final String? appliedSnapshotChecksum = await repository
          .appliedDriveSnapshotChecksum();
      final DriveLibraryChanges changes = await libraryCloud.pullLibraryChanges(
        excluding: await repository.processedDriveSegmentNames(),
        pageToken: await repository.driveChangePageToken(),
      );
      final DriveLibrarySnapshot? cloudSnapshot =
          changes.manifestChanged || appliedSnapshotChecksum == null
          ? await libraryCloud.pullLibrarySnapshot(
              excludingChecksum: appliedSnapshotChecksum,
              manifestFileId: changes.manifestFileId,
              snapshotFileId: changes.snapshotFileId,
              onProgress: (int received, int total) => _setTransferProgress(
                stage: 'Downloading Library backup…',
                transferred: received,
                total: total,
                start: 0.23,
                end: 0.48,
              ),
            )
          : null;
      if (cloudSnapshot != null &&
          !await repository.hasAppliedDriveSnapshot(cloudSnapshot.checksum)) {
        await repository.applyDriveSnapshot(
          cloudSnapshot,
          trackerTargets: targets,
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
      int applied = 0;
      for (final DriveReplicaSegment segment in changes.segments) {
        applied += await repository.applyDriveSegment(
          segment,
          trackerTargets: targets,
        );
      }
      await repository.saveDriveChangePageToken(changes.nextPageToken);
      if (applied > 0) {
        ref.invalidate(trackerLocalAnimeLibraryProvider);
        ref.invalidate(trackerLocalMangaLibraryProvider);
        ref.invalidate(trackerAnimeListProvider);
        ref.invalidate(trackerMangaListProvider);
      }
      if (changes.manifestChanged) {
        await repository.applyRemoteDeliveryLedger(
          await libraryCloud.readDeliveryLedger(
            manifestFileId: changes.manifestFileId,
          ),
        );
      }
      _markLibraryPulled(repository.replicaNamespace);
      _setProgress(stage: 'Uploading local changes…', progress: 0.76);
      final bool moreLocalChanges = await _pushPendingLibrarySegments(
        repository,
        libraryCloud,
        progressStart: 0.76,
        progressEnd: 0.8,
      );
      if (_disposed || _shuttingDown) return;
      // The library is the user's critical path. Addons are an independent
      // replica: a slow/failed addon request must not delay receiving or
      // publishing the latest library changes on another device.
      _setProgress(stage: 'Syncing addons…', progress: 0.8);
      try {
        final AddonDriveSyncResult addonResult = await AddonDriveSyncService(
          preferences: await SharedPreferences.getInstance(),
          store: ref.read(soraAddonStoreProvider),
        ).sync(cloud: cloud, deviceId: leaseDeviceId);
        if (addonResult.localStateChanged) {
          _applyingRemoteChanges = true;
          try {
            ref.invalidate(soraJsRuntimeProvider);
            ref.invalidate(addonCatalogProvider);
            await ref.read(soraAddonsProvider.notifier).load();
            await ref.read(addonSourcesProvider.notifier).load();
          } finally {
            _applyingRemoteChanges = false;
          }
        }
      } on Object catch (error) {
        if (_isCancelled(error)) rethrow;
        debugPrint('Google Drive addon sync failed: $error');
        replicaWarnings.add('addons');
      }
      final int pushedSegmentCount = await repository.pushedDriveSegmentCount();
      final bool needsCheckpoint =
          pushedSegmentCount >
              await repository.checkpointedDriveSegmentCount() ||
          (cloudSnapshot == null && appliedSnapshotChecksum == null);
      // Tracker delivery has its own background queue. Waiting for every
      // AniList/MAL/Shikimori request here can hold the Drive UI at 377/377
      // for hours even though all local segments are already uploaded.
      // The lease in this pass only protects the compact Drive checkpoint.
      if (needsCheckpoint) {
        _setProgress(stage: 'Preparing Library backup…', progress: 0.81);
      }
      ownsDeliveryLease =
          needsCheckpoint &&
          await libraryCloud.acquireDeliveryLease(deviceId: leaseDeviceId);
      if (ownsDeliveryLease) {
        await libraryCloud.mergeDeliveryLedger(
          await repository.confirmedTrackerDeliveryLedger(),
        );
      }
      final DriveLibrarySnapshot? outgoingSnapshot =
          ownsDeliveryLease && needsCheckpoint
          ? await repository.buildDriveSnapshot()
          : null;
      if (outgoingSnapshot != null) {
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
        await repository.markDriveSnapshotPublished(pushedSegmentCount);
      }
      _setProgress(stage: 'Finishing sync…', progress: 0.96);
      final DateTime completedAt = DateTime.now().toUtc();
      await (await SharedPreferences.getInstance()).setString(
        _googleDriveLastFullSyncAtKey,
        completedAt.toIso8601String(),
      );
      if (_disposed || _shuttingDown) return;
      if (outgoingSnapshot != null) {
        _localRetryAttempt = 0;
      } else if (needsCheckpoint) {
        // The immutable segments are already safe in Drive, but the compact
        // snapshot/count still belongs to the current lease holder. Retry the
        // checkpoint soon instead of waiting for the 15-minute periodic sync.
        _scheduleLocalCheckpointRetry();
      }
      if (moreLocalChanges) _scheduleLocalCheckpointRetry();
      final int localEntryCount = await repository.activeLibraryEntryCount();
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
          checking: false,
          connected: true,
          lastSyncAt: completedAt,
          appliedSegments: applied,
          clearProgress: true,
          cloudEntryCount: moreLocalChanges
              ? (outgoingSnapshot?.entryCount ?? cloudSnapshot?.entryCount)
              : localEntryCount,
          localEntryCount: localEntryCount,
          lastError: replicaWarnings.isEmpty
              ? null
              : _replicaWarningCode(replicaWarnings),
          clearError: replicaWarnings.isEmpty,
        ),
      );
      // Size is display-only. Listing every historical appData file must not
      // hold the sync button and Library readiness hostage.
      unawaited(_refreshDriveUsage(libraryCloud));
    } on Object catch (error) {
      if (_disposed || _shuttingDown || _isCancelled(error)) {
        return;
      }
      debugPrint('Google Drive sync failed: $error');
      if (localChangesOnly) {
        _scheduleLocalCheckpointRetry();
      } else {
        _scheduleFullSyncRetry();
      }
      final GoogleDriveSyncState latest = state.value ?? current;
      _setState(
        latest.copyWith(
          syncing: false,
          checking: false,
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
      if (!_disposed && !_shuttingDown && state.value?.checking == true) {
        _setState(state.value!.copyWith(checking: false));
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
        transferredBytes: 0,
        totalBytes: 0,
        processedItems: 0,
        totalItems: 0,
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

  Future<bool> _pushPendingLibrarySegments(
    CanonicalLibraryRepository repository,
    GoogleDriveCloudReplica cloud, {
    required double progressStart,
    required double progressEnd,
  }) async {
    final int initialPending = await repository.pendingDriveDeliveryCount();
    if (initialPending == 0) return false;
    int processed = 0;
    _setItemProgress(
      stage: 'Uploading local changes…',
      completed: 0,
      total: initialPending,
      start: progressStart,
      end: progressEnd,
    );
    DriveReplicaSegment? outgoing = await repository.buildPendingDriveSegment();
    while (outgoing != null && processed < initialPending) {
      final int batchSize = outgoing.operations.length;
      final double batchStart =
          progressStart +
          (progressEnd - progressStart) *
              (processed / initialPending).clamp(0.0, 1.0);
      final double batchEnd =
          progressStart +
          (progressEnd - progressStart) *
              ((processed + batchSize) / initialPending).clamp(0.0, 1.0);
      final CloudReplicaFile file = await cloud.pushSegment(
        outgoing,
        onProgress: (int sent, int total) => _setTransferProgress(
          stage: 'Uploading local changes…',
          transferred: sent,
          total: total,
          start: batchStart,
          end: batchEnd,
        ),
      );
      await repository.markDriveSegmentDelivered(
        outgoing,
        remoteFileId: file.id,
      );
      processed += batchSize;
      _setItemProgress(
        stage: 'Uploading local changes…',
        completed: processed.clamp(0, initialPending),
        total: initialPending,
        start: progressStart,
        end: progressEnd,
      );
      outgoing = await repository.buildPendingDriveSegment();
    }
    return (await repository.pendingDriveDeliveryCount()) > 0;
  }

  Future<void> _refreshDriveUsage(GoogleDriveCloudReplica cloud) async {
    try {
      final DriveReplicaUsage usage = await cloud.readUsage();
      if (_disposed || _shuttingDown) return;
      final GoogleDriveSyncState? current = state.value;
      if (current == null || !current.connected) return;
      _setState(
        current.copyWith(
          driveUsageBytes: usage.totalBytes,
          driveFileCount: usage.fileCount,
        ),
      );
    } on Object catch (error) {
      debugPrint('Could not refresh Google Drive storage size: $error');
    }
  }

  void _setState(GoogleDriveSyncState next) {
    if (_disposed) return;
    state = AsyncData(next);
  }

  void _markLibraryPulled(String workspace) {
    _pulledLibraryWorkspaces.add(workspace);
    _lastLibraryPullAt[workspace] = DateTime.now().toUtc();
    if (!_accountsRestored || !_trackerOutboxResumedWorkspaces.add(workspace)) {
      return;
    }
    // Resume the durable provider queue after an automatic retry succeeds.
    // A manual user edit never has to wait for this background work.
    unawaited(
      Future<void>(() async {
        if (_disposed || _shuttingDown) return;
        try {
          await ref.read(trackerSyncCoordinatorProvider).flushPending();
        } on Object catch (error) {
          debugPrint('Tracker outbox retry after Drive pull failed: $error');
        }
      }),
    );
  }

  bool _libraryPullIsFresh(String workspace) {
    final DateTime? last = _lastLibraryPullAt[workspace];
    return last != null &&
        DateTime.now().toUtc().difference(last) <=
            _trackerDeliveryPullFreshness;
  }

  void _scheduleLocalCheckpointRetry() {
    if (_disposed || _shuttingDown) return;
    if (_localRetryAttempt >= _maximumAutomaticRetries) return;
    _localCheckpointRetry?.cancel();
    final int exponent = _localRetryAttempt.clamp(0, 5);
    final Duration delay = Duration(
      seconds: (15 * (1 << exponent)).clamp(15, 300),
    );
    _localRetryAttempt += 1;
    _localCheckpointRetry = Timer(delay, () {
      _localCheckpointRetry = null;
      if (_disposed || _shuttingDown) return;
      unawaited(
        syncNow(background: true, localChangesOnly: true, automaticRetry: true),
      );
    });
  }

  void _scheduleFullSyncRetry() {
    if (_disposed || _shuttingDown) return;
    if (_fullRetryAttempt >= _maximumAutomaticRetries) return;
    _fullSyncRetry?.cancel();
    final int exponent = _fullRetryAttempt.clamp(0, 5);
    final Duration delay = Duration(
      seconds: (15 * (1 << exponent)).clamp(15, 300),
    );
    _fullRetryAttempt += 1;
    _fullSyncRetry = Timer(delay, () {
      _fullSyncRetry = null;
      if (_disposed || _shuttingDown) return;
      unawaited(syncNow(background: true, automaticRetry: true));
    });
  }

  Future<String?> _validAccessToken({CancelToken? cancelToken}) async {
    final String? storedAccessToken = await _storedAccessToken();
    if (storedAccessToken != null) return storedAccessToken;

    final String refreshToken =
        (await _storage.readGoogleDriveRefreshToken()) ?? '';
    if (refreshToken.isNotEmpty) {
      final GoogleDriveTokenBundle refreshed = await GoogleDriveOAuthService()
          .refresh(
            refreshToken: refreshToken,
            television:
                TvPlatform.isAndroidTv ||
                GoogleDriveNativeAuthService.isSupported,
            cancelToken: cancelToken,
          );
      await connect(refreshed);
      return refreshed.accessToken;
    }

    // Older native sessions may not have a refresh token. Probe the platform
    // SDK only as a last resort so re-signed/containerized mobile builds never
    // pay a four-second native-auth timeout on every Drive checkpoint.
    if (GoogleDriveNativeAuthService.isSupported) {
      try {
        final String? nativeToken = await const GoogleDriveNativeAuthService()
            .restoreAccessToken()
            .timeout(const Duration(seconds: 4));
        if (nativeToken != null && nativeToken.isNotEmpty) {
          await _storeNativeAccessToken(nativeToken);
          return nativeToken;
        }
      } on Object {
        // Fall through to the Worker-issued device-flow session below. This is
        // required for LiveContainer, TrollStore and re-signed iOS bundles.
      }
    }
    return null;
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
    CancelToken? cancelToken,
  }) async {
    try {
      final GoogleDriveAccountProfile account = await GoogleDriveAccountClient()
          .fetchProfile(accessToken, cancelToken: cancelToken);
      if (await _storedAccessToken() == accessToken) {
        await _storage.writeGoogleDriveAccountProfile(
          jsonEncode(account.toJson()),
        );
      }
      return account;
    } on Object catch (error) {
      if (_isCancelled(error)) rethrow;
      // Account decoration must never block local/cloud synchronization. The
      // next successful sync retries the lightweight Drive about.get call.
      return fallback;
    }
  }

  Future<void> _refreshAccountProfile(
    String accessToken, {
    GoogleDriveAccountProfile? fallback,
    CancelToken? cancelToken,
  }) async {
    try {
      final GoogleDriveAccountProfile? account =
          await _fetchAndStoreAccountProfile(
            accessToken,
            fallback: fallback,
            cancelToken: cancelToken,
          );
      if (account == null ||
          _disposed ||
          _shuttingDown ||
          await _storedAccessToken() != accessToken) {
        return;
      }
      final GoogleDriveSyncState? current = state.value;
      if (current?.connected == true) {
        _setState(current!.copyWith(account: account));
      }
    } on Object {
      // Profile decoration is independent of Library restoration.
    }
  }
}

bool _isCancelled(Object error) =>
    error is DioException && error.type == DioExceptionType.cancel;

Set<TrackerSource> _connectedTrackerTargets(SettingsState settings) =>
    <TrackerSource>{
      if (settings.hasAniListSession) TrackerSource.anilist,
      if (settings.hasMalSession) TrackerSource.mal,
      if (settings.hasShikimoriSession) TrackerSource.shikimori,
    };
