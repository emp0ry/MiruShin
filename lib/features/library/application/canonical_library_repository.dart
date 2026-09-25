import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../settings/application/settings_state.dart';
import '../../tracking/data/tracking_sync_store.dart';
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
  });

  final String workspaceId;
  final String databaseName;
  final String replicaNamespace;
  final bool importsLegacyData;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryWorkspaceScope &&
          workspaceId == other.workspaceId &&
          databaseName == other.databaseName &&
          replicaNamespace == other.replicaNamespace &&
          importsLegacyData == other.importsLegacyData;

  @override
  int get hashCode => Object.hash(
    workspaceId,
    databaseName,
    replicaNamespace,
    importsLegacyData,
  );
}

class DriveSnapshotApplyResult {
  const DriveSnapshotApplyResult({
    required this.cloudEntryCount,
    required this.localEntryCount,
    required this.restoredEntries,
    required this.freshBootstrap,
  });

  final int cloudEntryCount;
  final int localEntryCount;
  final int restoredEntries;
  final bool freshBootstrap;
}

final libraryWorkspaceScopeProvider = Provider<LibraryWorkspaceScope>((
  Ref ref,
) {
  final SettingsState settings = ref.watch(settingsProvider);
  final int? activeId = settings.anilistViewerId;
  final int? ownerId = settings.canonicalLibraryOwnerAniListId;
  if (activeId != null && (ownerId == null || activeId == ownerId)) {
    return LibraryWorkspaceScope(
      workspaceId: 'anilist:$activeId',
      databaseName: 'mirushin_canonical_library_v1',
      replicaNamespace: 'anilist-$activeId',
      importsLegacyData: true,
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
  return const LibraryWorkspaceScope(
    workspaceId: 'local',
    databaseName: 'mirushin_canonical_library_v1',
    replicaNamespace: 'local',
    importsLegacyData: true,
  );
});

typedef CanonicalLibraryDatabaseFactory =
    CanonicalLibraryDatabase Function(String name);

final canonicalLibraryDatabaseFactoryProvider =
    Provider<CanonicalLibraryDatabaseFactory>(
      (Ref ref) =>
          (String name) => CanonicalLibraryDatabase(null, name),
    );

final _canonicalLibraryDatabaseByNameProvider =
    Provider.family<CanonicalLibraryDatabase, String>((Ref ref, String name) {
      final CanonicalLibraryDatabase database = ref.watch(
        canonicalLibraryDatabaseFactoryProvider,
      )(name);
      ref.onDispose(database.close);
      return database;
    });

final canonicalLibraryDatabaseProvider = Provider<CanonicalLibraryDatabase>((
  Ref ref,
) {
  final String databaseName = ref.watch(
    libraryWorkspaceScopeProvider.select(
      (LibraryWorkspaceScope scope) => scope.databaseName,
    ),
  );
  // Account switches can leave an in-flight Drive delivery using the previous
  // workspace for a few milliseconds. The per-name provider keeps that DB
  // alive until the root ProviderContainer shuts down instead of closing its
  // isolate channel underneath the operation.
  return ref.watch(_canonicalLibraryDatabaseByNameProvider(databaseName));
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

    await database
        .into(database.canonicalLibraryRecords)
        .insertOnConflictUpdate(
          CanonicalLibraryRecordsCompanion.insert(
            localId: localId,
            status: canonical.status.name,
            progress: Value<int>(canonical.progress),
            progressVolumes: Value<int>(canonical.progressVolumes),
            repeatCount: Value<int>(canonical.repeat),
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
      if (direct != null) matches.add(direct.localId);
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
    if (shellLibrary != null) return;

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
    if (shellOperation != null ||
        shellEpisode != null ||
        shellPreference != null) {
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
    final UserMediaState targetState = UserMediaState.fromJson(
      _jsonMap(targetLibrary.canonicalStateJson),
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
  }) async {
    await initialize();
    if (!completeSnapshot) {
      return ProviderReconciliationResult(
        states: await loadTrackingStates(),
        journal: journal,
      );
    }
    return database.transaction(() async {
      final DateTime now = DateTime.now().toUtc();
      final int nowMs = now.millisecondsSinceEpoch;
      final List<UserMediaState> states = await loadTrackingStates();
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
          journal: journal,
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
          journal: journal,
          requiresAccountApproval: accountCursor.cursor == 'pending',
        );
      }

      final bool forceInitialImport = accountMetadata['initialImport'] == true;
      final List<_ReconciliationProposal> safeProposals =
          <_ReconciliationProposal>[];
      final List<_ReconciliationProposal> destructiveProposals =
          <_ReconciliationProposal>[];
      final Map<String, int> confirmationCounts = <String, int>{};
      final Map<String, String> incomingHashes = <String, String>{};

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
        if (changed.fields.isEmpty &&
            (previousRow?.destructiveConfirmationCount ?? 0) > 0 &&
            current != null) {
          changed = _providerPatchBetween(current, incoming, source);
        }
        final SyncJournalEntry? pending = _pendingForProvider(
          journal,
          incoming.identity,
          source,
        );
        if (pending != null && !pending.patch.delete) {
          changed = _patchSubset(
            changed,
            <UserMediaField>{...changed.fields}
              ..removeAll(pending.patch.fields),
          );
        }

        final String hash = _stateHash(incoming);
        incomingHashes[localId] = hash;
        final Set<UserMediaField> destructiveFields = current == null
            ? <UserMediaField>{}
            : _destructiveFields(current, changed);
        final Set<UserMediaField> safeFields = <UserMediaField>{
          ...changed.fields,
        }..removeAll(destructiveFields);
        if (safeFields.isNotEmpty ||
            (current == null && changed.fields.isNotEmpty)) {
          safeProposals.add(
            _ReconciliationProposal(
              localId: localId,
              current: current,
              incoming: incoming,
              patch: _patchSubset(changed, safeFields),
            ),
          );
        }
        if (destructiveFields.isNotEmpty) {
          final int confirmations = previousRow?.contentHash == hash
              ? previousRow!.destructiveConfirmationCount + 1
              : 1;
          confirmationCounts[localId] = confirmations;
          destructiveProposals.add(
            _ReconciliationProposal(
              localId: localId,
              current: current,
              incoming: incoming,
              patch: _patchSubset(changed, destructiveFields),
              destructive: true,
              confirmationCount: confirmations,
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
          journal,
          current.identity,
          source,
        );
        if (pending != null && !pending.patch.delete) continue;
        final int confirmations = previousRow.contentHash == '__missing__'
            ? previousRow.destructiveConfirmationCount + 1
            : 1;
        confirmationCounts[previousRow.localId] = confirmations;
        incomingHashes[previousRow.localId] = '__missing__';
        destructiveProposals.add(
          _ReconciliationProposal(
            localId: previousRow.localId,
            current: current,
            patch: UserMediaPatch(delete: true),
            destructive: true,
            remove: true,
            confirmationCount: confirmations,
          ),
        );
      }

      final int totalChanges =
          safeProposals.length + destructiveProposals.length;
      final bool massQuarantine =
          !forceInitialImport &&
          (destructiveProposals.length >= 10 || totalChanges >= 25);
      if (massQuarantine) {
        final String localId = (safeProposals.isNotEmpty
            ? safeProposals.first.localId
            : destructiveProposals.first.localId);
        await database
            .into(database.libraryConflictRecords)
            .insert(
              LibraryConflictRecordsCompanion.insert(
                conflictId: _uuid.v7(),
                localId: localId,
                fieldName: 'massProviderChange',
                localValueJson: jsonEncode(<String, dynamic>{
                  'provider': source.name,
                  'accountId': accountId,
                }),
                incomingValueJson: jsonEncode(<String, dynamic>{
                  'changes': totalChanges,
                  'destructive': destructiveProposals.length,
                }),
                createdAtMs: nowMs,
              ),
            );
      }

      for (final MapEntry<String, UserMediaState> incoming
          in incomingByLocal.entries) {
        await _writeFullProviderSnapshotLocked(
          localId: incoming.key,
          source: source,
          accountId: accountId,
          state: incoming.value,
          destructiveConfirmationCount: confirmationCounts[incoming.key] ?? 0,
          fetchedAt: now,
        );
      }
      for (final ProviderSnapshotRecord previousRow in previousRows) {
        if (incomingHashes[previousRow.localId] != '__missing__') continue;
        await (database.update(database.providerSnapshotRecords)..where(
              (ProviderSnapshotRecords table) =>
                  table.snapshotId.equals(previousRow.snapshotId),
            ))
            .write(
              ProviderSnapshotRecordsCompanion(
                normalizedJson: const Value<String>('{"deleted":true}'),
                rawJson: const Value<String>('{"deleted":true}'),
                contentHash: const Value<String>('__missing__'),
                fetchedAtMs: Value<int>(nowMs),
                destructiveConfirmationCount: Value<int>(
                  confirmationCounts[previousRow.localId] ?? 1,
                ),
              ),
            );
      }

      List<SyncJournalEntry> nextJournal = <SyncJournalEntry>[...journal];
      int importedChanges = 0;
      if (!massQuarantine) {
        final List<_ReconciliationProposal> accepted =
            <_ReconciliationProposal>[
              ...safeProposals,
              ...destructiveProposals.where(
                (_ReconciliationProposal proposal) =>
                    proposal.confirmationCount >= 2,
              ),
            ];
        for (final _ReconciliationProposal proposal in accepted) {
          final UserMediaState? before = proposal.current;
          UserMediaState? after;
          if (proposal.remove) {
            states.removeWhere(
              (UserMediaState state) =>
                  state.identity.localId == proposal.localId,
            );
          } else if (before == null) {
            after = proposal.incoming;
            states.add(after!);
          } else {
            final ProviderUserMediaState? providerSnapshot =
                proposal.incoming?.providerStates[source];
            after = before.apply(proposal.patch, now, providerSource: source);
            if (providerSnapshot != null) {
              after = after.withProviderSnapshot(
                providerSnapshot,
                identity: before.identity.merge(proposal.incoming!.identity),
                mediaItem: proposal.incoming!.mediaItem,
              );
            }
            final int index = states.indexWhere(
              (UserMediaState state) =>
                  state.identity.localId == proposal.localId,
            );
            states[index] = after;
          }
          final UserMediaPatch outboundPatch = proposal.remove
              ? UserMediaPatch(delete: true)
              : proposal.patch;
          if (propagationTargets.isNotEmpty) {
            nextJournal = _mergeJournalMutation(
              nextJournal,
              SyncJournalEntry(
                identity: after?.identity ?? before!.identity,
                patch: outboundPatch,
                pendingTargets: propagationTargets,
                createdAt: now,
                updatedAt: now,
                mediaTitle: after?.mediaItem.title ?? before?.mediaItem.title,
              ),
            );
          }
          await _appendOperationLocked(
            LibraryOperationDraft(
              localId: proposal.localId,
              originKind: LibraryOriginKind.provider,
              originId: '${source.name}:$accountId',
              intent: proposal.remove
                  ? LibraryMutationIntent.remove
                  : LibraryMutationIntent.remoteImport,
              fields: <String>{
                ...proposal.patch.fields.map(
                  (UserMediaField field) => field.name,
                ),
                if (proposal.remove) 'membership',
              },
              before: <String, dynamic>{
                if (before != null) 'state': before.toJson(),
              },
              after: <String, dynamic>{
                if (after != null) 'state': after.toJson(),
              },
              targets: propagationTargets
                  .map((TrackerSource target) => target.name)
                  .toSet(),
              occurredAt: now,
              title: after?.mediaItem.title ?? before?.mediaItem.title,
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
      accountMetadata['lastEntryCount'] = incomingByLocal.length;
      accountMetadata['lastSyncAt'] = now.toIso8601String();
      accountMetadata['quarantined'] = massQuarantine;
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
        quarantined: massQuarantine,
        importedChanges: importedChanges,
        destructiveChangesPending: destructiveProposals
            .where(
              (_ReconciliationProposal proposal) =>
                  proposal.confirmationCount < 2,
            )
            .length,
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

  Future<List<SyncJournalEntry>> loadJournal() =>
      _loadBucket('tracking.journal', SyncJournalEntry.fromJson);

  Future<void> saveJournal(List<SyncJournalEntry> values) => _writeBucket(
    'tracking.journal',
    values.map((SyncJournalEntry value) => value.toJson()).toList(),
  );

  Future<void> updateTrackerDelivery({
    required MediaIdentity identity,
    required TrackerSource target,
    required String state,
    String? error,
  }) async {
    await initialize();
    await database.transaction(() async {
      final String? localId = await _localIdForIdentityLocked(identity);
      if (localId == null) return;
      final List<LibraryOperationRecord> operations =
          await (database.select(database.libraryOperationRecords)..where(
                (LibraryOperationRecords table) =>
                    table.localId.equals(localId),
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
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final OutboxDeliveryRecord delivery in deliveries) {
        await (database.update(database.outboxDeliveryRecords)..where(
              (OutboxDeliveryRecords table) =>
                  table.deliveryId.equals(delivery.deliveryId),
            ))
            .write(
              OutboxDeliveryRecordsCompanion(
                state: Value<String>(state),
                attempts: Value<int>(
                  delivery.attempts + (state == 'retry' ? 1 : 0),
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
      }
    });
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
      for (final MapEntry<String, Map<String, String>> item in ledger.entries) {
        if (item.value['state'] != 'confirmed') continue;
        final OutboxDeliveryRecord? delivery =
            await (database.select(database.outboxDeliveryRecords)..where(
                  (OutboxDeliveryRecords table) =>
                      table.deliveryId.equals(item.key),
                ))
                .getSingleOrNull();
        if (delivery == null || delivery.target == 'drive') continue;
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
                state: const Value<String>('confirmed'),
                deliveredAtMs: Value<int>(
                  delivery.deliveredAtMs ?? confirmedAt,
                ),
                confirmedAtMs: Value<int>(confirmedAt),
                lastError: const Value<String?>(null),
              ),
            );
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

  Future<Map<TrackerSource, TrackerProviderHealth>> loadHealth() async {
    await initialize();
    final List<ProviderHealthRecord> rows = await database
        .select(database.providerHealthRecords)
        .get();
    final Map<TrackerSource, TrackerProviderHealth> result =
        <TrackerSource, TrackerProviderHealth>{};
    for (final ProviderHealthRecord row in rows) {
      try {
        final Object? decoded = jsonDecode(row.healthJson);
        if (decoded is! Map<String, dynamic>) continue;
        final TrackerProviderHealth value = TrackerProviderHealth.fromJson(
          decoded,
        );
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
                provider: value.provider.name,
                healthJson: jsonEncode(value.toJson()),
                updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      }
    });
  }

  Future<void> commitTrackingMutation({
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
      final List<UserMediaState> beforeStates = await loadTrackingStates();
      final List<LocalMediaFavoriteState> beforeFavorites =
          await loadFavorites();
      UserMediaState? before;
      for (final UserMediaState state in beforeStates) {
        if (state.identity.matches(identity)) {
          before = state;
          break;
        }
      }
      await _saveTrackingStatesLocked(states, tombstoneMissing: true);
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

      UserMediaState? after;
      for (final UserMediaState state in states) {
        if (state.identity.matches(identity)) {
          after = state;
          break;
        }
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
      final UserMediaState? canonicalAfter = after?.withIdentity(
        canonicalIdentity(after.identity),
      );
      bool favoriteValue(
        List<LocalMediaFavoriteState> values,
        MediaIdentity target,
      ) {
        for (final LocalMediaFavoriteState value in values) {
          if (value.identity.matches(target)) return value.favorite;
        }
        return false;
      }

      final bool beforeFavorite = favoriteValue(beforeFavorites, identity);
      final bool afterFavorite = favoriteValue(favorites, identity);
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
      await _appendOperationLocked(
        LibraryOperationDraft(
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
            ...patch.fields.map((UserMediaField field) => field.name),
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
          targets: targets.map((TrackerSource source) => source.name).toSet(),
          occurredAt: occurredAt,
          title:
              mediaTitle ?? after?.mediaItem.title ?? before?.mediaItem.title,
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

  Future<DriveReplicaSegment?> buildPendingDriveSegment({
    int limit = 200,
  }) async {
    await initialize();
    final List<OutboxDeliveryRecord> pending =
        await (database.select(database.outboxDeliveryRecords)
              ..where(
                (OutboxDeliveryRecords table) =>
                    table.target.equals('drive') &
                    table.state.isIn(const <String>['pending', 'retry']),
              )
              ..orderBy(<OrderClauseGenerator<OutboxDeliveryRecords>>[
                (OutboxDeliveryRecords table) =>
                    OrderingTerm.asc(table.deliveryId),
              ])
              ..limit(limit))
            .get();
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
    return DriveLibrarySnapshot(
      snapshotId: _uuid.v7(),
      deviceId: await deviceId(),
      createdAt: DateTime.now().toUtc(),
      replicaNamespace: replicaNamespace,
      media: media.map(_mediaRowJson).toList(growable: false),
      libraryEntries: library.map(_libraryRowJson).toList(growable: false),
      providerBindings: bindings
          .map(_providerBindingRowJson)
          .toList(growable: false),
      providerSnapshots: providerSnapshots
          .map(_providerSnapshotRowJson)
          .toList(growable: false),
      episodeStates: episodes.map(_episodeRowJson).toList(growable: false),
      streamPreferences: streams
          .map(_streamReplicaRowJson)
          .toList(growable: false),
      operations: operations.map(_operationRowJson).toList(growable: false),
    );
  }

  Future<bool> hasAppliedDriveSnapshot(String checksum) async {
    await initialize();
    final SyncCursorRecord? cursor =
        await (database.select(database.syncCursorRecords)..where(
              (SyncCursorRecords table) =>
                  table.scope.equals('drive.snapshot:$replicaNamespace'),
            ))
            .getSingleOrNull();
    return cursor?.cursor == checksum;
  }

  /// Atomically merges a complete Drive checkpoint into the current
  /// workspace. A fresh device must end with exactly the advertised number of
  /// active entries or the whole transaction is rolled back.
  Future<DriveSnapshotApplyResult> applyDriveSnapshot(
    DriveLibrarySnapshot snapshot, {
    void Function(int completed, int total)? onProgress,
  }) async {
    await initialize();
    if (snapshot.replicaNamespace != replicaNamespace &&
        !(importsLegacyData && snapshot.replicaNamespace == 'legacy')) {
      throw StateError(
        'Drive library workspace mismatch: '
        '${snapshot.replicaNamespace} != $replicaNamespace',
      );
    }
    return database.transaction(() async {
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
      final int total = snapshot.media.length + snapshot.libraryEntries.length;
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
        completed += 1;
        onProgress?.call(completed, total);
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
        freshBootstrap: freshBootstrap,
      );
    });
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
        if (duplicate != null) continue;

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
        final MediaIdentity incomingIdentity =
            incomingAfter?.identity ??
            incomingBefore?.identity ??
            MediaIdentity(
              localId: remoteLocalId,
              kind: '${mediaRow['mediaKind'] ?? ''}' == 'manga'
                  ? 'manga'
                  : null,
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
        for (final String field in fields) {
          if (_jsonEquivalent(currentRevisions[field], baseRevisions[field]) ||
              _jsonEquivalent(
                currentRevisions[field],
                resultingRevisions[field],
              )) {
            accepted.add(field);
          } else {
            await database
                .into(database.libraryConflictRecords)
                .insert(
                  LibraryConflictRecordsCompanion.insert(
                    conflictId: _uuid.v7(),
                    localId: localId,
                    fieldName: field,
                    localValueJson: jsonEncode(current?.toJson()),
                    incomingValueJson: jsonEncode(incomingAfter?.toJson()),
                    localOperationId: Value<String?>(
                      _jsonMap(
                        currentRevisions[field],
                      )['operationId']?.toString(),
                    ),
                    incomingOperationId: Value<String?>(operationId),
                    createdAtMs: importedAt.millisecondsSinceEpoch,
                  ),
                );
          }
        }
        if (accepted.isEmpty) continue;

        UserMediaState? next = current;
        final bool removesMembership =
            accepted.contains('membership') && incomingAfter == null;
        if (removesMembership) {
          if (currentRow != null) {
            await (database.update(database.canonicalLibraryRecords)..where(
                  (CanonicalLibraryRecords table) =>
                      table.localId.equals(localId),
                ))
                .write(
                  CanonicalLibraryRecordsCompanion(
                    inLibrary: const Value<bool>(false),
                    tombstonedAtMs: Value<int>(
                      importedAt.millisecondsSinceEpoch,
                    ),
                    updatedAtMs: Value<int>(importedAt.millisecondsSinceEpoch),
                  ),
                );
          }
          next = null;
        } else if (incomingAfter != null) {
          final MediaIdentity translated = MediaIdentity(
            localId: localId,
            kind: incomingAfter.identity.mediaKind,
            anilistId: incomingAfter.identity.anilistId,
            malId: incomingAfter.identity.malId,
            shikimoriId: incomingAfter.identity.shikimoriId,
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
              importedAt,
            );
            for (final ProviderUserMediaState provider
                in incomingAfter.providerStates.values) {
              next = next!.withProviderSnapshot(
                provider,
                identity: translated,
                mediaItem: incomingAfter.mediaItem,
              );
            }
          }
          await _upsertTrackingStateLocked(next!);
        }
        final Map<String, dynamic> nextRevisions = <String, dynamic>{
          ...currentRevisions,
        };
        for (final String field in accepted) {
          nextRevisions[field] = resultingRevisions[field];
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
        final UserMediaPatch outboundPatch = removesMembership
            ? UserMediaPatch(delete: true)
            : incomingAfter == null
            ? UserMediaPatch(fields: acceptedMediaFields)
            : _patchFromState(incomingAfter, acceptedMediaFields);
        if (outboundTargets.isNotEmpty &&
            (removesMembership || acceptedMediaFields.isNotEmpty)) {
          journal = _mergeJournalMutation(
            journal,
            SyncJournalEntry(
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
                fieldsJson: jsonEncode(accepted.toList()..sort()),
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
                occurredAtMs:
                    DateTime.tryParse(
                      '${remoteOperation['occurredAt'] ?? ''}',
                    )?.millisecondsSinceEpoch ??
                    segment.createdAt.millisecondsSinceEpoch,
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

      await _importDriveEpisodeRows(segment, translatedIds, importedAt);
      await _importDriveStreamRows(segment, translatedIds, importedAt);
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
    DateTime importedAt,
  ) async {
    for (final Map<String, dynamic> row in segment.episodeStates) {
      final String? localId = translatedIds['${row['localId'] ?? ''}'];
      if (localId == null) continue;
      final int season = (row['seasonNumber'] as num?)?.toInt() ?? 1;
      final double episode = (row['episodeNumber'] as num?)?.toDouble() ?? 0;
      final int watchCycle = (row['watchCycle'] as num?)?.toInt() ?? 0;
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
    final String operationId = _uuid.v7();
    final String currentDeviceId = await deviceId();
    final Set<String> deliveryTargets = <String>{'drive', ...draft.targets};
    final CanonicalLibraryRecord? entry =
        await (database.select(database.canonicalLibraryRecords)..where(
              (CanonicalLibraryRecords table) =>
                  table.localId.equals(draft.localId),
            ))
            .getSingleOrNull();
    final Map<String, dynamic> revisions = _jsonMap(entry?.fieldRevisionsJson);
    final Map<String, dynamic> beforeRevisions = Map<String, dynamic>.from(
      revisions,
    );
    for (final String field in draft.fields) {
      final Map<String, dynamic> previous = _jsonMap(revisions[field]);
      revisions[field] = <String, dynamic>{
        'counter': ((previous['counter'] as num?)?.toInt() ?? 0) + 1,
        'deviceId': currentDeviceId,
        'operationId': operationId,
        'origin': draft.originKind.name,
      };
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
            ),
          );
    }
    return operationId;
  }

  Stream<List<CanonicalLibraryConflict>> watchConflicts() {
    final query = database.select(database.libraryConflictRecords)
      ..where((LibraryConflictRecords table) => table.state.equals('open'))
      ..orderBy(<OrderClauseGenerator<LibraryConflictRecords>>[
        (LibraryConflictRecords table) => OrderingTerm.desc(table.createdAtMs),
      ]);
    return query.watch().map(
      (List<LibraryConflictRecord> rows) => rows
          .map(
            (LibraryConflictRecord row) => CanonicalLibraryConflict(
              conflictId: row.conflictId,
              localId: row.localId,
              fieldName: row.fieldName,
              localValue: _decodeJsonValue(row.localValueJson),
              incomingValue: _decodeJsonValue(row.incomingValueJson),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                row.createdAtMs,
                isUtc: true,
              ),
              state: row.state,
            ),
          )
          .toList(growable: false),
    );
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
      final UserMediaState? selected = takeIncoming ? incoming : current;
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

      final Set<UserMediaField> fields = field == null
          ? const <UserMediaField>{}
          : <UserMediaField>{field};
      final UserMediaPatch patch = next == null
          ? UserMediaPatch(delete: true)
          : membership
          ? UserMediaPatch(
              fields: const <UserMediaField>{UserMediaField.status},
              status: next.status,
            )
          : _patchFromState(next, fields);
      final MediaIdentity? resolvedIdentity =
          next?.identity ?? current?.identity ?? incoming?.identity;
      if (resolvedIdentity == null) {
        await _markConflictResolvedLocked(conflictId);
        return null;
      }
      if (trackerTargets.isNotEmpty &&
          (patch.delete || patch.touchesLibraryState)) {
        List<SyncJournalEntry> journal = await loadJournal();
        journal = _mergeJournalMutation(
          journal,
          SyncJournalEntry(
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
      final String operationId = await _appendOperationLocked(
        LibraryOperationDraft(
          localId: conflict.localId,
          originKind: LibraryOriginKind.user,
          intent: next == null
              ? LibraryMutationIntent.remove
              : LibraryMutationIntent.edit,
          fields: <String>{conflict.fieldName},
          before: <String, dynamic>{
            if (current != null) 'state': current.toJson(),
          },
          after: <String, dynamic>{if (next != null) 'state': next.toJson()},
          targets: <String>{
            'drive',
            ...trackerTargets.map((TrackerSource value) => value.name),
          },
          occurredAt: now,
          title: next?.mediaItem.title ?? current?.mediaItem.title,
        ),
      );
      await _markConflictResolvedLocked(conflictId);
      return operationId;
    });
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
      for (final LibraryOperationRecord row in rows) {
        final List<OutboxDeliveryRecord> deliveries =
            await (database.select(database.outboxDeliveryRecords)..where(
                  (OutboxDeliveryRecords table) =>
                      table.operationId.equals(row.operationId),
                ))
                .get();
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
      if (trackerTargets.isNotEmpty &&
          (patch.delete || patch.fields.isNotEmpty)) {
        List<SyncJournalEntry> journal = await loadJournal();
        journal = _mergeJournalMutation(
          journal,
          SyncJournalEntry(
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
    final String? localId = await _localIdForAlias(mediaId);
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
      final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final String id = '$localId:$watchCycle:$season:$episode';
      final EpisodeStateRecord? previous =
          await (database.select(database.episodeStateRecords)..where(
                (EpisodeStateRecords table) => table.episodeStateId.equals(id),
              ))
              .getSingleOrNull();
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
                  'completed': previous.completed,
                },
            },
            after: <String, dynamic>{
              'episode': <String, dynamic>{
                'season': season,
                'episode': episode,
                'positionSeconds': positionSeconds,
                'completed': completed,
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
    final CanonicalMediaRecord? direct =
        await (database.select(database.canonicalMediaRecords)..where(
              (CanonicalMediaRecords table) => table.localId.equals(alias),
            ))
            .getSingleOrNull();
    if (direct != null) return direct.localId;
    final MediaAliasRecord? mapped =
        await (database.select(database.mediaAliasRecords)
              ..where((MediaAliasRecords table) => table.alias.equals(alias)))
            .getSingleOrNull();
    return mapped?.localId;
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
    await database
        .into(database.legacyBucketRecords)
        .insertOnConflictUpdate(
          LegacyBucketRecordsCompanion.insert(
            bucket: name,
            valueJson: jsonEncode(value),
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

UserMediaState? _stateFromConflictJson(String source) {
  final Object? decoded = _decodeJsonValue(source);
  if (decoded is! Map) return null;
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
    this.destructive = false,
    this.remove = false,
    this.confirmationCount = 0,
  });

  final String localId;
  final UserMediaState? current;
  final UserMediaState? incoming;
  final UserMediaPatch patch;
  final bool destructive;
  final bool remove;
  final int confirmationCount;
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

String _stateHash(UserMediaState state) =>
    sha256.convert(utf8.encode(jsonEncode(state.toJson()))).toString();

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
  final ProviderUserMediaState? provider = incoming.providerStates[source];
  final Set<UserMediaField> supported = switch (source) {
    TrackerSource.anilist => <UserMediaField>{
      UserMediaField.status,
      UserMediaField.progress,
      UserMediaField.progressVolumes,
      UserMediaField.score,
      UserMediaField.notes,
      UserMediaField.repeat,
      UserMediaField.startedAt,
      UserMediaField.completedAt,
      UserMediaField.malPriority,
      UserMediaField.private,
      UserMediaField.hiddenFromStatusLists,
      UserMediaField.customLists,
      UserMediaField.advancedScores,
    },
    TrackerSource.mal => <UserMediaField>{
      UserMediaField.status,
      UserMediaField.progress,
      UserMediaField.progressVolumes,
      UserMediaField.score,
      UserMediaField.notes,
      UserMediaField.repeat,
      UserMediaField.startedAt,
      UserMediaField.completedAt,
      UserMediaField.priority,
      UserMediaField.malRewatchValue,
      UserMediaField.malTags,
    },
    TrackerSource.shikimori => <UserMediaField>{
      UserMediaField.status,
      UserMediaField.progress,
      UserMediaField.progressVolumes,
      UserMediaField.score,
      UserMediaField.notes,
      UserMediaField.repeat,
    },
  };
  final Set<UserMediaField> changed = <UserMediaField>{};
  bool differs(UserMediaField field, Object? before, Object? after) {
    if (!supported.contains(field)) return false;
    return previous == null || !_jsonEquivalent(before, after);
  }

  if (differs(
    UserMediaField.status,
    previous?.status.name,
    incoming.status.name,
  )) {
    changed.add(UserMediaField.status);
  }
  if (differs(UserMediaField.progress, previous?.progress, incoming.progress)) {
    changed.add(UserMediaField.progress);
  }
  if (differs(
    UserMediaField.progressVolumes,
    previous?.progressVolumes,
    incoming.progressVolumes,
  )) {
    changed.add(UserMediaField.progressVolumes);
  }
  if (differs(UserMediaField.score, previous?.score, incoming.score)) {
    changed.add(UserMediaField.score);
  }
  if (differs(UserMediaField.notes, previous?.notes, incoming.notes)) {
    changed.add(UserMediaField.notes);
  }
  if (differs(UserMediaField.repeat, previous?.repeat, incoming.repeat)) {
    changed.add(UserMediaField.repeat);
  }
  if (differs(
    UserMediaField.startedAt,
    previous?.startedAt?.toIso8601String(),
    incoming.startedAt?.toIso8601String(),
  )) {
    changed.add(UserMediaField.startedAt);
  }
  if (differs(
    UserMediaField.completedAt,
    previous?.completedAt?.toIso8601String(),
    incoming.completedAt?.toIso8601String(),
  )) {
    changed.add(UserMediaField.completedAt);
  }
  final ProviderUserMediaState? oldProvider = previous?.providerStates[source];
  final int priority = (provider?.data['priority'] as num?)?.toInt() ?? 0;
  final int previousPriority =
      (oldProvider?.data['priority'] as num?)?.toInt() ?? 0;
  if (differs(UserMediaField.priority, previousPriority, priority)) {
    changed.add(UserMediaField.priority);
  }
  final int malPriority = (provider?.data['priority'] as num?)?.toInt() ?? 0;
  final int previousMalPriority =
      (oldProvider?.data['priority'] as num?)?.toInt() ?? 0;
  if (differs(UserMediaField.malPriority, previousMalPriority, malPriority)) {
    changed.add(UserMediaField.malPriority);
  }
  final bool private = provider?.data['private'] == true;
  final bool previousPrivate = oldProvider?.data['private'] == true;
  if (differs(UserMediaField.private, previousPrivate, private)) {
    changed.add(UserMediaField.private);
  }
  final bool hidden = provider?.data['hiddenFromStatusLists'] == true;
  final bool previousHidden =
      oldProvider?.data['hiddenFromStatusLists'] == true;
  if (differs(UserMediaField.hiddenFromStatusLists, previousHidden, hidden)) {
    changed.add(UserMediaField.hiddenFromStatusLists);
  }
  final Map<String, bool> customLists = _providerBoolMap(
    provider?.data['customLists'],
  );
  final Map<String, bool> previousCustomLists = _providerBoolMap(
    oldProvider?.data['customLists'],
  );
  if (differs(UserMediaField.customLists, previousCustomLists, customLists)) {
    changed.add(UserMediaField.customLists);
  }
  final Map<String, double> advancedScores = _providerDoubleMap(
    provider?.data['advancedScores'],
  );
  final Map<String, double> previousAdvancedScores = _providerDoubleMap(
    oldProvider?.data['advancedScores'],
  );
  if (differs(
    UserMediaField.advancedScores,
    previousAdvancedScores,
    advancedScores,
  )) {
    changed.add(UserMediaField.advancedScores);
  }
  final String malRewatchKey = incoming.identity.mediaKind == 'manga'
      ? 'rereadValue'
      : 'rewatchValue';
  final int malRewatchValue =
      (provider?.data[malRewatchKey] as num?)?.toInt() ?? 0;
  final int previousMalRewatchValue =
      (oldProvider?.data[malRewatchKey] as num?)?.toInt() ?? 0;
  if (differs(
    UserMediaField.malRewatchValue,
    previousMalRewatchValue,
    malRewatchValue,
  )) {
    changed.add(UserMediaField.malRewatchValue);
  }
  final List<String> malTags = _providerStringList(provider?.data['tags'])
    ..sort();
  final List<String> previousMalTags = _providerStringList(
    oldProvider?.data['tags'],
  )..sort();
  if (differs(UserMediaField.malTags, previousMalTags, malTags)) {
    changed.add(UserMediaField.malTags);
  }
  return UserMediaPatch(
    status: incoming.status,
    progress: incoming.progress,
    progressVolumes: incoming.progressVolumes,
    score: incoming.score,
    notes: incoming.notes,
    repeat: incoming.repeat,
    startedAt: incoming.startedAt,
    completedAt: incoming.completedAt,
    priority: priority,
    private: private,
    hiddenFromStatusLists: hidden,
    customLists: customLists,
    advancedScores: advancedScores,
    malPriority: malPriority,
    malRewatchValue: malRewatchValue,
    malTags: malTags,
    fields: changed,
  );
}

Set<UserMediaField> _destructiveFields(
  UserMediaState current,
  UserMediaPatch patch,
) {
  final Set<UserMediaField> result = <UserMediaField>{};
  if (patch.touches(UserMediaField.progress) &&
      (patch.progress ?? 0) < current.progress) {
    result.add(UserMediaField.progress);
  }
  if (patch.touches(UserMediaField.progressVolumes) &&
      (patch.progressVolumes ?? 0) < current.progressVolumes) {
    result.add(UserMediaField.progressVolumes);
  }
  if (patch.touches(UserMediaField.repeat) &&
      (patch.repeat ?? 0) < current.repeat) {
    result.add(UserMediaField.repeat);
  }
  if (patch.touches(UserMediaField.status) &&
      _statusRank(patch.status ?? current.status) <
          _statusRank(current.status)) {
    result.add(UserMediaField.status);
  }
  if (patch.touches(UserMediaField.startedAt) &&
      current.startedAt != null &&
      patch.startedAt == null) {
    result.add(UserMediaField.startedAt);
  }
  if (patch.touches(UserMediaField.completedAt) &&
      current.completedAt != null &&
      patch.completedAt == null) {
    result.add(UserMediaField.completedAt);
  }
  return result;
}

int _statusRank(AniListListStatus status) => switch (status) {
  AniListListStatus.planning => 0,
  AniListListStatus.current => 1,
  AniListListStatus.paused => 1,
  AniListListStatus.dropped => 1,
  AniListListStatus.repeating => 2,
  AniListListStatus.completed => 3,
};

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

bool _jsonEquivalent(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

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
