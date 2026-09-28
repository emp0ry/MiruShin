import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/application/google_drive_sync_controller.dart';
import '../../settings/application/settings_state.dart';
import 'tracker_library_provider.dart';
import 'tracker_sync_coordinator.dart';

/// Runs one complete, provider-independent reconciliation after account
/// restoration and when the app returns to the foreground. There is no
/// periodic tracker polling: local mutations still use their own outboxes.
final trackerReconciliationLifecycleProvider = Provider<void>((Ref ref) {
  Timer? debounce;
  Future<void>? active;
  bool runAgain = false;
  bool disposed = false;
  DateTime? lastCompletedAt;

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
        await ref
            .read(googleDriveSyncControllerProvider.notifier)
            .syncBeforeTrackerReconciliation();
        if (disposed) return;
        final GoogleDriveSyncState? refreshed = ref
            .read(googleDriveSyncControllerProvider)
            .value;
        if (refreshed?.lastError ==
            'Google Drive sync failed. Please try again.') {
          return;
        }
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
      await coordinator.refreshAllConnectedLibraries();
      if (disposed) return;
      await coordinator.refreshAllConnectedLibraries(mediaKind: 'manga');
      if (disposed) return;
      ref.invalidate(trackerLocalAnimeLibraryProvider);
      ref.invalidate(trackerLocalMangaLibraryProvider);
      ref.invalidate(trackerAnimeListProvider);
      ref.invalidate(trackerMangaListProvider);
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
        settings.hasAniListSession,
        settings.malViewerId,
        settings.hasMalSession,
        settings.shikimoriViewerId,
        settings.hasShikimoriSession,
      ),
    ),
    (previous, next) {
      if (previous == null || previous == next) return;
      schedule(force: true);
    },
  );

  final AppLifecycleListener lifecycle = AppLifecycleListener(
    onResume: schedule,
  );
  ref.onDispose(() {
    disposed = true;
    runAgain = false;
    debounce?.cancel();
    lifecycle.dispose();
  });
});
