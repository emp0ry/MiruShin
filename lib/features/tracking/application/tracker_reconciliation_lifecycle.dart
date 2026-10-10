import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/application/canonical_library_repository.dart';
import '../../library/application/google_drive_sync_controller.dart';
import '../../settings/application/settings_state.dart';
import 'tracker_library_provider.dart';
import 'tracker_sync_coordinator.dart';

/// Runs one complete, provider-independent reconciliation after account
/// restoration, on resume, and once a minute while the app is foregrounded.
final trackerReconciliationLifecycleProvider = Provider<Future<void> Function()>(
  (Ref ref) {
    Timer? debounce;
    Future<void>? active;
    bool runAgain = false;
    bool disposed = false;
    DateTime? lastCompletedAt;
    bool foreground = true;

    Future<void> reconcile({bool force = false}) async {
      if (disposed) return;
      final DateTime now = DateTime.now().toUtc();
      final DateTime? last = lastCompletedAt;
      if (!force &&
          last != null &&
          now.difference(last) < const Duration(minutes: 1)) {
        return;
      }
      if (active != null) {
        runAgain = true;
        return active;
      }
      final Future<void> operation = () async {
        await ref.read(settingsProvider.notifier).ready;
        if (disposed) return;
        final GoogleDriveSyncState drive = await ref.read(
          googleDriveSyncControllerProvider.future,
        );
        if (disposed) return;
        if (drive.connected) {
          // Restore the current account's Drive operations before a provider
          // snapshot can be interpreted as a new local mutation on this device.
          final bool driveReady = await ref
              .read(googleDriveSyncControllerProvider.notifier)
              .ensureWorkspaceReadyForTrackerDelivery(
                ref.read(canonicalLibraryRepositoryProvider).replicaNamespace,
              );
          if (disposed || !driveReady) return;
        }
        final SettingsState settings = ref.read(settingsProvider);
        if (!settings.hasAniListSession &&
            !settings.hasMalSession &&
            !settings.hasShikimoriSession) {
          return;
        }
        final TrackerSyncCoordinator coordinator = ref.read(
          trackerSyncCoordinatorProvider,
        );
        // Queue both kinds on each provider's lane immediately. A stalled
        // catalog must not hold up another catalog's manga reconciliation.
        await Future.wait([
          coordinator.refreshAllConnectedLibraries(force: force),
          coordinator.refreshAllConnectedLibraries(
            mediaKind: 'manga',
            force: force,
          ),
        ]);
        if (disposed) return;
        ref.invalidate(trackerLocalAnimeLibraryProvider);
        ref.invalidate(trackerLocalMangaLibraryProvider);
        lastCompletedAt = DateTime.now().toUtc();
      }();
      active = operation;
      try {
        await operation;
      } on Object catch (error) {
        debugPrint('Tracker reconciliation failed safely: $error');
      } finally {
        if (identical(active, operation)) active = null;
        if (!disposed && runAgain) {
          runAgain = false;
          unawaited(reconcile(force: true));
        }
      }
    }

    void schedule({
      bool force = false,
      Duration delay = const Duration(seconds: 1),
    }) {
      if (disposed) return;
      debounce?.cancel();
      debounce = Timer(delay, () {
        if (disposed) return;
        unawaited(reconcile(force: force));
      });
    }

    unawaited(() async {
      await ref.read(settingsProvider.notifier).ready;
      if (disposed) return;
      // Reconciliation stays automatic, but does not compete with the first UI
      // frame, cached Board and local-library open on slower mobile devices.
      schedule(force: true, delay: const Duration(seconds: 3));
    }());

    ref.listen(
      settingsProvider.select(
        (SettingsState settings) => (
          settings.anilistViewerId,
          settings.anilistAccessToken,
          settings.hasAniListSession,
          settings.malViewerId,
          settings.malAccessToken,
          settings.hasMalSession,
          settings.shikimoriViewerId,
          settings.shikimoriAccessToken,
          settings.hasShikimoriSession,
          settings.primaryTrackerSource,
        ),
      ),
      (previous, next) {
        if (previous == null || previous == next) return;
        schedule(force: true);
      },
    );

    final periodic = Timer.periodic(const Duration(minutes: 1), (_) {
      if (foreground && !disposed && active == null) schedule();
    });
    bool? connected;
    final connectivity = Connectivity().onConnectivityChanged.listen(
      (values) {
        final available = values.any(
          (value) => value != ConnectivityResult.none,
        );
        if (available && connected == false && foreground && !disposed) {
          schedule(force: true, delay: const Duration(milliseconds: 150));
        }
        connected = available;
      },
      onError: (Object error) {
        // Network observation is only a wake-up hint; timed retries still work.
        debugPrint('Network-change observation unavailable: $error');
      },
    );
    final AppLifecycleListener lifecycle = AppLifecycleListener(
      onResume: () {
        foreground = true;
        schedule(force: true);
      },
      onPause: () {
        foreground = false;
      },
      onHide: () {
        foreground = false;
      },
    );
    Future<void> stop() async {
      if (disposed) {
        try {
          await active;
        } catch (_) {}
        return;
      }
      disposed = true;
      runAgain = false;
      debounce?.cancel();
      periodic.cancel();
      await connectivity.cancel();
      lifecycle.dispose();
      try {
        await active;
      } catch (_) {
        // The coordinator cancels network requests during process exit.
      }
    }

    ref.onDispose(() => unawaited(stop()));
    return stop;
  },
);
