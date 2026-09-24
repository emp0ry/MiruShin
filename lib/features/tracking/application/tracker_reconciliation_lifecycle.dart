import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  DateTime? lastCompletedAt;

  Future<void> reconcile({bool force = false}) async {
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
      await coordinator.refreshAllConnectedLibraries(mediaKind: 'manga');
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
      if (runAgain) {
        runAgain = false;
        unawaited(reconcile(force: true));
      }
    }
  }

  void schedule({bool force = false}) {
    debounce?.cancel();
    debounce = Timer(
      const Duration(seconds: 1),
      () => unawaited(reconcile(force: force)),
    );
  }

  unawaited(() async {
    await ref.read(settingsProvider.notifier).ready;
    schedule(force: true);
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
    debounce?.cancel();
    lifecycle.dispose();
  });
});
