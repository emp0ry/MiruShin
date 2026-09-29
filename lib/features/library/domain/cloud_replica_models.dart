import 'dart:convert';

import 'package:crypto/crypto.dart';

class DriveReplicaSegment {
  DriveReplicaSegment({
    required this.segmentId,
    required this.deviceId,
    required this.createdAt,
    required this.operations,
    required this.media,
    required this.libraryEntries,
    required this.episodeStates,
    required this.streamPreferences,
    this.replicaNamespace = 'legacy',
  });

  factory DriveReplicaSegment.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return DriveReplicaSegment(
      segmentId: '${json['segmentId'] ?? ''}',
      deviceId: '${json['deviceId'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime(1970),
      operations: maps(json['operations']),
      media: maps(json['media']),
      libraryEntries: maps(json['libraryEntries']),
      episodeStates: maps(json['episodeStates']),
      streamPreferences: maps(json['streamPreferences']),
      replicaNamespace: '${json['replicaNamespace'] ?? 'legacy'}',
    );
  }

  final String segmentId;
  final String deviceId;
  final DateTime createdAt;
  final List<Map<String, dynamic>> operations;
  final List<Map<String, dynamic>> media;
  final List<Map<String, dynamic>> libraryEntries;
  final List<Map<String, dynamic>> episodeStates;
  final List<Map<String, dynamic>> streamPreferences;
  final String replicaNamespace;

  String get fileName => replicaNamespace == 'legacy'
      ? 'mirushin.segment.$deviceId.$segmentId.json'
      : 'mirushin.$replicaNamespace.segment.$deviceId.$segmentId.json';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 1,
    'replicaNamespace': replicaNamespace,
    'segmentId': segmentId,
    'deviceId': deviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'operations': operations,
    'media': media,
    'libraryEntries': libraryEntries,
    'episodeStates': episodeStates,
    'streamPreferences': streamPreferences,
  };

  String encode() => jsonEncode(toJson());

  String get checksum => sha256.convert(utf8.encode(encode())).toString();
}

/// A complete, render-ready checkpoint of one Local Library workspace.
///
/// Operation segments remain the conflict-aware incremental protocol. This
/// snapshot is the fast bootstrap path for a fresh device: it contains every
/// canonical row needed to render and filter the Library before any tracker is
/// reachable. The fixed file is replaced only after its checksum and entry
/// count have been written to the workspace manifest.
class DriveLibrarySnapshot {
  DriveLibrarySnapshot({
    required this.snapshotId,
    required this.deviceId,
    required this.createdAt,
    required this.replicaNamespace,
    required this.media,
    required this.libraryEntries,
    required this.providerBindings,
    required this.providerSnapshots,
    required this.episodeStates,
    required this.streamPreferences,
    required this.operations,
  });

  factory DriveLibrarySnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return DriveLibrarySnapshot(
      snapshotId: '${json['snapshotId'] ?? ''}',
      deviceId: '${json['deviceId'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime(1970),
      replicaNamespace: '${json['replicaNamespace'] ?? 'legacy'}',
      media: maps(json['media']),
      libraryEntries: maps(json['libraryEntries']),
      providerBindings: maps(json['providerBindings']),
      providerSnapshots: maps(json['providerSnapshots']),
      episodeStates: maps(json['episodeStates']),
      streamPreferences: maps(json['streamPreferences']),
      operations: maps(json['operations']),
    );
  }

  final String snapshotId;
  final String deviceId;
  final DateTime createdAt;
  final String replicaNamespace;
  final List<Map<String, dynamic>> media;
  final List<Map<String, dynamic>> libraryEntries;
  final List<Map<String, dynamic>> providerBindings;
  final List<Map<String, dynamic>> providerSnapshots;
  final List<Map<String, dynamic>> episodeStates;
  final List<Map<String, dynamic>> streamPreferences;
  final List<Map<String, dynamic>> operations;

  String get fileName => replicaNamespace == 'legacy'
      ? 'mirushin.library.snapshot.v2.json'
      : 'mirushin.$replicaNamespace.library.snapshot.v2.json';

  int get entryCount => libraryEntries
      .where((Map<String, dynamic> row) => row['inLibrary'] == true)
      .length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 2,
    'snapshotId': snapshotId,
    'deviceId': deviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'replicaNamespace': replicaNamespace,
    'entryCount': entryCount,
    'media': media,
    'libraryEntries': libraryEntries,
    'providerBindings': providerBindings,
    'providerSnapshots': providerSnapshots,
    'episodeStates': episodeStates,
    'streamPreferences': streamPreferences,
    'operations': operations,
  };

  String encode() => jsonEncode(toJson());

  /// Checksum used by the first v2 implementation. Kept only so devices can
  /// read an already-uploaded checkpoint before replacing it with the stable
  /// content checksum on the next successful push.
  String get legacyEnvelopeChecksum =>
      sha256.convert(utf8.encode(encode())).toString();

  /// Identifies the actual checkpoint contents. Runtime envelope values are
  /// excluded so an unchanged library does not upload another full snapshot
  /// merely because a later sync generated a new id and timestamp.
  late final String checksum = sha256
      .convert(utf8.encode(_stableContentJson()))
      .toString();

  String _stableContentJson() {
    // Preserve the exact field order and bytes of the existing v2 checksum.
    // Reuse each encoded row for sorting and output instead of serializing the
    // entire provider/operation history a second time.
    final StringBuffer content = StringBuffer('{"schemaVersion":2,')
      ..write('"replicaNamespace":')
      ..write(jsonEncode(replicaNamespace))
      ..write(',"entryCount":')
      ..write(entryCount)
      ..write(',"media":')
      ..write(_stableSnapshotRowsJson(media))
      ..write(',"libraryEntries":')
      ..write(_stableSnapshotRowsJson(libraryEntries))
      ..write(',"providerBindings":')
      ..write(
        _stableSnapshotRowsJson(
          providerBindings.map((Map<String, dynamic> row) {
            final Map<String, dynamic> stable = Map<String, dynamic>.from(row);
            stable.remove('verifiedAtMs');
            return stable;
          }),
        ),
      )
      ..write(',"providerSnapshots":')
      ..write(
        _stableSnapshotRowsJson(
          providerSnapshots.map((Map<String, dynamic> row) {
            final Map<String, dynamic> stable = Map<String, dynamic>.from(row);
            stable.remove('fetchedAtMs');
            stable.remove('destructiveConfirmationCount');
            return stable;
          }),
        ),
      )
      ..write(',"episodeStates":')
      ..write(_stableSnapshotRowsJson(episodeStates))
      ..write(',"streamPreferences":')
      ..write(_stableSnapshotRowsJson(streamPreferences))
      ..write(',"operations":')
      ..write(_stableSnapshotRowsJson(operations))
      ..write('}');
    return content.toString();
  }

  int get encodedSizeBytes => utf8.encode(encode()).length;
}

String _stableSnapshotRowsJson(Iterable<Map<String, dynamic>> rows) {
  // Keep the v2 checksum byte-for-byte compatible with existing manifests.
  // Encoding inside the comparator used to serialize large provider snapshots
  // O(n log n) times on every backup; decorate each row only once instead.
  final List<String> encoded = rows.map(jsonEncode).toList(growable: false)
    ..sort();
  return '[${encoded.join(',')}]';
}

class CloudReplicaFile {
  const CloudReplicaFile({
    required this.id,
    required this.name,
    this.checksum,
    this.etag,
    this.sizeBytes,
  });

  final String id;
  final String name;
  final String? checksum;
  final String? etag;
  final int? sizeBytes;
}

class DriveLibraryChanges {
  const DriveLibraryChanges({
    required this.segments,
    required this.nextPageToken,
    this.manifestChanged = false,
    this.manifestFileId,
    this.snapshotFileId,
  });

  final List<DriveReplicaSegment> segments;
  final String nextPageToken;
  final bool manifestChanged;
  final String? manifestFileId;
  final String? snapshotFileId;
}

class DriveReplicaManifest {
  const DriveReplicaManifest({
    this.revision = 0,
    this.segments = const <String, String>{},
    this.processedByDevice = const <String, List<String>>{},
    this.deliveryLedger = const <String, Map<String, String>>{},
    this.snapshotFileName,
    this.snapshotChecksum,
    this.snapshotEntryCount,
    this.snapshotSizeBytes,
    this.snapshotCreatedAt,
    this.leaseOwner,
    this.leaseExpiresAt,
  });

  factory DriveReplicaManifest.fromJson(Map<String, dynamic> json) {
    final Object? segments = json['segments'];
    final Object? processed = json['processedByDevice'];
    final Object? ledger = json['deliveryLedger'];
    return DriveReplicaManifest(
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      segments: segments is Map
          ? <String, String>{
              for (final MapEntry<dynamic, dynamic> entry in segments.entries)
                '${entry.key}': '${entry.value}',
            }
          : const <String, String>{},
      processedByDevice: processed is Map
          ? <String, List<String>>{
              for (final MapEntry<dynamic, dynamic> entry in processed.entries)
                '${entry.key}': entry.value is List
                    ? (entry.value as List<dynamic>)
                          .map((dynamic value) => '$value')
                          .toList(growable: false)
                    : const <String>[],
            }
          : const <String, List<String>>{},
      deliveryLedger: ledger is Map
          ? <String, Map<String, String>>{
              for (final MapEntry<dynamic, dynamic> entry in ledger.entries)
                '${entry.key}': entry.value is Map
                    ? <String, String>{
                        for (final MapEntry<dynamic, dynamic> value
                            in (entry.value as Map).entries)
                          '${value.key}': '${value.value}',
                      }
                    : const <String, String>{},
            }
          : const <String, Map<String, String>>{},
      snapshotFileName: json['snapshotFileName']?.toString(),
      snapshotChecksum: json['snapshotChecksum']?.toString(),
      snapshotEntryCount: (json['snapshotEntryCount'] as num?)?.toInt(),
      snapshotSizeBytes: (json['snapshotSizeBytes'] as num?)?.toInt(),
      snapshotCreatedAt: DateTime.tryParse(
        '${json['snapshotCreatedAt'] ?? ''}',
      ),
      leaseOwner: json['leaseOwner']?.toString(),
      leaseExpiresAt: DateTime.tryParse('${json['leaseExpiresAt'] ?? ''}'),
    );
  }

  final int revision;
  final Map<String, String> segments;
  final Map<String, List<String>> processedByDevice;
  final Map<String, Map<String, String>> deliveryLedger;
  final String? snapshotFileName;
  final String? snapshotChecksum;
  final int? snapshotEntryCount;
  final int? snapshotSizeBytes;
  final DateTime? snapshotCreatedAt;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 1,
    'revision': revision,
    'segments': segments,
    'processedByDevice': processedByDevice,
    'deliveryLedger': deliveryLedger,
    if (snapshotFileName != null) 'snapshotFileName': snapshotFileName,
    if (snapshotChecksum != null) 'snapshotChecksum': snapshotChecksum,
    if (snapshotEntryCount != null) 'snapshotEntryCount': snapshotEntryCount,
    if (snapshotSizeBytes != null) 'snapshotSizeBytes': snapshotSizeBytes,
    if (snapshotCreatedAt != null)
      'snapshotCreatedAt': snapshotCreatedAt!.toUtc().toIso8601String(),
    if (leaseOwner != null) 'leaseOwner': leaseOwner,
    if (leaseExpiresAt != null)
      'leaseExpiresAt': leaseExpiresAt!.toUtc().toIso8601String(),
  };
}

abstract interface class CloudReplica {
  Future<CloudReplicaFile> pushSegment(DriveReplicaSegment segment);

  Future<List<DriveReplicaSegment>> pullSegments({
    required Set<String> excluding,
  });

  Future<Map<String, Map<String, String>>> readDeliveryLedger();

  Future<void> mergeDeliveryLedger(Map<String, Map<String, String>> deliveries);

  Future<bool> acquireDeliveryLease({
    required String deviceId,
    Duration duration = const Duration(minutes: 2),
  });

  Future<void> releaseDeliveryLease({required String deviceId});
}

class DriveReplicaUsage {
  const DriveReplicaUsage({
    required this.totalBytes,
    required this.fileCount,
    this.snapshotBytes = 0,
  });

  final int totalBytes;
  final int fileCount;
  final int snapshotBytes;
}
