import '../../library/application/canonical_library_repository.dart';
import '../domain/tracker_models.dart';
import '../domain/tracking_sync_models.dart';
import 'tracking_sync_store.dart';

class CanonicalTrackingSyncStore
    implements
        TrackingSyncStore,
        AtomicTrackingSyncStore,
        ReconciliationTrackingSyncStore,
        DeliveryTrackingSyncStore,
        MigrationSafeModeTrackingSyncStore {
  CanonicalTrackingSyncStore({
    required CanonicalLibraryRepository repository,
    SharedPreferencesTrackingSyncStore legacy =
        const SharedPreferencesTrackingSyncStore(),
  }) : _repository = repository,
       _legacy = legacy;

  final CanonicalLibraryRepository _repository;
  final SharedPreferencesTrackingSyncStore _legacy;
  Future<void>? _migration;
  bool _migrationSafeMode = false;

  Future<void> _ensureMigrated() => _migration ??= _migrate();

  Future<void> _migrate() async {
    try {
      await _repository.initialize();
      if (await _repository.hasMigration('tracking.shared_preferences.v1')) {
        return;
      }
      if (!_repository.importsLegacyData) {
        await _repository.importTrackingData(
          states: const <UserMediaState>[],
          journal: const <SyncJournalEntry>[],
          favorites: const <LocalMediaFavoriteState>[],
          health: const <TrackerSource, TrackerProviderHealth>{},
        );
        return;
      }
      final List<UserMediaState> states = await _legacy.loadStates();
      final List<SyncJournalEntry> journal = await _legacy.loadJournal();
      final List<LocalMediaFavoriteState> favorites = await _legacy
          .loadFavorites();
      final Map<TrackerSource, TrackerProviderHealth> health = await _legacy
          .loadHealth();
      await _repository.importTrackingData(
        states: states,
        journal: journal,
        favorites: favorites,
        health: health,
      );
    } on Object {
      // The import transaction is rolled back by Drift. Keep all legacy keys
      // untouched and serve them read/write for this process, but expose safe
      // mode so the engine never reconciles or delivers against trackers.
      _migrationSafeMode = true;
    }
  }

  @override
  Future<bool> isInMigrationSafeMode() async {
    await _ensureMigrated();
    return _migrationSafeMode;
  }

  @override
  Future<List<UserMediaState>> loadStates() async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.loadStates();
    return _repository.loadTrackingStates();
  }

  @override
  Future<void> saveStates(List<UserMediaState> states) async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.saveStates(states);
    await _repository.saveTrackingStates(states);
  }

  @override
  Future<List<SyncJournalEntry>> loadJournal() async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.loadJournal();
    return _repository.loadJournal();
  }

  @override
  Future<void> saveJournal(List<SyncJournalEntry> entries) async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.saveJournal(entries);
    await _repository.saveJournal(entries);
  }

  @override
  Future<List<LocalMediaFavoriteState>> loadFavorites() async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.loadFavorites();
    return _repository.loadFavorites();
  }

  @override
  Future<void> saveFavorites(List<LocalMediaFavoriteState> favorites) async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.saveFavorites(favorites);
    await _repository.saveFavorites(favorites);
  }

  @override
  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth() async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.loadHealth();
    return _repository.loadHealth();
  }

  @override
  Future<void> saveHealth(
    Map<TrackerSource, TrackerProviderHealth> health,
  ) async {
    await _ensureMigrated();
    if (_migrationSafeMode) return _legacy.saveHealth(health);
    await _repository.saveHealth(health);
  }

  @override
  Future<void> commitMutation({
    required List<UserMediaState> states,
    required List<SyncJournalEntry> journal,
    required List<LocalMediaFavoriteState> favorites,
    required MediaIdentity identity,
    required UserMediaPatch patch,
    required Set<TrackerSource> targets,
    required DateTime occurredAt,
    String? mediaTitle,
    TrackingEpisodeCheckpoint? episodeCheckpoint,
  }) async {
    await _ensureMigrated();
    if (_migrationSafeMode) {
      await _legacy.saveStates(states);
      await _legacy.saveFavorites(favorites);
      await _legacy.saveJournal(journal);
      return;
    }
    await _repository.commitTrackingMutation(
      states: states,
      journal: journal,
      favorites: favorites,
      identity: identity,
      patch: patch,
      targets: targets,
      occurredAt: occurredAt,
      mediaTitle: mediaTitle,
      episodeCheckpoint: episodeCheckpoint,
    );
  }

  @override
  Future<ProviderReconciliationResult> reconcileProviderSnapshot({
    required TrackerSource source,
    required String accountId,
    required String mediaKind,
    required List<UserMediaState> remote,
    required List<SyncJournalEntry> journal,
    required Set<TrackerSource> propagationTargets,
    required bool completeSnapshot,
  }) async {
    await _ensureMigrated();
    if (_migrationSafeMode) {
      return ProviderReconciliationResult(
        states: await _legacy.loadStates(),
        journal: await _legacy.loadJournal(),
      );
    }
    return _repository.reconcileProviderSnapshot(
      source: source,
      accountId: accountId,
      mediaKind: mediaKind,
      remote: remote,
      journal: journal,
      propagationTargets: propagationTargets,
      completeSnapshot: completeSnapshot,
    );
  }

  @override
  Future<void> updateTrackerDelivery({
    required MediaIdentity identity,
    required TrackerSource target,
    required String state,
    String? error,
  }) async {
    await _ensureMigrated();
    if (_migrationSafeMode) return;
    await _repository.updateTrackerDelivery(
      identity: identity,
      target: target,
      state: state,
      error: error,
    );
  }
}
