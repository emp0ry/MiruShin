import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/application/tracker_sync_coordinator.dart';

final libraryRefreshControllerProvider = Provider<LibraryRefreshController>((
  ref,
) {
  final sync = ref.watch(trackerSyncCoordinatorProvider);
  return LibraryRefreshController(
    (kind, force) => sync.refreshSelectedLibrary(mediaKind: kind, force: force),
  );
});

/// Shared by gestures, the desktop button and lifecycle refreshes. The provider
/// is scoped to the coordinator's account, selected source and sync mode.
class LibraryRefreshController {
  LibraryRefreshController(
    this._fetch, {
    DateTime Function()? now,
    this.waitTimeout = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;
  final Future<TrackerLibrarySnapshot> Function(String, bool) _fetch;
  final DateTime Function() _now;
  final Duration waitTimeout;
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, Future<void>> _pending = {};
  final Map<String, DateTime> _completed = {};

  Future<void> refresh(String kind, {bool force = true}) {
    final pending = _pending[kind];
    if (pending != null) return pending;
    final completed = _completed[kind];
    if (!force &&
        completed != null &&
        _now().difference(completed) < const Duration(minutes: 1)) {
      return Future.value();
    }
    // A catalog refresh can queue behind a long outbox replay or server
    // cooldown. Bound the UI wait without cancelling ordered sync writes.
    // Keep sharing the actual read after a timeout, so Retry/resume cannot
    // enqueue another full-list read every time the UI stops waiting.
    final operation = _inFlight[kind] ?? _startFetch(kind, force);
    late final Future<void> task;
    task = operation.timeout(waitTimeout).whenComplete(() {
      if (identical(_pending[kind], task)) _pending.remove(kind);
    });
    _pending[kind] = task;
    return task;
  }

  Future<void> _startFetch(String kind, bool force) {
    late final Future<void> operation;
    operation =
        Future<void>.sync(() async {
          final result = await _fetch(kind, force);
          if (result.fromCache) throw const LibraryRefreshUnavailable();
          _completed[kind] = _now();
        }).whenComplete(() {
          if (identical(_inFlight[kind], operation)) _inFlight.remove(kind);
        });
    _inFlight[kind] = operation;
    return operation;
  }
}

class LibraryRefreshUnavailable implements Exception {
  const LibraryRefreshUnavailable();
}
