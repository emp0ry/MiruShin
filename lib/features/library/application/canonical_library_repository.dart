import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../settings/application/settings_state.dart';
import '../../tracking/data/tracking_sync_store.dart';
import '../../tracking/domain/provider_field_projection.dart';
import '../../tracking/domain/tracker_models.dart';
import '../../tracking/domain/tracking_sync_models.dart';
import '../data/canonical_library_database.dart';
import '../domain/canonical_library_models.dart';
import '../domain/cloud_replica_models.dart';

class LibraryWorkspaceScope {
  const LibraryWorkspaceScope({
    required this.workspaceId,
    required this.databaseName,
    required this.replicaNamespace,
    required this.importsLegacyData,
    this.legacyDatabaseName,
  });

  final String workspaceId;
  final String databaseName;
  final String replicaNamespace;
  final bool importsLegacyData;
  final String? legacyDatabaseName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryWorkspaceScope &&
          workspaceId == other.workspaceId &&
          databaseName == other.databaseName &&
          replicaNamespace == other.replicaNamespace &&
          importsLegacyData == other.importsLegacyData &&
          legacyDatabaseName == other.legacyDatabaseName;

  @override
  int get hashCode => Object.hash(
    workspaceId,
    databaseName,
    replicaNamespace,
    importsLegacyData,
    legacyDatabaseName,
  );
}

class DriveSnapshotApplyResult {
  const DriveSnapshotApplyResult({
    required this.cloudEntryCount,
    required this.localEntryCount,
    required this.restoredEntries,
    required this.recoveredOperations,
    required this.freshBootstrap,
  });

  final int cloudEntryCount;
  final int localEntryCount;
  final int restoredEntries;
  final int recoveredOperations;
  final bool freshBootstrap;
}

final libraryWorkspaceScopeProvider = Provider<LibraryWorkspaceScope>((
  Ref ref,
) {
  final SettingsState settings = ref.watch(settingsProvider);
  // Signing out disconnects providers, but the user's last selected Local
  // Library must remain available offline. A fresh install with no selected
  // account still receives the independent `local` workspace.
  final int? activeId =
      settings.anilistViewerId ?? settings.selectedLibraryAniListId;
  final int? savedOwnerId = settings.canonicalLibraryOwnerAniListId;
  final int? ownerId =
      savedOwnerId ??
      (settings.anilistSavedAccounts.isNotEmpty
          ? settings.anilistSavedAccounts.first.viewerId
          : activeId);
  if (activeId != null && activeId == ownerId) {
    return LibraryWorkspaceScope(
      workspaceId: 'anilist:$activeId',
      databaseName: kIsWeb
          ? 'mirushin_canonical_library_v1'
          : 'mirushin_canonical_library_anilist_${activeId}_v1',
      replicaNamespace: 'anilist-$activeId',
      importsLegacyData: true,
      legacyDatabaseName: kIsWeb ? null : 'mirushin_canonical_library_v1',
    );
  }
  if (activeId != null) {
    return LibraryWorkspaceScope(
      workspaceId: 'anilist:$activeId',
      databaseName: 'mirushin_canonical_library_anilist_${activeId}_v1',
      replicaNamespace: 'anilist-$activeId',
      importsLegacyData: false,
    );
  }
  if (ownerId != null) {
    return const LibraryWorkspaceScope(
      workspaceId: 'local',
      databaseName: 'mirushin_canonical_library_local_v1',
      replicaNamespace: 'local',
      importsLegacyData: false,
    );
  }
  final bool canImportUnownedLegacyLibrary = ownerId == null;
  return LibraryWorkspaceScope(
    workspaceId: 'local',
    databaseName: kIsWeb
        ? 'mirushin_canonical_library_v1'
        : 'mirushin_canonical_library_local_v1',
    replicaNamespace: 'local',
    // If an AniList owner is known, the old unscoped database belongs to that
    // account even while it is signed out. Opening the local workspace must
    // never move or import another account's library.
    importsLegacyData: canImportUnownedLegacyLibrary,
    legacyDatabaseName: kIsWeb || !canImportUnownedLegacyLibrary
        ? null
        : 'mirushin_canonical_library_v1',
  );
});

typedef CanonicalLibraryDatabaseFactory =
    CanonicalLibraryDatabase Function(String name, String? legacyName);

final canonicalLibraryDatabaseFactoryProvider =
    Provider<CanonicalLibraryDatabaseFactory>(
      (Ref ref) =>
          (String name, String? legacyName) =>
              CanonicalLibraryDatabase(null, name, legacyName),
    );

/// Owns the shutdown of every workspace database opened during this process.
///
/// Riverpod disposal callbacks are synchronous, while Drift closes its native
/// database isolate asynchronously. Awaiting this registry from the desktop
/// exit handshake prevents the Dart VM from running sqlite statement
/// finalizers after the native connection has already been torn down.
class CanonicalLibraryDatabaseRegistry {
  final Set<CanonicalLibraryDatabase> _databases = <CanonicalLibraryDatabase>{};
  final Map<CanonicalLibraryDatabase, Future<void>> _closing =
      <CanonicalLibraryDatabase, Future<void>>{};
  Future<void>? _shutdown;
  bool _acceptingDatabases = true;

  bool get isShuttingDown => !_acceptingDatabases;

  void register(CanonicalLibraryDatabase database) {
    if (isShuttingDown) {
      throw StateError('Cannot open a library database during shutdown.');
    }
    if (_closing.containsKey(database)) return;
    _databases.add(database);
  }

  Future<void> close(CanonicalLibraryDatabase database) {
    return _closing.putIfAbsent(database, () async {
      _databases.remove(database);
      await database.close();
    });
  }

  Future<void> closeAll() {
    final Future<void>? shutdown = _shutdown;
    if (shutdown != null) return shutdown;
    _acceptingDatabases = false;
    final List<CanonicalLibraryDatabase> databases = _databases.toList(
      growable: false,
    );
    for (final database in databases) {
      close(database);
    }
    // A provider may already have started closing its DB. It is no longer in
    // _databases, but native exit must still wait for its isolate/read pool.
    return _shutdown = Future.wait<void>(
      _closing.values,
      eagerError: false,
    ).then((_) {});
  }
}

final canonicalLibraryDatabaseRegistryProvider =
    Provider<CanonicalLibraryDatabaseRegistry>(
      (Ref ref) => CanonicalLibraryDatabaseRegistry(),
    );

final _canonicalLibraryDatabaseByNameProvider =
    Provider.family<CanonicalLibraryDatabase, LibraryWorkspaceScope>((
      Ref ref,
      LibraryWorkspaceScope scope,
    ) {
      final CanonicalLibraryDatabaseRegistry registry = ref.watch(
        canonicalLibraryDatabaseRegistryProvider,
      );
      if (registry.isShuttingDown) {
        throw StateError('Cannot open a library database during shutdown.');
      }
      final CanonicalLibraryDatabase database = ref.watch(
        canonicalLibraryDatabaseFactoryProvider,
      )(scope.databaseName, scope.legacyDatabaseName);
      registry.register(database);
      ref.onDispose(() => unawaited(registry.close(database)));
      return database;
    });

final canonicalLibraryDatabaseProvider = Provider<CanonicalLibraryDatabase>((
  Ref ref,
) {
  final LibraryWorkspaceScope scope = ref.watch(libraryWorkspaceScopeProvider);
  // Account switches can leave an in-flight Drive delivery using the previous
  // workspace for a few milliseconds. The per-name provider keeps that DB
  // alive until the root ProviderContainer shuts down instead of closing its
  // isolate channel underneath the operation.
  return ref.watch(_canonicalLibraryDatabaseByNameProvider(scope));
});

final canonicalLibraryRepositoryProvider = Provider<CanonicalLibraryRepository>(
  (Ref ref) {
    final LibraryWorkspaceScope scope = ref.watch(
      libraryWorkspaceScopeProvider,
    );
    return CanonicalLibraryRepository(
      ref.watch(canonicalLibraryDatabaseProvider),
      workspaceId: scope.workspaceId,
      replicaNamespace: scope.replicaNamespace,
      importsLegacyData: scope.importsLegacyData,
    );
  },
);

final libraryActivityProvider =
    StreamProvider.autoDispose<List<LibraryActivityEvent>>((Ref ref) {
      return ref.watch(canonicalLibraryRepositoryProvider).watchActivity();
    });

final pendingDriveDeliveryCountProvider = StreamProvider.autoDispose<int>((
  Ref ref,
) {
  return ref
      .watch(canonicalLibraryRepositoryProvider)
      .watchPendingDriveDeliveryCount();
});

final libraryConflictsProvider =
    StreamProvider.autoDispose<List<CanonicalLibraryConflict>>((Ref ref) {
      return ref.watch(canonicalLibraryRepositoryProvider).watchConflicts();
    });

final pendingProviderAccountPreviewsProvider =
    FutureProvider.autoDispose<List<ProviderAccountPreview>>((Ref ref) {
      return ref
          .watch(canonicalLibraryRepositoryProvider)
          .pendingAccountPreviews();
    });

class CanonicalLibraryRepository {
  CanonicalLibraryRepository(
    this.database, {
    Uuid uuid = const Uuid(),
    this.workspaceId = 'legacy',
    this.replicaNamespace = 'legacy',
    this.importsLegacyData = true,
  }) : _uuid = uuid;

  final CanonicalLibraryDatabase database;
  final Uuid _uuid;
  final String workspaceId;
  final String replicaNamespace;
  final bool importsLegacyData;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await database.customSelect('SELECT 1').getSingle();
    await _ensureDeviceId();
  }

  /// Repairs only facts supported by existing operation history. No network
  /// read, wall-clock winner or guessed progress participates in this upgrade.
  Future<void> repairSyncConsistency() async {
    await initialize();
    await database.transaction(() async {
      final marker =
          await (database.select(database.syncCursorRecords)..where(
                (table) => table.scope.equals('migration:field-consistency.v1'),
              ))
              .getSingleOrNull();
      if (marker != null) return;
      final history =
          await (database.select(database.libraryOperationRecords)..orderBy([
                (table) => OrderingTerm.asc(table.occurredAtMs),
                (table) => OrderingTerm.asc(table.operationId),
              ]))
              .get();
      final operations = <String, Map<String, dynamic>>{
        for (final op in history)
          op.operationId: {
            'baseRevisions': _jsonMap(op.baseRevisionsJson),
            'after': _jsonMap(op.afterJson),
            'originKind': op.originKind,
            'occurredAtMs': op.occurredAtMs,
          },
      };
      final historyByLocal = <String, List<LibraryOperationRecord>>{};
      for (final op in history) {
        historyByLocal.putIfAbsent(op.localId, () => []).add(op);
      }
      final rows = await database
          .select(database.canonicalLibraryRecords)
          .get();
      final favoriteValues = await loadFavorites();
      for (final row in rows) {
        UserMediaState state = UserMediaState.fromJson(
          _jsonMap(row.canonicalStateJson),
        );
        final revisions = _jsonMap(row.fieldRevisionsJson);
        final originalFields = revisions.keys
            .where((field) => revisions[field] != null)
            .toSet();
        bool favorite = row.favorite;
        bool inLibrary = row.inLibrary;
        int? tombstonedAtMs = row.tombstonedAtMs;
        final Map<String, UserMediaState> parsedAfterStates = {};
        final rowHistory = historyByLocal[row.localId] ?? const [];
        // Legacy first-import operations had revisions in their history, but
        // not on their newly created canonical row. Recover matching values.
        for (final op in rowHistory) {
          final after = _jsonMap(operations[op.operationId]?['after']);
          final rawState = after['state'];
          final afterState = rawState is Map
              ? parsedAfterStates.putIfAbsent(
                  op.operationId,
                  () => UserMediaState.fromJson(
                    Map<String, dynamic>.from(rawState),
                  ),
                )
              : null;
          for (final field in _jsonStringSet(op.fieldsJson)) {
            if (originalFields.contains(field)) continue;
            if (_jsonEquivalent(
              _canonicalFieldValue(
                field,
                state,
                membership: row.inLibrary,
                favorite: favorite,
              ),
              _operationFieldValue(field, after, parsedState: afterState),
            )) {
              revisions[field] = _jsonMap(op.resultingRevisionsJson)[field];
            }
          }
        }
        // A stale whole-row write changed a value without changing its field
        // revision. Restore that revision's documented value, not a snapshot.
        for (final item in revisions.entries) {
          final leaves = _revisionLeaves(item.value);
          if (leaves.length != 1) continue;
          final id = _jsonMap(leaves.single)['operationId']?.toString();
          final op = operations[id];
          if (op == null) continue;
          final after = _jsonMap(op['after']);
          if (item.key == 'favorite' && after['favorite'] is bool) {
            favorite = after['favorite'] as bool;
          } else if (item.key == 'membership') {
            inLibrary = after['state'] is Map;
            tombstonedAtMs = inLibrary
                ? null
                : (op['occurredAtMs'] as int? ?? row.tombstonedAtMs);
          } else {
            final field = _fieldFromPersistedName(item.key);
            final raw = after['state'];
            if (field != null &&
                field != UserMediaField.favorite &&
                raw is Map) {
              state = state.apply(
                _patchFromState(
                  parsedAfterStates.putIfAbsent(
                    id!,
                    () =>
                        UserMediaState.fromJson(Map<String, dynamic>.from(raw)),
                  ),
                  {field},
                ),
                state.updatedAt.isAfter(
                      DateTime.fromMillisecondsSinceEpoch(
                        op['occurredAtMs'] as int,
                        isUtc: true,
                      ),
                    )
                    ? state.updatedAt
                    : DateTime.fromMillisecondsSinceEpoch(
                        op['occurredAtMs'] as int,
                        isUtc: true,
                      ),
              );
            }
          }
        }
        // The legacy favorites bucket is richer than SQLite's old default
        // false column; preserve it when no revisioned favorite exists.
        if (revisions['favorite'] == null) {
          for (final value in favoriteValues) {
            if (value.identity.matches(state.identity)) {
              favorite = value.favorite;
            }
          }
        }
        await _upsertTrackingStateLocked(state);
        await (database.update(
          database.canonicalLibraryRecords,
        )..where((table) => table.localId.equals(row.localId))).write(
          CanonicalLibraryRecordsCompanion(
            inLibrary: Value(inLibrary),
            tombstonedAtMs: Value(tombstonedAtMs),
            favorite: Value(favorite),
            fieldRevisionsJson: Value(jsonEncode(revisions)),
          ),
        );
        if (revisions.containsKey('favorite') || favorite) {
          await _setFavoriteLocked(
            localId: row.localId,
            identity: state.identity,
            favorite: favorite,
            at: state.updatedAt,
            mediaItem: state.mediaItem,
          );
        }
      }
      await _refreshActiveIdsLocked();
      await _retireObsoleteConflictsLocked(operations);
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: 'migration:field-consistency.v1',
              cursor: 'verified',
              updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
    });
  }

  Future<void> _retireObsoleteConflictsLocked(
    Map<String, Map<String, dynamic>> operations,
  ) async {
    final conflicts = await (database.select(
      database.libraryConflictRecords,
    )..where((table) => table.state.equals('open'))).get();
    final seen = <(String, String, String?)>{};
    for (final conflict in conflicts) {
      final row =
          await (database.select(database.canonicalLibraryRecords)
                ..where((table) => table.localId.equals(conflict.localId)))
              .getSingleOrNull();
      if (row == null) continue;
      Object? revision = _jsonMap(row.fieldRevisionsJson)[conflict.fieldName];
      final incoming = operations[conflict.incomingOperationId];
      if (incoming != null && !incoming.containsKey('after')) {
        final operation =
            await (database.selectOnly(database.libraryOperationRecords)
                  ..addColumns([database.libraryOperationRecords.afterJson])
                  ..where(
                    database.libraryOperationRecords.operationId.equals(
                      conflict.incomingOperationId!,
                    ),
                  ))
                .getSingleOrNull();
        if (operation != null) {
          incoming['after'] = _jsonMap(
            operation.read(database.libraryOperationRecords.afterJson),
          );
        }
      }
      final state = UserMediaState.fromJson(_jsonMap(row.canonicalStateJson));
      final legacyIncoming = _jsonMap(conflict.incomingValueJson);
      final incomingAfter = incoming != null
          ? _jsonMap(incoming['after'])
          : <String, dynamic>{
              if (legacyIncoming.containsKey('identity'))
                'state': legacyIncoming,
              if (legacyIncoming['favorite'] is bool)
                'favorite': legacyIncoming['favorite'],
              if (legacyIncoming['episode'] is Map)
                'episode': legacyIncoming['episode'],
            };
      Object? currentValue = _canonicalFieldValue(
        conflict.fieldName,
        state,
        membership: row.inLibrary,
        favorite: row.favorite,
      );
      if (conflict.fieldName == 'episodeProgress' &&
          incomingAfter['episode'] is Map) {
        final checkpoint = _jsonMap(incomingAfter['episode']);
        final episodeKey = _episodeRevisionKey(checkpoint);
        revision = _jsonMap(row.fieldRevisionsJson)[episodeKey] ?? revision;
        final episode =
            await (database.select(database.episodeStateRecords)..where(
                  (table) => table.episodeStateId.equals(
                    '${row.localId}:${(checkpoint['watchCycle'] as num?)?.toInt() ?? 0}:${(checkpoint['season'] as num?)?.toInt() ?? 1}:${(checkpoint['episode'] as num?)?.toDouble() ?? 1}',
                  ),
                ))
                .getSingleOrNull();
        currentValue = episode == null
            ? null
            : _episodeCheckpointValue(_episodeRowCheckpoint(episode));
      }
      final sameValue =
          (incoming != null ||
              legacyIncoming.containsKey('identity') ||
              (conflict.fieldName == 'favorite' &&
                  legacyIncoming['favorite'] is bool) ||
              legacyIncoming['episode'] is Map) &&
          (_fieldFromPersistedName(conflict.fieldName) != null ||
              conflict.fieldName == 'episodeProgress') &&
          _jsonEquivalent(
            currentValue,
            _operationFieldValue(conflict.fieldName, incomingAfter),
          );
      final obsolete =
          conflict.incomingOperationId != null &&
          _revisionDescendsFrom(
            revision,
            conflict.incomingOperationId!,
            conflict.fieldName,
            operations,
          );
      final staleProvider =
          (incoming?['originKind'] ??
                  _jsonMap(legacyIncoming['__incomingRevision'])['origin']) ==
              'provider' &&
          _revisionOrigins(revision).any((v) => v == 'user' || v == 'undo');
      final duplicate =
          conflict.incomingOperationId != null &&
          !seen.add((
            conflict.localId,
            conflict.fieldName,
            conflict.incomingOperationId,
          ));
      if (sameValue || obsolete || staleProvider || duplicate) {
        await (database.update(database.libraryConflictRecords)
              ..where((table) => table.conflictId.equals(conflict.conflictId)))
            .write(
              LibraryConflictRecordsCompanion(
                state: const Value('resolved'),
                resolvedAtMs: Value(
                  DateTime.now().toUtc().millisecondsSinceEpoch,
                ),
              ),
            );
      }
    }
  }

  Future<String> deviceId() async {
    await initialize();
    final LegacyBucketRecord? row =
        await (database.select(database.legacyBucketRecords)..where(
              (LegacyBucketRecords table) =>
                  table.bucket.equals('meta.deviceId'),
            ))
            .getSingleOrNull();
    if (row != null && row.valueJson.trim().isNotEmpty) return row.valueJson;
    return _ensureDeviceId();
  }

  Future<String> _ensureDeviceId() async {
    final LegacyBucketRecord? existing =
        await (database.select(database.legacyBucketRecords)..where(
              (LegacyBucketRecords table) =>
                  table.bucket.equals('meta.deviceId'),
            ))
            .getSingleOrNull();
    if (existing != null && existing.valueJson.trim().isNotEmpty) {
      return existing.valueJson;
    }
    final String id = _uuid.v7();
    await database
        .into(database.legacyBucketRecords)
        .insertOnConflictUpdate(
          LegacyBucketRecordsCompanion.insert(
            bucket: 'meta.deviceId',
            valueJson: id,
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  Future<bool> hasMigration(String name) async {
    await initialize();
    final SyncCursorRecord? cursor =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) =>
                  table.scope.equals('migration:$name'),
            ))
            .getSingleOrNull();
    return cursor?.cursor == 'complete';
  }

  Future<void> markMigrationComplete(String name) async {
    await database
        .into(database.syncCursorRecords)
        .insertOnConflictUpdate(
          SyncCursorRecordsCompanion.insert(
            scope: 'migration:$name',
            cursor: 'complete',
            metadataJson: const Value<String>('{}'),
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> importTrackingData({
    required List<UserMediaState> states,
    required List<SyncJournalEntry> journal,
    required List<LocalMediaFavoriteState> favorites,
    required Map<TrackerSource, TrackerProviderHealth> health,
  }) async {
    await initialize();
    if (await hasMigration('tracking.shared_preferences.v1')) return;
    await database.transaction(() async {
      await _writeBucketLocked(
        'migration.backup.tracking.shared_preferences.v1',
        <String, dynamic>{
          'states': states
              .map((UserMediaState value) => value.toJson())
              .toList(),
          'journal': journal
              .map((SyncJournalEntry value) => value.toJson())
              .toList(),
          'favorites': favorites
              .map((LocalMediaFavoriteState value) => value.toJson())
              .toList(),
          'health': health.values
              .map((TrackerProviderHealth value) => value.toJson())
              .toList(),
        },
      );
      await _saveTrackingStatesLocked(states, tombstoneMissing: false);
      await _writeBucketLocked(
        'tracking.journal',
        journal.map((SyncJournalEntry value) => value.toJson()).toList(),
      );
      await _writeBucketLocked(
        'tracking.favorites',
        favorites
            .map((LocalMediaFavoriteState value) => value.toJson())
            .toList(),
      );
      await _applyFavoritesLocked(favorites, states);
      for (final TrackerProviderHealth value in health.values) {
        await database
            .into(database.providerHealthRecords)
            .insertOnConflictUpdate(
              ProviderHealthRecordsCompanion.insert(
                provider: value.provider.name,
                healthJson: jsonEncode(value.toJson()),
                updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      }
      int verified = 0;
      for (final UserMediaState state in states) {
        final String? localId = await _localIdForIdentityLocked(state.identity);
        if (localId == null) {
          throw StateError(
            'Canonical Library migration lost ${state.identity.localId}.',
          );
        }
        final CanonicalLibraryRecord? row =
            await (database.select(database.canonicalLibraryRecords)..where(
                  (CanonicalLibraryRecords table) =>
                      table.localId.equals(localId) &
                      table.inLibrary.equals(true),
                ))
                .getSingleOrNull();
        if (row == null) {
          throw StateError(
            'Canonical Library migration did not persist ${state.identity.localId}.',
          );
        }
        verified += 1;
      }
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: 'migration:tracking.shared_preferences.v1',
              cursor: 'complete',
              metadataJson: Value<String>(
                jsonEncode(<String, int>{
                  'states': states.length,
                  'journal': journal.length,
                  'favorites': favorites.length,
                  'verified': verified,
                }),
              ),
              updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
    });
  }

  Future<void> importLegacyLocalLibrary(List<LibraryItem> items) async {
    await initialize();
    const String migration = 'library.localItems.v1';
    if (await hasMigration(migration)) return;
    if (!importsLegacyData) {
      await markMigrationComplete(migration);
      return;
    }
    await database.transaction(() async {
      await _writeBucketLocked(
        'migration.backup.$migration',
        items.map((LibraryItem value) => value.toJson()).toList(),
      );
      final List<UserMediaState> states = await loadTrackingStates();
      final List<LocalMediaFavoriteState> favorites = await loadFavorites();
      for (final LibraryItem item in items) {
        final MediaItem media = item.mediaItem;
        final bool canonical =
            media.type == MediaType.anime ||
            media.externalIds['anilist_type'] == 'MANGA' ||
            media.externalIds.containsKey('anilist') ||
            media.externalIds.containsKey('mal') ||
            media.externalIds.containsKey('shikimori');
        if (!canonical) continue;
        final MediaIdentity incomingIdentity = MediaIdentity.fromExternalIds(
          media.externalIds,
          mediaId: media.id,
        );
        final int existingIndex = states.indexWhere(
          (UserMediaState state) => state.identity.matches(incomingIdentity),
        );
        final int total = media.episodeCount ?? 0;
        final int progress = total > 0
            ? (item.progress.clamp(0.0, 1.0) * total).round()
            : (item.progress >= 1 ? 1 : 0);
        final TrackerSource source = incomingIdentity.anilistId != null
            ? TrackerSource.anilist
            : incomingIdentity.malId != null
            ? TrackerSource.mal
            : TrackerSource.shikimori;
        final UserMediaState migrated = UserMediaState(
          identity: incomingIdentity,
          mediaItem: media,
          status: _canonicalStatus(item.status),
          progress: progress,
          createdAt: item.addedAt.toUtc(),
          updatedAt: item.updatedAt.toUtc(),
          source: source,
        );
        if (existingIndex < 0) {
          states.add(migrated);
        }
        final String localId = await _upsertTrackingStateLocked(
          existingIndex < 0 ? migrated : states[existingIndex],
        );
        final MediaIdentity stableIdentity = MediaIdentity(
          localId: localId,
          kind: incomingIdentity.mediaKind,
          anilistId: incomingIdentity.anilistId,
          malId: incomingIdentity.malId,
          shikimoriId: incomingIdentity.shikimoriId,
        );
        if (item.status == LibraryStatus.favorite &&
            !favorites.any(
              (LocalMediaFavoriteState value) =>
                  value.identity.matches(stableIdentity),
            )) {
          favorites.add(
            LocalMediaFavoriteState(
              identity: stableIdentity,
              favorite: true,
              updatedAt: item.updatedAt.toUtc(),
            ),
          );
        }
        await _appendOperationLocked(
          LibraryOperationDraft(
            localId: localId,
            originKind: LibraryOriginKind.migration,
            intent: LibraryMutationIntent.add,
            fields: <String>{
              'membership',
              'status',
              'progress',
              if (item.status == LibraryStatus.favorite) 'favorite',
            },
            before: const <String, dynamic>{},
            after: <String, dynamic>{'state': migrated.toJson()},
            targets: const <String>{'drive'},
            occurredAt: item.updatedAt.toUtc(),
            title: media.title,
          ),
        );
      }
      await _saveTrackingStatesLocked(states, tombstoneMissing: false);
      await _writeBucketLocked(
        'tracking.favorites',
        favorites
            .map((LocalMediaFavoriteState value) => value.toJson())
            .toList(),
      );
      await _applyFavoritesLocked(favorites, states);
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: 'migration:$migration',
              cursor: 'complete',
              metadataJson: Value<String>(
                jsonEncode(<String, dynamic>{'sourceCount': items.length}),
              ),
              updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
    });
  }

  Future<List<UserMediaState>> loadTrackingStates() async {
    await initialize();
    final List<CanonicalLibraryRecord> rows =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) => table.inLibrary.equals(true),
            ))
            .get();
    final List<UserMediaState> result = <UserMediaState>[];
    for (final CanonicalLibraryRecord row in rows) {
      try {
        final Object? decoded = jsonDecode(row.canonicalStateJson);
        if (decoded is Map<String, dynamic>) {
          result.add(UserMediaState.fromJson(decoded));
        }
      } on Object {
        // A corrupt row is isolated instead of making the whole library fail.
      }
    }
    result.sort(
      (UserMediaState a, UserMediaState b) =>
          b.updatedAt.compareTo(a.updatedAt),
    );
    return result;
  }

  Future<void> saveTrackingStates(List<UserMediaState> states) async {
    await initialize();
    await database.transaction(
      () => _saveTrackingStatesLocked(states, tombstoneMissing: true),
    );
  }

  Future<void> upsertLocalState(
    UserMediaState state, {
    LibraryOriginKind originKind = LibraryOriginKind.user,
    LibraryMutationIntent intent = LibraryMutationIntent.edit,
    Set<String> fields = const <String>{'status'},
    Set<String> targets = const <String>{'drive'},
  }) async {
    await initialize();
    await database.transaction(() async {
      UserMediaState? before;
      for (final UserMediaState value in await loadTrackingStates()) {
        if (value.identity.matches(state.identity)) {
          before = value;
          break;
        }
      }
      final String localId = await _upsertTrackingStateLocked(state);
      final UserMediaState stored = state.withIdentity(
        MediaIdentity(
          localId: localId,
          kind: state.identity.mediaKind,
          anilistId: state.identity.anilistId,
          malId: state.identity.malId,
          shikimoriId: state.identity.shikimoriId,
        ),
      );
      final Set<String> stateIds = (await _readBucketLocked(
        'tracking.stateIds',
      )).whereType<String>().toSet()..add(localId);
      await _writeBucketLocked('tracking.stateIds', stateIds.toList()..sort());
      await _appendOperationLocked(
        LibraryOperationDraft(
          localId: localId,
          originKind: originKind,
          intent: before == null ? LibraryMutationIntent.add : intent,
          fields: fields,
          before: <String, dynamic>{
            if (before != null) 'state': before.toJson(),
          },
          after: <String, dynamic>{'state': stored.toJson()},
          targets: targets,
          occurredAt: state.updatedAt.toUtc(),
          title: state.mediaItem.title,
        ),
      );
    });
  }

  Future<void> removeLocalState(
    MediaIdentity identity, {
    Set<String> targets = const <String>{'drive'},
  }) async {
    await initialize();
    await database.transaction(() async {
      UserMediaState? before;
      for (final UserMediaState value in await loadTrackingStates()) {
        if (value.identity.matches(identity)) {
          before = value;
          break;
        }
      }
      if (before == null) return;
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await (database.update(database.canonicalLibraryRecords)..where(
            (CanonicalLibraryRecords table) =>
                table.localId.equals(before!.identity.localId),
          ))
          .write(
            CanonicalLibraryRecordsCompanion(
              inLibrary: const Value<bool>(false),
              tombstonedAtMs: Value<int>(now),
              updatedAtMs: Value<int>(now),
            ),
          );
      final Set<String> stateIds = (await _readBucketLocked(
        'tracking.stateIds',
      )).whereType<String>().toSet()..remove(before.identity.localId);
      await _writeBucketLocked('tracking.stateIds', stateIds.toList()..sort());
      await _appendOperationLocked(
        LibraryOperationDraft(
          localId: before.identity.localId,
          originKind: LibraryOriginKind.user,
          intent: LibraryMutationIntent.remove,
          fields: const <String>{'membership'},
          before: <String, dynamic>{'state': before.toJson()},
          after: const <String, dynamic>{},
          targets: targets,
          occurredAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
          title: before.mediaItem.title,
        ),
      );
    });
  }

  Future<void> _saveTrackingStatesLocked(
    List<UserMediaState> states, {
    required bool tombstoneMissing,
  }) async {
    final Set<String> nextIds = <String>{};
    for (final UserMediaState state in states) {
      final String localId = await _upsertTrackingStateLocked(state);
      nextIds.add(localId);
    }

    if (tombstoneMissing) {
      final Set<String> previousIds = (await _readBucketLocked(
        'tracking.stateIds',
      )).whereType<String>().toSet();
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final String removed in previousIds.difference(nextIds)) {
        await (database.update(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) => table.localId.equals(removed),
            ))
            .write(
              CanonicalLibraryRecordsCompanion(
                inLibrary: const Value<bool>(false),
                tombstonedAtMs: Value<int>(now),
                updatedAtMs: Value<int>(now),
              ),
            );
      }
    }
    await _writeBucketLocked('tracking.stateIds', nextIds.toList()..sort());
  }

  Future<String> _upsertTrackingStateLocked(UserMediaState state) async {
    final String localId = await _resolveOrCreateMediaLocked(
      identity: state.identity,
      mediaItem: state.mediaItem,
    );
    final MediaIdentity identity = MediaIdentity(
      localId: localId,
      kind: state.identity.mediaKind,
      anilistId: state.identity.anilistId,
      malId: state.identity.malId,
      shikimoriId: state.identity.shikimoriId,
    );
    UserMediaState canonical = state.withIdentity(identity);
    final CanonicalMediaRecord? canonicalMediaRow =
        await (database.select(database.canonicalMediaRecords)..where(
              (CanonicalMediaRecords table) => table.localId.equals(localId),
            ))
            .getSingleOrNull();
    if (canonicalMediaRow != null) {
      try {
        canonical = canonical.withMediaItem(
          MediaItem.fromJson(_jsonMap(canonicalMediaRow.mediaJson)),
        );
      } on Object {
        // Keep the incoming render metadata if the cached row is corrupt.
      }
    }
    final int createdAt = canonical.createdAt.toUtc().millisecondsSinceEpoch;
    final int updatedAt = canonical.updatedAt.toUtc().millisecondsSinceEpoch;
    final int? scoreRaw = canonical.score == null
        ? null
        : (canonical.score! * 10).round().clamp(0, 100);
    String? stateScoreFormat;
    for (final ProviderUserMediaState provider
        in canonical.providerStates.values) {
      final String candidate = '${provider.data['scoreFormat'] ?? ''}'.trim();
      if (candidate.isNotEmpty) {
        stateScoreFormat = candidate;
        break;
      }
    }
    final CanonicalLibraryRecord? existing =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) => table.localId.equals(localId),
            ))
            .getSingleOrNull();

    if (existing?.inLibrary == true &&
        existing!.canonicalStateJson == jsonEncode(canonical.toJson())) {
      return localId;
    }
    await database
        .into(database.canonicalLibraryRecords)
        .insertOnConflictUpdate(
          CanonicalLibraryRecordsCompanion.insert(
            localId: localId,
            status: canonical.status.name,
            progress: Value<int>(canonical.progress),
            progressVolumes: Value<int>(canonical.progressVolumes),
            repeatCount: Value<int>(canonical.repeat),
            favorite: Value<bool>(existing?.favorite ?? false),
            scoreRaw: Value<int?>(scoreRaw),
            scoreFormat: Value<String?>(
              stateScoreFormat ?? existing?.scoreFormat,
            ),
            notes: Value<String>(canonical.notes),
            canonicalStateJson: jsonEncode(canonical.toJson()),
            fieldRevisionsJson: Value<String>(
              existing?.fieldRevisionsJson ?? '{}',
            ),
            createdAtMs: existing?.createdAtMs ?? createdAt,
            updatedAtMs: updatedAt,
            inLibrary: const Value<bool>(true),
            startedYear: Value<int?>(canonical.startedAt?.year),
            startedMonth: Value<int?>(canonical.startedAt?.month),
            startedDay: Value<int?>(canonical.startedAt?.day),
            completedYear: Value<int?>(canonical.completedAt?.year),
            completedMonth: Value<int?>(canonical.completedAt?.month),
            completedDay: Value<int?>(canonical.completedAt?.day),
            tombstonedAtMs: const Value<int?>(null),
          ),
        );

    for (final ProviderUserMediaState snapshot
        in canonical.providerStates.values) {
      await _upsertProviderSnapshotLocked(
        localId: localId,
        accountId: 'active',
        snapshot: snapshot,
        completeSnapshot: true,
      );
    }
    return localId;
  }

  Future<String> resolveOrCreateMedia({
    required MediaIdentity identity,
    required MediaItem mediaItem,
  }) async {
    await initialize();
    return database.transaction(
      () =>
          _resolveOrCreateMediaLocked(identity: identity, mediaItem: mediaItem),
    );
  }

  /// Merges richer presentation data without changing the user's tracking
  /// state. The canonical media and library row are then replicated to Drive
  /// so a title remains fully renderable while providers are unavailable.
  Future<MediaItem> enrichPresentationMetadata({
    required MediaIdentity identity,
    required MediaItem mediaItem,
  }) async {
    await initialize();
    return database.transaction(() async {
      final String localId = await _resolveOrCreateMediaLocked(
        identity: identity,
        mediaItem: mediaItem,
      );
      final CanonicalMediaRecord storedMedia =
          await (database.select(database.canonicalMediaRecords)..where(
                (CanonicalMediaRecords table) => table.localId.equals(localId),
              ))
              .getSingle();
      final MediaItem merged = MediaItem.fromJson(
        _jsonMap(storedMedia.mediaJson),
      );
      final CanonicalLibraryRecord? libraryRow =
          await (database.select(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(localId) &
                    table.inLibrary.equals(true),
              ))
              .getSingleOrNull();
      if (libraryRow == null) return merged;

      final UserMediaState before = UserMediaState.fromJson(
        _jsonMap(libraryRow.canonicalStateJson),
      );
      if (jsonEncode(before.mediaItem.toJson()) ==
          jsonEncode(merged.toJson())) {
        return merged;
      }
      final UserMediaState after = before.withMediaItem(merged);
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await (database.update(database.canonicalLibraryRecords)..where(
            (CanonicalLibraryRecords table) => table.localId.equals(localId),
          ))
          .write(
            CanonicalLibraryRecordsCompanion(
              canonicalStateJson: Value<String>(jsonEncode(after.toJson())),
              updatedAtMs: Value<int>(now),
            ),
          );
      await _appendOperationLocked(
        LibraryOperationDraft(
          localId: localId,
          originKind: LibraryOriginKind.system,
          intent: LibraryMutationIntent.edit,
          fields: const <String>{'metadata'},
          before: <String, dynamic>{'media': before.mediaItem.toJson()},
          after: <String, dynamic>{'media': merged.toJson()},
          targets: const <String>{'drive'},
          occurredAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
          title: merged.title,
          visibleInLog: false,
        ),
      );
      return merged;
    });
  }

  /// Persists an exact provider id learned after a local entry was created.
  ///
  /// Identity discovery is deliberately separate from user-state mutations:
  /// learning an id must not change status, progress, timestamps, membership,
  /// or create a visible Library Log event. Conflicting bindings are recorded
  /// by the normal quarantine path and rejected.
  Future<bool> attachVerifiedProviderBinding({
    required MediaIdentity identity,
    required TrackerSource provider,
    required int externalMediaId,
    required String evidence,
  }) async {
    if (externalMediaId <= 0) return false;
    await initialize();
    return database.transaction(() async {
      final String? localId = await _localIdForIdentityLocked(identity);
      if (localId == null) return false;
      final bool attached = await _upsertBindingLocked(
        localId: localId,
        provider: provider.name,
        mediaKind: identity.mediaKind,
        externalMediaId: externalMediaId,
        evidence: evidence,
      );
      if (!attached) return false;

      final MediaIdentity nextIdentity = MediaIdentity(
        localId: localId,
        kind: identity.mediaKind,
        anilistId: provider == TrackerSource.anilist
            ? externalMediaId
            : identity.anilistId,
        malId: provider == TrackerSource.mal ? externalMediaId : identity.malId,
        shikimoriId: provider == TrackerSource.shikimori
            ? externalMediaId
            : identity.shikimoriId,
      );

      final CanonicalMediaRecord? mediaRow =
          await (database.select(database.canonicalMediaRecords)..where(
                (CanonicalMediaRecords table) => table.localId.equals(localId),
              ))
              .getSingleOrNull();
      if (mediaRow != null) {
        try {
          final Object? decoded = jsonDecode(mediaRow.mediaJson);
          if (decoded is Map) {
            final MediaItem media = MediaItem.fromJson(
              Map<String, dynamic>.from(decoded),
            );
            final MediaItem nextMedia = media.copyWith(
              externalIds: nextIdentity.mergeExternalIds(media.externalIds),
            );
            await (database.update(database.canonicalMediaRecords)..where(
                  (CanonicalMediaRecords table) =>
                      table.localId.equals(localId),
                ))
                .write(
                  CanonicalMediaRecordsCompanion(
                    mediaJson: Value<String>(jsonEncode(nextMedia.toJson())),
                    updatedAtMs: Value<int>(
                      DateTime.now().toUtc().millisecondsSinceEpoch,
                    ),
                  ),
                );
          }
        } on Object {
          // The verified binding remains useful even if cached presentation
          // metadata is corrupt and has to be repaired separately.
        }
      }

      final CanonicalLibraryRecord? libraryRow =
          await (database.select(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(localId),
              ))
              .getSingleOrNull();
      if (libraryRow != null) {
        try {
          final Object? decoded = jsonDecode(libraryRow.canonicalStateJson);
          if (decoded is Map) {
            final UserMediaState state = UserMediaState.fromJson(
              Map<String, dynamic>.from(decoded),
            );
            await (database.update(database.canonicalLibraryRecords)..where(
                  (CanonicalLibraryRecords table) =>
                      table.localId.equals(localId),
                ))
                .write(
                  CanonicalLibraryRecordsCompanion(
                    canonicalStateJson: Value<String>(
                      jsonEncode(state.withIdentity(nextIdentity).toJson()),
                    ),
                  ),
                );
          }
        } on Object {
          // Keep the exact binding. Corrupt canonical state is isolated by the
          // normal Library loader and must not turn into a wrong provider id.
        }
      }

      final String providerAlias = identity.mediaKind == 'manga'
          ? '${provider.name}:manga:$externalMediaId'
          : '${provider.name}:$externalMediaId';
      await database
          .into(database.mediaAliasRecords)
          .insertOnConflictUpdate(
            MediaAliasRecordsCompanion.insert(
              alias: providerAlias,
              localId: localId,
              createdAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
      return true;
    });
  }

  Future<String> _resolveOrCreateMediaLocked({
    required MediaIdentity identity,
    required MediaItem mediaItem,
  }) async {
    final Set<String> matches = <String>{};
    if (identity.localId.trim().isNotEmpty) {
      final MediaAliasRecord? alias =
          await (database.select(database.mediaAliasRecords)..where(
                (MediaAliasRecords table) =>
                    table.alias.equals(identity.localId),
              ))
              .getSingleOrNull();
      if (alias != null) matches.add(alias.localId);

      final CanonicalMediaRecord? direct =
          await (database.select(database.canonicalMediaRecords)..where(
                (CanonicalMediaRecords table) =>
                    table.localId.equals(identity.localId),
              ))
              .getSingleOrNull();
      if (direct != null && alias == null) matches.add(direct.localId);
    }
    if (mediaItem.id.trim().isNotEmpty) {
      final MediaAliasRecord? mediaAlias =
          await (database.select(database.mediaAliasRecords)..where(
                (MediaAliasRecords table) => table.alias.equals(mediaItem.id),
              ))
              .getSingleOrNull();
      if (mediaAlias != null) matches.add(mediaAlias.localId);
    }

    final Map<String, int?> ids = <String, int?>{
      TrackerSource.anilist.name: identity.anilistId,
      TrackerSource.mal.name: identity.malId,
      TrackerSource.shikimori.name: identity.shikimoriId,
    };
    for (final MapEntry<String, int?> id in ids.entries) {
      if (id.value == null || id.value! <= 0) continue;
      final ProviderBindingRecord? binding =
          await (database.select(database.providerBindingRecords)..where(
                (ProviderBindingRecords table) =>
                    table.provider.equals(id.key) &
                    table.mediaKind.equals(identity.mediaKind) &
                    table.externalMediaId.equals(id.value!),
              ))
              .getSingleOrNull();
      if (binding != null && !binding.quarantined) matches.add(binding.localId);
    }

    if (matches.length > 1) {
      final String first = matches.first;
      await _recordIdentityConflictLocked(
        localId: first,
        incoming: identity.toJson(),
        matches: matches,
      );
      return first;
    }

    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final String localId = matches.isEmpty ? _uuid.v7() : matches.single;
    final CanonicalMediaRecord? existing =
        await (database.select(database.canonicalMediaRecords)..where(
              (CanonicalMediaRecords table) => table.localId.equals(localId),
            ))
            .getSingleOrNull();
    MediaItem canonicalMedia = mediaItem.copyWith(
      externalIds: identity.mergeExternalIds(mediaItem.externalIds),
    );
    if (existing != null) {
      try {
        canonicalMedia = _mergePresentationMetadata(
          MediaItem.fromJson(_jsonMap(existing.mediaJson)),
          canonicalMedia,
          identity,
        );
      } on Object {
        // Replace only the corrupt cached presentation row.
      }
    }
    final String canonicalMediaJson = jsonEncode(canonicalMedia.toJson());
    if (existing == null || existing.mediaJson != canonicalMediaJson) {
      await database
          .into(database.canonicalMediaRecords)
          .insertOnConflictUpdate(
            CanonicalMediaRecordsCompanion.insert(
              localId: localId,
              mediaKind: identity.mediaKind,
              mediaJson: canonicalMediaJson,
              createdAtMs: existing?.createdAtMs ?? now,
              updatedAtMs: now,
            ),
          );
    }

    if (identity.localId.trim().isNotEmpty &&
        !identity.localId.endsWith(':unresolved')) {
      await database
          .into(database.mediaAliasRecords)
          .insertOnConflictUpdate(
            MediaAliasRecordsCompanion.insert(
              alias: identity.localId,
              localId: localId,
              createdAtMs: now,
            ),
          );
    }
    if (mediaItem.id.trim().isNotEmpty) {
      await database
          .into(database.mediaAliasRecords)
          .insertOnConflictUpdate(
            MediaAliasRecordsCompanion.insert(
              alias: mediaItem.id,
              localId: localId,
              createdAtMs: now,
            ),
          );
    }
    for (final MapEntry<String, int?> id in ids.entries) {
      if (id.value == null || id.value! <= 0) continue;
      await _upsertBindingLocked(
        localId: localId,
        provider: id.key,
        mediaKind: identity.mediaKind,
        externalMediaId: id.value!,
        evidence: 'verified_external_id',
      );
    }
    return localId;
  }

  MediaItem _mergePresentationMetadata(
    MediaItem cached,
    MediaItem incoming,
    MediaIdentity identity,
  ) {
    final int cachedRank = _metadataProviderRank(cached.sourceProvider);
    final int incomingRank = _metadataProviderRank(incoming.sourceProvider);
    final bool incomingPreferred = incomingRank >= cachedRank;

    String choose(String oldValue, String nextValue) {
      final String oldTrimmed = oldValue.trim();
      final String nextTrimmed = nextValue.trim();
      if (nextTrimmed.isEmpty) return oldValue;
      if (oldTrimmed.isEmpty ||
          _isTechnicalMediaTitle(oldTrimmed) ||
          oldTrimmed == 'No AniList description yet.') {
        return nextValue;
      }
      return incomingPreferred ? nextValue : oldValue;
    }

    int chooseInt(int oldValue, int nextValue) =>
        nextValue > 0 && (oldValue <= 0 || incomingPreferred)
        ? nextValue
        : oldValue;
    double chooseDouble(double oldValue, double nextValue) =>
        nextValue > 0 && (oldValue <= 0 || incomingPreferred)
        ? nextValue
        : oldValue;
    int? chooseNullableInt(int? oldValue, int? nextValue) =>
        nextValue != null &&
            nextValue > 0 &&
            (oldValue == null || oldValue <= 0 || incomingPreferred)
        ? nextValue
        : oldValue;
    final List<String> aliases = <String>{
      ...cached.aliases.where((String value) => value.trim().isNotEmpty),
      ...incoming.aliases.where((String value) => value.trim().isNotEmpty),
    }.toList(growable: false);
    final List<String> genres = <String>{
      ...cached.genres,
      ...incoming.genres,
    }.where((String value) => value.trim().isNotEmpty).toList(growable: false);
    return MediaItem(
      id: cached.id.trim().isNotEmpty ? cached.id : incoming.id,
      title: choose(cached.title, incoming.title),
      originalTitle: choose(cached.originalTitle, incoming.originalTitle),
      overview: choose(cached.overview, incoming.overview),
      type: incomingPreferred ? incoming.type : cached.type,
      year: chooseInt(cached.year, incoming.year),
      posterUrl: choose(cached.posterUrl, incoming.posterUrl),
      backdropUrl: choose(cached.backdropUrl, incoming.backdropUrl),
      rating: chooseDouble(cached.rating, incoming.rating),
      genres: genres,
      sourceProvider: incomingPreferred
          ? incoming.sourceProvider
          : cached.sourceProvider,
      externalIds: identity.mergeExternalIds(<String, String>{
        ...cached.externalIds,
        ...incoming.externalIds,
      }),
      runtimeMinutes: chooseNullableInt(
        cached.runtimeMinutes,
        incoming.runtimeMinutes,
      ),
      episodeCount: chooseNullableInt(
        cached.episodeCount,
        incoming.episodeCount,
      ),
      seasons:
          incoming.seasons.isNotEmpty &&
              (cached.seasons.isEmpty || incomingPreferred)
          ? incoming.seasons
          : cached.seasons,
      statusLabel: choose(cached.statusLabel, incoming.statusLabel),
      aliases: aliases,
      originalLanguage: choose(
        cached.originalLanguage,
        incoming.originalLanguage,
      ),
      trailer:
          incoming.trailer != null &&
              (cached.trailer == null || incomingPreferred)
          ? incoming.trailer
          : cached.trailer,
    );
  }

  int _metadataProviderRank(String provider) {
    final String normalized = provider.trim().toLowerCase();
    if (normalized.contains('anilist')) return 4;
    if (normalized.contains('myanimelist') || normalized == 'mal') return 3;
    if (normalized.contains('shikimori')) return 2;
    return 1;
  }

  bool _isTechnicalMediaTitle(String title) {
    final String value = title.trim();
    if (value.isEmpty || value.toLowerCase() == 'saved media') return true;
    return RegExp(
      r'^(anime|manga)\s*#\d+$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  Future<bool> _upsertBindingLocked({
    required String localId,
    required String provider,
    required String mediaKind,
    required int externalMediaId,
    required String evidence,
    int? providerEntryId,
    int? verifiedAtMs,
    bool? quarantined,
  }) async {
    final ProviderBindingRecord? byExternal =
        await (database.select(database.providerBindingRecords)..where(
              (ProviderBindingRecords table) =>
                  table.provider.equals(provider) &
                  table.mediaKind.equals(mediaKind) &
                  table.externalMediaId.equals(externalMediaId),
            ))
            .getSingleOrNull();
    if (byExternal != null && byExternal.localId != localId) {
      await _recordIdentityConflictLocked(
        localId: localId,
        incoming: <String, Object>{provider: externalMediaId},
        matches: <String>{localId, byExternal.localId},
      );
      return false;
    }
    final ProviderBindingRecord? byLocal =
        await (database.select(database.providerBindingRecords)..where(
              (ProviderBindingRecords table) =>
                  table.localId.equals(localId) &
                  table.provider.equals(provider),
            ))
            .getSingleOrNull();
    if (byLocal != null && byLocal.externalMediaId != externalMediaId) {
      await _recordIdentityConflictLocked(
        localId: localId,
        incoming: <String, Object>{provider: externalMediaId},
        matches: <String>{localId},
      );
      return false;
    }
    final bool acceptsIncomingMetadata =
        byLocal == null ||
        verifiedAtMs == null ||
        verifiedAtMs >= byLocal.verifiedAtMs;
    await database
        .into(database.providerBindingRecords)
        .insertOnConflictUpdate(
          ProviderBindingRecordsCompanion(
            id: byLocal == null
                ? const Value<int>.absent()
                : Value<int>(byLocal.id),
            localId: Value<String>(localId),
            provider: Value<String>(provider),
            mediaKind: Value<String>(mediaKind),
            externalMediaId: Value<int>(externalMediaId),
            providerEntryId: Value<int?>(
              acceptsIncomingMetadata
                  ? providerEntryId ?? byLocal?.providerEntryId
                  : byLocal.providerEntryId,
            ),
            evidence: Value<String>(
              acceptsIncomingMetadata ? evidence : byLocal.evidence,
            ),
            verifiedAtMs: Value<int>(
              acceptsIncomingMetadata
                  ? verifiedAtMs ??
                        DateTime.now().toUtc().millisecondsSinceEpoch
                  : byLocal.verifiedAtMs,
            ),
            quarantined: Value<bool>(
              acceptsIncomingMetadata
                  ? quarantined ?? false
                  : byLocal.quarantined,
            ),
          ),
        );
    return true;
  }

  Future<void> _recordIdentityConflictLocked({
    required String localId,
    required Map<String, dynamic> incoming,
    required Set<String> matches,
  }) async {
    final String localValueJson = jsonEncode(matches.toList()..sort());
    final LibraryConflictRecord? duplicate =
        await (database.select(database.libraryConflictRecords)..where(
              (LibraryConflictRecords table) =>
                  table.fieldName.equals('identity') &
                  table.state.equals('open') &
                  table.localValueJson.equals(localValueJson),
            ))
            .getSingleOrNull();
    if (duplicate != null) return;
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database
        .into(database.libraryConflictRecords)
        .insert(
          LibraryConflictRecordsCompanion.insert(
            conflictId: _uuid.v7(),
            localId: localId,
            fieldName: 'identity',
            localValueJson: localValueJson,
            incomingValueJson: jsonEncode(incoming),
            createdAtMs: now,
          ),
        );
  }

  /// Repairs a legacy provider-only shell after an authenticated snapshot
  /// supplies an exact cross-provider id. Older Shikimori snapshots could be
  /// stored before GraphQL enrichment returned their MAL id, leaving an empty
  /// Shikimori record next to the real MAL/AniList record. The shell is safe to
  /// collapse only when it has no user state, history, playback, or stream
  /// preferences of its own.
  Future<void> _repairExactProviderShellLocked({
    required MediaIdentity identity,
    required TrackerSource source,
  }) async {
    final int? sourceId = identity.idFor(source);
    if (sourceId == null) return;
    final Map<TrackerSource, int?> exactIds = <TrackerSource, int?>{
      TrackerSource.anilist: identity.anilistId,
      TrackerSource.mal: identity.malId,
      TrackerSource.shikimori: identity.shikimoriId,
    };
    if (exactIds.entries.where((entry) => entry.value != null).length < 2) {
      return;
    }

    final ProviderBindingRecord? sourceBinding =
        await (database.select(database.providerBindingRecords)..where(
              (ProviderBindingRecords table) =>
                  table.provider.equals(source.name) &
                  table.mediaKind.equals(identity.mediaKind) &
                  table.externalMediaId.equals(sourceId),
            ))
            .getSingleOrNull();
    if (sourceBinding == null) return;

    final Set<String> exactTargets = <String>{};
    for (final MapEntry<TrackerSource, int?> exact in exactIds.entries) {
      if (exact.key == source || exact.value == null) continue;
      final ProviderBindingRecord? binding =
          await (database.select(database.providerBindingRecords)..where(
                (ProviderBindingRecords table) =>
                    table.provider.equals(exact.key.name) &
                    table.mediaKind.equals(identity.mediaKind) &
                    table.externalMediaId.equals(exact.value!),
              ))
              .getSingleOrNull();
      if (binding != null && binding.localId != sourceBinding.localId) {
        exactTargets.add(binding.localId);
      }
    }
    if (exactTargets.length != 1) return;
    final String targetLocalId = exactTargets.single;
    final String shellLocalId = sourceBinding.localId;

    final CanonicalLibraryRecord? targetLibrary =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) =>
                  table.localId.equals(targetLocalId),
            ))
            .getSingleOrNull();
    if (targetLibrary == null) return;
    final CanonicalLibraryRecord? shellLibrary =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) =>
                  table.localId.equals(shellLocalId),
            ))
            .getSingleOrNull();

    final LibraryOperationRecord? shellOperation =
        await (database.select(database.libraryOperationRecords)
              ..where(
                (LibraryOperationRecords table) =>
                    table.localId.equals(shellLocalId),
              )
              ..limit(1))
            .getSingleOrNull();
    final EpisodeStateRecord? shellEpisode =
        await (database.select(database.episodeStateRecords)
              ..where(
                (EpisodeStateRecords table) =>
                    table.localId.equals(shellLocalId),
              )
              ..limit(1))
            .getSingleOrNull();
    final StreamPreferenceRecord? shellPreference =
        await (database.select(database.streamPreferenceRecords)
              ..where(
                (StreamPreferenceRecords table) =>
                    table.localId.equals(shellLocalId),
              )
              ..limit(1))
            .getSingleOrNull();
    if (shellLibrary == null &&
        (shellOperation != null ||
            shellEpisode != null ||
            shellPreference != null)) {
      return;
    }

    final List<ProviderBindingRecord> shellBindings =
        await (database.select(database.providerBindingRecords)..where(
              (ProviderBindingRecords table) =>
                  table.localId.equals(shellLocalId),
            ))
            .get();
    if (shellBindings.any(
      (ProviderBindingRecord binding) =>
          binding.provider != source.name ||
          binding.externalMediaId != sourceId,
    )) {
      return;
    }
    final List<ProviderSnapshotRecord> shellSnapshots =
        await (database.select(database.providerSnapshotRecords)..where(
              (ProviderSnapshotRecords table) =>
                  table.localId.equals(shellLocalId),
            ))
            .get();
    if (shellSnapshots.any(
      (ProviderSnapshotRecord snapshot) => snapshot.provider != source.name,
    )) {
      return;
    }

    final ProviderBindingRecord? targetSourceBinding =
        await (database.select(database.providerBindingRecords)..where(
              (ProviderBindingRecords table) =>
                  table.localId.equals(targetLocalId) &
                  table.provider.equals(source.name),
            ))
            .getSingleOrNull();
    if (targetSourceBinding != null &&
        targetSourceBinding.externalMediaId != sourceId) {
      return;
    }

    if (shellLibrary != null) {
      await _mergeVerifiedMediaHistoryLocked(
        targetLibrary,
        shellLibrary,
        source,
      );
    }

    await (database.delete(database.providerSnapshotRecords)..where(
          (ProviderSnapshotRecords table) => table.localId.equals(shellLocalId),
        ))
        .go();
    if (targetSourceBinding == null) {
      await (database.update(database.providerBindingRecords)..where(
            (ProviderBindingRecords table) => table.id.equals(sourceBinding.id),
          ))
          .write(
            ProviderBindingRecordsCompanion(
              localId: Value<String>(targetLocalId),
              evidence: const Value<String>('exact_cross_provider_snapshot'),
              verifiedAtMs: Value<int>(
                DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
              quarantined: const Value<bool>(false),
            ),
          );
    } else {
      await (database.delete(database.providerBindingRecords)..where(
            (ProviderBindingRecords table) => table.id.equals(sourceBinding.id),
          ))
          .go();
    }
    await (database.update(database.mediaAliasRecords)..where(
          (MediaAliasRecords table) => table.localId.equals(shellLocalId),
        ))
        .write(
          MediaAliasRecordsCompanion(localId: Value<String>(targetLocalId)),
        );

    final MediaIdentity exactIdentity = MediaIdentity(
      localId: targetLocalId,
      kind: identity.mediaKind,
      anilistId: identity.anilistId,
      malId: identity.malId,
      shikimoriId: identity.shikimoriId,
    );
    final CanonicalMediaRecord? targetMedia =
        await (database.select(database.canonicalMediaRecords)..where(
              (CanonicalMediaRecords table) =>
                  table.localId.equals(targetLocalId),
            ))
            .getSingleOrNull();
    if (targetMedia != null) {
      final MediaItem media = MediaItem.fromJson(
        _jsonMap(targetMedia.mediaJson),
      );
      await (database.update(database.canonicalMediaRecords)..where(
            (CanonicalMediaRecords table) =>
                table.localId.equals(targetLocalId),
          ))
          .write(
            CanonicalMediaRecordsCompanion(
              mediaJson: Value<String>(
                jsonEncode(
                  media
                      .copyWith(
                        externalIds: exactIdentity.mergeExternalIds(
                          media.externalIds,
                        ),
                      )
                      .toJson(),
                ),
              ),
              updatedAtMs: Value<int>(
                DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            ),
          );
    }
    final latestTarget = await (database.select(
      database.canonicalLibraryRecords,
    )..where((table) => table.localId.equals(targetLocalId))).getSingle();
    final UserMediaState targetState = UserMediaState.fromJson(
      _jsonMap(latestTarget.canonicalStateJson),
    );
    await (database.update(database.canonicalLibraryRecords)..where(
          (CanonicalLibraryRecords table) =>
              table.localId.equals(targetLocalId),
        ))
        .write(
          CanonicalLibraryRecordsCompanion(
            canonicalStateJson: Value<String>(
              jsonEncode(
                targetState
                    .withIdentity(targetState.identity.merge(exactIdentity))
                    .toJson(),
              ),
            ),
          ),
        );

    final List<LibraryConflictRecord> openIdentityConflicts =
        await (database.select(database.libraryConflictRecords)..where(
              (LibraryConflictRecords table) =>
                  table.fieldName.equals('identity') &
                  table.state.equals('open'),
            ))
            .get();
    final int resolvedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final LibraryConflictRecord conflict in openIdentityConflicts) {
      final Set<String> conflictMatches = _dynamicStringSet(
        _decodeJsonValue(conflict.localValueJson),
      );
      if (!conflictMatches.contains(targetLocalId) ||
          !conflictMatches.contains(shellLocalId)) {
        continue;
      }
      await (database.update(database.libraryConflictRecords)..where(
            (LibraryConflictRecords table) =>
                table.conflictId.equals(conflict.conflictId),
          ))
          .write(
            LibraryConflictRecordsCompanion(
              state: const Value<String>('resolved'),
              resolvedAtMs: Value<int>(resolvedAt),
            ),
          );
    }
  }

  Future<void> _mergeVerifiedMediaHistoryLocked(
    CanonicalLibraryRecord target,
    CanonicalLibraryRecord duplicate,
    TrackerSource source,
  ) async {
    final root = target.localId;
    final old = duplicate.localId;
    var state = UserMediaState.fromJson(_jsonMap(target.canonicalStateJson));
    final other = UserMediaState.fromJson(
      _jsonMap(duplicate.canonicalStateJson),
    );
    final revisions = _jsonMap(target.fieldRevisionsJson);
    final otherRevisions = _jsonMap(duplicate.fieldRevisionsJson);
    for (final field in providerEntryFields(
      source,
      mediaKind: state.identity.mediaKind,
    )) {
      final left = revisions[field.name];
      final right = otherRevisions[field.name];
      if (_jsonEquivalent(
        providerFieldValue(state, field),
        providerFieldValue(other, field),
      )) {
        revisions[field.name] = _mergeEquivalentRevisions(left, right);
      } else if (_revisionEditTime(right) > _revisionEditTime(left)) {
        state = state.apply(
          _patchFromState(other, {field}),
          state.updatedAt.isAfter(other.updatedAt)
              ? state.updatedAt
              : other.updatedAt,
          providerSource: source,
        );
        revisions[field.name] = right;
      } else if (_revisionEditTime(right) == _revisionEditTime(left)) {
        await _recordProviderReviewLocked(
          localId: root,
          field: field.name,
          source: source,
          accountId:
              (await (database.select(database.providerSnapshotRecords)
                        ..where(
                          (table) =>
                              table.localId.equals(old) &
                              table.provider.equals(source.name),
                        )
                        ..limit(1))
                      .getSingleOrNull())
                  ?.accountId ??
              '',
          current: state,
          incoming: other,
          reason:
              'Verified duplicate has divergent values without an unambiguous newer edit date.',
        );
      }
    }
    for (final item in otherRevisions.entries) {
      if (!revisions.containsKey(item.key)) {
        revisions[item.key] = item.value;
      } else if (item.key == 'membership') {
        revisions[item.key] = _mergeEquivalentRevisions(
          revisions[item.key],
          item.value,
        );
      } else if (item.key.startsWith('episodeProgress:') &&
          _revisionEditTime(item.value) >
              _revisionEditTime(revisions[item.key])) {
        revisions[item.key] = item.value;
      }
    }
    // Move audit records intact; revisions continue referring to their original IDs.
    await (database.update(database.libraryOperationRecords)
          ..where((t) => t.localId.equals(old)))
        .write(LibraryOperationRecordsCompanion(localId: Value(root)));
    await (database.update(database.libraryConflictRecords)
          ..where((t) => t.localId.equals(old)))
        .write(LibraryConflictRecordsCompanion(localId: Value(root)));
    final episodes = await (database.select(
      database.episodeStateRecords,
    )..where((t) => t.localId.equals(old))).get();
    for (final episode in episodes) {
      final existing =
          await (database.select(database.episodeStateRecords)..where(
                (t) =>
                    t.localId.equals(root) &
                    t.seasonNumber.equals(episode.seasonNumber) &
                    t.episodeNumber.equals(episode.episodeNumber) &
                    t.watchCycle.equals(episode.watchCycle),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await (database.update(
          database.episodeStateRecords,
        )..where((t) => t.episodeStateId.equals(episode.episodeStateId))).write(
          EpisodeStateRecordsCompanion(
            localId: Value(root),
            episodeStateId: Value(
              '$root:${episode.watchCycle}:${episode.seasonNumber}:${episode.episodeNumber}',
            ),
          ),
        );
      } else {
        if (episode.updatedAtMs > existing.updatedAtMs) {
          await (database.update(
                database.episodeStateRecords,
              )..where((t) => t.episodeStateId.equals(existing.episodeStateId)))
              .write(
                EpisodeStateRecordsCompanion(
                  positionSeconds: Value(episode.positionSeconds),
                  durationSeconds: Value(episode.durationSeconds),
                  completed: Value(episode.completed || existing.completed),
                  updatedAtMs: Value(episode.updatedAtMs),
                ),
              );
        }
        await (database.delete(
          database.episodeStateRecords,
        )..where((t) => t.episodeStateId.equals(episode.episodeStateId))).go();
      }
    }
    await (database.update(database.streamPreferenceRecords)
          ..where((t) => t.localId.equals(old)))
        .write(StreamPreferenceRecordsCompanion(localId: Value(root)));
    final snapshots = await (database.select(
      database.providerSnapshotRecords,
    )..where((t) => t.localId.equals(old))).get();
    for (final snapshot in snapshots) {
      final existing =
          await (database.select(database.providerSnapshotRecords)..where(
                (t) =>
                    t.localId.equals(root) &
                    t.provider.equals(snapshot.provider) &
                    t.accountId.equals(snapshot.accountId),
              ))
              .getSingleOrNull();
      final remote = _providerStateFromSnapshot(snapshot);
      if (remote != null &&
          (existing == null || snapshot.fetchedAtMs > existing.fetchedAtMs)) {
        await _writeFullProviderSnapshotLocked(
          localId: root,
          source: TrackerSource.fromName(snapshot.provider),
          accountId: snapshot.accountId,
          state: remote.withIdentity(remote.identity.withLocalId(root)),
          destructiveConfirmationCount: snapshot.destructiveConfirmationCount,
          fetchedAt: DateTime.fromMillisecondsSinceEpoch(
            snapshot.fetchedAtMs,
            isUtc: true,
          ),
        );
      }
    }
    // Keep the old media row as an alias anchor for old Drive segments/devices.
    await database
        .into(database.mediaAliasRecords)
        .insertOnConflictUpdate(
          MediaAliasRecordsCompanion.insert(
            alias: old,
            localId: root,
            createdAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
    final journal = await loadJournal();
    await _writeBucketLocked('tracking.journal', [
      for (final job in journal)
        (job.identity.localId == old
                ? job.withIdentity(job.identity.withLocalId(root))
                : job)
            .toJson(),
    ]);
    final favorites = await loadFavorites();
    final byIdentity = <String, LocalMediaFavoriteState>{};
    for (var favorite in favorites) {
      if (favorite.identity.localId == old) {
        favorite = favorite.withIdentity(favorite.identity.withLocalId(root));
      }
      final key = favorite.identity.localId;
      if (byIdentity[key] == null ||
          favorite.updatedAt.isAfter(byIdentity[key]!.updatedAt)) {
        byIdentity[key] = favorite;
      }
    }
    await _writeBucketLocked(
      'tracking.favorites',
      byIdentity.values.map((f) => f.toJson()).toList(),
    );
    await (database.update(
      database.canonicalLibraryRecords,
    )..where((t) => t.localId.equals(root))).write(
      CanonicalLibraryRecordsCompanion(
        canonicalStateJson: Value(jsonEncode(state.toJson())),
        fieldRevisionsJson: Value(jsonEncode(revisions)),
        watchCycle: Value(
          target.watchCycle > duplicate.watchCycle
              ? target.watchCycle
              : duplicate.watchCycle,
        ),
        favorite: Value(byIdentity[root]?.favorite ?? target.favorite),
      ),
    );
    await (database.delete(
      database.canonicalLibraryRecords,
    )..where((t) => t.localId.equals(old))).go();
  }

  Future<void> _upsertProviderSnapshotLocked({
    required String localId,
    required String accountId,
    required ProviderUserMediaState snapshot,
    required bool completeSnapshot,
  }) async {
    final String raw = jsonEncode(snapshot.toJson());
    final String id = '${snapshot.provider.name}:$accountId:$localId';
    await database
        .into(database.providerSnapshotRecords)
        .insertOnConflictUpdate(
          ProviderSnapshotRecordsCompanion.insert(
            snapshotId: id,
            localId: localId,
            provider: snapshot.provider.name,
            accountId: accountId,
            providerEntryId: Value<int?>(snapshot.entryId),
            normalizedJson: raw,
            rawJson: raw,
            contentHash: sha256.convert(utf8.encode(raw)).toString(),
            fetchedAtMs: (snapshot.updatedAt ?? DateTime.now())
                .toUtc()
                .millisecondsSinceEpoch,
            completeSnapshot: completeSnapshot,
          ),
        );
  }

  Future<List<ProviderAccountPreview>> pendingAccountPreviews() async {
    await initialize();
    final List<SyncCursorRecord> rows =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) =>
                  table.scope.like('provider-account:%') &
                  table.cursor.equals('pending'),
            ))
            .get();
    final List<UserMediaState> localStates = await loadTrackingStates();
    final List<ProviderAccountPreview> previews = <ProviderAccountPreview>[];
    for (final SyncCursorRecord row in rows) {
      final List<String> parts = row.scope.split(':');
      final String provider = parts.length > 1 ? parts[1] : 'unknown';
      final String accountId = parts.length > 2
          ? parts.sublist(2).join(':')
          : 'unknown';
      final Map<String, dynamic> metadata = _jsonMap(row.metadataJson);
      final List<ProviderSnapshotRecord> snapshots =
          await (database.select(database.providerSnapshotRecords)..where(
                (ProviderSnapshotRecords table) =>
                    table.provider.equals(provider) &
                    table.accountId.equals(accountId) &
                    table.completeSnapshot.equals(true),
              ))
              .get();
      final List<ProviderAccountPreviewEntry> entries =
          <ProviderAccountPreviewEntry>[];
      for (final ProviderSnapshotRecord snapshot in snapshots) {
        try {
          final UserMediaState remote = UserMediaState.fromJson(
            _jsonMap(snapshot.normalizedJson),
          );
          UserMediaState? local;
          for (final UserMediaState candidate in localStates) {
            if (candidate.identity.localId == snapshot.localId ||
                candidate.identity.matches(remote.identity)) {
              local = candidate;
              break;
            }
          }
          final bool unchanged =
              local != null &&
              local.status == remote.status &&
              local.progress == remote.progress &&
              local.progressVolumes == remote.progressVolumes &&
              local.repeat == remote.repeat &&
              local.score == remote.score &&
              local.notes == remote.notes;
          entries.add(
            ProviderAccountPreviewEntry(
              localId: snapshot.localId,
              mediaKind: remote.identity.mediaKind,
              title: remote.mediaItem.title,
              changeKind: local == null
                  ? 'new'
                  : unchanged
                  ? 'unchanged'
                  : 'different',
              remoteStatus: remote.status.name,
              remoteProgress: remote.progress,
              remoteScore: remote.score,
              localStatus: local?.status.name,
              localProgress: local?.progress,
              localScore: local?.score,
            ),
          );
        } on Object {
          // Keep a corrupt provider row isolated from the rest of the preview.
        }
      }
      entries.sort(
        (
          ProviderAccountPreviewEntry first,
          ProviderAccountPreviewEntry second,
        ) => first.title.toLowerCase().compareTo(second.title.toLowerCase()),
      );
      previews.add(
        ProviderAccountPreview(
          provider: provider,
          accountId: accountId,
          entryCount:
              (metadata['entryCount'] as num?)?.toInt() ?? entries.length,
          localEntryCount: (metadata['localEntryCount'] as num?)?.toInt() ?? 0,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.updatedAtMs,
            isUtc: true,
          ),
          entries: entries,
        ),
      );
    }
    return previews;
  }

  Future<void> approveProviderAccount({
    required String provider,
    required String accountId,
  }) async {
    await initialize();
    final String scope = 'provider-account:$provider:$accountId';
    final SyncCursorRecord? existing =
        await (database.select(database.syncCursorRecords)
              ..where((SyncCursorRecords table) => table.scope.equals(scope)))
            .getSingleOrNull();
    final Map<String, dynamic> metadata = _jsonMap(existing?.metadataJson)
      ..['initialImport'] = true
      ..['approvedAt'] = DateTime.now().toUtc().toIso8601String();
    await database
        .into(database.syncCursorRecords)
        .insertOnConflictUpdate(
          SyncCursorRecordsCompanion.insert(
            scope: scope,
            cursor: 'approved',
            metadataJson: Value<String>(jsonEncode(metadata)),
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> rejectProviderAccount({
    required String provider,
    required String accountId,
  }) async {
    await initialize();
    final String scope = 'provider-account:$provider:$accountId';
    final SyncCursorRecord? existing =
        await (database.select(database.syncCursorRecords)
              ..where((SyncCursorRecords table) => table.scope.equals(scope)))
            .getSingleOrNull();
    final Map<String, dynamic> metadata = _jsonMap(existing?.metadataJson)
      ..['rejectedAt'] = DateTime.now().toUtc().toIso8601String();
    await database
        .into(database.syncCursorRecords)
        .insertOnConflictUpdate(
          SyncCursorRecordsCompanion.insert(
            scope: scope,
            cursor: 'rejected',
            metadataJson: Value<String>(jsonEncode(metadata)),
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<ProviderReconciliationResult> reconcileProviderSnapshot({
    required TrackerSource source,
    required String accountId,
    required String mediaKind,
    required List<UserMediaState> remote,
    required List<SyncJournalEntry> journal,
    required Set<TrackerSource> propagationTargets,
    required bool completeSnapshot,
    Map<TrackerSource, String> propagationAccountIds =
        const <TrackerSource, String>{},
  }) async {
    await initialize();
    if (!completeSnapshot) {
      return ProviderReconciliationResult(
        states: await loadTrackingStates(),
        journal: await loadJournal(),
      );
    }
    return database.transaction(() async {
      final DateTime now = DateTime.now().toUtc();
      final int nowMs = now.millisecondsSinceEpoch;
      final List<UserMediaState> states = await loadTrackingStates();
      final List<SyncJournalEntry> liveJournal = await loadJournal();
      final String accountScope = 'provider-account:${source.name}:$accountId';
      final SyncCursorRecord? accountCursor =
          await (database.select(database.syncCursorRecords)..where(
                (SyncCursorRecords table) => table.scope.equals(accountScope),
              ))
              .getSingleOrNull();
      final Map<String, dynamic> accountMetadata = _jsonMap(
        accountCursor?.metadataJson,
      );
      final Set<String> localIdsForKind =
          (await (database.select(database.canonicalMediaRecords)..where(
                    (CanonicalMediaRecords table) =>
                        table.mediaKind.equals(mediaKind),
                  ))
                  .get())
              .map((CanonicalMediaRecord row) => row.localId)
              .toSet();
      final List<ProviderSnapshotRecord> previousRows =
          await (database.select(database.providerSnapshotRecords)..where(
                (ProviderSnapshotRecords table) =>
                    table.provider.equals(source.name) &
                    table.accountId.equals(accountId) &
                    table.localId.isIn(localIdsForKind),
              ))
              .get();
      final Map<String, ProviderSnapshotRecord> previousByLocal =
          <String, ProviderSnapshotRecord>{
            for (final ProviderSnapshotRecord row in previousRows)
              row.localId: row,
          };

      final Map<String, UserMediaState> incomingByLocal =
          <String, UserMediaState>{};
      for (final UserMediaState incoming in remote) {
        if (incoming.identity.mediaKind != mediaKind) continue;
        await _repairExactProviderShellLocked(
          identity: incoming.identity,
          source: source,
        );
        final String localId = await _resolveOrCreateMediaLocked(
          identity: incoming.identity,
          mediaItem: incoming.mediaItem,
        );
        bool ambiguous = false;
        for (final provider in TrackerSource.values) {
          final id = incoming.identity.idFor(provider);
          if (id == null) continue;
          final binding =
              await (database.select(database.providerBindingRecords)..where(
                    (table) =>
                        table.provider.equals(provider.name) &
                        table.mediaKind.equals(mediaKind) &
                        table.externalMediaId.equals(id),
                  ))
                  .getSingleOrNull();
          if (binding != null && binding.localId != localId) ambiguous = true;
        }
        if (ambiguous) continue;
        final MediaIdentity identity = MediaIdentity(
          localId: localId,
          kind: incoming.identity.mediaKind,
          anilistId: incoming.identity.anilistId,
          malId: incoming.identity.malId,
          shikimoriId: incoming.identity.shikimoriId,
        );
        final UserMediaState normalized = incoming.withIdentity(identity);
        incomingByLocal[localId] = normalized;
        final ProviderUserMediaState? providerState =
            normalized.providerStates[source];
        final int? externalId = identity.idFor(source);
        if (externalId != null) {
          await _upsertBindingLocked(
            localId: localId,
            provider: source.name,
            mediaKind: identity.mediaKind,
            externalMediaId: externalId,
            providerEntryId: providerState?.entryId,
            evidence: 'authenticated_provider_snapshot',
          );
        }
      }

      // Exact-identity repair may have merged rows and re-pointed journal aliases.
      // Never save the pre-repair list back over those verified changes.
      states
        ..clear()
        ..addAll(await loadTrackingStates());
      liveJournal
        ..clear()
        ..addAll(await loadJournal());
      if (accountCursor == null) {
        for (final MapEntry<String, UserMediaState> incoming
            in incomingByLocal.entries) {
          await _writeFullProviderSnapshotLocked(
            localId: incoming.key,
            source: source,
            accountId: accountId,
            state: incoming.value,
            destructiveConfirmationCount: 0,
            fetchedAt: now,
          );
        }
        await database
            .into(database.syncCursorRecords)
            .insertOnConflictUpdate(
              SyncCursorRecordsCompanion.insert(
                scope: accountScope,
                cursor: 'pending',
                metadataJson: Value<String>(
                  jsonEncode(<String, dynamic>{
                    'entryCount': incomingByLocal.length,
                    'localEntryCount': states.length,
                    'createdAt': now.toIso8601String(),
                  }),
                ),
                updatedAtMs: nowMs,
              ),
            );
        return ProviderReconciliationResult(
          states: states,
          journal: liveJournal,
          requiresAccountApproval: true,
        );
      }
      if (accountCursor.cursor == 'pending') {
        for (final MapEntry<String, UserMediaState> incoming
            in incomingByLocal.entries) {
          await _writeFullProviderSnapshotLocked(
            localId: incoming.key,
            source: source,
            accountId: accountId,
            state: incoming.value,
            destructiveConfirmationCount: 0,
            fetchedAt: now,
          );
        }
        final Expression<int> previewCount = database
            .providerSnapshotRecords
            .snapshotId
            .count();
        final int previewEntryCount =
            await (database.selectOnly(database.providerSnapshotRecords)
                  ..addColumns(<Expression<Object>>[previewCount])
                  ..where(
                    database.providerSnapshotRecords.provider.equals(
                          source.name,
                        ) &
                        database.providerSnapshotRecords.accountId.equals(
                          accountId,
                        ),
                  ))
                .map((TypedResult row) => row.read(previewCount) ?? 0)
                .getSingle();
        accountMetadata['entryCount'] = previewEntryCount;
        accountMetadata['localEntryCount'] = states.length;
        await database
            .into(database.syncCursorRecords)
            .insertOnConflictUpdate(
              SyncCursorRecordsCompanion.insert(
                scope: accountScope,
                cursor: 'pending',
                metadataJson: Value<String>(jsonEncode(accountMetadata)),
                updatedAtMs: nowMs,
              ),
            );
      }
      if (accountCursor.cursor != 'approved') {
        return ProviderReconciliationResult(
          states: states,
          journal: liveJournal,
          requiresAccountApproval: true,
        );
      }

      final importedKinds = _dynamicStringSet(
        accountMetadata['importedMediaKinds'],
      );
      final bool forceInitialImport =
          accountMetadata['initialImport'] == true ||
          !importedKinds.contains(mediaKind);
      final List<_ReconciliationProposal> safeProposals =
          <_ReconciliationProposal>[];
      int pendingDeletions = 0;
      int pendingChanges = 0;

      for (final MapEntry<String, UserMediaState> incomingEntry
          in incomingByLocal.entries) {
        final String localId = incomingEntry.key;
        final UserMediaState incoming = incomingEntry.value;
        final ProviderSnapshotRecord? previousRow = previousByLocal[localId];
        final UserMediaState? previousProvider = previousRow == null
            ? null
            : _providerStateFromSnapshot(previousRow);
        final int currentIndex = states.indexWhere(
          (UserMediaState state) => state.identity.localId == localId,
        );
        final UserMediaState? current = currentIndex < 0
            ? null
            : states[currentIndex];
        UserMediaPatch changed = _providerPatchBetween(
          forceInitialImport ? null : previousProvider,
          incoming,
          source,
        );
        if (current == null) {
          final deleted = await (database.select(
            database.canonicalLibraryRecords,
          )..where((table) => table.localId.equals(localId))).getSingleOrNull();
          if (deleted != null && !deleted.inLibrary) {
            final remoteMs =
                (incoming.providerStates[source]?.updatedAt ??
                        incoming.updatedAt)
                    .toUtc()
                    .millisecondsSinceEpoch;
            final deletedMs = _revisionEditTime(
              _jsonMap(deleted.fieldRevisionsJson)['membership'],
            );
            if (remoteMs <= 0 || deletedMs <= 0 || remoteMs == deletedMs) {
              await _recordProviderReviewLocked(
                localId: localId,
                field: 'membership',
                source: source,
                accountId: accountId,
                current: null,
                incoming: incoming,
                reason:
                    'Catalog membership conflicts with a local deletion without a newer edit date.',
              );
              continue;
            }
            if (remoteMs < deletedMs) continue;
          }
        }
        final reviews =
            await (database.select(database.libraryConflictRecords)..where(
                  (table) =>
                      table.localId.equals(localId) &
                      table.state.equals('open'),
                ))
                .get();
        final reviewedFields = reviews
            .where(
              (row) =>
                  _jsonMap(row.incomingValueJson)['provider'] == source.name &&
                  _jsonMap(row.incomingValueJson)['accountId'] == accountId,
            )
            .map((row) => _fieldFromPersistedName(row.fieldName))
            .whereType<UserMediaField>()
            .toSet();
        if (current != null &&
            ((previousRow?.destructiveConfirmationCount ?? 0) > 0 ||
                reviewedFields.isNotEmpty)) {
          changed = _providerPatchBetween(current, incoming, source);
        }

        if (current != null &&
            changed.touches(UserMediaField.score) &&
            source != TrackerSource.anilist) {
          final row = await (database.select(
            database.canonicalLibraryRecords,
          )..where((table) => table.localId.equals(localId))).getSingleOrNull();
          final revision = _jsonMap(_jsonMap(row?.fieldRevisionsJson)['score']);
          final operationId = revision['operationId']?.toString();
          if (operationId != null) {
            final delivered =
                await (database.select(database.outboxDeliveryRecords)..where(
                      (table) =>
                          table.operationId.equals(operationId) &
                          table.target.equals(source.name) &
                          table.accountId.equals(accountId) &
                          table.state.equals('confirmed'),
                    ))
                    .getSingleOrNull();
            // Integer-score trackers acknowledge a projection of the precise
            // local score. That echo is not a user edit to the raw score.
            if (delivered != null &&
                (current.score ?? 0).round() == (incoming.score ?? 0)) {
              changed = _patchSubset(
                changed,
                {...changed.fields}..remove(UserMediaField.score),
              );
            }
          }
        }

        if (current != null) {
          final row = await (database.select(
            database.canonicalLibraryRecords,
          )..where((table) => table.localId.equals(localId))).getSingleOrNull();
          final revisions = _jsonMap(row?.fieldRevisionsJson);
          final remoteEdit =
              incoming.providerStates[source]?.updatedAt ?? incoming.updatedAt;
          final remoteMs = remoteEdit.toUtc().millisecondsSinceEpoch;
          final acceptedFields = <UserMediaField>{};
          bool needsReview = false;
          for (final field in changed.fields) {
            if (providerConfirmsPatch(
              _patchFromState(current, {field}),
              incoming,
              source,
            )) {
              await _resolveProviderReviewsLocked(
                localId,
                field.name,
                source,
                accountId,
              );
              continue;
            }
            final firstObservation =
                revisions[field.name] == null &&
                !liveJournal.any(
                  (job) =>
                      job.identity.matches(current.identity) &&
                      job.patch.touches(field),
                ) &&
                ((current.providerStates[source] != null &&
                        !providerReturnedField(current, source, field)) ||
                    (current.providerStates[source] == null &&
                        !providerEntryFields(
                          current.source,
                          mediaKind: current.identity.mediaKind,
                        ).contains(field)));
            if (firstObservation && remoteMs > 0) {
              // A previously absent field has no local edit to supersede.
              // Another field's edit time must not turn a default into a clear.
              acceptedFields.add(field);
              await _resolveProviderReviewsLocked(
                localId,
                field.name,
                source,
                accountId,
              );
              continue;
            }
            int localMs = _revisionEditTime(revisions[field.name]);
            for (final job in liveJournal) {
              if (revisions[field.name] == null &&
                  job.identity.matches(incoming.identity) &&
                  job.patch.touches(field) &&
                  job.updatedAt.millisecondsSinceEpoch > localMs) {
                localMs = job.updatedAt.millisecondsSinceEpoch;
              }
            }
            if (localMs == 0 && revisions[field.name] == null) {
              localMs = current.updatedAt.millisecondsSinceEpoch;
            }
            if (remoteMs > 0 && localMs > 0 && remoteMs > localMs) {
              acceptedFields.add(field);
              await _resolveProviderReviewsLocked(
                localId,
                field.name,
                source,
                accountId,
              );
            } else if (remoteMs <= 0 || localMs <= 0 || remoteMs == localMs) {
              needsReview = true;
              await _recordProviderReviewLocked(
                localId: localId,
                field: field.name,
                source: source,
                accountId: accountId,
                current: current,
                incoming: incoming,
                reason: remoteMs <= 0
                    ? 'Catalog did not provide an edit date.'
                    : localMs <= 0
                    ? 'Local edit date is unknown; review this change.'
                    : 'Different values have the same edit date.',
              );
            } else {
              await _queueCanonicalRepairLocked(
                current,
                field,
                revisions[field.name],
                source,
                accountId,
                liveJournal,
              );
            }
          }
          if (needsReview) pendingChanges++;
          changed = _patchSubset(changed, acceptedFields);
        }

        // A verified newer edit is valid even when progress decreases or a
        // date is explicitly cleared. Counts do not establish data loss.
        if (changed.fields.isNotEmpty) {
          safeProposals.add(
            _ReconciliationProposal(
              localId: localId,
              current: current,
              incoming: incoming,
              patch: changed,
            ),
          );
        }
      }

      for (final ProviderSnapshotRecord previousRow in previousRows) {
        if (incomingByLocal.containsKey(previousRow.localId)) continue;
        final int stateIndex = states.indexWhere(
          (UserMediaState state) =>
              state.identity.localId == previousRow.localId,
        );
        if (stateIndex < 0) continue;
        final UserMediaState current = states[stateIndex];
        final SyncJournalEntry? pending = _pendingForProvider(
          liveJournal,
          current.identity,
          source,
        );
        if (pending != null && !pending.patch.delete) continue;
        await _recordProviderReviewLocked(
          localId: previousRow.localId,
          field: 'membership',
          source: source,
          accountId: accountId,
          current: current,
          incoming: null,
          reason:
              'Missing from the complete catalog list; deletion has no edit date.',
        );
        pendingDeletions++;
        continue;
      }

      // Old count-only warnings are superseded by the per-entry review above.
      final legacyWarnings =
          await (database.select(database.libraryConflictRecords)..where(
                (table) =>
                    table.fieldName.equals('massProviderChange') &
                    table.state.equals('open'),
              ))
              .get();
      for (final warning in legacyWarnings) {
        final scope = _jsonMap(warning.localValueJson);
        if (scope['provider'] == source.name &&
            scope['accountId'] == accountId) {
          await _markConflictResolvedLocked(warning.conflictId);
        }
      }

      for (final MapEntry<String, UserMediaState> incoming
          in incomingByLocal.entries) {
        await _writeFullProviderSnapshotLocked(
          localId: incoming.key,
          source: source,
          accountId: accountId,
          state: incoming.value,
          destructiveConfirmationCount: 0,
          fetchedAt: now,
        );
      }

      List<SyncJournalEntry> nextJournal = <SyncJournalEntry>[...liveJournal];
      int importedChanges = 0;
      {
        for (final _ReconciliationProposal proposal in safeProposals) {
          final UserMediaState? before = proposal.current;
          UserMediaState? after;
          final int? knownTotal =
              proposal.incoming?.mediaItem.episodeCount ??
              before?.mediaItem.episodeCount;
          final bool repairsCompletedProgress =
              proposal.incoming?.identity.mediaKind == 'anime' &&
              proposal.incoming?.status == AniListListStatus.completed &&
              knownTotal != null &&
              knownTotal > 0 &&
              (proposal.incoming?.progress ?? 0) < knownTotal;
          final DateTime editAt =
              proposal.incoming?.providerStates[source]?.updatedAt ??
              proposal.incoming?.updatedAt ??
              now;
          final UserMediaPatch acceptedPatch = repairsCompletedProgress
              ? proposal.patch.mergedWith(
                  UserMediaPatch(
                    progress: repairsCompletedProgress ? knownTotal : null,
                  ),
                )
              : proposal.patch;
          final Set<TrackerSource> outboundTargets = <TrackerSource>{
            ...propagationTargets,
            if (repairsCompletedProgress) source,
          };
          if (before == null) {
            after = proposal.incoming;
            if (repairsCompletedProgress) {
              after = after!.apply(
                acceptedPatch,
                editAt,
                providerSource: source,
              );
            }
            states.add(after!);
          } else {
            final ProviderUserMediaState? providerSnapshot =
                proposal.incoming?.providerStates[source];
            after = before.apply(acceptedPatch, editAt, providerSource: source);
            if (providerSnapshot != null) {
              final MediaIdentity mergedIdentity = before.identity.merge(
                proposal.incoming!.identity,
              );
              after = after.withProviderSnapshot(
                ProviderUserMediaState(
                  provider: source,
                  entryId: providerSnapshot.entryId,
                  rawStatus: providerSnapshot.rawStatus,
                  rawScore: providerSnapshot.rawScore,
                  updatedAt: providerSnapshot.updatedAt,
                  data: {
                    ...providerSnapshot.data,
                    for (final key in _canonicalProviderDataKeys(source))
                      if (after.providerStates[source]?.data.containsKey(key) ==
                          true)
                        key: after.providerStates[source]!.data[key],
                  },
                ),
                identity: mergedIdentity,
                mediaItem: _mergePresentationMetadata(
                  before.mediaItem,
                  proposal.incoming!.mediaItem,
                  mergedIdentity,
                ),
              );
            }
            final int index = states.indexWhere(
              (UserMediaState state) =>
                  state.identity.localId == proposal.localId,
            );
            states[index] = after;
          }
          final UserMediaPatch outboundPatch = acceptedPatch;
          final String operationId = const Uuid().v7();
          // Retire only older fields actually superseded by this catalog edit.
          for (int i = nextJournal.length - 1; i >= 0; i--) {
            final job = nextJournal[i];
            if (!job.identity.matches(after.identity) ||
                !job.updatedAt.isBefore(editAt) ||
                job.patch.delete) {
              continue;
            }
            final remaining = job.patch.fields.difference(acceptedPatch.fields);
            if (remaining.length == job.patch.fields.length) continue;
            if (remaining.isEmpty) {
              nextJournal.removeAt(i);
              if (job.operationId != null) {
                await (database.update(database.outboxDeliveryRecords)..where(
                      (table) =>
                          table.operationId.equals(job.operationId!) &
                          table.target.isNotValue('drive') &
                          table.state.isNotValue('confirmed'),
                    ))
                    .write(
                      const OutboxDeliveryRecordsCompanion(
                        state: Value('superseded'),
                        lastError: Value('Replaced by a newer catalog edit.'),
                      ),
                    );
              }
            } else {
              nextJournal[i] = SyncJournalEntry.fromJson({
                ...job.toJson(),
                'patch': _patchSubset(job.patch, remaining).toJson(),
              });
            }
          }
          // The first import must have a row BEFORE assigning its revisions.
          // Otherwise the next user action gets a null causal base on A while
          // B has already received the initial import's revision.
          await _upsertTrackingStateLocked(after);
          if (outboundTargets.isNotEmpty) {
            nextJournal = _mergeJournalMutation(
              nextJournal,
              SyncJournalEntry(
                operationId: operationId,
                identity: after.identity,
                patch: outboundPatch,
                pendingTargets: outboundTargets,
                createdAt: editAt,
                updatedAt: editAt,
                mediaTitle: after.mediaItem.title,
                targetAccountIds: <TrackerSource, String>{
                  for (final TrackerSource target in outboundTargets)
                    if (target == source)
                      target: accountId
                    else if (propagationAccountIds[target] != null)
                      target: propagationAccountIds[target]!,
                },
              ),
            );
          }
          await _appendOperationLocked(
            LibraryOperationDraft(
              operationId: operationId,
              localId: proposal.localId,
              originKind: LibraryOriginKind.provider,
              originId: '${source.name}:$accountId',
              intent: LibraryMutationIntent.remoteImport,
              fields: <String>{
                ...acceptedPatch.fields.map(
                  (UserMediaField field) => field.name,
                ),
                if (before == null) 'membership',
              },
              before: <String, dynamic>{
                if (before != null) 'state': before.toJson(),
              },
              after: <String, dynamic>{'state': after.toJson()},
              targets: outboundTargets
                  .map((TrackerSource target) => target.name)
                  .toSet(),
              occurredAt: editAt,
              editTimeVerified: editAt.millisecondsSinceEpoch > 0,
              title: after.mediaItem.title,
              targetAccountIds: <String, String>{
                for (final TrackerSource target in outboundTargets)
                  if (target == source)
                    target.name: accountId
                  else if (propagationAccountIds[target] != null)
                    target.name: propagationAccountIds[target]!,
              },
            ),
          );
          importedChanges += 1;
        }
        await _saveTrackingStatesLocked(states, tombstoneMissing: true);
        await _writeBucketLocked(
          'tracking.journal',
          nextJournal.map((SyncJournalEntry value) => value.toJson()).toList(),
        );
      }

      accountMetadata['initialImport'] = false;
      accountMetadata['importedMediaKinds'] = ({
        ...importedKinds,
        mediaKind,
      }.toList()..sort());
      accountMetadata['lastEntryCount'] = incomingByLocal.length;
      accountMetadata['lastSyncAt'] = now.toIso8601String();
      accountMetadata['quarantined'] = false;
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: accountScope,
              cursor: 'approved',
              metadataJson: Value<String>(jsonEncode(accountMetadata)),
              updatedAtMs: nowMs,
            ),
          );
      return ProviderReconciliationResult(
        states: states,
        journal: nextJournal,
        quarantined: false,
        importedChanges: importedChanges,
        destructiveChangesPending: pendingDeletions + pendingChanges,
      );
    });
  }

  Future<void> _writeFullProviderSnapshotLocked({
    required String localId,
    required TrackerSource source,
    required String accountId,
    required UserMediaState state,
    required int destructiveConfirmationCount,
    required DateTime fetchedAt,
  }) async {
    final fields = providerEntryFields(
      source,
      mediaKind: state.identity.mediaKind,
    );
    final fresh = fields
        .where((field) => providerReturnedField(state, source, field))
        .toSet();
    final previousRow =
        await (database.select(database.providerSnapshotRecords)..where(
              (table) =>
                  table.snapshotId.equals('${source.name}:$accountId:$localId'),
            ))
            .getSingleOrNull();
    final previous = previousRow == null
        ? null
        : _providerStateFromSnapshot(previousRow);
    final known = previous == null
        ? <UserMediaField>{}
        : fields
              .where(
                (field) =>
                    _providerPreviouslyObservedField(previous, source, field),
              )
              .toSet();
    // Preserve previously observed values across partial responses, but keep
    // their freshness separate so delivery waits for a current observation.
    if (previous != null) {
      state = state.apply(
        _patchFromState(previous, known.difference(fresh)),
        state.updatedAt,
        providerSource: source,
      );
    }
    final json = state.toJson();
    final providerJson = Map<String, dynamic>.from(
      (json['providerStates'] as Map)[source.name] as Map? ?? {},
    );
    providerJson['provider'] = source.name;
    providerJson['data'] = <String, dynamic>{
      ...?providerJson['data'] as Map?,
      'presentFields': fresh.map((field) => field.name).toList(),
      'knownFields': {...known, ...fresh}.map((field) => field.name).toList(),
    };
    json['providerStates'] = <String, dynamic>{
      ...json['providerStates'] as Map,
      source.name: providerJson,
    };
    state = UserMediaState.fromJson(json);
    final String normalized = jsonEncode(state.toJson());
    final ProviderUserMediaState? providerState = state.providerStates[source];
    final String raw = jsonEncode(providerState?.toJson() ?? state.toJson());
    await database
        .into(database.providerSnapshotRecords)
        .insertOnConflictUpdate(
          ProviderSnapshotRecordsCompanion.insert(
            snapshotId: '${source.name}:$accountId:$localId',
            localId: localId,
            provider: source.name,
            accountId: accountId,
            providerEntryId: Value<int?>(providerState?.entryId),
            normalizedJson: normalized,
            rawJson: raw,
            contentHash: _stateHash(state),
            fetchedAtMs: fetchedAt.millisecondsSinceEpoch,
            completeSnapshot: true,
            destructiveConfirmationCount: Value<int>(
              destructiveConfirmationCount,
            ),
          ),
        );
  }

  Future<Set<UserMediaField>> unobservedDeliveryFields(
    SyncJournalEntry mutation,
    TrackerSource source,
    String accountId,
  ) async {
    await initialize();
    if (mutation.patch.delete) return const {};
    final localId = await _localIdForIdentityLocked(mutation.identity);
    if (localId == null) return const {};
    final row =
        await (database.select(database.providerSnapshotRecords)..where(
              (table) =>
                  table.localId.equals(localId) &
                  table.provider.equals(source.name) &
                  table.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    final snapshot = row == null ? null : _providerStateFromSnapshot(row);
    // A title absent from a complete reconciled list is a legitimate new add.
    if (snapshot == null) return const {};
    return mutation.patch.fields
        .intersection(
          providerEntryFields(source, mediaKind: mutation.identity.mediaKind),
        )
        .where((field) => !providerReturnedField(snapshot, source, field))
        .toSet();
  }

  Future<List<SyncJournalEntry>> loadJournal() =>
      _loadBucket('tracking.journal', SyncJournalEntry.fromJson);

  Future<Map<String, dynamic>> loadProviderFieldCache(
    String provider,
    String accountId,
    String kind,
  ) async {
    await initialize();
    final row =
        await (database.select(database.legacyBucketRecords)..where(
              (table) => table.bucket.equals(
                'provider-fields:$provider:$accountId:$kind',
              ),
            ))
            .getSingleOrNull();
    return _jsonMap(row?.valueJson);
  }

  Future<void> saveProviderFieldCache(
    String provider,
    String accountId,
    String kind,
    Map<String, dynamic> fields,
  ) => _writeBucket('provider-fields:$provider:$accountId:$kind', fields);

  /// One-time best-effort recovery of the pre-v2 title-coalesced queue. Old
  /// SQLite operation/outbox rows are authoritative when they still exist;
  /// otherwise the old journal remains intact and is read back before write.
  Future<void> _resolveProviderReviewsLocked(
    String localId,
    String field,
    TrackerSource source,
    String accountId,
  ) async {
    final rows =
        await (database.select(database.libraryConflictRecords)..where(
              (table) =>
                  table.localId.equals(localId) &
                  table.fieldName.equals(field) &
                  table.state.equals('open'),
            ))
            .get();
    for (final row in rows) {
      final value = _jsonMap(row.incomingValueJson);
      if (value['provider'] == source.name && value['accountId'] == accountId) {
        await _markConflictResolvedLocked(row.conflictId);
      }
    }
  }

  Future<void> _recordProviderReviewLocked({
    required String localId,
    required String field,
    required TrackerSource source,
    required String accountId,
    required UserMediaState? current,
    required UserMediaState? incoming,
    required String reason,
  }) async {
    final rows =
        await (database.select(database.libraryConflictRecords)..where(
              (table) =>
                  table.localId.equals(localId) &
                  table.fieldName.equals(field) &
                  table.state.equals('open'),
            ))
            .get();
    final canonical = await (database.select(
      database.canonicalLibraryRecords,
    )..where((table) => table.localId.equals(localId))).getSingleOrNull();
    final localMs = _revisionEditTime(
      _jsonMap(canonical?.fieldRevisionsJson)[field],
    );
    final value = <String, dynamic>{
      'provider': source.name,
      'accountId': accountId,
      'reason': reason,
      'title': incoming?.mediaItem.title ?? current?.mediaItem.title,
      if (incoming != null) 'state': incoming.toJson(),
      'editAt':
          (incoming?.providerStates[source]?.updatedAt ?? incoming?.updatedAt)
              ?.toIso8601String(),
      if (localMs > 0)
        'localEditAt': DateTime.fromMillisecondsSinceEpoch(
          localMs,
          isUtc: true,
        ).toIso8601String(),
      if (incoming != null) 'catalogIds': incoming.identity.toJson(),
    };
    final existing = rows.where((row) {
      final scope = _jsonMap(row.incomingValueJson);
      return scope['provider'] == source.name &&
          scope['accountId'] == accountId;
    }).firstOrNull;
    if (existing != null) {
      await (database.update(
        database.libraryConflictRecords,
      )..where((table) => table.conflictId.equals(existing.conflictId))).write(
        LibraryConflictRecordsCompanion(
          incomingValueJson: Value(jsonEncode(value)),
        ),
      );
      return;
    }
    await database
        .into(database.libraryConflictRecords)
        .insert(
          LibraryConflictRecordsCompanion.insert(
            conflictId: _uuid.v7(),
            localId: localId,
            fieldName: field,
            localValueJson: jsonEncode({'state': current?.toJson()}),
            incomingValueJson: jsonEncode(value),
            createdAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  // Re-send the winning operation, without stamping a repair as a new edit.
  Future<void> _queueCanonicalRepairLocked(
    UserMediaState current,
    UserMediaField field,
    Object? revision,
    TrackerSource source,
    String accountId,
    List<SyncJournalEntry> journal,
  ) async {
    if (journal.any(
      (job) =>
          job.identity.matches(current.identity) &&
          job.tracks(source) &&
          (job.targetAccountIds[source] == null ||
              job.targetAccountIds[source] == accountId) &&
          job.patch.touches(field),
    )) {
      return;
    }
    final leaves = _revisionLeaves(revision).map(_jsonMap).toList()
      ..sort((a, b) => _revisionEditTime(b).compareTo(_revisionEditTime(a)));
    if (leaves.isEmpty) return;
    final operationId = leaves.first['operationId']?.toString();
    final operation = operationId == null
        ? null
        : await (database.select(database.libraryOperationRecords)
                ..where((table) => table.operationId.equals(operationId)))
              .getSingleOrNull();
    if (operation == null) return;
    final at = DateTime.fromMillisecondsSinceEpoch(
      _revisionEditTime(revision),
      isUtc: true,
    );
    final existing = journal.indexWhere(
      (job) =>
          job.operationId == operationId &&
          (job.targetAccountIds[source] == null ||
              job.targetAccountIds[source] == accountId),
    );
    final patch = _patchFromState(current, {field});
    if (existing < 0) {
      journal.add(
        SyncJournalEntry(
          operationId: operationId,
          identity: current.identity,
          patch: patch,
          pendingTargets: {source},
          createdAt: at,
          updatedAt: at,
          mediaTitle: current.mediaItem.title,
          targetAccountIds: {source: accountId},
        ),
      );
    } else {
      final job = journal[existing];
      journal[existing] = SyncJournalEntry.fromJson({
        ...job.toJson(),
        'patch': job.patch.mergedWith(patch).toJson(),
        'pendingTargets': {
          ...job.pendingTargets,
          source,
        }.map((target) => target.name).toList(),
        'targetAccountIds': {
          ...job.targetAccountIds.map(
            (key, value) => MapEntry(key.name, value),
          ),
          source.name: accountId,
        },
      });
    }
    await database
        .into(database.outboxDeliveryRecords)
        .insertOnConflictUpdate(
          OutboxDeliveryRecordsCompanion.insert(
            deliveryId: '$operationId:${source.name}:$accountId:reconcile',
            operationId: operation.operationId,
            target: source.name,
            accountId: Value(accountId),
            state: 'pending',
            lastError: const Value(
              'Catalog has an older edit; queued the current canonical value.',
            ),
          ),
        );
  }

  Future<void> compactPendingDeliveries(
    TrackerSource source,
    String accountId,
  ) async {
    await initialize();
    await database.transaction(() async {
      final journal = await loadJournal();
      final states = {
        for (final state in await loadTrackingStates())
          state.identity.localId: state,
      };
      final blocked = await unresolvedProviderDeliveryBlocks({
        source: accountId,
      });
      final conflicts = await unresolvedConflictLocalOperationIds();
      final groups = <String, int>{};
      for (int i = 0; i < journal.length; i++) {
        final job = journal[i];
        final id = await _localIdForIdentityLocked(job.identity);
        if (id == null || !job.tracks(source)) continue;
        if (job.patch.delete ||
            job.patch.touches(UserMediaField.favorite) ||
            job.awaitingRemoteTargets.contains(source) ||
            job.readbackBeforeWrite ||
            job.operationId == null ||
            conflicts.contains(job.operationId) ||
            blocked.contains((id, source)) ||
            (job.targetAccountIds[source] != null &&
                job.targetAccountIds[source] != accountId)) {
          groups.remove(id);
          continue;
        }
        final previous = groups[id];
        final state = states[id];
        if (previous != null && state != null) {
          final old = journal[previous];
          final patch = _patchFromState(state, {
            ...old.patch.fields,
            ...job.patch.fields,
          });
          journal[i] = SyncJournalEntry.fromJson({
            ...job.toJson(),
            'patch': patch.toJson(),
          });
          journal[previous] = old.deliveredTo(source).confirmedBy(source);
          await (database.update(database.outboxDeliveryRecords)..where(
                (table) =>
                    table.operationId.equals(old.operationId!) &
                    table.target.equals(source.name) &
                    (table.accountId.equals(accountId) |
                        table.accountId.isNull()) &
                    table.state.isNotValue('confirmed'),
              ))
              .write(
                const OutboxDeliveryRecordsCompanion(
                  state: Value('superseded'),
                  lastError: Value(
                    'Combined into the newest queued edit for this title.',
                  ),
                ),
              );
        }
        groups[id] = i;
      }
      await _writeBucketLocked(
        'tracking.journal',
        journal
            .where((job) => !job.isSettled)
            .map((job) => job.toJson())
            .toList(),
      );
    });
  }

  /// Rebuild missing transport jobs only from durable operations and current
  /// field revisions. Obsolete values are never replayed merely to clear a log.
  Future<void> recoverIndependentSyncBacklog() async {
    await initialize();
    if (await hasMigration('sync.independent.v3')) return;
    await database.transaction(() async {
      final journal = await loadJournal();
      final claimed = journal
          .map((job) => job.operationId)
          .whereType<String>()
          .toSet();
      final history = await database
          .select(database.libraryOperationRecords)
          .get();
      final byId = {for (final op in history) op.operationId: op};
      Object? normalize(Object? value) {
        if (value is List) return value.map(normalize).toList();
        if (value is! Map) return value;
        final leaf = Map<String, dynamic>.from(value);
        if (leaf['origin'] != 'provider' ||
            leaf.containsKey('editTimeVerified')) {
          return leaf;
        }
        final op = byId[leaf['operationId']];
        final after = _jsonMap(op?.afterJson)['state'];
        final provider = op?.originId?.split(':').first;
        final providers = after is Map ? after['providerStates'] : null;
        final data = providers is Map ? providers[provider] : null;
        final time = data is Map
            ? DateTime.tryParse('${data['updatedAt'] ?? ''}')
            : null;
        leaf['occurredAtMs'] = time?.toUtc().millisecondsSinceEpoch ?? 0;
        leaf['editTimeVerified'] = time != null;
        return leaf;
      }

      for (final op in history) {
        final before = _jsonMap(
          op.baseRevisionsJson,
        ).map((key, value) => MapEntry(key, normalize(value)));
        final after = _jsonMap(
          op.resultingRevisionsJson,
        ).map((key, value) => MapEntry(key, normalize(value)));
        if (!_jsonEquivalent(before, _jsonMap(op.baseRevisionsJson)) ||
            !_jsonEquivalent(after, _jsonMap(op.resultingRevisionsJson))) {
          await (database.update(
            database.libraryOperationRecords,
          )..where((table) => table.operationId.equals(op.operationId))).write(
            LibraryOperationRecordsCompanion(
              baseRevisionsJson: Value(jsonEncode(before)),
              resultingRevisionsJson: Value(jsonEncode(after)),
            ),
          );
        }
      }
      final rows = await database
          .select(database.canonicalLibraryRecords)
          .get();
      for (final row in rows) {
        final revisions = _jsonMap(
          row.fieldRevisionsJson,
        ).map((key, value) => MapEntry(key, normalize(value)));
        if (!_jsonEquivalent(revisions, _jsonMap(row.fieldRevisionsJson))) {
          await (database.update(
            database.canonicalLibraryRecords,
          )..where((table) => table.localId.equals(row.localId))).write(
            CanonicalLibraryRecordsCompanion(
              fieldRevisionsJson: Value(jsonEncode(revisions)),
            ),
          );
        }
      }
      final byLocal = {
        for (final row
            in await database.select(database.canonicalLibraryRecords).get())
          row.localId: row,
      };
      final pending =
          await (database.select(database.outboxDeliveryRecords)..where(
                (table) =>
                    table.target.isNotValue('drive') &
                    table.state.isNotIn([
                      'confirmed',
                      'superseded',
                      'unsupported',
                    ]),
              ))
              .get();
      for (final op
          in history
            ..sort((a, b) => a.occurredAtMs.compareTo(b.occurredAtMs))) {
        if (claimed.contains(op.operationId)) continue;
        final deliveries = pending
            .where((delivery) => delivery.operationId == op.operationId)
            .toList();
        final row = byLocal[op.localId];
        if (deliveries.isEmpty || row == null) continue;
        final current = UserMediaState.fromJson(
          _jsonMap(row.canonicalStateJson),
        );
        final recovered = _recoverOperationJournalEntry(
          op,
          deliveries,
          current.identity,
        );
        if (recovered == null) continue;
        final after = _jsonMap(op.afterJson)['state'];
        final intended = after is Map
            ? UserMediaState.fromJson(Map<String, dynamic>.from(after))
            : null;
        final fields = recovered.patch.fields
            .where(
              (field) =>
                  intended == null ||
                  _jsonEquivalent(
                    _canonicalFieldValue(
                      field.name,
                      current,
                      membership: row.inLibrary,
                      favorite: row.favorite,
                    ),
                    _canonicalFieldValue(
                      field.name,
                      intended,
                      membership: true,
                      favorite: row.favorite,
                    ),
                  ),
            )
            .toSet();
        if (recovered.patch.delete && row.inLibrary) {
          fields.clear();
        }
        if ((recovered.patch.delete && row.inLibrary) ||
            (!recovered.patch.delete && fields.isEmpty)) {
          for (final delivery in deliveries) {
            await (database.update(database.outboxDeliveryRecords)..where(
                  (table) => table.deliveryId.equals(delivery.deliveryId),
                ))
                .write(
                  const OutboxDeliveryRecordsCompanion(
                    state: Value('superseded'),
                    lastError: Value(
                      'Newer canonical edits replaced this operation.',
                    ),
                  ),
                );
          }
        } else {
          journal.add(
            SyncJournalEntry.fromJson({
              ...recovered.toJson(),
              'patch': _patchSubset(recovered.patch, fields).toJson(),
              'readbackBeforeWrite': true,
            }),
          );
        }
      }
      await _writeBucketLocked(
        'tracking.journal',
        journal.map((job) => job.toJson()).toList(),
      );
      await markMigrationComplete('sync.independent.v3');
    });
  }

  Future<void> recoverLegacyOperationDeliveries() async {
    await initialize();
    if (await hasMigration('journal.operationReplay.v2')) return;
    await database.transaction(() async {
      final List<SyncJournalEntry> old = await loadJournal();
      if (old.every((SyncJournalEntry entry) => entry.operationId != null)) {
        await markMigrationComplete('journal.operationReplay.v2');
        return;
      }
      final List<OutboxDeliveryRecord> pending =
          await (database.select(database.outboxDeliveryRecords)..where(
                (OutboxDeliveryRecords table) =>
                    table.target.isNotValue('drive') &
                    table.state.isNotValue('confirmed'),
              ))
              .get();
      final Set<String> pendingIds = pending
          .map((OutboxDeliveryRecord row) => row.operationId)
          .toSet();
      final List<LibraryOperationRecord> operations = pendingIds.isEmpty
          ? const <LibraryOperationRecord>[]
          : await (database.select(database.libraryOperationRecords)..where(
                  (LibraryOperationRecords table) =>
                      table.operationId.isIn(pendingIds),
                ))
                .get();
      operations.sort((a, b) {
        final int time = a.occurredAtMs.compareTo(b.occurredAtMs);
        return time != 0 ? time : a.operationId.compareTo(b.operationId);
      });
      final Set<String> claimed = old
          .map((SyncJournalEntry entry) => entry.operationId)
          .whereType<String>()
          .toSet();
      final List<SyncJournalEntry> recovered = <SyncJournalEntry>[];
      for (final SyncJournalEntry legacy in old) {
        if (legacy.operationId != null) {
          recovered.add(legacy);
          continue;
        }
        final String? localId = await _localIdForIdentityLocked(
          legacy.identity,
        );
        final Set<TrackerSource> expected = <TrackerSource>{
          ...legacy.pendingTargets,
          ...legacy.awaitingRemoteTargets,
        };
        final Set<TrackerSource> covered = <TrackerSource>{};
        for (final LibraryOperationRecord operation in operations) {
          if (operation.localId != localId ||
              !claimed.add(operation.operationId)) {
            continue;
          }
          final List<OutboxDeliveryRecord> deliveries = pending
              .where(
                (OutboxDeliveryRecord row) =>
                    row.operationId == operation.operationId &&
                    expected.any(
                      (TrackerSource target) => target.name == row.target,
                    ),
              )
              .toList(growable: false);
          if (deliveries.isEmpty) {
            claimed.remove(operation.operationId);
            continue;
          }
          final SyncJournalEntry? entry = _recoverOperationJournalEntry(
            operation,
            deliveries,
            legacy.identity,
          );
          if (entry == null) {
            claimed.remove(operation.operationId);
            continue;
          }
          recovered.add(entry);
          covered.addAll(<TrackerSource>{
            ...entry.pendingTargets,
            ...entry.awaitingRemoteTargets,
          });
        }
        final Set<TrackerSource> remainingPending = <TrackerSource>{
          ...legacy.pendingTargets,
        }..removeAll(covered);
        final Set<TrackerSource> remainingAwaiting = <TrackerSource>{
          ...legacy.awaitingRemoteTargets,
        }..removeAll(covered);
        if (remainingPending.isNotEmpty || remainingAwaiting.isNotEmpty) {
          recovered.add(
            SyncJournalEntry(
              identity: legacy.identity,
              patch: legacy.patch,
              pendingTargets: remainingPending,
              awaitingRemoteTargets: remainingAwaiting,
              createdAt: legacy.createdAt,
              updatedAt: legacy.updatedAt,
              mediaTitle: legacy.mediaTitle,
              providerEntryIds: legacy.providerEntryIds,
              targetAccountIds: legacy.targetAccountIds,
              readbackBeforeWrite: true,
            ),
          );
        }
      }
      await _writeBucketLocked(
        'tracking.journal',
        recovered.map((SyncJournalEntry entry) => entry.toJson()).toList(),
      );
      await markMigrationComplete('journal.operationReplay.v2');
    });
  }

  SyncJournalEntry? _recoverOperationJournalEntry(
    LibraryOperationRecord operation,
    List<OutboxDeliveryRecord> deliveries,
    MediaIdentity fallbackIdentity,
  ) {
    final Map<String, dynamic> after = _jsonMap(operation.afterJson);
    final Map<String, dynamic> before = _jsonMap(operation.beforeJson);
    final Object? rawState = after['state'];
    final Object? rawPrevious = before['state'];
    final UserMediaState? state = rawState is Map
        ? UserMediaState.fromJson(Map<String, dynamic>.from(rawState))
        : null;
    final UserMediaState? previous = rawPrevious is Map
        ? UserMediaState.fromJson(Map<String, dynamic>.from(rawPrevious))
        : null;
    final bool remove = operation.intent == LibraryMutationIntent.remove.name;
    if (!remove && state == null && after['favorite'] is! bool) return null;
    final Set<String> changed = _jsonStringSet(operation.fieldsJson);
    final Set<UserMediaField> fields = changed
        .map(_fieldFromPersistedName)
        .whereType<UserMediaField>()
        .toSet();
    if (changed.contains('membership') && state != null) {
      fields.addAll(<UserMediaField>{
        UserMediaField.status,
        UserMediaField.progress,
      });
    }
    UserMediaPatch patch = remove
        ? UserMediaPatch(delete: true)
        : state == null
        ? UserMediaPatch()
        : _patchFromState(state, fields);
    if (after['favorite'] is bool) {
      patch = patch.mergedWith(
        UserMediaPatch(favorite: after['favorite'] as bool),
      );
    }
    final Set<TrackerSource> pendingTargets = <TrackerSource>{};
    final Set<TrackerSource> awaitingTargets = <TrackerSource>{};
    final Map<TrackerSource, String> accountIds = <TrackerSource, String>{};
    for (final OutboxDeliveryRecord delivery in deliveries) {
      final TrackerSource target = TrackerSource.fromName(delivery.target);
      if (delivery.state == 'delivered') {
        awaitingTargets.add(target);
      } else {
        pendingTargets.add(target);
      }
      if (delivery.accountId != null) {
        accountIds[target] = delivery.accountId!;
      }
    }
    final DateTime occurredAt = DateTime.fromMillisecondsSinceEpoch(
      operation.occurredAtMs,
      isUtc: true,
    );
    return SyncJournalEntry(
      operationId: operation.operationId,
      identity: (state?.identity ?? previous?.identity ?? fallbackIdentity)
          .merge(fallbackIdentity),
      patch: patch,
      pendingTargets: pendingTargets,
      awaitingRemoteTargets: awaitingTargets,
      createdAt: occurredAt,
      updatedAt: occurredAt,
      mediaTitle: operation.title ?? state?.mediaItem.title,
      targetAccountIds: accountIds,
      readbackBeforeWrite: true,
    );
  }

  Future<void> saveJournal(List<SyncJournalEntry> values) => _writeBucket(
    'tracking.journal',
    values.map((SyncJournalEntry value) => value.toJson()).toList(),
  );

  Future<void> saveJournalChanges(
    List<SyncJournalEntry> before,
    List<SyncJournalEntry> after,
  ) async {
    await initialize();
    await database.transaction(() async {
      String key(SyncJournalEntry entry) =>
          entry.operationId ??
          'legacy:${jsonEncode(entry.identity.toJson())}:${entry.createdAt.toIso8601String()}:${jsonEncode(entry.patch.toJson())}';
      final Map<String, SyncJournalEntry> live = {
        for (final entry in await loadJournal()) key(entry): entry,
      };
      final Map<String, SyncJournalEntry> next = {
        for (final entry in after) key(entry): entry,
      };
      for (final entry in before) {
        final current = live[key(entry)];
        final changed = next.remove(key(entry));
        if (current == null) continue;
        // Independent workers may settle different targets of the same job.
        // Apply only transport deltas; never overwrite a concurrently rebased patch.
        final removedPending = entry.pendingTargets.difference(
          changed?.pendingTargets ?? {},
        );
        final removedAwaiting = entry.awaitingRemoteTargets.difference(
          changed?.awaitingRemoteTargets ?? {},
        );
        final addedAwaiting =
            (changed?.awaitingRemoteTargets ?? <TrackerSource>{})
                .difference(entry.awaitingRemoteTargets)
                .intersection(current.pendingTargets);
        final merged = SyncJournalEntry(
          operationId: current.operationId,
          identity: current.identity,
          patch: current.patch,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
          mediaTitle: current.mediaTitle,
          providerEntryIds: current.providerEntryIds,
          targetAccountIds: current.targetAccountIds,
          readbackBeforeWrite:
              current.readbackBeforeWrite ||
              (changed?.readbackBeforeWrite ?? false),
          pendingTargets: current.pendingTargets.difference(removedPending),
          awaitingRemoteTargets: {
            ...current.awaitingRemoteTargets,
            ...addedAwaiting,
          }..removeAll(removedAwaiting),
        );
        if (merged.isSettled) {
          live.remove(key(entry));
        } else {
          live[key(entry)] = merged;
        }
      }
      final Set<String> baselineIds = before.map(key).toSet();
      for (final entry in next.values) {
        if (!baselineIds.contains(key(entry))) {
          live.putIfAbsent(key(entry), () => entry);
        }
      }
      await _writeBucketLocked(
        'tracking.journal',
        live.values.map((e) => e.toJson()).toList(),
      );
    });
  }

  Future<void> updateTrackerDelivery({
    String? operationId,
    String? accountId,
    required MediaIdentity identity,
    required TrackerSource target,
    required String state,
    String? error,
    DateTime? nextAttemptAt,
  }) async {
    await initialize();
    await database.transaction(() async {
      final String? localId = await _localIdForIdentityLocked(identity);
      if (localId == null) return;
      final List<LibraryOperationRecord> operations =
          await (database.select(database.libraryOperationRecords)..where(
                (LibraryOperationRecords table) =>
                    table.localId.equals(localId) &
                    (operationId == null
                        ? const Constant(true)
                        : table.operationId.equals(operationId)),
              ))
              .get();
      final Set<String> operationIds = operations
          .map((LibraryOperationRecord value) => value.operationId)
          .toSet();
      if (operationIds.isEmpty) return;
      final List<OutboxDeliveryRecord> deliveries =
          await (database.select(database.outboxDeliveryRecords)..where(
                (OutboxDeliveryRecords table) =>
                    table.target.equals(target.name) &
                    table.operationId.isIn(operationIds) &
                    table.state.isNotValue('confirmed'),
              ))
              .get();
      // A pre-v2 journal entry might represent several historic operations.
      // Never bulk-confirm them from one provider read-back.
      if (operationId == null && deliveries.length != 1) return;
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final OutboxDeliveryRecord delivery in deliveries) {
        if (accountId != null &&
            delivery.accountId != null &&
            delivery.accountId != accountId) {
          continue;
        }
        await (database.update(database.outboxDeliveryRecords)..where(
              (OutboxDeliveryRecords table) =>
                  table.deliveryId.equals(delivery.deliveryId),
            ))
            .write(
              OutboxDeliveryRecordsCompanion(
                accountId: Value<String?>(accountId ?? delivery.accountId),
                state: Value<String>(state),
                lastAttemptAtMs: state == 'sending'
                    ? Value(now)
                    : const Value.absent(),
                nextAttemptAtMs: Value(
                  nextAttemptAt?.toUtc().millisecondsSinceEpoch,
                ),
                attempts: Value<int>(
                  delivery.attempts + (state == 'sending' ? 1 : 0),
                ),
                deliveredAtMs: state == 'delivered' || state == 'confirmed'
                    ? Value<int>(delivery.deliveredAtMs ?? now)
                    : const Value<int?>.absent(),
                confirmedAtMs: state == 'confirmed'
                    ? Value<int>(now)
                    : const Value<int?>.absent(),
                lastError: Value<String?>(error),
              ),
            );
        if (state == 'confirmed') {
          final operation = operations.firstWhere(
            (op) => op.operationId == delivery.operationId,
          );
          final providerAccount = accountId ?? delivery.accountId;
          if (providerAccount != null) {
            await _advanceConfirmedProviderSnapshotLocked(
              operation,
              target,
              providerAccount,
            );
          }
        }
      }
    });
  }

  Future<void> _advanceConfirmedProviderSnapshotLocked(
    LibraryOperationRecord operation,
    TrackerSource provider,
    String accountId,
  ) async {
    final snapshot =
        await (database.select(database.providerSnapshotRecords)..where(
              (table) =>
                  table.localId.equals(operation.localId) &
                  table.provider.equals(provider.name) &
                  table.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    if (snapshot == null) return;
    final after = _jsonMap(operation.afterJson)['state'];
    if (after is! Map) {
      return; // Removal is verified by the next complete snapshot.
    }
    final intended = UserMediaState.fromJson(Map<String, dynamic>.from(after));
    final previous = _providerStateFromSnapshot(snapshot);
    if (previous == null) return;
    final supported = _providerPatchBetween(null, intended, provider).fields;
    final fields =
        _jsonStringSet(
            operation.fieldsJson,
          ).map(_fieldFromPersistedName).whereType<UserMediaField>().toSet()
          ..retainAll(supported);
    if (fields.isEmpty) return;
    UserMediaPatch patch = _patchFromState(intended, fields);
    if (provider != TrackerSource.anilist &&
        fields.contains(UserMediaField.score)) {
      patch = patch.mergedWith(
        UserMediaPatch(
          score: integerProviderScore(intended.score ?? 0).toDouble(),
        ),
      );
    }
    final projected = previous.apply(
      patch,
      previous.updatedAt,
      providerSource: provider,
    );
    // Read-back proved these fields were delivered to THIS account. Advance
    // its comparison baseline so the provider's rounded score/status echo is
    // not imported as a fresh manual action on the next background pass.
    await (database.update(
      database.providerSnapshotRecords,
    )..where((table) => table.snapshotId.equals(snapshot.snapshotId))).write(
      ProviderSnapshotRecordsCompanion(
        normalizedJson: Value(jsonEncode(projected.toJson())),
        contentHash: Value(_stateHash(projected)),
        destructiveConfirmationCount: const Value(0),
      ),
    );
  }

  Future<Map<String, Map<String, String>>>
  confirmedTrackerDeliveryLedger() async {
    await initialize();
    final List<OutboxDeliveryRecord> rows =
        await (database.select(database.outboxDeliveryRecords)..where(
              (OutboxDeliveryRecords table) =>
                  table.target.isNotValue('drive') &
                  table.state.equals('confirmed'),
            ))
            .get();
    return <String, Map<String, String>>{
      for (final OutboxDeliveryRecord row in rows)
        row.deliveryId: <String, String>{
          'state': 'confirmed',
          if (row.confirmedAtMs != null)
            'confirmedAt': DateTime.fromMillisecondsSinceEpoch(
              row.confirmedAtMs!,
              isUtc: true,
            ).toIso8601String(),
          if (row.accountId != null) 'accountId': row.accountId!,
        },
    };
  }

  Future<void> applyRemoteDeliveryLedger(
    Map<String, Map<String, String>> ledger,
  ) async {
    if (ledger.isEmpty) return;
    await initialize();
    await database.transaction(() async {
      final Set<(String, String)> affected = <(String, String)>{};
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final ordered = ledger.entries.toList()
        ..sort((a, b) {
          int confirmedAt(Map<String, String> value) =>
              DateTime.tryParse(
                value['confirmedAt'] ?? '',
              )?.millisecondsSinceEpoch ??
              0;
          return confirmedAt(a.value).compareTo(confirmedAt(b.value));
        });
      for (final MapEntry<String, Map<String, String>> item in ordered) {
        if (item.value['state'] != 'confirmed') continue;
        final OutboxDeliveryRecord? delivery =
            await (database.select(database.outboxDeliveryRecords)..where(
                  (OutboxDeliveryRecords table) =>
                      table.deliveryId.equals(item.key),
                ))
                .getSingleOrNull();
        if (delivery == null || delivery.target == 'drive') continue;
        final accountId = item.value['accountId'];
        if (delivery.accountId != null && delivery.accountId != accountId) {
          continue;
        }
        if (delivery.state == 'confirmed' && delivery.accountId == accountId) {
          continue;
        }
        final LibraryOperationRecord? operation =
            await (database.select(database.libraryOperationRecords)..where(
                  (LibraryOperationRecords table) =>
                      table.operationId.equals(delivery.operationId),
                ))
                .getSingleOrNull();
        if (operation == null) continue;
        final int confirmedAt =
            DateTime.tryParse(
              item.value['confirmedAt'] ?? '',
            )?.millisecondsSinceEpoch ??
            now;
        await (database.update(database.outboxDeliveryRecords)..where(
              (OutboxDeliveryRecords table) =>
                  table.deliveryId.equals(delivery.deliveryId),
            ))
            .write(
              OutboxDeliveryRecordsCompanion(
                accountId: Value(accountId ?? delivery.accountId),
                state: const Value<String>('confirmed'),
                deliveredAtMs: Value<int>(
                  delivery.deliveredAtMs ?? confirmedAt,
                ),
                confirmedAtMs: Value<int>(confirmedAt),
                lastError: const Value<String?>(null),
              ),
            );
        if (accountId != null) {
          await _advanceConfirmedProviderSnapshotLocked(
            operation,
            TrackerSource.fromName(delivery.target),
            accountId,
          );
        }
        affected.add((operation.localId, delivery.target));
      }

      if (affected.isEmpty) return;
      List<SyncJournalEntry> journal = await loadJournal();
      for (final (String localId, String targetName) in affected) {
        final TrackerSource target = TrackerSource.fromName(targetName);
        final List<LibraryOperationRecord> localOperations =
            await (database.select(database.libraryOperationRecords)..where(
                  (LibraryOperationRecords table) =>
                      table.localId.equals(localId),
                ))
                .get();
        final Set<String> localOperationIds = localOperations
            .map((LibraryOperationRecord value) => value.operationId)
            .toSet();
        final List<OutboxDeliveryRecord> outstanding = localOperationIds.isEmpty
            ? const <OutboxDeliveryRecord>[]
            : await (database.select(database.outboxDeliveryRecords)
                    ..where(
                      (OutboxDeliveryRecords table) =>
                          table.target.equals(targetName) &
                          table.operationId.isIn(localOperationIds) &
                          table.state.isNotValue('confirmed'),
                    )
                    ..limit(1))
                  .get();
        if (outstanding.isNotEmpty) continue;
        final CanonicalLibraryRecord? localState =
            await (database.select(database.canonicalLibraryRecords)..where(
                  (CanonicalLibraryRecords table) =>
                      table.localId.equals(localId),
                ))
                .getSingleOrNull();
        final UserMediaState? canonicalState = localState == null
            ? null
            : UserMediaState.fromJson(_jsonMap(localState.canonicalStateJson));
        journal = journal
            .map(
              (SyncJournalEntry entry) =>
                  entry.identity.localId == localId ||
                      (canonicalState != null &&
                          entry.identity.matches(canonicalState.identity))
                  ? entry.confirmedBy(target).deliveredTo(target)
                  : entry,
            )
            .where((SyncJournalEntry entry) => !entry.isSettled)
            .toList(growable: false);
      }
      await _writeBucketLocked(
        'tracking.journal',
        journal.map((SyncJournalEntry value) => value.toJson()).toList(),
      );
    });
  }

  Future<List<LocalMediaFavoriteState>> loadFavorites() =>
      _loadBucket('tracking.favorites', LocalMediaFavoriteState.fromJson);

  Stream<List<LocalMediaFavoriteState>> watchFavorites() =>
      Stream<void>.fromFuture(initialize()).asyncExpand(
        (_) =>
            (database.select(database.legacyBucketRecords)
                  ..where((table) => table.bucket.equals('tracking.favorites')))
                .watch()
                .map(
                  (rows) => rows.isEmpty
                      ? <LocalMediaFavoriteState>[]
                      : _jsonList(rows.single.valueJson)
                            .whereType<Map>()
                            .map(
                              (value) => LocalMediaFavoriteState.fromJson(
                                Map<String, dynamic>.from(value),
                              ),
                            )
                            .toList(),
                ),
      );

  Stream<List<UserMediaState>> watchTrackingStates() =>
      Stream<void>.fromFuture(initialize()).asyncExpand(
        (_) =>
            (database.select(database.canonicalLibraryRecords)
                  ..where((table) => table.inLibrary.equals(true)))
                .watch()
                .distinct((left, right) {
                  if (left.length != right.length) return false;
                  for (int index = 0; index < left.length; index++) {
                    if (left[index].localId != right[index].localId ||
                        left[index].canonicalStateJson !=
                            right[index].canonicalStateJson) {
                      return false;
                    }
                  }
                  return true;
                })
                .map(
                  (rows) =>
                      rows
                          .map(
                            (row) => UserMediaState.fromJson(
                              _jsonMap(row.canonicalStateJson),
                            ),
                          )
                          .toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
                ),
      );

  Future<void> _setFavoriteLocked({
    required String localId,
    required MediaIdentity identity,
    required bool favorite,
    required DateTime at,
    MediaItem? mediaItem,
  }) async {
    final values = await loadFavorites();
    values.removeWhere((value) => value.identity.matches(identity));
    values.add(
      LocalMediaFavoriteState(
        identity: identity,
        favorite: favorite,
        updatedAt: at,
      ),
    );
    await _writeBucketLocked(
      'tracking.favorites',
      values.map((v) => v.toJson()).toList(),
    );
    final row = await (database.select(
      database.canonicalLibraryRecords,
    )..where((table) => table.localId.equals(localId))).getSingleOrNull();
    if (row == null) {
      final shell = UserMediaState(
        identity: identity,
        mediaItem: mediaItem ?? _placeholderMedia(identity),
        status: AniListListStatus.planning,
        progress: 0,
        createdAt: at,
        updatedAt: at,
        source: TrackerSource.anilist,
      );
      await _upsertTrackingStateLocked(shell);
      await (database.update(
        database.canonicalLibraryRecords,
      )..where((table) => table.localId.equals(localId))).write(
        const CanonicalLibraryRecordsCompanion(inLibrary: Value(false)),
      );
    }
    await (database.update(database.canonicalLibraryRecords)
          ..where((table) => table.localId.equals(localId)))
        .write(CanonicalLibraryRecordsCompanion(favorite: Value(favorite)));
  }

  Future<void> saveFavorites(List<LocalMediaFavoriteState> values) async {
    await initialize();
    await database.transaction(() async {
      await _writeBucketLocked(
        'tracking.favorites',
        values.map((LocalMediaFavoriteState value) => value.toJson()).toList(),
      );
      await _applyFavoritesLocked(values, await loadTrackingStates());
    });
  }

  /// Stores the compatibility/local catalog view in the same workspace SQLite
  /// database as the canonical library. This replaces the old multi-megabyte
  /// SharedPreferences payload while TMDB and other non-tracker items keep
  /// their existing behavior.
  Future<List<LibraryItem>> loadLocalLibraryItems() =>
      _loadBucket('local.libraryItems.v2', LibraryItem.fromJson);

  Future<void> saveLocalLibraryItems(List<LibraryItem> values) => _writeBucket(
    'local.libraryItems.v2',
    values.map((LibraryItem value) => value.toJson()).toList(growable: false),
  );

  /// Raw episode aliases that cannot yet be attached to an exact canonical
  /// media id (for example a Sora source episode) also belong in SQLite, never
  /// NSUserDefaults. Exact identities continue to use EpisodeStateRecords and
  /// are included in Drive snapshots.
  Future<Map<String, dynamic>> loadLocalEpisodeProgress() async {
    await initialize();
    final LegacyBucketRecord? row =
        await (database.select(database.legacyBucketRecords)..where(
              (LegacyBucketRecords table) =>
                  table.bucket.equals('local.episodeProgress.v2'),
            ))
            .getSingleOrNull();
    if (row == null || row.valueJson.isEmpty) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(row.valueJson);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  Future<void> saveLocalEpisodeProgress(Map<String, dynamic> values) =>
      _writeBucket('local.episodeProgress.v2', values);

  /// Patch one compatibility checkpoint atomically in SQLite. Playback must
  /// not copy/JSON-encode the entire episode history on the UI isolate for
  /// every five-second tick or race another alias checkpoint's full save.
  Future<void> saveLocalEpisodeCheckpoint(
    String key,
    Map<String, dynamic> checkpoint,
  ) async {
    await initialize();
    // Replace this key before merging: EpisodeProgress.toJson omits false
    // completion/unknown duration, which must not inherit the previous values.
    await database.customUpdate(
      '''INSERT INTO legacy_bucket_records (bucket, value_json, updated_at_ms)
         VALUES (?, ?, ?)
         ON CONFLICT(bucket) DO UPDATE SET
           value_json = json_patch(
             json_patch(
               CASE WHEN json_valid(legacy_bucket_records.value_json)
                 THEN legacy_bucket_records.value_json ELSE '{}' END,
               json_object(?, NULL)),
             excluded.value_json),
           updated_at_ms = excluded.updated_at_ms''',
      variables: [
        const Variable<String>('local.episodeProgress.v2'),
        Variable<String>(jsonEncode({key: checkpoint})),
        Variable<int>(DateTime.now().toUtc().millisecondsSinceEpoch),
        Variable<String>(key),
      ],
      updates: {database.legacyBucketRecords},
    );
  }

  Future<void> _applyFavoritesLocked(
    List<LocalMediaFavoriteState> favorites,
    List<UserMediaState> states,
  ) async {
    await database
        .update(database.canonicalLibraryRecords)
        .write(
          const CanonicalLibraryRecordsCompanion(favorite: Value<bool>(false)),
        );
    for (final LocalMediaFavoriteState favorite in favorites) {
      if (!favorite.favorite) continue;
      for (final UserMediaState state in states) {
        if (!state.identity.matches(favorite.identity)) continue;
        final String? localId = await _localIdForIdentityLocked(state.identity);
        if (localId == null) break;
        await (database.update(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) => table.localId.equals(localId),
            ))
            .write(
              const CanonicalLibraryRecordsCompanion(
                favorite: Value<bool>(true),
              ),
            );
        break;
      }
    }
  }

  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth({
    Map<TrackerSource, String> accountIds = const {},
  }) async {
    await initialize();
    final List<ProviderHealthRecord> rows = await (database.select(
      database.providerHealthRecords,
    )..orderBy([(table) => OrderingTerm.asc(table.updatedAtMs)])).get();
    final Map<TrackerSource, TrackerProviderHealth> result =
        <TrackerSource, TrackerProviderHealth>{};
    for (final ProviderHealthRecord row in rows) {
      try {
        final Object? decoded = jsonDecode(row.healthJson);
        if (decoded is! Map<String, dynamic>) continue;
        final TrackerProviderHealth value = TrackerProviderHealth.fromJson(
          decoded,
        );
        final expectedAccount = accountIds[value.provider];
        if (expectedAccount != null &&
            value.accountId != null &&
            value.accountId != expectedAccount) {
          continue;
        }
        // A legacy unscoped row must not override this account's own state.
        if (expectedAccount != null &&
            value.accountId == null &&
            result[value.provider]?.accountId == expectedAccount) {
          continue;
        }
        result[value.provider] = value;
      } on Object {
        // Keep other providers available when one health row is corrupt.
      }
    }
    return result;
  }

  Future<void> saveHealth(
    Map<TrackerSource, TrackerProviderHealth> values,
  ) async {
    await initialize();
    await database.transaction(() async {
      for (final TrackerProviderHealth value in values.values) {
        await database
            .into(database.providerHealthRecords)
            .insertOnConflictUpdate(
              ProviderHealthRecordsCompanion.insert(
                provider: value.accountId == null
                    ? value.provider.name
                    : '${value.provider.name}:${value.accountId}',
                healthJson: jsonEncode(value.toJson()),
                updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      }
    });
  }

  Future<void> commitTrackingMutation({
    String? operationId,
    required List<UserMediaState> states,
    required List<SyncJournalEntry> journal,
    required List<LocalMediaFavoriteState> favorites,
    required MediaIdentity identity,
    required UserMediaPatch patch,
    required Set<TrackerSource> targets,
    required DateTime occurredAt,
    String? mediaTitle,
    LibraryOriginKind originKind = LibraryOriginKind.user,
    String? originId,
    TrackingEpisodeCheckpoint? episodeCheckpoint,
  }) async {
    await initialize();
    await database.transaction(() async {
      final String? knownId = await _localIdForIdentityLocked(identity);
      final CanonicalLibraryRecord? liveRow = knownId == null
          ? null
          : await (database.select(database.canonicalLibraryRecords)
                  ..where((table) => table.localId.equals(knownId)))
                .getSingleOrNull();
      final UserMediaState? before = liveRow?.inLibrary == true
          ? UserMediaState.fromJson(_jsonMap(liveRow!.canonicalStateJson))
          : null;
      UserMediaState? after;
      for (final UserMediaState state in states) {
        if (state.identity.matches(identity)) {
          after = state;
          break;
        }
      }
      // The caller's list was read before this transaction. Apply only the
      // requested fields to the live row, never replace a workspace with that
      // stale list (Drive and background reconciliation can run meanwhile).
      if (patch.delete) {
        after = null;
      } else if (before != null) {
        UserMediaState live = before.withIdentity(
          before.identity.merge(identity),
        );
        if ((live.mediaItem.episodeCount ?? 0) <= 0 &&
            (after?.mediaItem.episodeCount ?? 0) > 0) {
          live = live.withMediaItem(
            live.mediaItem.copyWith(
              episodeCount: after!.mediaItem.episodeCount,
            ),
          );
        }
        after = live.apply(patch, occurredAt);
      } else if (!patch.touchesLibraryState) {
        // A stale caller can still hold this row after a concurrent deletion.
        // Favorite/checkpoint-only actions must never re-add membership.
        after = null;
      }
      final String localId = await _resolveOrCreateMediaLocked(
        identity: after?.identity ?? before?.identity ?? identity,
        mediaItem:
            after?.mediaItem ??
            before?.mediaItem ??
            _placeholderMedia(identity),
      );
      MediaIdentity canonicalIdentity(MediaIdentity value) => MediaIdentity(
        localId: localId,
        kind: value.mediaKind,
        anilistId: value.anilistId,
        malId: value.malId,
        shikimoriId: value.shikimoriId,
      );
      final UserMediaState? canonicalBefore = before?.withIdentity(
        canonicalIdentity(before.identity),
      );
      UserMediaState? canonicalAfter = after?.withIdentity(
        canonicalIdentity(after.identity),
      );
      final effectiveFields = canonicalBefore == null
          ? patch.fields
          : patch.fields.where((field) {
              if (field == UserMediaField.favorite) {
                return (liveRow?.favorite ?? false) != patch.favorite;
              }
              return !_jsonEquivalent(
                _canonicalFieldValue(
                  field.name,
                  canonicalBefore,
                  membership: true,
                  favorite: liveRow?.favorite ?? false,
                ),
                _canonicalFieldValue(
                  field.name,
                  canonicalAfter,
                  membership: true,
                  favorite: liveRow?.favorite ?? false,
                ),
              );
            }).toSet();
      if (effectiveFields.isEmpty &&
          canonicalBefore != null &&
          canonicalAfter != null) {
        canonicalAfter = canonicalAfter.apply(
          UserMediaPatch(fields: {}),
          canonicalBefore.updatedAt,
        );
      }
      if (canonicalAfter != null) {
        await _upsertTrackingStateLocked(canonicalAfter);
      } else if (before != null && patch.delete) {
        await (database.update(
          database.canonicalLibraryRecords,
        )..where((table) => table.localId.equals(localId))).write(
          CanonicalLibraryRecordsCompanion(
            inLibrary: const Value(false),
            tombstonedAtMs: Value(occurredAt.toUtc().millisecondsSinceEpoch),
            updatedAtMs: Value(occurredAt.toUtc().millisecondsSinceEpoch),
          ),
        );
      }
      final Set<String> activeIds = (await _readBucketLocked(
        'tracking.stateIds',
      )).whereType<String>().toSet();
      if (canonicalAfter != null) activeIds.add(localId);
      if (patch.delete) activeIds.remove(localId);
      await _writeBucketLocked('tracking.stateIds', activeIds.toList()..sort());
      final List<SyncJournalEntry> liveJournal = await loadJournal();
      for (final SyncJournalEntry entry in journal) {
        if (entry.operationId == operationId &&
            !liveJournal.any(
              (value) => value.operationId == entry.operationId,
            )) {
          if (effectiveFields.isNotEmpty ||
              patch.delete ||
              (canonicalBefore == null && canonicalAfter != null)) {
            liveJournal.add(
              SyncJournalEntry.fromJson({
                ...entry.toJson(),
                'patch': _patchSubset(entry.patch, effectiveFields).toJson(),
              }),
            );
          }
        }
      }
      await _writeBucketLocked(
        'tracking.journal',
        liveJournal.map((value) => value.toJson()).toList(),
      );
      final bool beforeFavorite = liveRow?.favorite ?? false;
      final bool afterFavorite = patch.touches(UserMediaField.favorite)
          ? patch.favorite ?? beforeFavorite
          : beforeFavorite;
      if (patch.touches(UserMediaField.favorite)) {
        await _setFavoriteLocked(
          localId: localId,
          identity: canonicalIdentity(
            after?.identity ?? before?.identity ?? identity,
          ),
          favorite: afterFavorite,
          at: occurredAt,
          mediaItem: after?.mediaItem ?? before?.mediaItem,
        );
      }
      final bool addsMembership =
          canonicalBefore == null && canonicalAfter != null;
      EpisodeStateRecord? previousEpisode;
      if (episodeCheckpoint != null) {
        final String episodeId =
            '$localId:${episodeCheckpoint.watchCycle}:${episodeCheckpoint.season}:${episodeCheckpoint.episode}';
        previousEpisode =
            await (database.select(database.episodeStateRecords)..where(
                  (EpisodeStateRecords table) =>
                      table.episodeStateId.equals(episodeId),
                ))
                .getSingleOrNull();
        await database
            .into(database.episodeStateRecords)
            .insertOnConflictUpdate(
              EpisodeStateRecordsCompanion.insert(
                episodeStateId: episodeId,
                localId: localId,
                seasonNumber: episodeCheckpoint.season,
                episodeNumber: episodeCheckpoint.episode,
                positionSeconds: Value<int>(
                  episodeCheckpoint.positionSeconds.clamp(0, 0x7fffffff),
                ),
                durationSeconds: Value<int?>(episodeCheckpoint.durationSeconds),
                completed: Value<bool>(episodeCheckpoint.completed),
                watchCycle: Value<int>(episodeCheckpoint.watchCycle),
                updatedAtMs: occurredAt.toUtc().millisecondsSinceEpoch,
              ),
            );
      }
      final bool completedEpisodeNow =
          episodeCheckpoint?.completed == true &&
          previousEpisode?.completed != true;
      if (effectiveFields.isEmpty &&
          !addsMembership &&
          !patch.delete &&
          episodeCheckpoint == null) {
        return;
      }
      await _appendOperationLocked(
        LibraryOperationDraft(
          operationId: operationId,
          localId: localId,
          originKind: originKind,
          originId: originId,
          intent: completedEpisodeNow
              ? LibraryMutationIntent.episodeCompleted
              : addsMembership
              ? LibraryMutationIntent.add
              : patch.delete
              ? LibraryMutationIntent.remove
              : patch.touches(UserMediaField.progress)
              ? LibraryMutationIntent.progress
              : LibraryMutationIntent.edit,
          fields: <String>{
            ...effectiveFields.map((UserMediaField field) => field.name),
            if (episodeCheckpoint != null) 'episodeProgress',
            if (addsMembership) 'membership',
            if (patch.delete) 'membership',
          },
          before: <String, dynamic>{
            if (canonicalBefore != null) 'state': canonicalBefore.toJson(),
            if (patch.touches(UserMediaField.favorite))
              'favorite': beforeFavorite,
            if (previousEpisode != null)
              'episode': <String, dynamic>{
                'season': previousEpisode.seasonNumber,
                'episode': previousEpisode.episodeNumber,
                'positionSeconds': previousEpisode.positionSeconds,
                'durationSeconds': previousEpisode.durationSeconds,
                'completed': previousEpisode.completed,
                'watchCycle': previousEpisode.watchCycle,
              },
          },
          after: <String, dynamic>{
            if (canonicalAfter != null) 'state': canonicalAfter.toJson(),
            if (patch.touches(UserMediaField.favorite))
              'favorite': afterFavorite,
            if (episodeCheckpoint != null)
              'episode': <String, dynamic>{
                'season': episodeCheckpoint.season,
                'episode': episodeCheckpoint.episode,
                'positionSeconds': episodeCheckpoint.positionSeconds,
                'durationSeconds': episodeCheckpoint.durationSeconds,
                'completed': episodeCheckpoint.completed,
                'watchCycle': episodeCheckpoint.watchCycle,
              },
          },
          targets:
              (effectiveFields.isEmpty && !addsMembership && !patch.delete
                      ? <TrackerSource>{}
                      : targets)
                  .map((TrackerSource source) => source.name)
                  .toSet(),
          occurredAt: occurredAt,
          title:
              mediaTitle ?? after?.mediaItem.title ?? before?.mediaItem.title,
          targetAccountIds: <String, String>{
            for (final SyncJournalEntry entry in journal)
              if (entry.operationId == operationId)
                for (final MapEntry<TrackerSource, String> account
                    in entry.targetAccountIds.entries)
                  account.key.name: account.value,
          },
        ),
      );
    });
  }

  Future<String> appendOperation(LibraryOperationDraft draft) async {
    await initialize();
    return database.transaction(() => _appendOperationLocked(draft));
  }

  /// Emits only when the amount of unsent local Drive work changes.
  ///
  /// This is the event source for lightweight, debounced cloud pushes. It does
  /// not poll SQLite or Google Drive, and confirmed deliveries disappear from
  /// the stream so a successful upload cannot schedule itself again.
  Stream<int> watchPendingDriveDeliveryCount() {
    return Stream<void>.fromFuture(initialize())
        .asyncExpand((_) {
          final SimpleSelectStatement<
            $OutboxDeliveryRecordsTable,
            OutboxDeliveryRecord
          >
          query = database.select(database.outboxDeliveryRecords)
            ..where(
              (OutboxDeliveryRecords table) =>
                  table.target.equals('drive') &
                  table.state.isIn(const <String>['pending', 'retry']),
            );
          return query.watch();
        })
        .map((List<OutboxDeliveryRecord> rows) => rows.length)
        .distinct();
  }

  Future<int> pendingDriveDeliveryCount() async {
    await initialize();
    final Expression<int> count = database.outboxDeliveryRecords.deliveryId
        .count();
    final TypedResult row =
        await (database.selectOnly(database.outboxDeliveryRecords)
              ..addColumns(<Expression<Object>>[count])
              ..where(
                database.outboxDeliveryRecords.target.equals('drive') &
                    database.outboxDeliveryRecords.state.isIn(const <String>[
                      'pending',
                      'retry',
                    ]),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<DriveReplicaSegment?> buildPendingDriveSegment({
    int limit = 200,
  }) async {
    await initialize();
    // Delivery IDs are not a chronological queue (legacy IDs in particular
    // are not UUIDv7). Preserve delete→add and conflict-resolution order even
    // when a backlog spans several Drive segments.
    final List<QueryRow> orderedIds = await database
        .customSelect(
          'SELECT d.delivery_id FROM outbox_delivery_records AS d '
          'JOIN library_operation_records AS o ON o.operation_id = d.operation_id '
          "WHERE d.target = 'drive' AND d.state IN ('pending', 'retry') "
          'ORDER BY o.occurred_at_ms ASC, o.operation_id ASC LIMIT ?',
          variables: <Variable<int>>[Variable<int>(limit)],
          readsFrom: <ResultSetImplementation>{
            database.outboxDeliveryRecords,
            database.libraryOperationRecords,
          },
        )
        .get();
    final List<String> deliveryIds = orderedIds
        .map((QueryRow row) => row.read<String>('delivery_id'))
        .toList(growable: false);
    if (deliveryIds.isEmpty) return null;
    final List<OutboxDeliveryRecord> pending = deliveryIds.isEmpty
        ? const <OutboxDeliveryRecord>[]
        : await (database.select(database.outboxDeliveryRecords)..where(
                (OutboxDeliveryRecords table) =>
                    table.deliveryId.isIn(deliveryIds),
              ))
              .get();
    final Map<String, int> order = <String, int>{
      for (var index = 0; index < deliveryIds.length; index += 1)
        deliveryIds[index]: index,
    };
    pending.sort(
      (OutboxDeliveryRecord a, OutboxDeliveryRecord b) =>
          (order[a.deliveryId] ?? 0).compareTo(order[b.deliveryId] ?? 0),
    );
    if (pending.isEmpty) return null;
    final List<LibraryOperationRecord> operations = <LibraryOperationRecord>[];
    final Set<String> localIds = <String>{};
    for (final OutboxDeliveryRecord delivery in pending) {
      final LibraryOperationRecord? operation =
          await (database.select(database.libraryOperationRecords)..where(
                (LibraryOperationRecords table) =>
                    table.operationId.equals(delivery.operationId),
              ))
              .getSingleOrNull();
      if (operation == null) continue;
      operations.add(operation);
      localIds.add(operation.localId);
    }
    if (operations.isEmpty) return null;
    final List<CanonicalMediaRecord> media =
        await (database.select(database.canonicalMediaRecords)..where(
              (CanonicalMediaRecords table) => table.localId.isIn(localIds),
            ))
            .get();
    final List<CanonicalLibraryRecord> library =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) => table.localId.isIn(localIds),
            ))
            .get();
    final List<EpisodeStateRecord> episodes =
        await (database.select(database.episodeStateRecords)..where(
              (EpisodeStateRecords table) => table.localId.isIn(localIds),
            ))
            .get();
    final List<StreamPreferenceRecord> streams =
        await (database.select(database.streamPreferenceRecords)..where(
              (StreamPreferenceRecords table) => table.localId.isIn(localIds),
            ))
            .get();
    return DriveReplicaSegment(
      segmentId: _uuid.v7(),
      deviceId: await deviceId(),
      createdAt: DateTime.now().toUtc(),
      operations: operations.map(_operationRowJson).toList(growable: false),
      media: media.map(_mediaRowJson).toList(growable: false),
      libraryEntries: library.map(_libraryRowJson).toList(growable: false),
      episodeStates: episodes.map(_episodeRowJson).toList(growable: false),
      streamPreferences: streams
          .map(_streamReplicaRowJson)
          .toList(growable: false),
      replicaNamespace: replicaNamespace,
    );
  }

  Future<DriveLibrarySnapshot> buildDriveSnapshot() async {
    await initialize();
    final List<CanonicalLibraryRecord> library = await database
        .select(database.canonicalLibraryRecords)
        .get();
    final Set<String> localIds = library
        .map((CanonicalLibraryRecord row) => row.localId)
        .toSet();
    final List<CanonicalMediaRecord> media = localIds.isEmpty
        ? const <CanonicalMediaRecord>[]
        : await (database.select(database.canonicalMediaRecords)..where(
                (CanonicalMediaRecords table) => table.localId.isIn(localIds),
              ))
              .get();
    final List<ProviderBindingRecord> bindings = localIds.isEmpty
        ? const <ProviderBindingRecord>[]
        : await (database.select(database.providerBindingRecords)..where(
                (ProviderBindingRecords table) => table.localId.isIn(localIds),
              ))
              .get();
    final List<ProviderSnapshotRecord> providerSnapshots = localIds.isEmpty
        ? const <ProviderSnapshotRecord>[]
        : await (database.select(database.providerSnapshotRecords)..where(
                (ProviderSnapshotRecords table) => table.localId.isIn(localIds),
              ))
              .get();
    final List<EpisodeStateRecord> episodes = localIds.isEmpty
        ? const <EpisodeStateRecord>[]
        : await (database.select(database.episodeStateRecords)..where(
                (EpisodeStateRecords table) => table.localId.isIn(localIds),
              ))
              .get();
    final List<StreamPreferenceRecord> streams = localIds.isEmpty
        ? const <StreamPreferenceRecord>[]
        : await (database.select(database.streamPreferenceRecords)..where(
                (StreamPreferenceRecords table) => table.localId.isIn(localIds),
              ))
              .get();
    final List<LibraryOperationRecord> operations = localIds.isEmpty
        ? const <LibraryOperationRecord>[]
        : await (database.select(database.libraryOperationRecords)..where(
                (LibraryOperationRecords table) => table.localId.isIn(localIds),
              ))
              .get();
    return compute(
      _buildDriveSnapshotFromRows,
      _DriveSnapshotRows(
        snapshotId: _uuid.v7(),
        deviceId: await deviceId(),
        createdAt: DateTime.now().toUtc(),
        replicaNamespace: replicaNamespace,
        media: media,
        library: library,
        bindings: bindings,
        providerSnapshots: providerSnapshots,
        episodes: episodes,
        streams: streams,
        operations: operations,
      ),
      debugLabel: 'MiruShin Drive snapshot rows',
    );
  }

  /// Number of immutable local segments already confirmed by Drive. A full
  /// backup can be deferred while these segments remain sufficient for a new
  /// device to replay the latest user actions.
  Future<int> pushedDriveSegmentCount() async {
    await initialize();
    final count = database.syncCursorRecords.scope.count();
    final row =
        await (database.selectOnly(database.syncCursorRecords)
              ..addColumns(<Expression<Object>>[count])
              ..where(database.syncCursorRecords.scope.like('drive.pushed:%')))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> activeLibraryEntryCount() async {
    await initialize();
    final count = database.canonicalLibraryRecords.localId.count();
    final row =
        await (database.selectOnly(database.canonicalLibraryRecords)
              ..addColumns(<Expression<Object>>[count])
              ..where(database.canonicalLibraryRecords.inLibrary.equals(true)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> checkpointedDriveSegmentCount() async {
    await initialize();
    final SyncCursorRecord? row =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) =>
                  table.scope.equals('drive.snapshot.pushedSegmentCount.v1'),
            ))
            .getSingleOrNull();
    return int.tryParse(row?.cursor ?? '') ?? 0;
  }

  /// Record only the count captured before building the published snapshot.
  /// A segment uploaded concurrently remains above this watermark and will
  /// cause another checkpoint on a later full sync.
  Future<void> markDriveSnapshotPublished(int pushedSegmentCount) async {
    await initialize();
    await database
        .into(database.syncCursorRecords)
        .insertOnConflictUpdate(
          SyncCursorRecordsCompanion.insert(
            scope: 'drive.snapshot.pushedSegmentCount.v1',
            cursor: '$pushedSegmentCount',
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<String?> appliedDriveSnapshotChecksum() async {
    await initialize();
    final SyncCursorRecord? cursor =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) => table.scope.equals(
                'drive.snapshot.reconciled.v2:$replicaNamespace',
              ),
            ))
            .getSingleOrNull();
    return cursor?.cursor;
  }

  Future<bool> hasAppliedDriveSnapshot(String checksum) async =>
      await appliedDriveSnapshotChecksum() == checksum;

  /// Atomically merges a complete Drive checkpoint into the current
  /// workspace. A fresh device must end with exactly the advertised number of
  /// active entries or the whole transaction is rolled back.
  Future<DriveSnapshotApplyResult> applyDriveSnapshot(
    DriveLibrarySnapshot snapshot, {
    void Function(int completed, int total)? onProgress,
    Set<TrackerSource> trackerTargets = const <TrackerSource>{},
  }) async {
    await initialize();
    if (snapshot.replicaNamespace != replicaNamespace &&
        !(importsLegacyData && snapshot.replicaNamespace == 'legacy')) {
      throw StateError(
        'Drive library workspace mismatch: '
        '${snapshot.replicaNamespace} != $replicaNamespace',
      );
    }
    final DriveSnapshotApplyResult
    baseResult = await database.transaction(() async {
      final int beforeCount =
          await (database.selectOnly(database.canonicalLibraryRecords)
                ..addColumns(<Expression<Object>>[
                  database.canonicalLibraryRecords.localId.count(),
                ])
                ..where(
                  database.canonicalLibraryRecords.inLibrary.equals(true),
                ))
              .map(
                (TypedResult row) =>
                    row.read(
                      database.canonicalLibraryRecords.localId.count(),
                    ) ??
                    0,
              )
              .getSingle();
      final bool freshBootstrap = beforeCount == 0;
      final Map<String, String> translatedIds = <String, String>{};
      // Progress is expressed in actual canonical titles. Media and entry rows
      // are two halves of the same title and must not make a 375-title restore
      // look like 750 separate uploads/downloads in the UI.
      final int total = snapshot.libraryEntries.length;
      int completed = 0;

      for (final Map<String, dynamic> row in snapshot.media) {
        final String remoteLocalId = '${row['localId'] ?? ''}';
        final Object? rawMedia = row['media'];
        if (remoteLocalId.isEmpty || rawMedia is! Map) continue;
        final MediaItem media = MediaItem.fromJson(
          Map<String, dynamic>.from(rawMedia),
        );
        final MediaIdentity parsed = MediaIdentity.fromExternalIds(
          media.externalIds,
          mediaId: media.id,
        );
        translatedIds[remoteLocalId] = await _resolveOrCreateMediaLocked(
          identity: MediaIdentity(
            localId: remoteLocalId,
            kind: '${row['mediaKind'] ?? ''}' == 'manga' ? 'manga' : null,
            anilistId: parsed.anilistId,
            malId: parsed.malId,
            shikimoriId: parsed.shikimoriId,
          ),
          mediaItem: media,
        );
      }

      int restored = 0;
      final Set<String> activeIds = (await _readBucketLocked(
        'tracking.stateIds',
      )).whereType<String>().toSet();
      final Set<String> restoredRemoteIds = <String>{};
      for (final Map<String, dynamic> row in snapshot.libraryEntries) {
        final String remoteLocalId = '${row['localId'] ?? ''}';
        final Object? rawState = row['state'];
        if (remoteLocalId.isEmpty || rawState is! Map) continue;
        final UserMediaState remote = UserMediaState.fromJson(
          Map<String, dynamic>.from(rawState),
        );
        final String localId = translatedIds[remoteLocalId] ??=
            await _resolveOrCreateMediaLocked(
              identity: remote.identity,
              mediaItem: remote.mediaItem,
            );
        final CanonicalLibraryRecord? existing =
            await (database.select(database.canonicalLibraryRecords)..where(
                  (CanonicalLibraryRecords table) =>
                      table.localId.equals(localId),
                ))
                .getSingleOrNull();
        final int remoteUpdated =
            (row['updatedAtMs'] as num?)?.toInt() ??
            remote.updatedAt.toUtc().millisecondsSinceEpoch;
        // A checkpoint is authoritative for missing rows, not a second merge
        // protocol. Existing rows continue to merge through immutable
        // operations and field revisions below, so a newer whole-record
        // timestamp can never erase an unrelated local field change.
        if (existing == null) {
          final MediaIdentity translated = MediaIdentity(
            localId: localId,
            kind: remote.identity.mediaKind,
            anilistId: remote.identity.anilistId,
            malId: remote.identity.malId,
            shikimoriId: remote.identity.shikimoriId,
          );
          await _upsertTrackingStateLocked(remote.withIdentity(translated));
          bool? restoredFavorite = row['favorite'] as bool?;
          if (restoredFavorite == null) {
            // Compatibility with checkpoints written before favorite was
            // serialized: recover it from the immutable operation history.
            final history =
                snapshot.operations
                    .where(
                      (op) =>
                          op['localId'] == remoteLocalId &&
                          _jsonMap(op['after']).containsKey('favorite'),
                    )
                    .toList()
                  ..sort(
                    (a, b) =>
                        '${a['occurredAt']}'.compareTo('${b['occurredAt']}'),
                  );
            if (history.isNotEmpty) {
              restoredFavorite =
                  _jsonMap(history.last['after'])['favorite'] as bool?;
            }
          }
          if (restoredFavorite != null) {
            await _setFavoriteLocked(
              localId: localId,
              identity: translated,
              favorite: restoredFavorite,
              at: DateTime.fromMillisecondsSinceEpoch(
                remoteUpdated,
                isUtc: true,
              ),
              mediaItem: remote.mediaItem,
            );
          }
          await (database.update(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(localId),
              ))
              .write(
                CanonicalLibraryRecordsCompanion(
                  inLibrary: Value<bool>(row['inLibrary'] == true),
                  fieldRevisionsJson: Value<String>(
                    jsonEncode(_jsonMap(row['fieldRevisions'])),
                  ),
                  updatedAtMs: Value<int>(remoteUpdated),
                  tombstonedAtMs: Value<int?>(
                    (row['tombstonedAtMs'] as num?)?.toInt(),
                  ),
                ),
              );
          restored += 1;
          restoredRemoteIds.add(remoteLocalId);
          if (row['inLibrary'] == true) {
            activeIds.add(localId);
          } else {
            activeIds.remove(localId);
          }
        }
        completed += 1;
        onProgress?.call(completed, total);
      }
      await _writeBucketLocked('tracking.stateIds', activeIds.toList()..sort());

      for (final Map<String, dynamic> row in snapshot.providerBindings) {
        final String? localId = translatedIds['${row['localId'] ?? ''}'];
        final int externalId = (row['externalMediaId'] as num?)?.toInt() ?? 0;
        if (localId == null || externalId <= 0) continue;
        await _upsertBindingLocked(
          localId: localId,
          provider: '${row['provider'] ?? ''}',
          mediaKind: '${row['mediaKind'] ?? 'anime'}',
          externalMediaId: externalId,
          providerEntryId: (row['providerEntryId'] as num?)?.toInt(),
          evidence: '${row['evidence'] ?? 'drive_snapshot'}',
          verifiedAtMs: (row['verifiedAtMs'] as num?)?.toInt(),
          quarantined: row['quarantined'] == true,
        );
      }
      for (final Map<String, dynamic> row in snapshot.providerSnapshots) {
        final String? localId = translatedIds['${row['localId'] ?? ''}'];
        if (localId == null) continue;
        final String provider = '${row['provider'] ?? ''}';
        final String accountId = '${row['accountId'] ?? 'active'}';
        if (provider.isEmpty) continue;
        final String snapshotId = '$provider:$accountId:$localId';
        final int fetchedAtMs =
            (row['fetchedAtMs'] as num?)?.toInt() ??
            snapshot.createdAt.millisecondsSinceEpoch;
        final ProviderSnapshotRecord? existingSnapshot =
            await (database.select(database.providerSnapshotRecords)..where(
                  (ProviderSnapshotRecords table) =>
                      table.snapshotId.equals(snapshotId),
                ))
                .getSingleOrNull();
        if (existingSnapshot != null &&
            existingSnapshot.fetchedAtMs >= fetchedAtMs) {
          continue;
        }
        await database
            .into(database.providerSnapshotRecords)
            .insertOnConflictUpdate(
              ProviderSnapshotRecordsCompanion.insert(
                snapshotId: snapshotId,
                localId: localId,
                provider: provider,
                accountId: accountId,
                providerEntryId: Value<int?>(
                  (row['providerEntryId'] as num?)?.toInt(),
                ),
                normalizedJson: jsonEncode(
                  row['normalized'] ?? const <String, dynamic>{},
                ),
                rawJson: jsonEncode(row['raw'] ?? const <String, dynamic>{}),
                contentHash: '${row['contentHash'] ?? ''}',
                fetchedAtMs: fetchedAtMs,
                completeSnapshot: row['completeSnapshot'] == true,
                destructiveConfirmationCount: Value<int>(
                  (row['destructiveConfirmationCount'] as num?)?.toInt() ?? 0,
                ),
              ),
            );
      }

      final DriveReplicaSegment rows = DriveReplicaSegment(
        segmentId: snapshot.snapshotId,
        deviceId: snapshot.deviceId,
        createdAt: snapshot.createdAt,
        operations: const <Map<String, dynamic>>[],
        media: snapshot.media,
        libraryEntries: snapshot.libraryEntries,
        episodeStates: snapshot.episodeStates,
        streamPreferences: snapshot.streamPreferences,
        replicaNamespace: snapshot.replicaNamespace,
      );
      await _importDriveEpisodeRows(rows, translatedIds, snapshot.createdAt);
      await _importDriveStreamRows(rows, translatedIds, snapshot.createdAt);
      await _importSnapshotOperations(
        snapshot.operations.where(
          (Map<String, dynamic> row) =>
              restoredRemoteIds.contains('${row['localId'] ?? ''}'),
        ),
        translatedIds,
      );

      final int localCount =
          await (database.selectOnly(database.canonicalLibraryRecords)
                ..addColumns(<Expression<Object>>[
                  database.canonicalLibraryRecords.localId.count(),
                ])
                ..where(
                  database.canonicalLibraryRecords.inLibrary.equals(true),
                ))
              .map(
                (TypedResult row) =>
                    row.read(
                      database.canonicalLibraryRecords.localId.count(),
                    ) ??
                    0,
              )
              .getSingle();
      if (freshBootstrap && localCount != snapshot.entryCount) {
        throw StateError(
          'Drive snapshot restore count mismatch: '
          '$localCount != ${snapshot.entryCount}',
        );
      }
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: 'drive.snapshot:${snapshot.replicaNamespace}',
              cursor: snapshot.checksum,
              metadataJson: Value<String>(
                jsonEncode(<String, dynamic>{
                  'snapshotId': snapshot.snapshotId,
                  'entryCount': snapshot.entryCount,
                  'localEntryCount': localCount,
                }),
              ),
              updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
      return DriveSnapshotApplyResult(
        cloudEntryCount: snapshot.entryCount,
        localEntryCount: localCount,
        restoredEntries: restored,
        recoveredOperations: 0,
        freshBootstrap: freshBootstrap,
      );
    });

    // A checkpoint is also the durable repair path when an older client
    // missed (or incorrectly skipped) one of the immutable segment files.
    // Replay only operation IDs absent locally and let applyDriveSegment's
    // per-field causal revision checks decide what is safe. This never turns
    // the checkpoint into a whole-record latest-wins overwrite.
    final List<Map<String, dynamic>> orderedOperations =
        snapshot.operations.toList(growable: false)
          ..sort((Map<String, dynamic> left, Map<String, dynamic> right) {
            final DateTime leftAt =
                DateTime.tryParse('${left['occurredAt'] ?? ''}') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
            final DateTime rightAt =
                DateTime.tryParse('${right['occurredAt'] ?? ''}') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
            final int occurred = leftAt.compareTo(rightAt);
            if (occurred != 0) return occurred;
            return '${left['operationId'] ?? ''}'.compareTo(
              '${right['operationId'] ?? ''}',
            );
          });
    final int recovered = await applyDriveSegment(
      DriveReplicaSegment(
        segmentId: 'snapshot-recovery-v2-${snapshot.checksum}',
        deviceId: snapshot.deviceId,
        createdAt: snapshot.createdAt,
        operations: orderedOperations,
        media: snapshot.media,
        libraryEntries: snapshot.libraryEntries,
        episodeStates: snapshot.episodeStates,
        streamPreferences: snapshot.streamPreferences,
        replicaNamespace: snapshot.replicaNamespace,
      ),
      trackerTargets: trackerTargets,
    );
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database
        .into(database.syncCursorRecords)
        .insertOnConflictUpdate(
          SyncCursorRecordsCompanion.insert(
            scope: 'drive.snapshot.reconciled.v2:${snapshot.replicaNamespace}',
            cursor: snapshot.checksum,
            metadataJson: Value<String>(
              jsonEncode(<String, dynamic>{
                'snapshotId': snapshot.snapshotId,
                'entryCount': snapshot.entryCount,
                'recoveredOperations': recovered,
              }),
            ),
            updatedAtMs: now,
          ),
        );
    final Expression<int> activeCount = database.canonicalLibraryRecords.localId
        .count();
    final TypedResult countRow =
        await (database.selectOnly(database.canonicalLibraryRecords)
              ..addColumns(<Expression<Object>>[activeCount])
              ..where(database.canonicalLibraryRecords.inLibrary.equals(true)))
            .getSingle();
    final int reconciledLocalCount = countRow.read(activeCount) ?? 0;
    return DriveSnapshotApplyResult(
      cloudEntryCount: baseResult.cloudEntryCount,
      localEntryCount: reconciledLocalCount,
      restoredEntries: baseResult.restoredEntries,
      recoveredOperations: recovered,
      freshBootstrap: baseResult.freshBootstrap,
    );
  }

  Future<void> _importSnapshotOperations(
    Iterable<Map<String, dynamic>> operations,
    Map<String, String> translatedIds,
  ) async {
    for (final Map<String, dynamic> row in operations) {
      final String operationId = '${row['operationId'] ?? ''}';
      final String? localId = translatedIds['${row['localId'] ?? ''}'];
      if (operationId.isEmpty || localId == null) continue;
      final LibraryOperationRecord? existing =
          await (database.select(database.libraryOperationRecords)..where(
                (LibraryOperationRecords table) =>
                    table.operationId.equals(operationId),
              ))
              .getSingleOrNull();
      if (existing != null) continue;
      await database
          .into(database.libraryOperationRecords)
          .insert(
            LibraryOperationRecordsCompanion.insert(
              operationId: operationId,
              localId: localId,
              deviceId: '${row['deviceId'] ?? ''}',
              originKind:
                  '${row['originKind'] ?? LibraryOriginKind.drive.name}',
              originId: Value<String?>(row['originId']?.toString()),
              intent: '${row['intent'] ?? LibraryMutationIntent.edit.name}',
              fieldsJson: jsonEncode(row['fields'] ?? const <String>[]),
              beforeJson: jsonEncode(
                row['before'] ?? const <String, dynamic>{},
              ),
              afterJson: jsonEncode(row['after'] ?? const <String, dynamic>{}),
              baseRevisionsJson: jsonEncode(
                row['baseRevisions'] ?? const <String, dynamic>{},
              ),
              resultingRevisionsJson: jsonEncode(
                row['resultingRevisions'] ?? const <String, dynamic>{},
              ),
              targetsJson: jsonEncode(row['targets'] ?? const <String>[]),
              undoOf: Value<String?>(row['undoOf']?.toString()),
              title: Value<String?>(row['title']?.toString()),
              visibleInLog: Value<bool>(row['visibleInLog'] != false),
              occurredAtMs:
                  DateTime.tryParse(
                    '${row['occurredAt'] ?? ''}',
                  )?.millisecondsSinceEpoch ??
                  DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          );
    }
  }

  Future<void> markDriveSegmentDelivered(
    DriveReplicaSegment segment, {
    required String remoteFileId,
  }) async {
    await initialize();
    await database.transaction(() async {
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final Set<String> operationIds = segment.operations
          .map((Map<String, dynamic> value) => '${value['operationId'] ?? ''}')
          .where((String value) => value.isNotEmpty)
          .toSet();
      if (operationIds.isNotEmpty) {
        await (database.update(database.outboxDeliveryRecords)..where(
              (OutboxDeliveryRecords table) =>
                  table.target.equals('drive') &
                  table.operationId.isIn(operationIds),
            ))
            .write(
              OutboxDeliveryRecordsCompanion(
                state: const Value<String>('confirmed'),
                deliveredAtMs: Value<int>(now),
                confirmedAtMs: Value<int>(now),
                lastError: const Value<String?>(null),
              ),
            );
      }
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: 'drive.pushed:${segment.fileName}',
              cursor: remoteFileId,
              metadataJson: Value<String>(
                jsonEncode(<String, dynamic>{'checksum': segment.checksum}),
              ),
              updatedAtMs: now,
            ),
          );
    });
  }

  Future<Set<String>> processedDriveSegmentNames() async {
    await initialize();
    final List<SyncCursorRecord> rows =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) =>
                  table.scope.like('drive.pulled:%') |
                  table.scope.like('drive.pushed:%'),
            ))
            .get();
    return rows
        .map((SyncCursorRecord row) => row.scope.split(':').skip(1).join(':'))
        .where((String value) => value.isNotEmpty)
        .toSet();
  }

  Future<String?> driveChangePageToken() async {
    await initialize();
    final SyncCursorRecord? row =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) =>
                  table.scope.equals('drive.changes.pageToken'),
            ))
            .getSingleOrNull();
    return row?.cursor;
  }

  Future<void> saveDriveChangePageToken(String token) async {
    await initialize();
    await database
        .into(database.syncCursorRecords)
        .insertOnConflictUpdate(
          SyncCursorRecordsCompanion.insert(
            scope: 'drive.changes.pageToken',
            cursor: token,
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<int> applyDriveSegment(
    DriveReplicaSegment segment, {
    required Set<TrackerSource> trackerTargets,
  }) async {
    await initialize();
    if (segment.replicaNamespace != replicaNamespace &&
        !(importsLegacyData && segment.replicaNamespace == 'legacy')) {
      throw StateError(
        'Drive library workspace mismatch: '
        '${segment.replicaNamespace} != $replicaNamespace',
      );
    }
    return database.transaction(() async {
      final SyncCursorRecord? processed =
          await (database.select(database.syncCursorRecords)..where(
                (SyncCursorRecords table) =>
                    table.scope.equals('drive.pulled:${segment.fileName}'),
              ))
              .getSingleOrNull();
      if (processed != null) return 0;
      final DateTime importedAt = DateTime.now().toUtc();
      int applied = 0;
      List<SyncJournalEntry> journal = await loadJournal();
      final Map<String, Map<String, dynamic>> mediaByRemoteId =
          <String, Map<String, dynamic>>{
            for (final Map<String, dynamic> value in segment.media)
              '${value['localId'] ?? ''}': value,
          };
      final Map<String, String> translatedIds = <String, String>{};

      final handledEpisodes = <String>{};
      final knownOperations = await _readRevisionGraphLocked();
      for (final Map<String, dynamic> remoteOperation in segment.operations) {
        final String operationId = '${remoteOperation['operationId'] ?? ''}';
        final String remoteLocalId = '${remoteOperation['localId'] ?? ''}';
        if (operationId.isEmpty || remoteLocalId.isEmpty) continue;
        final LibraryOperationRecord? duplicate =
            await (database.select(database.libraryOperationRecords)..where(
                  (LibraryOperationRecords table) =>
                      table.operationId.equals(operationId),
                ))
                .getSingleOrNull();
        if (duplicate != null) {
          translatedIds[remoteLocalId] = duplicate.localId;
          final episodeKey = _episodeRevisionKey(
            _jsonMap(duplicate.afterJson)['episode'],
          );
          if (episodeKey != null) {
            handledEpisodes.add('${duplicate.localId}:$episodeKey');
          }
          continue;
        }

        final Map<String, dynamic> mediaRow =
            mediaByRemoteId[remoteLocalId] ?? const <String, dynamic>{};
        final Map<String, dynamic> after = _jsonMap(remoteOperation['after']);
        final Map<String, dynamic> before = _jsonMap(remoteOperation['before']);
        final Object? rawAfterState = after['state'];
        final Object? rawBeforeState = before['state'];
        final UserMediaState? incomingAfter = rawAfterState is Map
            ? UserMediaState.fromJson(Map<String, dynamic>.from(rawAfterState))
            : null;
        final UserMediaState? incomingBefore = rawBeforeState is Map
            ? UserMediaState.fromJson(Map<String, dynamic>.from(rawBeforeState))
            : null;
        final DateTime operationAt =
            DateTime.tryParse(
              '${remoteOperation['occurredAt'] ?? ''}',
            )?.toUtc() ??
            incomingAfter?.updatedAt.toUtc() ??
            segment.createdAt.toUtc();
        final MediaItem mediaItem =
            incomingAfter?.mediaItem ??
            incomingBefore?.mediaItem ??
            (mediaRow['media'] is Map
                ? MediaItem.fromJson(
                    Map<String, dynamic>.from(mediaRow['media'] as Map),
                  )
                : _placeholderMedia(
                    MediaIdentity(
                      localId: remoteLocalId,
                      kind: '${mediaRow['mediaKind'] ?? ''}' == 'manga'
                          ? 'manga'
                          : null,
                    ),
                    mediaId: remoteLocalId,
                  ));
        final mediaIdentity = MediaIdentity.fromExternalIds(
          mediaItem.externalIds,
          mediaId: mediaItem.id,
        );
        final MediaIdentity incomingIdentity =
            incomingAfter?.identity ??
            incomingBefore?.identity ??
            MediaIdentity(
              localId: remoteLocalId,
              kind: mediaIdentity.mediaKind,
              anilistId: mediaIdentity.anilistId,
              malId: mediaIdentity.malId,
              shikimoriId: mediaIdentity.shikimoriId,
            );
        final String localId = translatedIds[remoteLocalId] ??=
            await _resolveOrCreateMediaLocked(
              identity: incomingIdentity,
              mediaItem: mediaItem,
            );
        final CanonicalLibraryRecord? currentRow =
            await (database.select(database.canonicalLibraryRecords)..where(
                  (CanonicalLibraryRecords table) =>
                      table.localId.equals(localId),
                ))
                .getSingleOrNull();
        final UserMediaState? current = currentRow == null
            ? null
            : UserMediaState.fromJson(_jsonMap(currentRow.canonicalStateJson));
        final Set<String> fields = _dynamicStringSet(remoteOperation['fields']);
        final Map<String, dynamic> baseRevisions = _jsonMap(
          remoteOperation['baseRevisions'],
        );
        final Map<String, dynamic> resultingRevisions = _jsonMap(
          remoteOperation['resultingRevisions'],
        );
        final Map<String, dynamic> currentRevisions = _jsonMap(
          currentRow?.fieldRevisionsJson,
        );
        final Set<String> accepted = <String>{};
        final Set<String> equivalent = <String>{};
        final String? episodeRevisionKey = fields.contains('episodeProgress')
            ? _episodeRevisionKey(after['episode'])
            : null;
        EpisodeStateRecord? currentEpisode;
        if (fields.contains('episodeProgress') && after['episode'] is Map) {
          final checkpoint = _jsonMap(after['episode']);
          final season = (checkpoint['season'] as num?)?.toInt() ?? 1;
          final episode = (checkpoint['episode'] as num?)?.toDouble() ?? 1;
          final cycle = (checkpoint['watchCycle'] as num?)?.toInt() ?? 0;
          currentEpisode =
              await (database.select(database.episodeStateRecords)..where(
                    (table) =>
                        table.localId.equals(localId) &
                        table.seasonNumber.equals(season) &
                        table.episodeNumber.equals(episode) &
                        table.watchCycle.equals(cycle),
                  ))
                  .getSingleOrNull();
          handledEpisodes.add('$localId:${_episodeRevisionKey(checkpoint)}');
        }
        for (final String field in fields) {
          final currentRevision =
              field == 'episodeProgress' && episodeRevisionKey != null
              ? currentRevisions[episodeRevisionKey] ?? currentRevisions[field]
              : currentRevisions[field];
          final Object? currentValue = field == 'episodeProgress'
              ? (currentEpisode == null
                    ? null
                    : _episodeCheckpointValue({
                        'season': currentEpisode.seasonNumber,
                        'episode': currentEpisode.episodeNumber,
                        'watchCycle': currentEpisode.watchCycle,
                        'positionSeconds': currentEpisode.positionSeconds,
                        'durationSeconds': currentEpisode.durationSeconds,
                        'completed': currentEpisode.completed,
                      }))
              : _canonicalFieldValue(
                  field,
                  current,
                  membership: currentRow?.inLibrary ?? false,
                  favorite: currentRow?.favorite ?? false,
                );
          final Object? beforeValue = _operationFieldValue(
            field,
            before,
            parsedState: incomingBefore,
          );
          final Object? afterValue = _operationFieldValue(
            field,
            after,
            parsedState: incomingAfter,
          );
          // Do not replay an ancestor after a newer descendant has already
          // arrived via a checkpoint or another device's segment.
          if (_revisionDescendsFrom(
            currentRevision,
            operationId,
            field,
            knownOperations,
          )) {
            continue;
          }
          if (field != 'metadata' &&
              _jsonEquivalent(currentValue, afterValue)) {
            accepted.add(field);
            equivalent.add(field);
          } else if (_baseRevisionMatches(
                currentRevision,
                baseRevisions[field],
              ) ||
              _jsonEquivalent(currentRevision, resultingRevisions[field]) ||
              (field == 'episodeProgress' && currentEpisode == null) ||
              (field != 'metadata' &&
                  _jsonEquivalent(currentValue, beforeValue))) {
            accepted.add(field);
          } else if (_revisionEditTime(resultingRevisions[field]) > 0 &&
              _revisionEditTime(currentRevision) > 0 &&
              _revisionEditTime(resultingRevisions[field]) !=
                  _revisionEditTime(currentRevision)) {
            if (_revisionEditTime(resultingRevisions[field]) >
                _revisionEditTime(currentRevision)) {
              accepted.add(field);
            }
          } else if ('${remoteOperation['originKind']}' ==
                  LibraryOriginKind.provider.name &&
              _revisionOrigins(currentRevisions[field]).any(
                (origin) =>
                    origin == LibraryOriginKind.user.name ||
                    origin == LibraryOriginKind.undo.name,
              )) {
            // Independently fetched provider state has no causal evidence of
            // replacing an explicit local action. Its fetch time is not an
            // action timestamp and must not turn it into a winning edit.
            continue;
          } else {
            final existingConflict =
                await (database.select(database.libraryConflictRecords)..where(
                      (table) =>
                          table.localId.equals(localId) &
                          table.fieldName.equals(field) &
                          table.incomingOperationId.equals(operationId),
                    ))
                    .getSingleOrNull();
            if (existingConflict != null) continue;
            await database
                .into(database.libraryConflictRecords)
                .insert(
                  LibraryConflictRecordsCompanion.insert(
                    conflictId: _uuid.v7(),
                    localId: localId,
                    fieldName: field,
                    localValueJson: jsonEncode({
                      ...?current?.toJson(),
                      if (field == 'favorite')
                        'favorite': currentRow?.favorite ?? false,
                      if (field == 'episodeProgress' && currentEpisode != null)
                        'episode': _episodeRowCheckpoint(currentEpisode),
                    }),
                    incomingValueJson: jsonEncode(<String, dynamic>{
                      ...?incomingAfter?.toJson(),
                      if (incomingAfter == null && field == 'membership')
                        '__deleted': true,
                      if (field == 'favorite') 'favorite': after['favorite'],
                      if (field == 'episodeProgress')
                        'episode': after['episode'],
                      '__incomingRevision': resultingRevisions[field],
                    }),
                    localOperationId: Value<String?>(
                      _jsonMap(currentRevision)['operationId']?.toString(),
                    ),
                    incomingOperationId: Value<String?>(operationId),
                    createdAtMs: importedAt.millisecondsSinceEpoch,
                  ),
                );
          }
        }
        knownOperations[operationId] = remoteOperation;
        if (accepted.isEmpty) {
          await _recordReceivedDriveOperationLocked(
            remoteOperation,
            localId,
            segment.deviceId,
            operationAt,
            importedAt,
          );
          continue;
        }

        // A resolution operation may explicitly name both sides of a prior
        // conflict as causal parents. Once it applies, that old prompt is no
        // longer actionable on this device.
        for (final String field in accepted) {
          final Object? rawBase = baseRevisions[field];
          if (rawBase is! List) continue;
          final Set<String> parentIds = rawBase
              .whereType<Map>()
              .map(
                (Map<dynamic, dynamic> value) =>
                    value['operationId']?.toString(),
              )
              .whereType<String>()
              .toSet();
          if (parentIds.isEmpty) continue;
          await (database.update(database.libraryConflictRecords)..where(
                (LibraryConflictRecords table) =>
                    table.localId.equals(localId) &
                    table.fieldName.equals(field) &
                    table.state.equals('open') &
                    (table.localOperationId.isIn(parentIds) |
                        table.incomingOperationId.isIn(parentIds)),
              ))
              .write(
                LibraryConflictRecordsCompanion(
                  state: const Value<String>('resolved'),
                  resolvedAtMs: Value<int>(importedAt.millisecondsSinceEpoch),
                ),
              );
        }

        UserMediaState? next = current;
        final bool removesMembership =
            accepted.contains('membership') && incomingAfter == null;
        if (removesMembership) {
          if (currentRow == null) {
            // Keep a revisioned tombstone even if deletion arrives before
            // the original add segment. A late add must not resurrect it.
            final identity = MediaIdentity(
              localId: localId,
              kind: incomingIdentity.mediaKind,
              anilistId: incomingIdentity.anilistId,
              malId: incomingIdentity.malId,
              shikimoriId: incomingIdentity.shikimoriId,
            );
            await _upsertTrackingStateLocked(
              incomingBefore?.withIdentity(identity) ??
                  UserMediaState(
                    identity: identity,
                    mediaItem: mediaItem,
                    status: AniListListStatus.planning,
                    progress: 0,
                    createdAt: operationAt,
                    updatedAt: operationAt,
                    source: TrackerSource.anilist,
                  ),
            );
          }
          await (database.update(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(localId),
              ))
              .write(
                CanonicalLibraryRecordsCompanion(
                  inLibrary: const Value<bool>(false),
                  tombstonedAtMs: Value<int>(
                    operationAt.millisecondsSinceEpoch,
                  ),
                  updatedAtMs: Value<int>(operationAt.millisecondsSinceEpoch),
                ),
              );
          next = null;
        } else if (incomingAfter != null) {
          final mergedIdentity =
              current?.identity.merge(incomingAfter.identity) ??
              incomingAfter.identity;
          final MediaIdentity translated = MediaIdentity(
            localId: localId,
            kind: mergedIdentity.mediaKind,
            anilistId: mergedIdentity.anilistId,
            malId: mergedIdentity.malId,
            shikimoriId: mergedIdentity.shikimoriId,
          );
          if (current == null) {
            next = incomingAfter.withIdentity(translated);
          } else {
            final Set<UserMediaField> acceptedFields = accepted
                .map(_fieldFromPersistedName)
                .whereType<UserMediaField>()
                .toSet();
            next = current.apply(
              _patchFromState(incomingAfter, acceptedFields),
              current.updatedAt.isAfter(operationAt)
                  ? current.updatedAt
                  : operationAt,
            );
            // Provider-specific editable fields were already patched above.
            // A full stale provider payload must not replace independent
            // priority/privacy/custom-list edits that were not accepted.
            next = next.withIdentity(translated);
          }
          await _upsertTrackingStateLocked(next);
          final bool legacyAdd =
              currentRow == null &&
              incomingBefore == null &&
              const {
                'add',
                'remoteImport',
                'migration',
              }.contains(remoteOperation['intent']);
          if (currentRow?.inLibrary != true &&
              !accepted.contains('membership') &&
              !legacyAdd) {
            await (database.update(
              database.canonicalLibraryRecords,
            )..where((table) => table.localId.equals(localId))).write(
              CanonicalLibraryRecordsCompanion(
                inLibrary: const Value(false),
                tombstonedAtMs: Value(currentRow?.tombstonedAtMs),
              ),
            );
          }
        }
        final Map<String, dynamic> nextRevisions = <String, dynamic>{
          ...currentRevisions,
        };
        for (final String field in accepted) {
          nextRevisions[field] = resultingRevisions[field];
          if (equivalent.contains(field)) {
            nextRevisions[field] = _mergeEquivalentRevisions(
              field == 'episodeProgress' && episodeRevisionKey != null
                  ? currentRevisions[episodeRevisionKey] ??
                        currentRevisions[field]
                  : currentRevisions[field],
              resultingRevisions[field],
            );
          }
        }
        if (accepted.contains('episodeProgress') &&
            episodeRevisionKey != null) {
          if (currentRow == null && next == null) {
            await _ensureHiddenTrackingRowLocked(
              localId,
              mediaItem,
              operationAt,
            );
          }
          nextRevisions[episodeRevisionKey] = nextRevisions['episodeProgress'];
          await _writeReceivedEpisodeCheckpointLocked(
            localId,
            _jsonMap(after['episode']),
            operationAt,
            currentEpisode,
          );
        }
        if (accepted.contains('favorite') && after['favorite'] is bool) {
          await _setFavoriteLocked(
            localId: localId,
            identity: MediaIdentity(
              localId: localId,
              kind: incomingIdentity.mediaKind,
              anilistId: incomingIdentity.anilistId,
              malId: incomingIdentity.malId,
              shikimoriId: incomingIdentity.shikimoriId,
            ),
            favorite: after['favorite'] as bool,
            at: operationAt,
            mediaItem: mediaItem,
          );
        }
        await (database.update(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) => table.localId.equals(localId),
            ))
            .write(
              CanonicalLibraryRecordsCompanion(
                fieldRevisionsJson: Value<String>(jsonEncode(nextRevisions)),
              ),
            );

        final String originKind =
            '${remoteOperation['originKind'] ?? LibraryOriginKind.drive.name}';
        final String? originId = remoteOperation['originId']?.toString();
        final Set<TrackerSource> outboundTargets = <TrackerSource>{
          ...trackerTargets,
        };
        if (originKind == LibraryOriginKind.provider.name && originId != null) {
          final String providerName = originId.split(':').first;
          outboundTargets.removeWhere(
            (TrackerSource target) => target.name == providerName,
          );
        }
        final Set<UserMediaField> acceptedMediaFields = accepted
            .map(_fieldFromPersistedName)
            .whereType<UserMediaField>()
            .toSet();
        UserMediaPatch outboundPatch = removesMembership
            ? UserMediaPatch(delete: true)
            : incomingAfter == null
            ? UserMediaPatch(fields: acceptedMediaFields)
            : _patchFromState(incomingAfter, acceptedMediaFields).mergedWith(
                accepted.contains('favorite') && after['favorite'] is bool
                    ? UserMediaPatch(favorite: after['favorite'] as bool)
                    : UserMediaPatch(fields: const {}),
              );
        if (!removesMembership &&
            accepted.contains('favorite') &&
            after['favorite'] is bool) {
          outboundPatch = outboundPatch.mergedWith(
            UserMediaPatch(favorite: after['favorite'] as bool),
          );
        }
        final libraryRow = await (database.select(
          database.canonicalLibraryRecords,
        )..where((table) => table.localId.equals(localId))).getSingleOrNull();
        if (!removesMembership && libraryRow?.inLibrary != true) {
          outboundPatch = _patchSubset(
            outboundPatch,
            {...outboundPatch.fields}..retainAll({UserMediaField.favorite}),
          );
        }
        if (!removesMembership && outboundPatch.fields.isEmpty) {
          outboundTargets.clear();
        }
        if (outboundTargets.isNotEmpty &&
            (removesMembership || outboundPatch.fields.isNotEmpty)) {
          journal = _mergeJournalMutation(
            journal,
            SyncJournalEntry(
              operationId: operationId,
              identity: next?.identity ?? current?.identity ?? incomingIdentity,
              patch: outboundPatch,
              pendingTargets: outboundTargets,
              createdAt: importedAt,
              updatedAt: importedAt,
              mediaTitle: next?.mediaItem.title ?? current?.mediaItem.title,
            ),
          );
        }
        await database
            .into(database.libraryOperationRecords)
            .insert(
              LibraryOperationRecordsCompanion.insert(
                operationId: operationId,
                localId: localId,
                deviceId: '${remoteOperation['deviceId'] ?? segment.deviceId}',
                originKind: originKind,
                originId: Value<String?>(originId),
                intent:
                    '${remoteOperation['intent'] ?? LibraryMutationIntent.edit.name}',
                fieldsJson: jsonEncode(fields.toList()..sort()),
                beforeJson: jsonEncode(before),
                afterJson: jsonEncode(after),
                baseRevisionsJson: jsonEncode(baseRevisions),
                resultingRevisionsJson: jsonEncode(resultingRevisions),
                targetsJson: jsonEncode(
                  outboundTargets
                      .map((TrackerSource source) => source.name)
                      .toList(),
                ),
                undoOf: Value<String?>(remoteOperation['undoOf']?.toString()),
                title: Value<String?>(remoteOperation['title']?.toString()),
                visibleInLog: const Value<bool>(true),
                occurredAtMs: operationAt.millisecondsSinceEpoch,
              ),
            );
        await database
            .into(database.outboxDeliveryRecords)
            .insertOnConflictUpdate(
              OutboxDeliveryRecordsCompanion.insert(
                deliveryId: '$operationId:drive',
                operationId: operationId,
                target: 'drive',
                state: 'confirmed',
                deliveredAtMs: Value<int>(importedAt.millisecondsSinceEpoch),
                confirmedAtMs: Value<int>(importedAt.millisecondsSinceEpoch),
              ),
            );
        for (final TrackerSource target in outboundTargets) {
          await database
              .into(database.outboxDeliveryRecords)
              .insertOnConflictUpdate(
                OutboxDeliveryRecordsCompanion.insert(
                  deliveryId: '$operationId:${target.name}',
                  operationId: operationId,
                  target: target.name,
                  state: 'pending',
                ),
              );
        }
        applied += 1;
      }

      await _importDriveEpisodeRows(
        segment,
        translatedIds,
        importedAt,
        handledEpisodes: handledEpisodes,
      );
      await _importDriveStreamRows(segment, translatedIds, importedAt);
      await _refreshActiveIdsLocked();
      await _retireObsoleteConflictsLocked(knownOperations);
      await _writeBucketLocked(
        'tracking.journal',
        journal.map((SyncJournalEntry value) => value.toJson()).toList(),
      );
      await database
          .into(database.syncCursorRecords)
          .insertOnConflictUpdate(
            SyncCursorRecordsCompanion.insert(
              scope: 'drive.pulled:${segment.fileName}',
              cursor: segment.checksum,
              metadataJson: Value<String>(
                jsonEncode(<String, dynamic>{'applied': applied}),
              ),
              updatedAtMs: importedAt.millisecondsSinceEpoch,
            ),
          );
      return applied;
    });
  }

  Future<void> _importDriveEpisodeRows(
    DriveReplicaSegment segment,
    Map<String, String> translatedIds,
    DateTime importedAt, {
    Set<String> handledEpisodes = const {},
  }) async {
    for (final Map<String, dynamic> row in segment.episodeStates) {
      final String? localId = translatedIds['${row['localId'] ?? ''}'];
      if (localId == null) continue;
      final int season = (row['seasonNumber'] as num?)?.toInt() ?? 1;
      final double episode = (row['episodeNumber'] as num?)?.toDouble() ?? 0;
      final int watchCycle = (row['watchCycle'] as num?)?.toInt() ?? 0;
      if (handledEpisodes.contains(
        '$localId:episodeProgress:$watchCycle:$season:$episode',
      )) {
        continue;
      }
      final int incomingUpdated =
          (row['updatedAtMs'] as num?)?.toInt() ??
          importedAt.millisecondsSinceEpoch;
      final String id = '$localId:$watchCycle:$season:$episode';
      final EpisodeStateRecord? existing =
          await (database.select(database.episodeStateRecords)..where(
                (EpisodeStateRecords table) => table.episodeStateId.equals(id),
              ))
              .getSingleOrNull();
      if (existing != null && existing.updatedAtMs >= incomingUpdated) continue;
      await database
          .into(database.episodeStateRecords)
          .insertOnConflictUpdate(
            EpisodeStateRecordsCompanion.insert(
              episodeStateId: id,
              localId: localId,
              seasonNumber: season,
              episodeNumber: episode,
              positionSeconds: Value<int>(
                (row['positionSeconds'] as num?)?.toInt() ?? 0,
              ),
              durationSeconds: Value<int?>(
                (row['durationSeconds'] as num?)?.toInt(),
              ),
              completed: Value<bool>(row['completed'] == true),
              watchCycle: Value<int>(watchCycle),
              updatedAtMs: incomingUpdated,
            ),
          );
    }
  }

  Future<void> _writeReceivedEpisodeCheckpointLocked(
    String localId,
    Map<String, dynamic> checkpoint,
    DateTime at,
    EpisodeStateRecord? previous,
  ) async {
    final season = (checkpoint['season'] as num?)?.toInt() ?? 1;
    final episode = (checkpoint['episode'] as num?)?.toDouble() ?? 1;
    final cycle = (checkpoint['watchCycle'] as num?)?.toInt() ?? 0;
    await database
        .into(database.episodeStateRecords)
        .insertOnConflictUpdate(
          EpisodeStateRecordsCompanion.insert(
            episodeStateId: '$localId:$cycle:$season:$episode',
            localId: localId,
            seasonNumber: season,
            episodeNumber: episode,
            watchCycle: Value(cycle),
            positionSeconds: Value(
              ((checkpoint['positionSeconds'] as num?)?.toInt() ?? 0).clamp(
                0,
                0x7fffffff,
              ),
            ),
            durationSeconds: Value(
              (checkpoint['durationSeconds'] as num?)?.toInt() ??
                  previous?.durationSeconds,
            ),
            completed: Value(checkpoint['completed'] == true),
            updatedAtMs: at.toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> _importDriveStreamRows(
    DriveReplicaSegment segment,
    Map<String, String> translatedIds,
    DateTime importedAt,
  ) async {
    for (final Map<String, dynamic> row in segment.streamPreferences) {
      final String? localId = translatedIds['${row['localId'] ?? ''}'];
      if (localId == null) continue;
      final int? season = (row['seasonNumber'] as num?)?.toInt();
      final double? episode = (row['episodeNumber'] as num?)?.toDouble();
      final int incomingUpdated =
          (row['updatedAtMs'] as num?)?.toInt() ??
          importedAt.millisecondsSinceEpoch;
      final String id = season == null && episode == null
          ? '$localId:title'
          : '$localId:${season ?? 'all'}:${episode ?? 'all'}';
      final StreamPreferenceRecord? existing =
          await (database.select(database.streamPreferenceRecords)..where(
                (StreamPreferenceRecords table) =>
                    table.preferenceId.equals(id),
              ))
              .getSingleOrNull();
      if (existing != null && existing.updatedAtMs >= incomingUpdated) continue;
      await database
          .into(database.streamPreferenceRecords)
          .insertOnConflictUpdate(
            StreamPreferenceRecordsCompanion.insert(
              preferenceId: id,
              localId: localId,
              seasonNumber: Value<int?>(season),
              episodeNumber: Value<double?>(episode),
              addonId: Value<String>('${row['addonId'] ?? ''}'),
              sourceId: Value<String>('${row['sourceId'] ?? ''}'),
              serverId: Value<String>('${row['serverId'] ?? ''}'),
              serverTitle: Value<String>('${row['serverTitle'] ?? ''}'),
              voiceoverId: Value<String>('${row['voiceoverId'] ?? ''}'),
              voiceoverTitle: Value<String>('${row['voiceoverTitle'] ?? ''}'),
              qualityId: Value<String>('${row['qualityId'] ?? ''}'),
              qualityLabel: Value<String>('${row['qualityLabel'] ?? ''}'),
              updatedAtMs: incomingUpdated,
            ),
          );
    }
  }

  Future<String> _appendOperationLocked(LibraryOperationDraft draft) async {
    final String operationId = draft.operationId ?? _uuid.v7();
    final String currentDeviceId = await deviceId();
    final Set<String> deliveryTargets = <String>{'drive', ...draft.targets};
    CanonicalLibraryRecord? entry =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) =>
                  table.localId.equals(draft.localId),
            ))
            .getSingleOrNull();
    if (entry == null && draft.fields.contains('episodeProgress')) {
      final media = await (database.select(
        database.canonicalMediaRecords,
      )..where((table) => table.localId.equals(draft.localId))).getSingle();
      entry = await _ensureHiddenTrackingRowLocked(
        draft.localId,
        MediaItem.fromJson(_jsonMap(media.mediaJson)),
        draft.occurredAt,
      );
    }
    final Map<String, dynamic> revisions = _jsonMap(entry?.fieldRevisionsJson);
    final Map<String, dynamic> beforeRevisions = Map<String, dynamic>.from(
      revisions,
    );
    final episodeKey = draft.fields.contains('episodeProgress')
        ? _episodeRevisionKey(draft.after['episode'])
        : null;
    if (episodeKey != null) {
      // The next checkpoint depends on this episode, not the most recently
      // touched episode elsewhere in the same title.
      beforeRevisions['episodeProgress'] = revisions[episodeKey];
    }
    for (final MapEntry<String, List<Object?>> alternate
        in draft.baseRevisionAlternatives.entries) {
      if (!draft.fields.contains(alternate.key)) continue;
      final List<Object?> acceptedBases = <Object?>[
        beforeRevisions[alternate.key],
      ];
      for (final Object? revision in alternate.value) {
        if (!acceptedBases.any(
          (Object? existing) => _jsonEquivalent(existing, revision),
        )) {
          acceptedBases.add(revision);
        }
      }
      beforeRevisions[alternate.key] = acceptedBases;
    }
    for (final String field in draft.fields) {
      revisions[field] = <String, dynamic>{
        'counter': _revisionCounter(beforeRevisions[field]) + 1,
        'deviceId': currentDeviceId,
        'operationId': operationId,
        'origin': draft.originKind.name,
        'occurredAtMs': draft.occurredAt.toUtc().millisecondsSinceEpoch,
        'editTimeVerified':
            draft.originKind != LibraryOriginKind.provider ||
            draft.editTimeVerified,
      };
    }
    if (episodeKey != null) {
      revisions[episodeKey] = revisions['episodeProgress'];
    }
    if (entry != null) {
      await (database.update(database.canonicalLibraryRecords)..where(
            (CanonicalLibraryRecords table) =>
                table.localId.equals(draft.localId),
          ))
          .write(
            CanonicalLibraryRecordsCompanion(
              fieldRevisionsJson: Value<String>(jsonEncode(revisions)),
            ),
          );
    }
    await database
        .into(database.libraryOperationRecords)
        .insert(
          LibraryOperationRecordsCompanion.insert(
            operationId: operationId,
            localId: draft.localId,
            deviceId: currentDeviceId,
            originKind: draft.originKind.name,
            originId: Value<String?>(draft.originId),
            intent: draft.intent.name,
            fieldsJson: jsonEncode(draft.fields.toList()..sort()),
            beforeJson: jsonEncode(draft.before),
            afterJson: jsonEncode(draft.after),
            baseRevisionsJson: jsonEncode(beforeRevisions),
            resultingRevisionsJson: jsonEncode(revisions),
            targetsJson: jsonEncode(deliveryTargets.toList()..sort()),
            undoOf: Value<String?>(draft.undoOf),
            title: Value<String?>(draft.title),
            visibleInLog: Value<bool>(draft.visibleInLog),
            occurredAtMs: draft.occurredAt.toUtc().millisecondsSinceEpoch,
          ),
        );
    for (final String target in deliveryTargets) {
      await database
          .into(database.outboxDeliveryRecords)
          .insertOnConflictUpdate(
            OutboxDeliveryRecordsCompanion.insert(
              deliveryId: '$operationId:$target',
              operationId: operationId,
              target: target,
              state: 'pending',
              accountId: Value<String?>(draft.targetAccountIds[target]),
            ),
          );
    }
    return operationId;
  }

  Future<CanonicalLibraryRecord> _ensureHiddenTrackingRowLocked(
    String localId,
    MediaItem media,
    DateTime at,
  ) async {
    final known = MediaIdentity.fromExternalIds(
      media.externalIds,
      mediaId: media.id,
    );
    await _upsertTrackingStateLocked(
      UserMediaState(
        identity: MediaIdentity(
          localId: localId,
          kind: known.mediaKind,
          anilistId: known.anilistId,
          malId: known.malId,
          shikimoriId: known.shikimoriId,
        ),
        mediaItem: media,
        status: AniListListStatus.planning,
        progress: 0,
        createdAt: at,
        updatedAt: at,
        source: TrackerSource.anilist,
      ),
    );
    await (database.update(database.canonicalLibraryRecords)
          ..where((table) => table.localId.equals(localId)))
        .write(const CanonicalLibraryRecordsCompanion(inLibrary: Value(false)));
    return (database.select(
      database.canonicalLibraryRecords,
    )..where((table) => table.localId.equals(localId))).getSingle();
  }

  Future<void> _refreshActiveIdsLocked() async {
    final table = database.canonicalLibraryRecords;
    final rows =
        await (database.selectOnly(table)
              ..addColumns([table.localId])
              ..where(table.inLibrary.equals(true)))
            .get();
    await _writeBucketLocked(
      'tracking.stateIds',
      rows.map((row) => row.read(table.localId)!).toList()..sort(),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _readRevisionGraphLocked() async {
    final table = database.libraryOperationRecords;
    // Causal checks need small revision edges, not every title's rich media
    // payload repeated throughout the entire operation history.
    final rows =
        await (database.selectOnly(table)..addColumns([
              table.operationId,
              table.baseRevisionsJson,
              table.originKind,
              table.fieldsJson,
            ]))
            .get();
    final result = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final bases = _jsonMap(row.read(table.baseRevisionsJson));
      result[row.read(table.operationId)!] = {
        'originKind': row.read(table.originKind),
        'baseRevisions': {
          for (final field in _jsonStringSet(row.read(table.fieldsJson)!))
            field: bases[field],
        },
      };
    }
    return result;
  }

  Future<void> _recordReceivedDriveOperationLocked(
    Map<String, dynamic> operation,
    String localId,
    String deviceId,
    DateTime at,
    DateTime receivedAt,
  ) async {
    final String id = '${operation['operationId']}';
    // Even a quarantined operation was received. Persist its original causal
    // history so another checkpoint cannot create the same prompts again.
    await database
        .into(database.libraryOperationRecords)
        .insertOnConflictUpdate(
          LibraryOperationRecordsCompanion.insert(
            operationId: id,
            localId: localId,
            deviceId: '${operation['deviceId'] ?? deviceId}',
            originKind: '${operation['originKind'] ?? 'drive'}',
            originId: Value(operation['originId']?.toString()),
            intent: '${operation['intent'] ?? 'edit'}',
            fieldsJson: jsonEncode(
              _dynamicStringSet(operation['fields']).toList()..sort(),
            ),
            beforeJson: jsonEncode(_jsonMap(operation['before'])),
            afterJson: jsonEncode(_jsonMap(operation['after'])),
            baseRevisionsJson: jsonEncode(_jsonMap(operation['baseRevisions'])),
            resultingRevisionsJson: jsonEncode(
              _jsonMap(operation['resultingRevisions']),
            ),
            targetsJson: '[]',
            title: Value(operation['title']?.toString()),
            undoOf: Value(operation['undoOf']?.toString()),
            occurredAtMs: at.millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.outboxDeliveryRecords)
        .insertOnConflictUpdate(
          OutboxDeliveryRecordsCompanion.insert(
            deliveryId: '$id:drive',
            operationId: id,
            target: 'drive',
            state: 'confirmed',
            deliveredAtMs: Value(receivedAt.millisecondsSinceEpoch),
            confirmedAtMs: Value(receivedAt.millisecondsSinceEpoch),
          ),
        );
  }

  Stream<List<CanonicalLibraryConflict>> watchConflicts() {
    final query = database.select(database.libraryConflictRecords)
      ..where((LibraryConflictRecords table) => table.state.equals('open'))
      ..orderBy(<OrderClauseGenerator<LibraryConflictRecords>>[
        (LibraryConflictRecords table) => OrderingTerm.desc(table.createdAtMs),
      ]);
    return query.watch().asyncMap((rows) async {
      final media = rows.isEmpty
          ? const <CanonicalMediaRecord>[]
          : await (database.select(database.canonicalMediaRecords)..where(
                  (table) => table.localId.isIn(rows.map((row) => row.localId)),
                ))
                .get();
      final titles = {
        for (final row in media)
          row.localId: _jsonMap(row.mediaJson)['title']?.toString(),
      };
      return rows
          .map(
            (LibraryConflictRecord row) => CanonicalLibraryConflict(
              conflictId: row.conflictId,
              localId: row.localId,
              fieldName: row.fieldName,
              localValue: _decodeJsonValue(row.localValueJson),
              incomingValue: _publicConflictValue(row.incomingValueJson),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row.createdAtMs,
                isUtc: true,
              ),
              state: row.state,
              title: titles[row.localId],
            ),
          )
          .toList(growable: false);
    });
  }

  /// A conflicting stale-device operation must not be sent to a tracker while
  /// the user is deciding which field value to keep.
  Future<Set<String>> unresolvedConflictLocalOperationIds() async {
    await initialize();
    final List<LibraryConflictRecord> rows =
        await (database.select(database.libraryConflictRecords)..where(
              (LibraryConflictRecords table) =>
                  table.state.equals('open') &
                  table.localOperationId.isNotNull(),
            ))
            .get();
    return rows
        .map((LibraryConflictRecord row) => row.localOperationId)
        .whereType<String>()
        .where((String id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<(String, TrackerSource)>> unresolvedProviderDeliveryBlocks(
    Map<TrackerSource, String> accounts,
  ) async {
    await initialize();
    final rows = await (database.select(
      database.libraryConflictRecords,
    )..where((table) => table.state.equals('open'))).get();
    final result = <(String, TrackerSource)>{};
    for (final row in rows) {
      final value = _jsonMap(row.incomingValueJson);
      if (value['provider'] is String) {
        final provider = TrackerSource.fromName(value['provider'] as String);
        if (accounts[provider] == value['accountId']) {
          result.add((row.localId, provider));
        }
      } else if (row.fieldName == 'identity') {
        final matches = _dynamicStringSet(_decodeJsonValue(row.localValueJson));
        for (final id in {...matches, row.localId}) {
          for (final provider in accounts.keys) {
            result.add((id, provider));
          }
        }
      }
    }
    return result;
  }

  Future<String?> resolveConflict({
    required String conflictId,
    required bool takeIncoming,
    required Set<TrackerSource> trackerTargets,
  }) async {
    await initialize();
    return database.transaction(() async {
      final LibraryConflictRecord conflict =
          await (database.select(database.libraryConflictRecords)..where(
                (LibraryConflictRecords table) =>
                    table.conflictId.equals(conflictId) &
                    table.state.equals('open'),
              ))
              .getSingle();
      final UserMediaField? field = _fieldFromPersistedName(conflict.fieldName);
      final bool membership = conflict.fieldName == 'membership';
      if (conflict.fieldName == 'episodeProgress') {
        return _resolveEpisodeConflictLocked(
          conflict,
          takeIncoming: takeIncoming,
        );
      }
      if (field == null && !membership) {
        await _markConflictResolvedLocked(conflictId);
        return null;
      }

      final CanonicalLibraryRecord? currentRow =
          await (database.select(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(conflict.localId),
              ))
              .getSingleOrNull();
      final UserMediaState? current = currentRow == null
          ? null
          : UserMediaState.fromJson(_jsonMap(currentRow.canonicalStateJson));
      final UserMediaState? incoming = _stateFromConflictJson(
        conflict.incomingValueJson,
      );
      final UserMediaState? selected = takeIncoming
          ? incoming
          : (membership && currentRow?.inLibrary == false ? null : current);
      final incomingFavorite = _jsonMap(conflict.incomingValueJson)['favorite'];
      final bool selectedFavorite =
          field == UserMediaField.favorite &&
              takeIncoming &&
              incomingFavorite is bool
          ? incomingFavorite
          : currentRow?.favorite ?? false;
      UserMediaState? next = current;
      if (membership) {
        next = selected;
      } else if (selected != null) {
        next = current == null
            ? selected
            : current.apply(
                _patchFromState(selected, <UserMediaField>{field!}),
                DateTime.now().toUtc(),
              );
      }

      final DateTime now = DateTime.now().toUtc();
      if (next == null) {
        if (currentRow != null) {
          await (database.update(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(conflict.localId),
              ))
              .write(
                CanonicalLibraryRecordsCompanion(
                  inLibrary: const Value<bool>(false),
                  tombstonedAtMs: Value<int>(now.millisecondsSinceEpoch),
                  updatedAtMs: Value<int>(now.millisecondsSinceEpoch),
                ),
              );
        }
      } else {
        await _upsertTrackingStateLocked(next);
      }

      // Once the last conflict for a local operation is resolved, its old
      // provider delivery must never run after the user's decision. Rebase
      // all fields from that pending operation onto the selected current
      // state and deliver that as a new operation instead.
      final Set<UserMediaField> fields = <UserMediaField>{?field};
      final Map<String, List<Object?>> alternateBases =
          <String, List<Object?>>{};
      final Map<String, dynamic> incomingConflictValue = _jsonMap(
        conflict.incomingValueJson,
      );
      if (incomingConflictValue.containsKey('__incomingRevision')) {
        alternateBases[conflict.fieldName] = <Object?>[
          incomingConflictValue['__incomingRevision'],
        ];
      }
      final String? staleOperationId = conflict.localOperationId;
      if (staleOperationId != null && staleOperationId.isNotEmpty) {
        final List<LibraryConflictRecord> otherOpenConflicts =
            await (database.select(database.libraryConflictRecords)..where(
                  (LibraryConflictRecords table) =>
                      table.localOperationId.equals(staleOperationId) &
                      table.state.equals('open') &
                      table.conflictId.isNotValue(conflictId),
                ))
                .get();
        if (otherOpenConflicts.isEmpty) {
          final List<SyncJournalEntry> journal = await loadJournal();
          final SyncJournalEntry? staleEntry = journal
              .where(
                (SyncJournalEntry entry) =>
                    entry.operationId == staleOperationId,
              )
              .firstOrNull;
          if (staleEntry != null) {
            fields.addAll(staleEntry.patch.fields);
            final LibraryOperationRecord? staleOperation =
                await (database.select(database.libraryOperationRecords)..where(
                      (LibraryOperationRecords table) =>
                          table.operationId.equals(staleOperationId),
                    ))
                    .getSingleOrNull();
            final Map<String, dynamic> staleBases = _jsonMap(
              staleOperation?.baseRevisionsJson,
            );
            for (final UserMediaField staleField in staleEntry.patch.fields) {
              final Object? base = staleBases[staleField.name];
              alternateBases
                  .putIfAbsent(staleField.name, () => <Object?>[])
                  .addAll(base is List ? base : <Object?>[base]);
            }
            await _writeBucketLocked(
              'tracking.journal',
              journal
                  .where(
                    (SyncJournalEntry entry) =>
                        entry.operationId != staleOperationId,
                  )
                  .map((SyncJournalEntry entry) => entry.toJson())
                  .toList(),
            );
            await (database.update(database.outboxDeliveryRecords)..where(
                  (OutboxDeliveryRecords table) =>
                      table.operationId.equals(staleOperationId) &
                      table.target.isNotValue('drive') &
                      table.state.isIn(const <String>['pending', 'retry']),
                ))
                .write(
                  const OutboxDeliveryRecordsCompanion(
                    state: Value<String>('superseded'),
                  ),
                );
          }
        }
      }
      UserMediaPatch patch = next == null
          ? UserMediaPatch(delete: true)
          : _patchFromState(next, <UserMediaField>{
              ...fields,
              if (membership) UserMediaField.status,
            });
      final MediaIdentity? resolvedIdentity =
          next?.identity ?? current?.identity ?? incoming?.identity;
      if (resolvedIdentity == null) {
        await _markConflictResolvedLocked(conflictId);
        return null;
      }
      if (fields.contains(UserMediaField.favorite)) {
        patch = patch.mergedWith(UserMediaPatch(favorite: selectedFavorite));
        await _setFavoriteLocked(
          localId: conflict.localId,
          identity: resolvedIdentity,
          favorite: selectedFavorite,
          at: now,
          mediaItem: next?.mediaItem ?? current?.mediaItem,
        );
      }
      if (!membership && currentRow?.inLibrary == false) {
        await (database.update(
          database.canonicalLibraryRecords,
        )..where((table) => table.localId.equals(conflict.localId))).write(
          CanonicalLibraryRecordsCompanion(
            inLibrary: const Value(false),
            tombstonedAtMs: Value(currentRow?.tombstonedAtMs),
          ),
        );
      }
      await _refreshActiveIdsLocked();
      final String operationId = const Uuid().v7();
      if (trackerTargets.isNotEmpty &&
          (patch.delete ||
              patch.touchesLibraryState ||
              patch.touches(UserMediaField.favorite))) {
        List<SyncJournalEntry> journal = await loadJournal();
        journal = _mergeJournalMutation(
          journal,
          SyncJournalEntry(
            operationId: operationId,
            identity: resolvedIdentity,
            patch: patch,
            pendingTargets: trackerTargets,
            createdAt: now,
            updatedAt: now,
            mediaTitle: next?.mediaItem.title ?? current?.mediaItem.title,
          ),
        );
        await _writeBucketLocked(
          'tracking.journal',
          journal.map((SyncJournalEntry value) => value.toJson()).toList(),
        );
      }
      await _appendOperationLocked(
        LibraryOperationDraft(
          operationId: operationId,
          localId: conflict.localId,
          originKind: LibraryOriginKind.user,
          intent: next == null
              ? LibraryMutationIntent.remove
              : LibraryMutationIntent.edit,
          fields: <String>{
            conflict.fieldName,
            ...fields.map((UserMediaField value) => value.name),
          },
          before: <String, dynamic>{
            if (current != null) 'state': current.toJson(),
            if (fields.contains(UserMediaField.favorite))
              'favorite': currentRow?.favorite ?? false,
          },
          after: <String, dynamic>{
            if (next != null) 'state': next.toJson(),
            if (fields.contains(UserMediaField.favorite))
              'favorite': selectedFavorite,
          },
          targets: <String>{
            'drive',
            ...trackerTargets.map((TrackerSource value) => value.name),
          },
          occurredAt: now,
          title: next?.mediaItem.title ?? current?.mediaItem.title,
          baseRevisionAlternatives: alternateBases,
        ),
      );
      await _markConflictResolvedLocked(conflictId);
      return operationId;
    });
  }

  Future<String?> _resolveEpisodeConflictLocked(
    LibraryConflictRecord conflict, {
    required bool takeIncoming,
  }) async {
    final incoming = _jsonMap(conflict.incomingValueJson);
    final operation = conflict.incomingOperationId == null
        ? null
        : await (database.select(database.libraryOperationRecords)..where(
                (table) =>
                    table.operationId.equals(conflict.incomingOperationId!),
              ))
              .getSingleOrNull();
    final rawCheckpoint =
        incoming['episode'] ?? _jsonMap(operation?.afterJson)['episode'];
    if (rawCheckpoint is! Map) {
      await _markConflictResolvedLocked(conflict.conflictId);
      return null;
    }
    final checkpoint = Map<String, dynamic>.from(rawCheckpoint);
    final cycle = (checkpoint['watchCycle'] as num?)?.toInt() ?? 0;
    final season = (checkpoint['season'] as num?)?.toInt() ?? 1;
    final episode = (checkpoint['episode'] as num?)?.toDouble() ?? 1;
    final previous =
        await (database.select(database.episodeStateRecords)..where(
              (table) => table.episodeStateId.equals(
                '${conflict.localId}:$cycle:$season:$episode',
              ),
            ))
            .getSingleOrNull();
    final selected = takeIncoming
        ? checkpoint
        : previous == null
        ? null
        : _episodeRowCheckpoint(previous);
    if (selected == null) {
      await _markConflictResolvedLocked(conflict.conflictId);
      return null;
    }
    final now = DateTime.now().toUtc();
    await _writeReceivedEpisodeCheckpointLocked(
      conflict.localId,
      selected,
      now,
      previous,
    );
    final id = await _appendOperationLocked(
      LibraryOperationDraft(
        localId: conflict.localId,
        originKind: LibraryOriginKind.user,
        intent: LibraryMutationIntent.progress,
        fields: const {'episodeProgress'},
        before: {
          if (previous != null) 'episode': _episodeRowCheckpoint(previous),
        },
        after: {'episode': selected},
        targets: const {'drive'},
        occurredAt: now,
        baseRevisionAlternatives: {
          'episodeProgress': [
            incoming['__incomingRevision'] ??
                _jsonMap(operation?.resultingRevisionsJson)['episodeProgress'],
          ],
        },
      ),
    );
    await _markConflictResolvedLocked(conflict.conflictId);
    return id;
  }

  Future<void> _markConflictResolvedLocked(String conflictId) async {
    await (database.update(database.libraryConflictRecords)..where(
          (LibraryConflictRecords table) => table.conflictId.equals(conflictId),
        ))
        .write(
          LibraryConflictRecordsCompanion(
            state: const Value<String>('resolved'),
            resolvedAtMs: Value<int>(
              DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          ),
        );
  }

  Stream<List<LibraryActivityEvent>> watchActivity({int limit = 500}) {
    final trigger = database.customSelect(
      'SELECT 1',
      readsFrom: <ResultSetImplementation>{
        database.libraryOperationRecords,
        database.outboxDeliveryRecords,
      },
    );
    return trigger.watch().asyncMap((List<QueryRow> _) async {
      final List<LibraryOperationRecord> rows =
          await (database.select(database.libraryOperationRecords)
                ..where(
                  (LibraryOperationRecords table) =>
                      table.visibleInLog.equals(true),
                )
                ..orderBy(<OrderClauseGenerator<LibraryOperationRecords>>[
                  (LibraryOperationRecords table) =>
                      OrderingTerm.desc(table.occurredAtMs),
                ])
                ..limit(limit))
              .get();
      final List<LibraryActivityEvent> result = <LibraryActivityEvent>[];
      final deliveriesByOperation = <String, List<OutboxDeliveryRecord>>{};
      if (rows.isNotEmpty) {
        final deliveries =
            await (database.select(database.outboxDeliveryRecords)..where(
                  (table) => table.operationId.isIn(
                    rows.map((row) => row.operationId),
                  ),
                ))
                .get();
        for (final delivery in deliveries) {
          deliveriesByOperation
              .putIfAbsent(delivery.operationId, () => [])
              .add(delivery);
        }
      }
      for (final LibraryOperationRecord row in rows) {
        final deliveries =
            deliveriesByOperation[row.operationId] ??
            const <OutboxDeliveryRecord>[];
        result.add(_activityFromRow(row, deliveries));
      }
      return result;
    });
  }

  Future<LibraryUndoPreview> previewUndo(String operationId) async {
    await initialize();
    final LibraryOperationRecord operation =
        await (database.select(database.libraryOperationRecords)..where(
              (LibraryOperationRecords table) =>
                  table.operationId.equals(operationId),
            ))
            .getSingle();
    final CanonicalLibraryRecord? current =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) =>
                  table.localId.equals(operation.localId),
            ))
            .getSingleOrNull();
    final Map<String, dynamic> expectedRevisions = _jsonMap(
      operation.resultingRevisionsJson,
    );
    final Map<String, dynamic> currentRevisions = _jsonMap(
      current?.fieldRevisionsJson,
    );
    final Set<String> safe = <String>{};
    final Set<String> blocked = <String>{};
    for (final String field in _jsonStringSet(operation.fieldsJson)) {
      if (_jsonEquivalent(expectedRevisions[field], currentRevisions[field])) {
        safe.add(field);
      } else {
        blocked.add(field);
      }
    }
    return LibraryUndoPreview(
      operationId: operation.operationId,
      title: operation.title,
      safeFields: safe,
      blockedFields: blocked,
      before: _jsonMap(operation.beforeJson),
      after: _jsonMap(operation.afterJson),
    );
  }

  Future<String> undo(String operationId, {Set<String>? fields}) async {
    await initialize();
    return database.transaction(() async {
      final LibraryOperationRecord operation =
          await (database.select(database.libraryOperationRecords)..where(
                (LibraryOperationRecords table) =>
                    table.operationId.equals(operationId),
              ))
              .getSingle();
      final CanonicalLibraryRecord current =
          await (database.select(database.canonicalLibraryRecords)..where(
                (CanonicalLibraryRecords table) =>
                    table.localId.equals(operation.localId),
              ))
              .getSingle();
      final Map<String, dynamic> expectedRevisions = _jsonMap(
        operation.resultingRevisionsJson,
      );
      final Map<String, dynamic> currentRevisions = _jsonMap(
        current.fieldRevisionsJson,
      );
      final Set<String> operationFields = _jsonStringSet(operation.fieldsJson);
      final Set<String> selected = fields == null
          ? operationFields
          : <String>{...fields};
      if (selected.isEmpty || !operationFields.containsAll(selected)) {
        throw StateError('Choose at least one field changed by this event.');
      }
      for (final String field in selected) {
        if (!_jsonEquivalent(
          expectedRevisions[field],
          currentRevisions[field],
        )) {
          throw StateError(
            'Cannot safely undo $field because it has a newer change.',
          );
        }
      }
      final Map<String, dynamic> before = _jsonMap(operation.beforeJson);
      final Object? rawBeforeState = before['state'];
      final UserMediaState? beforeState = rawBeforeState is Map
          ? UserMediaState.fromJson(Map<String, dynamic>.from(rawBeforeState))
          : null;
      final UserMediaState currentState = UserMediaState.fromJson(
        _jsonMap(current.canonicalStateJson),
      );
      final UserMediaState? visibleCurrent = current.inLibrary
          ? currentState
          : null;
      UserMediaState? next = visibleCurrent;
      final bool restoresMembership = selected.contains('membership');
      if (restoresMembership) {
        next = beforeState == null ? null : next ?? beforeState;
      }
      final Set<UserMediaField> restoredFields = selected
          .map(_fieldFromPersistedName)
          .whereType<UserMediaField>()
          .where((UserMediaField field) => field != UserMediaField.favorite)
          .toSet();
      if (next != null && beforeState != null && restoredFields.isNotEmpty) {
        next = next.apply(
          _patchFromState(beforeState, restoredFields),
          DateTime.now().toUtc(),
        );
      }
      if (next == null) {
        await (database.update(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) =>
                  table.localId.equals(operation.localId),
            ))
            .write(
              CanonicalLibraryRecordsCompanion(
                inLibrary: const Value<bool>(false),
                tombstonedAtMs: Value<int>(
                  DateTime.now().toUtc().millisecondsSinceEpoch,
                ),
              ),
            );
      } else {
        await _upsertTrackingStateLocked(next);
      }

      final bool restoresFavorite = selected.contains(
        UserMediaField.favorite.name,
      );
      final bool favoriteAfterUndo = restoresFavorite
          ? before['favorite'] == true
          : current.favorite;
      if (restoresFavorite) {
        final MediaIdentity identity =
            next?.identity ?? beforeState?.identity ?? currentState.identity;
        final List<LocalMediaFavoriteState> favorites = await loadFavorites();
        final int favoriteIndex = favorites.indexWhere(
          (LocalMediaFavoriteState value) => value.identity.matches(identity),
        );
        final LocalMediaFavoriteState restoredFavorite =
            LocalMediaFavoriteState(
              identity: identity,
              favorite: favoriteAfterUndo,
              updatedAt: DateTime.now().toUtc(),
            );
        if (favoriteIndex < 0) {
          favorites.add(restoredFavorite);
        } else {
          favorites[favoriteIndex] = restoredFavorite;
        }
        await _writeBucketLocked(
          'tracking.favorites',
          favorites
              .map((LocalMediaFavoriteState value) => value.toJson())
              .toList(),
        );
        await _applyFavoritesLocked(favorites, await loadTrackingStates());
      }

      final DateTime now = DateTime.now().toUtc();
      final MediaIdentity identity =
          next?.identity ?? beforeState?.identity ?? currentState.identity;
      Set<UserMediaField> outboundFields = restoredFields;
      if (restoresMembership && next != null) {
        outboundFields = UserMediaField.values
            .where((UserMediaField field) => field != UserMediaField.favorite)
            .toSet();
      }
      UserMediaPatch patch = next == null
          ? UserMediaPatch(delete: true)
          : _patchFromState(next, outboundFields);
      if (restoresFavorite) {
        patch = patch.mergedWith(UserMediaPatch(favorite: favoriteAfterUndo));
      }
      final Set<TrackerSource> trackerTargets =
          _jsonStringSet(operation.targetsJson)
              .where(
                (String value) => TrackerSource.values.any(
                  (TrackerSource source) => source.name == value,
                ),
              )
              .map(TrackerSource.fromName)
              .toSet();
      final String undoOperationId = const Uuid().v7();
      if (trackerTargets.isNotEmpty &&
          (patch.delete || patch.fields.isNotEmpty)) {
        List<SyncJournalEntry> journal = await loadJournal();
        journal = _mergeJournalMutation(
          journal,
          SyncJournalEntry(
            operationId: undoOperationId,
            identity: identity,
            patch: patch,
            pendingTargets: trackerTargets,
            createdAt: now,
            updatedAt: now,
            mediaTitle: operation.title,
          ),
        );
        await _writeBucketLocked(
          'tracking.journal',
          journal.map((SyncJournalEntry value) => value.toJson()).toList(),
        );
      }
      return _appendOperationLocked(
        LibraryOperationDraft(
          operationId: undoOperationId,
          localId: operation.localId,
          originKind: LibraryOriginKind.undo,
          intent: LibraryMutationIntent.undo,
          fields: selected,
          before: <String, dynamic>{
            if (visibleCurrent != null) 'state': visibleCurrent.toJson(),
            if (restoresFavorite) 'favorite': current.favorite,
          },
          after: <String, dynamic>{
            if (next != null) 'state': next.toJson(),
            if (restoresFavorite) 'favorite': favoriteAfterUndo,
          },
          targets: _jsonStringSet(operation.targetsJson),
          occurredAt: now,
          title: operation.title,
          undoOf: operation.operationId,
        ),
      );
    });
  }

  Future<CanonicalEpisodeProgress?> loadEpisodeProgress({
    required String mediaId,
    required int season,
    required double episode,
    int watchCycle = 0,
  }) async {
    await initialize();
    final identity = MediaIdentity.fromExternalIds(const {}, mediaId: mediaId);
    if (identity.hasProviderId) {
      final blocked =
          await (database.select(database.providerBindingRecords)..where(
                (t) =>
                    t.quarantined.equals(true) &
                    t.mediaKind.equals(identity.mediaKind) &
                    ((t.provider.equals('anilist') &
                            t.externalMediaId.equals(
                              identity.anilistId ?? -1,
                            )) |
                        (t.provider.equals('mal') &
                            t.externalMediaId.equals(identity.malId ?? -1)) |
                        (t.provider.equals('shikimori') &
                            t.externalMediaId.equals(
                              identity.shikimoriId ?? -1,
                            ))),
              ))
              .get();
      if (blocked.isNotEmpty) return null;
    }
    final String? localId =
        await _localIdForAlias(mediaId) ??
        await _localIdForIdentityLocked(identity);
    if (localId == null) return null;
    final EpisodeStateRecord? row =
        await (database.select(database.episodeStateRecords)..where(
              (EpisodeStateRecords table) =>
                  table.localId.equals(localId) &
                  table.seasonNumber.equals(season) &
                  table.episodeNumber.equals(episode) &
                  table.watchCycle.equals(watchCycle),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return CanonicalEpisodeProgress(
      positionSeconds: row.positionSeconds,
      durationSeconds: row.durationSeconds,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAtMs,
        isUtc: true,
      ),
      completed: row.completed,
      watchCycle: row.watchCycle,
    );
  }

  /// Observe only this title's checkpoints, not the whole playback history.
  /// Exact, verified provider bindings also work before an alias is created.
  Stream<Map<(int, double), CanonicalEpisodeProgress>> watchEpisodeProgress(
    String mediaId, {
    int watchCycle = 0,
  }) async* {
    await initialize();
    final identity = MediaIdentity.fromExternalIds(const {}, mediaId: mediaId);
    final query = database.customSelect(
      '''SELECT e.* FROM episode_state_records e
         WHERE e.watch_cycle = ? AND NOT EXISTS (
           SELECT 1 FROM provider_binding_records
           WHERE quarantined = 1 AND media_kind = ? AND (
             (provider = 'anilist' AND external_media_id = ?) OR
             (provider = 'mal' AND external_media_id = ?) OR
             (provider = 'shikimori' AND external_media_id = ?)
           )
         ) AND (
           e.local_id = ? OR e.local_id IN (
             SELECT local_id FROM media_alias_records WHERE alias = ?
           ) OR e.local_id IN (
             SELECT local_id FROM provider_binding_records
             WHERE quarantined = 0 AND media_kind = ? AND (
               (provider = 'anilist' AND external_media_id = ?) OR
               (provider = 'mal' AND external_media_id = ?) OR
               (provider = 'shikimori' AND external_media_id = ?)
             )
           )
         )''',
      variables: [
        Variable<int>(watchCycle),
        Variable<String>(identity.mediaKind),
        Variable<int>(identity.anilistId ?? -1),
        Variable<int>(identity.malId ?? -1),
        Variable<int>(identity.shikimoriId ?? -1),
        Variable<String>(mediaId),
        Variable<String>(mediaId),
        Variable<String>(identity.mediaKind),
        Variable<int>(identity.anilistId ?? -1),
        Variable<int>(identity.malId ?? -1),
        Variable<int>(identity.shikimoriId ?? -1),
      ],
      readsFrom: {
        database.episodeStateRecords,
        database.mediaAliasRecords,
        database.providerBindingRecords,
      },
    );
    yield* query.watch().map(
      (rows) => {
        for (final row in rows)
          (
            row.read<int>('season_number'),
            row.read<double>('episode_number'),
          ): CanonicalEpisodeProgress(
            positionSeconds: row.read<int>('position_seconds'),
            durationSeconds: row.readNullable<int>('duration_seconds'),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('updated_at_ms'),
              isUtc: true,
            ),
            completed: row.read<bool>('completed'),
            watchCycle: row.read<int>('watch_cycle'),
          ),
      },
    );
  }

  Future<void> saveEpisodeProgress({
    required String mediaId,
    required int season,
    required double episode,
    required int positionSeconds,
    int? durationSeconds,
    bool completed = false,
    int watchCycle = 0,
    MediaItem? mediaItem,
    bool recordActivity = true,
    bool onlyIfMissing = false,
    DateTime? occurredAt,
  }) async {
    await initialize();
    await database.transaction(() async {
      String? localId = await _localIdForAlias(mediaId);
      if (localId == null) {
        final MediaIdentity identity = MediaIdentity.fromExternalIds(
          mediaItem?.externalIds ?? const <String, String>{},
          mediaId: mediaId,
        );
        localId = await _resolveOrCreateMediaLocked(
          identity: identity,
          mediaItem: mediaItem ?? _placeholderMedia(identity, mediaId: mediaId),
        );
      }
      final int now = (occurredAt ?? DateTime.now())
          .toUtc()
          .millisecondsSinceEpoch;
      final String id = '$localId:$watchCycle:$season:$episode';
      final EpisodeStateRecord? previous =
          await (database.select(database.episodeStateRecords)..where(
                (EpisodeStateRecords table) => table.episodeStateId.equals(id),
              ))
              .getSingleOrNull();
      // Compatibility migration must not replay stale source/device state
      // over a newer canonical checkpoint (including an intentional reset).
      if (onlyIfMissing && previous != null) return;
      await database
          .into(database.episodeStateRecords)
          .insertOnConflictUpdate(
            EpisodeStateRecordsCompanion.insert(
              episodeStateId: id,
              localId: localId,
              seasonNumber: season,
              episodeNumber: episode,
              positionSeconds: Value<int>(positionSeconds.clamp(0, 0x7fffffff)),
              durationSeconds: Value<int?>(durationSeconds),
              completed: Value<bool>(completed),
              watchCycle: Value<int>(watchCycle),
              updatedAtMs: now,
            ),
          );
      final bool completedNow = completed && previous?.completed != true;
      final bool checkpointDue =
          previous == null ||
          completedNow ||
          (positionSeconds - previous.positionSeconds).abs() >= 30 ||
          now - previous.updatedAtMs >=
              const Duration(minutes: 1).inMilliseconds;
      if (checkpointDue) {
        await _appendOperationLocked(
          LibraryOperationDraft(
            localId: localId,
            originKind: LibraryOriginKind.player,
            intent: completedNow
                ? LibraryMutationIntent.episodeCompleted
                : LibraryMutationIntent.progress,
            fields: <String>{'episodeProgress'},
            before: <String, dynamic>{
              if (previous != null)
                'episode': <String, dynamic>{
                  'season': previous.seasonNumber,
                  'episode': previous.episodeNumber,
                  'positionSeconds': previous.positionSeconds,
                  'durationSeconds': previous.durationSeconds,
                  'completed': previous.completed,
                  'watchCycle': previous.watchCycle,
                },
            },
            after: <String, dynamic>{
              'episode': <String, dynamic>{
                'season': season,
                'episode': episode,
                'positionSeconds': positionSeconds,
                'durationSeconds': durationSeconds,
                'completed': completed,
                'watchCycle': watchCycle,
              },
            },
            targets: const <String>{'drive'},
            occurredAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
            title: mediaItem?.title,
            visibleInLog: recordActivity && completedNow,
          ),
        );
      }
    });
  }

  Future<CanonicalStreamPreference?> loadStreamPreference({
    required String mediaId,
  }) async {
    await initialize();
    final String? localId = await _localIdForAlias(mediaId);
    if (localId == null) return null;
    final StreamPreferenceRecord? row =
        await (database.select(database.streamPreferenceRecords)..where(
              (StreamPreferenceRecords table) =>
                  table.localId.equals(localId) & table.seasonNumber.isNull(),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return CanonicalStreamPreference(
      addonId: row.addonId,
      sourceId: row.sourceId,
      serverId: row.serverId,
      serverTitle: row.serverTitle,
      voiceoverId: row.voiceoverId,
      voiceoverTitle: row.voiceoverTitle,
      qualityId: row.qualityId,
      qualityLabel: row.qualityLabel,
    );
  }

  Future<void> saveStreamPreference({
    required MediaIdentity identity,
    required MediaItem mediaItem,
    required CanonicalStreamPreference preference,
    bool recordActivity = true,
  }) async {
    await initialize();
    await database.transaction(() async {
      final String localId = await _resolveOrCreateMediaLocked(
        identity: identity,
        mediaItem: mediaItem,
      );
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final StreamPreferenceRecord? previous =
          await (database.select(database.streamPreferenceRecords)..where(
                (StreamPreferenceRecords table) =>
                    table.preferenceId.equals('$localId:title'),
              ))
              .getSingleOrNull();
      await database
          .into(database.streamPreferenceRecords)
          .insertOnConflictUpdate(
            StreamPreferenceRecordsCompanion.insert(
              preferenceId: '$localId:title',
              localId: localId,
              addonId: Value<String>(preference.addonId),
              sourceId: Value<String>(preference.sourceId),
              serverId: Value<String>(preference.serverId),
              serverTitle: Value<String>(preference.serverTitle),
              voiceoverId: Value<String>(preference.voiceoverId),
              voiceoverTitle: Value<String>(preference.voiceoverTitle),
              qualityId: Value<String>(preference.qualityId),
              qualityLabel: Value<String>(preference.qualityLabel),
              updatedAtMs: now,
            ),
          );
      final bool changed =
          previous == null ||
          previous.addonId != preference.addonId ||
          previous.sourceId != preference.sourceId ||
          previous.serverId != preference.serverId ||
          previous.serverTitle != preference.serverTitle ||
          previous.voiceoverId != preference.voiceoverId ||
          previous.voiceoverTitle != preference.voiceoverTitle ||
          previous.qualityId != preference.qualityId ||
          previous.qualityLabel != preference.qualityLabel;
      if (changed) {
        await _appendOperationLocked(
          LibraryOperationDraft(
            localId: localId,
            originKind: LibraryOriginKind.user,
            intent: LibraryMutationIntent.streamPreference,
            fields: const <String>{'streamPreference'},
            before: <String, dynamic>{
              if (previous != null) 'preference': _streamRowJson(previous),
            },
            after: <String, dynamic>{
              'preference': _streamPreferenceJson(preference),
            },
            targets: const <String>{'drive'},
            occurredAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
            title: mediaItem.title,
            visibleInLog: recordActivity,
          ),
        );
      }
    });
  }

  Future<void> saveStreamPreferenceByMediaId({
    required String mediaId,
    required MediaType mediaType,
    required CanonicalStreamPreference preference,
    String title = 'Saved media',
    bool recordActivity = true,
  }) {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      const <String, String>{},
      mediaId: mediaId,
    );
    return saveStreamPreference(
      identity: identity,
      mediaItem: MediaItem(
        id: mediaId,
        title: title,
        originalTitle: '',
        overview: '',
        type: mediaType,
        year: 0,
        posterUrl: '',
        backdropUrl: '',
        rating: 0,
        genres: const <String>[],
        sourceProvider: 'MiruShin Local',
        externalIds: identity.mergeExternalIds(const <String, String>{}),
        statusLabel: '',
      ),
      preference: preference,
      recordActivity: recordActivity,
    );
  }

  Future<String?> _localIdForAlias(String alias) async {
    final mapped = await (database.select(
      database.mediaAliasRecords,
    )..where((table) => table.alias.equals(alias))).getSingleOrNull();
    if (mapped != null) return mapped.localId;
    final CanonicalMediaRecord? direct =
        await (database.select(database.canonicalMediaRecords)..where(
              (CanonicalMediaRecords table) => table.localId.equals(alias),
            ))
            .getSingleOrNull();
    if (direct != null) return direct.localId;
    return null;
  }

  Future<String?> _localIdForIdentityLocked(MediaIdentity identity) async {
    final String? direct = await _localIdForAlias(identity.localId);
    if (direct != null) return direct;
    final Map<String, int?> candidates = <String, int?>{
      TrackerSource.anilist.name: identity.anilistId,
      TrackerSource.mal.name: identity.malId,
      TrackerSource.shikimori.name: identity.shikimoriId,
    };
    for (final MapEntry<String, int?> candidate in candidates.entries) {
      final int? id = candidate.value;
      if (id == null || id <= 0) continue;
      final ProviderBindingRecord? binding =
          await (database.select(database.providerBindingRecords)..where(
                (ProviderBindingRecords table) =>
                    table.provider.equals(candidate.key) &
                    table.mediaKind.equals(identity.mediaKind) &
                    table.externalMediaId.equals(id) &
                    table.quarantined.equals(false),
              ))
              .getSingleOrNull();
      if (binding != null) return binding.localId;
    }
    return null;
  }

  Future<List<T>> _loadBucket<T>(
    String name,
    T Function(Map<String, dynamic>) decode,
  ) async {
    await initialize();
    final List<dynamic> values = await _readBucketLocked(name);
    final List<T> result = <T>[];
    for (final Object? value in values) {
      if (value is! Map) continue;
      try {
        result.add(decode(Map<String, dynamic>.from(value)));
      } on Object {
        // Isolate a corrupt legacy element.
      }
    }
    return result;
  }

  Future<List<dynamic>> _readBucketLocked(String name) async {
    final LegacyBucketRecord? row =
        await (database.select(database.legacyBucketRecords)
              ..where((LegacyBucketRecords table) => table.bucket.equals(name)))
            .getSingleOrNull();
    if (row == null || row.valueJson.isEmpty) return <dynamic>[];
    try {
      final Object? decoded = jsonDecode(row.valueJson);
      return decoded is List<dynamic> ? decoded : <dynamic>[];
    } on Object {
      return <dynamic>[];
    }
  }

  Future<void> _writeBucket(String name, Object value) async {
    await initialize();
    await database.transaction(() => _writeBucketLocked(name, value));
  }

  Future<void> _writeBucketLocked(String name, Object value) async {
    final encoded = jsonEncode(value);
    final existing = await (database.select(
      database.legacyBucketRecords,
    )..where((table) => table.bucket.equals(name))).getSingleOrNull();
    if (existing?.valueJson == encoded) return;
    await database
        .into(database.legacyBucketRecords)
        .insertOnConflictUpdate(
          LegacyBucketRecordsCompanion.insert(
            bucket: name,
            valueJson: encoded,
            updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  LibraryActivityEvent _activityFromRow(
    LibraryOperationRecord row,
    List<OutboxDeliveryRecord> deliveries,
  ) => LibraryActivityEvent(
    operationId: row.operationId,
    localId: row.localId,
    deviceId: row.deviceId,
    originKind: LibraryOriginKind.values.firstWhere(
      (LibraryOriginKind value) => value.name == row.originKind,
      orElse: () => LibraryOriginKind.system,
    ),
    originId: row.originId,
    intent: LibraryMutationIntent.values.firstWhere(
      (LibraryMutationIntent value) => value.name == row.intent,
      orElse: () => LibraryMutationIntent.edit,
    ),
    fields: _jsonStringSet(row.fieldsJson),
    before: _jsonMap(row.beforeJson),
    after: _jsonMap(row.afterJson),
    targets: _jsonStringSet(row.targetsJson),
    occurredAt: DateTime.fromMillisecondsSinceEpoch(
      row.occurredAtMs,
      isUtc: true,
    ),
    title: row.title,
    undoOf: row.undoOf,
    deliveryStates: <String, String>{
      for (final OutboxDeliveryRecord value in deliveries)
        value.target: value.state,
    },
    deliveryDetails: {
      for (final value in deliveries)
        value.target: LibraryDeliveryDetail(
          error: value.lastError,
          attempts: value.attempts,
          accountId: value.accountId,
          lastAttemptAt: value.lastAttemptAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  value.lastAttemptAtMs!,
                  isUtc: true,
                ),
          nextAttemptAt: value.nextAttemptAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  value.nextAttemptAtMs!,
                  isUtc: true,
                ),
        ),
    },
  );

  MediaItem _placeholderMedia(MediaIdentity identity, {String? mediaId}) =>
      MediaItem(
        id: mediaId ?? identity.localId,
        title: 'Saved media',
        originalTitle: '',
        overview: '',
        type: MediaType.anime,
        year: 0,
        posterUrl: '',
        backdropUrl: '',
        rating: 0,
        genres: const <String>[],
        sourceProvider: 'MiruShin Local',
        externalIds: identity.mergeExternalIds(const <String, String>{}),
        statusLabel: '',
      );
}

Map<String, dynamic> _jsonMap(Object? source) {
  if (source is Map<String, dynamic>) return Map<String, dynamic>.from(source);
  if (source is Map) return Map<String, dynamic>.from(source);
  if (source is! String || source.isEmpty) return <String, dynamic>{};
  try {
    final Object? decoded = jsonDecode(source);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } on Object {
    return <String, dynamic>{};
  }
}

Object? _decodeJsonValue(String source) {
  try {
    return jsonDecode(source);
  } on Object {
    return source;
  }
}

Object? _publicConflictValue(String source) {
  final Object? decoded = _decodeJsonValue(source);
  if (decoded is! Map) return decoded;
  if (decoded['__deleted'] == true) return null;
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
      if (!'${entry.key}'.startsWith('__')) '${entry.key}': entry.value,
  };
}

UserMediaState? _stateFromConflictJson(String source) {
  final Object? decoded = _decodeJsonValue(source);
  if (decoded is! Map) return null;
  if (decoded['__deleted'] == true) return null;
  if (decoded.containsKey('state')) {
    final state = decoded['state'];
    return state is Map
        ? UserMediaState.fromJson(Map<String, dynamic>.from(state))
        : null;
  }
  if (decoded.containsKey('provider') && !decoded.containsKey('identity')) {
    return null;
  }
  try {
    return UserMediaState.fromJson(Map<String, dynamic>.from(decoded));
  } on Object {
    return null;
  }
}

Set<String> _jsonStringSet(String source) {
  try {
    final Object? decoded = jsonDecode(source);
    return decoded is List
        ? decoded.map((Object? value) => '$value').toSet()
        : <String>{};
  } on Object {
    return <String>{};
  }
}

Map<String, dynamic> _streamRowJson(StreamPreferenceRecord value) =>
    <String, dynamic>{
      'addonId': value.addonId,
      'sourceId': value.sourceId,
      'serverId': value.serverId,
      'serverTitle': value.serverTitle,
      'voiceoverId': value.voiceoverId,
      'voiceoverTitle': value.voiceoverTitle,
      'qualityId': value.qualityId,
      'qualityLabel': value.qualityLabel,
    };

Map<String, dynamic> _streamPreferenceJson(CanonicalStreamPreference value) =>
    <String, dynamic>{
      'addonId': value.addonId,
      'sourceId': value.sourceId,
      'serverId': value.serverId,
      'serverTitle': value.serverTitle,
      'voiceoverId': value.voiceoverId,
      'voiceoverTitle': value.voiceoverTitle,
      'qualityId': value.qualityId,
      'qualityLabel': value.qualityLabel,
    };

class _DriveSnapshotRows {
  const _DriveSnapshotRows({
    required this.snapshotId,
    required this.deviceId,
    required this.createdAt,
    required this.replicaNamespace,
    required this.media,
    required this.library,
    required this.bindings,
    required this.providerSnapshots,
    required this.episodes,
    required this.streams,
    required this.operations,
  });

  final String snapshotId;
  final String deviceId;
  final DateTime createdAt;
  final String replicaNamespace;
  final List<CanonicalMediaRecord> media;
  final List<CanonicalLibraryRecord> library;
  final List<ProviderBindingRecord> bindings;
  final List<ProviderSnapshotRecord> providerSnapshots;
  final List<EpisodeStateRecord> episodes;
  final List<StreamPreferenceRecord> streams;
  final List<LibraryOperationRecord> operations;
}

DriveLibrarySnapshot _buildDriveSnapshotFromRows(_DriveSnapshotRows rows) =>
    DriveLibrarySnapshot(
      snapshotId: rows.snapshotId,
      deviceId: rows.deviceId,
      createdAt: rows.createdAt,
      replicaNamespace: rows.replicaNamespace,
      media: rows.media.map(_mediaRowJson).toList(growable: false),
      libraryEntries: rows.library.map(_libraryRowJson).toList(growable: false),
      providerBindings: rows.bindings
          .map(_providerBindingRowJson)
          .toList(growable: false),
      providerSnapshots: rows.providerSnapshots
          .map(_providerSnapshotRowJson)
          .toList(growable: false),
      episodeStates: rows.episodes.map(_episodeRowJson).toList(growable: false),
      streamPreferences: rows.streams
          .map(_streamReplicaRowJson)
          .toList(growable: false),
      operations: rows.operations
          .map(_operationRowJson)
          .toList(growable: false),
    );

Map<String, dynamic> _operationRowJson(LibraryOperationRecord value) =>
    <String, dynamic>{
      'operationId': value.operationId,
      'localId': value.localId,
      'deviceId': value.deviceId,
      'originKind': value.originKind,
      if (value.originId != null) 'originId': value.originId,
      'intent': value.intent,
      'fields': _jsonList(value.fieldsJson),
      'before': _jsonMap(value.beforeJson),
      'after': _jsonMap(value.afterJson),
      'baseRevisions': _jsonMap(value.baseRevisionsJson),
      'resultingRevisions': _jsonMap(value.resultingRevisionsJson),
      'targets': _jsonList(value.targetsJson),
      if (value.undoOf != null) 'undoOf': value.undoOf,
      if (value.title != null) 'title': value.title,
      'visibleInLog': value.visibleInLog,
      'occurredAt': DateTime.fromMillisecondsSinceEpoch(
        value.occurredAtMs,
        isUtc: true,
      ).toIso8601String(),
    };

Map<String, dynamic> _mediaRowJson(CanonicalMediaRecord value) =>
    <String, dynamic>{
      'localId': value.localId,
      'mediaKind': value.mediaKind,
      'media': _jsonMap(value.mediaJson),
      'createdAtMs': value.createdAtMs,
      'updatedAtMs': value.updatedAtMs,
    };

Map<String, dynamic> _libraryRowJson(CanonicalLibraryRecord value) =>
    <String, dynamic>{
      'localId': value.localId,
      'inLibrary': value.inLibrary,
      'favorite': value.favorite,
      'state': _jsonMap(value.canonicalStateJson),
      'fieldRevisions': _jsonMap(value.fieldRevisionsJson),
      'updatedAtMs': value.updatedAtMs,
      if (value.tombstonedAtMs != null) 'tombstonedAtMs': value.tombstonedAtMs,
    };

Map<String, dynamic> _providerBindingRowJson(
  ProviderBindingRecord value,
) => <String, dynamic>{
  'localId': value.localId,
  'provider': value.provider,
  'mediaKind': value.mediaKind,
  'externalMediaId': value.externalMediaId,
  if (value.providerEntryId != null) 'providerEntryId': value.providerEntryId,
  'evidence': value.evidence,
  'verifiedAtMs': value.verifiedAtMs,
  'quarantined': value.quarantined,
};

Map<String, dynamic> _providerSnapshotRowJson(
  ProviderSnapshotRecord value,
) => <String, dynamic>{
  'localId': value.localId,
  'provider': value.provider,
  'accountId': value.accountId,
  if (value.providerEntryId != null) 'providerEntryId': value.providerEntryId,
  'normalized': _jsonMap(value.normalizedJson),
  'raw': _decodeJsonValue(value.rawJson),
  'contentHash': value.contentHash,
  'fetchedAtMs': value.fetchedAtMs,
  'completeSnapshot': value.completeSnapshot,
  'destructiveConfirmationCount': value.destructiveConfirmationCount,
};

Map<String, dynamic> _episodeRowJson(
  EpisodeStateRecord value,
) => <String, dynamic>{
  'localId': value.localId,
  'seasonNumber': value.seasonNumber,
  'episodeNumber': value.episodeNumber,
  'positionSeconds': value.positionSeconds,
  if (value.durationSeconds != null) 'durationSeconds': value.durationSeconds,
  'completed': value.completed,
  'watchCycle': value.watchCycle,
  'updatedAtMs': value.updatedAtMs,
};

Map<String, dynamic> _streamReplicaRowJson(StreamPreferenceRecord value) =>
    <String, dynamic>{
      'localId': value.localId,
      if (value.seasonNumber != null) 'seasonNumber': value.seasonNumber,
      if (value.episodeNumber != null) 'episodeNumber': value.episodeNumber,
      ..._streamRowJson(value),
      'updatedAtMs': value.updatedAtMs,
    };

List<dynamic> _jsonList(String source) {
  try {
    final Object? decoded = jsonDecode(source);
    return decoded is List ? decoded : <dynamic>[];
  } on Object {
    return <dynamic>[];
  }
}

Set<String> _dynamicStringSet(Object? value) {
  if (value is String) return _jsonStringSet(value);
  return value is List
      ? value.map((Object? item) => '$item').toSet()
      : <String>{};
}

UserMediaField? _fieldFromPersistedName(String value) {
  for (final UserMediaField field in UserMediaField.values) {
    if (field.name == value) return field;
  }
  return null;
}

UserMediaPatch _patchFromState(
  UserMediaState state,
  Set<UserMediaField> fields,
) {
  final ProviderUserMediaState? provider =
      state.providerStates[TrackerSource.anilist];
  final ProviderUserMediaState? mal = state.providerStates[TrackerSource.mal];
  final String malRewatchKey = state.identity.mediaKind == 'manga'
      ? 'rereadValue'
      : 'rewatchValue';
  return UserMediaPatch(
    status: state.status,
    progress: state.progress,
    progressVolumes: state.progressVolumes,
    score: state.score,
    notes: state.notes,
    repeat: state.repeat,
    startedAt: state.startedAt,
    completedAt: state.completedAt,
    priority: (provider?.data['priority'] as num?)?.toInt(),
    private: provider?.data['private'] as bool?,
    hiddenFromStatusLists: provider?.data['hiddenFromStatusLists'] as bool?,
    customLists: _providerBoolMap(provider?.data['customLists']),
    advancedScores: _providerDoubleMap(provider?.data['advancedScores']),
    scoreFormat: provider?.data['scoreFormat']?.toString(),
    malPriority: (mal?.data['priority'] as num?)?.toInt(),
    malRewatchValue: (mal?.data[malRewatchKey] as num?)?.toInt(),
    malTags: _providerStringList(mal?.data['tags']),
    fields: fields,
  );
}

class _ReconciliationProposal {
  const _ReconciliationProposal({
    required this.localId,
    required this.current,
    required this.patch,
    this.incoming,
  });

  final String localId;
  final UserMediaState? current;
  final UserMediaState? incoming;
  final UserMediaPatch patch;
}

UserMediaState? _providerStateFromSnapshot(ProviderSnapshotRecord row) {
  if (row.contentHash == '__missing__') return null;
  try {
    final Object? decoded = jsonDecode(row.normalizedJson);
    return decoded is Map<String, dynamic>
        ? UserMediaState.fromJson(decoded)
        : null;
  } on Object {
    return null;
  }
}

String _stateHash(UserMediaState state) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          for (final field in providerEntryFields(
            state.source,
            mediaKind: state.identity.mediaKind,
          ))
            if (providerReturnedField(state, state.source, field))
              field.name: providerFieldValue(state, field),
        }),
      ),
    )
    .toString();

int _revisionEditTime(Object? revision) =>
    _revisionLeaves(revision).fold<int>(0, (latest, leaf) {
      final data = _jsonMap(leaf);
      final value =
          data['origin'] == 'provider' && data['editTimeVerified'] != true
          ? 0
          : (data['occurredAtMs'] as num?)?.toInt() ?? 0;
      return value > latest ? value : latest;
    });

SyncJournalEntry? _pendingForProvider(
  List<SyncJournalEntry> journal,
  MediaIdentity identity,
  TrackerSource source,
) {
  for (final SyncJournalEntry entry in journal.reversed) {
    if (entry.identity.matches(identity) && entry.tracks(source)) return entry;
  }
  return null;
}

List<SyncJournalEntry> _mergeJournalMutation(
  List<SyncJournalEntry> journal,
  SyncJournalEntry incoming,
) {
  final List<SyncJournalEntry> result = <SyncJournalEntry>[...journal];
  if (incoming.operationId != null) {
    result.add(incoming);
    return result;
  }
  final int index = result.indexWhere(
    (SyncJournalEntry current) => current.identity.matches(incoming.identity),
  );
  if (index < 0) {
    result.add(incoming);
  } else {
    result[index] = result[index].mergedWith(incoming);
  }
  return result;
}

UserMediaPatch _providerPatchBetween(
  UserMediaState? previous,
  UserMediaState incoming,
  TrackerSource source,
) {
  final changed =
      providerEntryFields(source, mediaKind: incoming.identity.mediaKind)
          .where(
            (field) =>
                providerReturnedField(incoming, source, field) &&
                (previous == null ||
                    !_providerPreviouslyObservedField(
                      previous,
                      source,
                      field,
                    ) ||
                    !_jsonEquivalent(
                      _canonicalFieldValue(
                        field.name,
                        previous,
                        membership: true,
                        favorite: false,
                      ),
                      _canonicalFieldValue(
                        field.name,
                        incoming,
                        membership: true,
                        favorite: false,
                      ),
                    )),
          )
          .toSet();
  return _patchFromState(incoming, changed);
}

bool _providerPreviouslyObservedField(
  UserMediaState state,
  TrackerSource source,
  UserMediaField field,
) {
  final known = state.providerStates[source]?.data['knownFields'];
  return known is List
      ? known.contains(field.name)
      : providerReturnedField(state, source, field);
}

AniListListStatus _canonicalStatus(LibraryStatus status) => switch (status) {
  LibraryStatus.watching => AniListListStatus.current,
  LibraryStatus.completed => AniListListStatus.completed,
  LibraryStatus.dropped => AniListListStatus.dropped,
  LibraryStatus.planned ||
  LibraryStatus.favorite ||
  LibraryStatus.local => AniListListStatus.planning,
};

UserMediaPatch _patchSubset(UserMediaPatch patch, Set<UserMediaField> fields) =>
    UserMediaPatch(
      status: patch.status,
      progress: patch.progress,
      progressVolumes: patch.progressVolumes,
      score: patch.score,
      notes: patch.notes,
      repeat: patch.repeat,
      startedAt: patch.startedAt,
      completedAt: patch.completedAt,
      priority: patch.priority,
      private: patch.private,
      hiddenFromStatusLists: patch.hiddenFromStatusLists,
      customLists: patch.customLists,
      advancedScores: patch.advancedScores,
      scoreFormat: patch.scoreFormat,
      malPriority: patch.malPriority,
      malRewatchValue: patch.malRewatchValue,
      malTags: patch.malTags,
      favorite: patch.favorite,
      delete: patch.delete,
      fields: fields,
    );

List<Object?> _revisionLeaves(Object? value) =>
    value is List ? value.expand(_revisionLeaves).toList() : <Object?>[value];

bool _baseRevisionMatches(Object? current, Object? base) =>
    _revisionLeaves(current).every(
      (value) => _revisionLeaves(base).any(
        (candidate) =>
            _jsonEquivalent(value, candidate) ||
            (_jsonMap(value)['operationId'] != null &&
                _jsonMap(value)['operationId'] ==
                    _jsonMap(candidate)['operationId']),
      ),
    );

Object? _mergeEquivalentRevisions(Object? current, Object? incoming) {
  final values = <Object?>[];
  for (final value in [
    ..._revisionLeaves(current),
    ..._revisionLeaves(incoming),
  ]) {
    if (value != null && !values.any((v) => _jsonEquivalent(v, value))) {
      values.add(value);
    }
  }
  return values.length == 1 ? values.single : values;
}

int _revisionCounter(Object? value) =>
    _revisionLeaves(value).fold(0, (count, revision) {
      final next = (_jsonMap(revision)['counter'] as num?)?.toInt() ?? 0;
      return count > next ? count : next;
    });

Iterable<String> _revisionOrigins(Object? value) =>
    _revisionLeaves(value).map((v) => '${_jsonMap(v)['origin'] ?? ''}');

bool _revisionDescendsFrom(
  Object? revision,
  String ancestor,
  String field,
  Map<String, Map<String, dynamic>> operations,
) {
  final pending = _revisionLeaves(revision)
      .map((v) => _jsonMap(v)['operationId']?.toString())
      .whereType<String>()
      .toList();
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (!visited.add(id)) continue;
    if (id == ancestor) return true;
    final base = _jsonMap(operations[id]?['baseRevisions'])[field];
    pending.addAll(
      _revisionLeaves(
        base,
      ).map((v) => _jsonMap(v)['operationId']?.toString()).whereType<String>(),
    );
  }
  return false;
}

Object? _canonicalFieldValue(
  String field,
  UserMediaState? state, {
  required bool membership,
  required bool favorite,
}) {
  if (field == 'membership') return membership;
  if (field == 'favorite') return favorite;
  if (state == null) return null;
  final mediaField = _fieldFromPersistedName(field);
  if (mediaField == null) return null;
  final value = _patchFromState(state, {mediaField}).toJson()[field];
  return switch (mediaField) {
    UserMediaField.score ||
    UserMediaField.priority ||
    UserMediaField.malPriority ||
    UserMediaField.malRewatchValue => value ?? 0,
    UserMediaField.private ||
    UserMediaField.hiddenFromStatusLists => value ?? false,
    UserMediaField.malTags => _providerStringList(value)..sort(),
    UserMediaField.startedAt ||
    UserMediaField.completedAt => providerFieldValue(state, mediaField),
    UserMediaField.customLists || UserMediaField.advancedScores => {
      if (value is Map)
        for (final entry in value.entries)
          if (entry.value != false && entry.value != 0) entry.key: entry.value,
    },
    _ => value,
  };
}

Set<String> _canonicalProviderDataKeys(TrackerSource provider) =>
    switch (provider) {
      TrackerSource.anilist => const {
        'priority',
        'private',
        'hiddenFromStatusLists',
        'customLists',
        'advancedScores',
        'scoreFormat',
      },
      TrackerSource.mal => const {
        'priority',
        'rewatchValue',
        'rereadValue',
        'tags',
      },
      TrackerSource.shikimori => const {},
    };

Object? _operationFieldValue(
  String field,
  Map<String, dynamic> operation, {
  UserMediaState? parsedState,
}) {
  if (field == 'favorite') return operation['favorite'];
  if (field == 'episodeProgress') {
    return _episodeCheckpointValue(operation['episode']);
  }
  final raw = operation['state'];
  final state =
      parsedState ??
      (raw is Map
          ? UserMediaState.fromJson(Map<String, dynamic>.from(raw))
          : null);
  return _canonicalFieldValue(
    field,
    state,
    membership: state != null,
    favorite: false,
  );
}

Object? _episodeCheckpointValue(Object? value) {
  if (value is! Map) return null;
  return <String, dynamic>{
    'season': (value['season'] as num?)?.toInt() ?? 1,
    'episode': (value['episode'] as num?)?.toDouble() ?? 1,
    'watchCycle': (value['watchCycle'] as num?)?.toInt() ?? 0,
    'positionSeconds': (value['positionSeconds'] as num?)?.toInt() ?? 0,
    'completed': value['completed'] == true,
  };
}

String? _episodeRevisionKey(Object? value) {
  if (value is! Map) return null;
  final cycle = (value['watchCycle'] as num?)?.toInt() ?? 0;
  final season = (value['season'] as num?)?.toInt() ?? 1;
  final episode = (value['episode'] as num?)?.toDouble() ?? 1;
  return 'episodeProgress:$cycle:$season:$episode';
}

Map<String, dynamic> _episodeRowCheckpoint(EpisodeStateRecord row) => {
  'season': row.seasonNumber,
  'episode': row.episodeNumber,
  'positionSeconds': row.positionSeconds,
  'durationSeconds': row.durationSeconds,
  'completed': row.completed,
  'watchCycle': row.watchCycle,
};

bool _jsonEquivalent(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              _jsonEquivalent(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (!_jsonEquivalent(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

Map<String, bool> _providerBoolMap(Object? value) {
  if (value is! Map) return <String, bool>{};
  return <String, bool>{
    for (final MapEntry<dynamic, dynamic> entry in value.entries)
      '${entry.key}': entry.value == true,
  };
}

Map<String, double> _providerDoubleMap(Object? value) {
  if (value is! Map) return <String, double>{};
  return <String, double>{
    for (final MapEntry<dynamic, dynamic> entry in value.entries)
      if (entry.value is num) '${entry.key}': (entry.value as num).toDouble(),
  };
}

List<String> _providerStringList(Object? value) {
  if (value is! List) return <String>[];
  return value
      .map((Object? item) => '$item'.trim())
      .where((String item) => item.isNotEmpty)
      .toSet()
      .toList(growable: true);
}
