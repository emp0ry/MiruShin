part of 'canonical_library_repository.dart';

bool _isPlaybackRevisionField(String key) =>
    key == 'episodeProgress' ||
    key.startsWith('episodeProgress:') ||
    key == 'streamPreference';

/// A separate projection of the canonical checkpoint tables. None of these
/// methods loads library entries, provider snapshots, or the operation graph.
extension PlaybackLibraryRepository on CanonicalLibraryRepository {
  Stream<int> watchPendingCloudDeliveryCount({required bool includeLibrary}) {
    return Stream<void>.fromFuture(initialize()).asyncExpand((_) {
      final table = database.outboxDeliveryRecords;
      final count = table.deliveryId.count();
      return (database.selectOnly(table)
            ..addColumns([count])
            ..where(
              table.target.isIn([
                    'drive.playback',
                    if (includeLibrary) 'drive',
                  ]) &
                  table.state.isIn(['pending', 'retry']),
            ))
          .watchSingle()
          .map((row) => row.read(count) ?? 0)
          .distinct();
    });
  }

  Future<List<String>> pendingPlaybackDeliveryIds() async {
    await initialize();
    final rows =
        await (database.select(database.outboxDeliveryRecords)..where(
              (t) =>
                  t.target.equals('drive.playback') &
                  t.state.isIn(['pending', 'retry']),
            ))
            .get();
    return rows.map((row) => row.deliveryId).toList();
  }

  Future<String?> lastPlaybackChecksum() async {
    await initialize();
    return (await (database.select(database.syncCursorRecords)
              ..where((t) => t.scope.equals('playback.synced.v1')))
            .getSingleOrNull())
        ?.cursor;
  }

  Future<void> markPlaybackSynced(
    String checksum, {
    required List<String> deliveryIds,
  }) async {
    await initialize();
    await database.transaction(() async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      // Chunk IDs to stay below SQLite's bind parameter limit.
      for (var offset = 0; offset < deliveryIds.length; offset += 200) {
        await (database.update(database.outboxDeliveryRecords)..where(
              (t) =>
                  t.target.equals('drive.playback') &
                  t.deliveryId.isIn(deliveryIds.skip(offset).take(200)),
            ))
            .write(
              OutboxDeliveryRecordsCompanion(
                state: const Value('confirmed'),
                deliveredAtMs: Value(now),
                confirmedAtMs: Value(now),
              ),
            );
      }
      await _writePlaybackCursor('playback.synced.v1', checksum);
    });
  }

  Future<Map<String, String>> processedPlaybackChecksums() async {
    await initialize();
    const prefix = 'playback.pulled.v1:';
    final rows = await (database.select(
      database.syncCursorRecords,
    )..where((t) => t.scope.like('$prefix%'))).get();
    return {
      for (final row in rows) row.scope.substring(prefix.length): row.cursor,
    };
  }

  Future<void> _writePlaybackCursor(String scope, String value) => database
      .into(database.syncCursorRecords)
      .insertOnConflictUpdate(
        SyncCursorRecordsCompanion.insert(
          scope: scope,
          cursor: value,
          updatedAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );

  Future<PlaybackReplicaSnapshot> buildPlaybackSnapshot() async {
    await initialize();
    return database.transaction(() async {
      final episodes = await (database.select(
        database.episodeStateRecords,
      )..orderBy([(t) => OrderingTerm.asc(t.episodeStateId)])).get();
      final streams = await (database.select(
        database.streamPreferenceRecords,
      )..orderBy([(t) => OrderingTerm.asc(t.preferenceId)])).get();
      final mediaRows = await database
          .customSelect(
            'SELECT m.local_id, m.media_kind, l.field_revisions_json, '
            "CASE WHEN json_valid(m.media_json) THEN json_extract(m.media_json, '\$.id') END AS media_id, "
            "CASE WHEN json_valid(m.media_json) THEN json_extract(m.media_json, '\$.type') END AS media_type "
            'FROM canonical_media_records m '
            'LEFT JOIN canonical_library_records l ON l.local_id = m.local_id '
            'WHERE EXISTS (SELECT 1 FROM episode_state_records e WHERE e.local_id = m.local_id) '
            'OR EXISTS (SELECT 1 FROM stream_preference_records s WHERE s.local_id = m.local_id) '
            'ORDER BY m.local_id',
            readsFrom: {
              database.canonicalMediaRecords,
              database.canonicalLibraryRecords,
              database.episodeStateRecords,
              database.streamPreferenceRecords,
            },
          )
          .get();
      final localDevice = await deviceId();
      final media = <Map<String, dynamic>>[];
      final revisions = <String, Map<String, dynamic>>{};
      for (final row in mediaRows) {
        final id = row.read<String>('local_id');
        revisions[id] = _jsonMap(
          row.readNullable<String>('field_revisions_json'),
        );
        // Extract identifiers inside SQLite instead of expanding artwork,
        // descriptions, seasons, or other cached metadata on Flutter's isolate.
        final mediaId = row.data['media_id']?.toString() ?? id;
        final bindings =
            await (database.select(database.providerBindingRecords)..where(
                  (t) => t.localId.equals(id) & t.quarantined.equals(false),
                ))
                .get();
        int? binding(String provider) => bindings
            .where((b) => b.provider == provider)
            .map((b) => b.externalMediaId)
            .firstOrNull;
        final identity = MediaIdentity(
          localId: id,
          kind: row.read<String>('media_kind'),
          anilistId: binding('anilist'),
          malId: binding('mal'),
          shikimoriId: binding('shikimori'),
        );
        final safeAliases = <String>{
          for (final binding in bindings) ...[
            '${binding.provider}:${binding.externalMediaId}',
            if (identity.mediaKind == 'manga')
              '${binding.provider}:manga:${binding.externalMediaId}',
          ],
        };
        final trackerId = RegExp(
          r'^(anilist|mal|shikimori):',
        ).hasMatch(mediaId);
        media.add({
          'identity': identity.toJson(),
          'mediaId': trackerId && !safeAliases.contains(mediaId) ? id : mediaId,
          'mediaType': row.data['media_type']?.toString() ?? 'anime',
        });
      }

      final bases = <String, Object?>{};
      Future<Object?> base(Object? revision, String field) async {
        final operationId = _jsonMap(revision)['operationId']?.toString();
        if (operationId == null) return null;
        final key = '$operationId:$field';
        if (!bases.containsKey(key)) {
          final operation = await database
              .customSelect(
                'SELECT CASE WHEN json_valid(base_revisions_json) '
                "THEN json_extract(base_revisions_json, '\$.$field') END AS revision "
                'FROM library_operation_records WHERE operation_id = ?',
                variables: [Variable<String>(operationId)],
                readsFrom: {database.libraryOperationRecords},
              )
              .getSingleOrNull();
          final value = operation?.data['revision'];
          bases[key] = value is String ? jsonDecode(value) : value;
        }
        return bases[key];
      }

      Map<String, dynamic> legacy(String key, int at) => {
        'counter': 0,
        'deviceId': localDevice,
        'operationId': 'legacy:$key:$at',
        'origin': 'migration',
        'occurredAtMs': at,
        'editTimeVerified': true,
      };
      final episodeValues = <Map<String, dynamic>>[];
      for (final row in episodes) {
        final key =
            'episodeProgress:${row.watchCycle}:${row.seasonNumber}:${row.episodeNumber}';
        final storedRevision = revisions[row.localId]?[key];
        // SQLite keeps fine-grained positions between historical checkpoints.
        // Give those values their own actual edit time, rather than attaching
        // a new value to an older operation's revision.
        final fineGrained =
            storedRevision == null ||
            _revisionEditTime(storedRevision) < row.updatedAtMs;
        final revision = fineGrained
            ? legacy(row.episodeStateId, row.updatedAtMs)
            : storedRevision;
        episodeValues.add({
          'localId': row.localId,
          'seasonNumber': row.seasonNumber,
          'episodeNumber': row.episodeNumber,
          'positionSeconds': row.positionSeconds,
          'durationSeconds': row.durationSeconds,
          'completed': row.completed,
          'watchCycle': row.watchCycle,
          'updatedAtMs': row.updatedAtMs,
          'revision': revision,
          'baseRevision': fineGrained && storedRevision != null
              ? storedRevision
              : await base(revision, 'episodeProgress'),
        });
      }
      final streamValues = <Map<String, dynamic>>[];
      for (final row in streams) {
        final revision =
            revisions[row.localId]?['streamPreference'] ??
            legacy(row.preferenceId, row.updatedAtMs);
        streamValues.add({
          'localId': row.localId,
          'seasonNumber': row.seasonNumber,
          'episodeNumber': row.episodeNumber,
          ..._streamRowJson(row),
          'updatedAtMs': row.updatedAtMs,
          'revision': revision,
        });
      }
      return PlaybackReplicaSnapshot(
        replicaNamespace: replicaNamespace,
        deviceId: localDevice,
        media: media,
        episodes: episodeValues,
        streamPreferences: streamValues,
      );
    });
  }

  Future<void> applyPlaybackSnapshot(PlaybackReplicaSnapshot snapshot) async {
    await initialize();
    if (snapshot.replicaNamespace != replicaNamespace) {
      throw StateError('Playback workspace mismatch.');
    }
    await database.transaction(() async {
      final scope = 'playback.pulled.v1:${snapshot.fileName}';
      final processed = await (database.select(
        database.syncCursorRecords,
      )..where((t) => t.scope.equals(scope))).getSingleOrNull();
      if (processed?.cursor == snapshot.checksum) return;
      final translated = <String, String>{};
      for (final row in snapshot.media) {
        final identity = MediaIdentity.fromJson(_jsonMap(row['identity']));
        if (identity.localId.isEmpty) {
          throw const FormatException('Missing playback identity.');
        }
        final placeholder = _placeholderMedia(
          identity,
          mediaId: row['mediaId'] as String?,
        );
        final media = MediaItem.fromJson({
          ...placeholder.toJson(),
          'type': row['mediaType'],
        });
        final id = await _resolveOrCreateMediaLocked(
          identity: identity,
          mediaItem: media,
        );
        translated[identity.localId] = id;
        final existing = await (database.select(
          database.canonicalLibraryRecords,
        )..where((t) => t.localId.equals(id))).getSingleOrNull();
        if (existing == null) {
          await _ensureHiddenTrackingRowLocked(
            id,
            media,
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
        }
      }
      for (final incoming in snapshot.episodes) {
        final localId = translated[incoming['localId']];
        if (localId == null) {
          throw const FormatException('Unknown playback identity.');
        }
        final season = (incoming['seasonNumber'] as num).toInt();
        final episode = (incoming['episodeNumber'] as num).toDouble();
        final cycle = (incoming['watchCycle'] as num).toInt();
        final at = (incoming['updatedAtMs'] as num).toInt();
        if (!episode.isFinite ||
            episode < 0 ||
            season < 0 ||
            cycle < 0 ||
            at < 0) {
          throw const FormatException('Invalid playback checkpoint.');
        }
        final id = '$localId:$cycle:$season:$episode';
        final current = await (database.select(
          database.episodeStateRecords,
        )..where((t) => t.episodeStateId.equals(id))).getSingleOrNull();
        final library = await (database.select(
          database.canonicalLibraryRecords,
        )..where((t) => t.localId.equals(localId))).getSingle();
        final revisions = _jsonMap(library.fieldRevisionsJson);
        final key = 'episodeProgress:$cycle:$season:$episode';
        final revision = incoming['revision'];
        final storedRevision = revisions[key];
        final currentRevision =
            current != null &&
                (storedRevision == null ||
                    _revisionEditTime(storedRevision) < current.updatedAtMs)
            ? <String, dynamic>{
                'operationId':
                    'legacy:${current.episodeStateId}:${current.updatedAtMs}',
                'deviceId': await deviceId(),
                'origin': 'migration',
                'occurredAtMs': current.updatedAtMs,
              }
            : storedRevision;
        final checkpoint = <String, dynamic>{
          'season': season,
          'episode': episode,
          'watchCycle': cycle,
          'positionSeconds': incoming['positionSeconds'],
          'durationSeconds': incoming['durationSeconds'],
          'completed': incoming['completed'],
        };
        final same =
            current != null &&
            _jsonEquivalent(
              _episodeCheckpointValue(_episodeRowCheckpoint(current)),
              _episodeCheckpointValue(checkpoint),
            );
        final incomingTime = _revisionEditTime(revision);
        final currentTime = _revisionEditTime(currentRevision);
        final accepted =
            current == null ||
            same ||
            (currentRevision != null &&
                incoming['baseRevision'] != null &&
                _baseRevisionMatches(
                  currentRevision,
                  incoming['baseRevision'],
                )) ||
            (incomingTime > 0 &&
                incomingTime >
                    (currentTime > 0 ? currentTime : current.updatedAtMs));
        if (accepted) {
          if (!same || at > current.updatedAtMs) {
            await _writeReceivedEpisodeCheckpointLocked(
              localId,
              checkpoint,
              DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
              current,
            );
          }
          revisions[key] = same
              ? _mergeEquivalentRevisions(currentRevision, revision)
              : revision;
          await (database.update(
            database.canonicalLibraryRecords,
          )..where((t) => t.localId.equals(localId))).write(
            CanonicalLibraryRecordsCompanion(
              fieldRevisionsJson: Value(jsonEncode(revisions)),
            ),
          );
          if (current != null && (!same || incoming['baseRevision'] is List)) {
            final parents = _revisionLeaves(incoming['baseRevision'])
                .map((value) => _jsonMap(value)['operationId']?.toString())
                .whereType<String>()
                .toSet();
            final conflicts =
                await (database.select(database.libraryConflictRecords)..where(
                      (t) =>
                          t.localId.equals(localId) &
                          t.fieldName.equals('episodeProgress') &
                          t.state.equals('open'),
                    ))
                    .get();
            for (final conflict in conflicts) {
              final value = _jsonMap(conflict.incomingValueJson);
              // Only retire a conflict for this exact episode/watch cycle.
              if (_episodeRevisionKey(value['episode']) != key) continue;
              if (parents.contains(conflict.localOperationId) ||
                  parents.contains(conflict.incomingOperationId) ||
                  (incomingTime > currentTime &&
                      incomingTime >
                          _revisionEditTime(value['__incomingRevision']))) {
                await _markConflictResolvedLocked(conflict.conflictId);
              }
            }
          }
        } else if (incomingTime ==
                (currentTime > 0 ? currentTime : current.updatedAtMs) &&
            !_jsonEquivalent(currentRevision, revision)) {
          final operationId =
              _jsonMap(revision)['operationId']?.toString() ?? '$id:$at';
          final conflictId = 'playback:$operationId:$localId';
          await database
              .into(database.libraryConflictRecords)
              .insert(
                LibraryConflictRecordsCompanion.insert(
                  conflictId: conflictId,
                  localId: localId,
                  fieldName: 'episodeProgress',
                  localValueJson: jsonEncode({
                    'episode': _episodeRowCheckpoint(current),
                  }),
                  incomingValueJson: jsonEncode({
                    'episode': checkpoint,
                    '__incomingRevision': revision,
                  }),
                  localOperationId: Value(
                    _jsonMap(currentRevision)['operationId']?.toString(),
                  ),
                  incomingOperationId: Value(operationId),
                  createdAtMs: DateTime.now().toUtc().millisecondsSinceEpoch,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
      // Stream choices already use timestamp replacement in the full protocol.
      // A deterministic revision tie-break makes compact files order-independent.
      for (final incoming in snapshot.streamPreferences) {
        final localId = translated[incoming['localId']];
        if (localId == null) {
          throw const FormatException('Unknown stream identity.');
        }
        final season = (incoming['seasonNumber'] as num?)?.toInt();
        final episode = (incoming['episodeNumber'] as num?)?.toDouble();
        final id = season == null && episode == null
            ? '$localId:title'
            : '$localId:${season ?? 'all'}:${episode ?? 'all'}';
        final existing = await (database.select(
          database.streamPreferenceRecords,
        )..where((t) => t.preferenceId.equals(id))).getSingleOrNull();
        final library = await (database.select(
          database.canonicalLibraryRecords,
        )..where((t) => t.localId.equals(localId))).getSingle();
        final revisions = _jsonMap(library.fieldRevisionsJson);
        final at = (incoming['updatedAtMs'] as num).toInt();
        if (existing != null &&
            (existing.updatedAtMs > at ||
                (existing.updatedAtMs == at &&
                    jsonEncode(
                          revisions['streamPreference'],
                        ).compareTo(jsonEncode(incoming['revision'])) >=
                        0))) {
          continue;
        }
        // Reuse the whitelist-only row importer; it never creates operations.
        await _importDriveStreamRows(
          DriveReplicaSegment(
            segmentId: '',
            deviceId: snapshot.deviceId,
            createdAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
            operations: [],
            media: [],
            libraryEntries: [],
            episodeStates: [],
            streamPreferences: [incoming],
          ),
          translated,
          DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
          replaceEqualTimestamp: true,
        );
        revisions['streamPreference'] = incoming['revision'];
        await (database.update(
          database.canonicalLibraryRecords,
        )..where((t) => t.localId.equals(localId))).write(
          CanonicalLibraryRecordsCompanion(
            fieldRevisionsJson: Value(jsonEncode(revisions)),
          ),
        );
      }
      await _writePlaybackCursor(scope, snapshot.checksum);
    });
  }
}
