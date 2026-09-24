import 'dart:convert';

import 'package:crypto/crypto.dart';

class AddonSyncVersion implements Comparable<AddonSyncVersion> {
  const AddonSyncVersion({required this.changedAt, required this.deviceId});

  factory AddonSyncVersion.fromJson(Map<String, dynamic> json) =>
      AddonSyncVersion(
        changedAt:
            DateTime.tryParse('${json['changedAt'] ?? ''}')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        deviceId: '${json['deviceId'] ?? ''}',
      );

  final DateTime changedAt;
  final String deviceId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'changedAt': changedAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
  };

  @override
  int compareTo(AddonSyncVersion other) {
    final int time = changedAt.compareTo(other.changedAt);
    return time != 0 ? time : deviceId.compareTo(other.deviceId);
  }
}

class AddonSyncValue {
  const AddonSyncValue({required this.version, required this.value});

  factory AddonSyncValue.fromJson(Map<String, dynamic> json) {
    final Object? rawVersion = json['version'];
    final Object? rawValue = json['value'];
    return AddonSyncValue(
      version: AddonSyncVersion.fromJson(
        rawVersion is Map
            ? Map<String, dynamic>.from(rawVersion)
            : const <String, dynamic>{},
      ),
      value: rawValue is Map
          ? Map<String, dynamic>.from(rawValue)
          : const <String, dynamic>{},
    );
  }

  final AddonSyncVersion version;
  final Map<String, dynamic> value;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version.toJson(),
    'value': value,
  };
}

class AddonReplicaSegment {
  const AddonReplicaSegment({
    required this.deviceId,
    required this.revision,
    required this.createdAt,
    required this.addons,
    required this.addonTombstones,
    required this.sources,
    required this.sourceTombstones,
  });

  factory AddonReplicaSegment.fromPayload(Map<String, dynamic> json) {
    Map<String, AddonSyncValue> values(Object? raw) => raw is Map
        ? <String, AddonSyncValue>{
            for (final MapEntry<dynamic, dynamic> entry in raw.entries)
              '${entry.key}': AddonSyncValue.fromJson(
                entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : const <String, dynamic>{},
              ),
          }
        : const <String, AddonSyncValue>{};
    Map<String, AddonSyncVersion> tombstones(Object? raw) => raw is Map
        ? <String, AddonSyncVersion>{
            for (final MapEntry<dynamic, dynamic> entry in raw.entries)
              '${entry.key}': AddonSyncVersion.fromJson(
                entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : const <String, dynamic>{},
              ),
          }
        : const <String, AddonSyncVersion>{};
    return AddonReplicaSegment(
      deviceId: '${json['deviceId'] ?? ''}',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      addons: values(json['addons']),
      addonTombstones: tombstones(json['addonTombstones']),
      sources: values(json['sources']),
      sourceTombstones: tombstones(json['sourceTombstones']),
    );
  }

  factory AddonReplicaSegment.decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Addon replica must be an object.');
    }
    final Map<String, dynamic> wrapper = Map<String, dynamic>.from(decoded);
    final String payload = '${wrapper['payload'] ?? ''}';
    final String expected = '${wrapper['checksum'] ?? ''}';
    final String actual = sha256.convert(utf8.encode(payload)).toString();
    if (payload.isEmpty || expected.isEmpty || expected != actual) {
      throw const FormatException('Addon replica checksum mismatch.');
    }
    final Object? payloadJson = jsonDecode(payload);
    if (payloadJson is! Map) {
      throw const FormatException('Addon replica payload must be an object.');
    }
    return AddonReplicaSegment.fromPayload(
      Map<String, dynamic>.from(payloadJson),
    );
  }

  final String deviceId;
  final int revision;
  final DateTime createdAt;
  final Map<String, AddonSyncValue> addons;
  final Map<String, AddonSyncVersion> addonTombstones;
  final Map<String, AddonSyncValue> sources;
  final Map<String, AddonSyncVersion> sourceTombstones;

  String get fileName => 'mirushin.addons.segment.$deviceId.$revision.v1.json';

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'schemaVersion': 1,
    'deviceId': deviceId,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'addons': <String, dynamic>{
      for (final MapEntry<String, AddonSyncValue> entry in addons.entries)
        entry.key: entry.value.toJson(),
    },
    'addonTombstones': <String, dynamic>{
      for (final MapEntry<String, AddonSyncVersion> entry
          in addonTombstones.entries)
        entry.key: entry.value.toJson(),
    },
    'sources': <String, dynamic>{
      for (final MapEntry<String, AddonSyncValue> entry in sources.entries)
        entry.key: entry.value.toJson(),
    },
    'sourceTombstones': <String, dynamic>{
      for (final MapEntry<String, AddonSyncVersion> entry
          in sourceTombstones.entries)
        entry.key: entry.value.toJson(),
    },
  };

  String encode() {
    final String payload = jsonEncode(toPayload());
    return jsonEncode(<String, dynamic>{
      'payload': payload,
      'checksum': sha256.convert(utf8.encode(payload)).toString(),
    });
  }
}

abstract interface class AddonCloudReplica {
  Future<void> pushAddonSegment(AddonReplicaSegment segment);

  Future<List<AddonReplicaSegment>> pullAddonSegments({
    required Set<String> excluding,
  });
}
