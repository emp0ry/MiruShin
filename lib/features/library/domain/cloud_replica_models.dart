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

class CloudReplicaFile {
  const CloudReplicaFile({
    required this.id,
    required this.name,
    this.checksum,
    this.etag,
  });

  final String id;
  final String name;
  final String? checksum;
  final String? etag;
}

class DriveReplicaManifest {
  const DriveReplicaManifest({
    this.revision = 0,
    this.segments = const <String, String>{},
    this.processedByDevice = const <String, List<String>>{},
    this.deliveryLedger = const <String, Map<String, String>>{},
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
      leaseOwner: json['leaseOwner']?.toString(),
      leaseExpiresAt: DateTime.tryParse('${json['leaseExpiresAt'] ?? ''}'),
    );
  }

  final int revision;
  final Map<String, String> segments;
  final Map<String, List<String>> processedByDevice;
  final Map<String, Map<String, String>> deliveryLedger;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': 1,
    'revision': revision,
    'segments': segments,
    'processedByDevice': processedByDevice,
    'deliveryLedger': deliveryLedger,
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
