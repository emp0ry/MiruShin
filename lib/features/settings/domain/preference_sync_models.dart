import 'dart:convert';

import 'package:crypto/crypto.dart';

class PreferenceSyncVersion implements Comparable<PreferenceSyncVersion> {
  const PreferenceSyncVersion({
    required this.changedAt,
    required this.deviceId,
  });

  factory PreferenceSyncVersion.fromJson(Map<String, dynamic> json) =>
      PreferenceSyncVersion(
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
  int compareTo(PreferenceSyncVersion other) {
    final int time = changedAt.compareTo(other.changedAt);
    return time != 0 ? time : deviceId.compareTo(other.deviceId);
  }
}

class PreferenceSyncValue {
  const PreferenceSyncValue({required this.version, required this.value});

  factory PreferenceSyncValue.fromJson(Map<String, dynamic> json) {
    final Object? rawVersion = json['version'];
    return PreferenceSyncValue(
      version: PreferenceSyncVersion.fromJson(
        rawVersion is Map
            ? Map<String, dynamic>.from(rawVersion)
            : const <String, dynamic>{},
      ),
      value: json['value'],
    );
  }

  final PreferenceSyncVersion version;
  final Object? value;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version.toJson(),
    'value': value,
  };
}

class PreferenceReplicaSegment {
  const PreferenceReplicaSegment({
    required this.deviceId,
    required this.revision,
    required this.createdAt,
    required this.values,
    required this.tombstones,
  });

  factory PreferenceReplicaSegment.fromPayload(Map<String, dynamic> json) {
    final Object? rawValues = json['values'];
    final Object? rawTombstones = json['tombstones'];
    return PreferenceReplicaSegment(
      deviceId: '${json['deviceId'] ?? ''}',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      values: rawValues is Map
          ? <String, PreferenceSyncValue>{
              for (final MapEntry<dynamic, dynamic> entry in rawValues.entries)
                '${entry.key}': PreferenceSyncValue.fromJson(
                  entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : const <String, dynamic>{},
                ),
            }
          : const <String, PreferenceSyncValue>{},
      tombstones: rawTombstones is Map
          ? <String, PreferenceSyncVersion>{
              for (final MapEntry<dynamic, dynamic> entry
                  in rawTombstones.entries)
                '${entry.key}': PreferenceSyncVersion.fromJson(
                  entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : const <String, dynamic>{},
                ),
            }
          : const <String, PreferenceSyncVersion>{},
    );
  }

  factory PreferenceReplicaSegment.decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Preferences replica must be an object.');
    }
    final Map<String, dynamic> wrapper = Map<String, dynamic>.from(decoded);
    final String payload = '${wrapper['payload'] ?? ''}';
    final String expected = '${wrapper['checksum'] ?? ''}';
    final String actual = sha256.convert(utf8.encode(payload)).toString();
    if (payload.isEmpty || expected.isEmpty || expected != actual) {
      throw const FormatException('Preferences replica checksum mismatch.');
    }
    final Object? payloadJson = jsonDecode(payload);
    if (payloadJson is! Map) {
      throw const FormatException(
        'Preferences replica payload must be an object.',
      );
    }
    return PreferenceReplicaSegment.fromPayload(
      Map<String, dynamic>.from(payloadJson),
    );
  }

  final String deviceId;
  final int revision;
  final DateTime createdAt;
  final Map<String, PreferenceSyncValue> values;
  final Map<String, PreferenceSyncVersion> tombstones;

  String get fileName =>
      'mirushin.preferences.segment.$deviceId.$revision.v1.json';

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'schemaVersion': 1,
    'deviceId': deviceId,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'values': <String, dynamic>{
      for (final MapEntry<String, PreferenceSyncValue> entry in values.entries)
        entry.key: entry.value.toJson(),
    },
    'tombstones': <String, dynamic>{
      for (final MapEntry<String, PreferenceSyncVersion> entry
          in tombstones.entries)
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

abstract interface class PreferenceCloudReplica {
  Future<void> pushPreferenceSegment(PreferenceReplicaSegment segment);

  Future<List<PreferenceReplicaSegment>> pullPreferenceSegments({
    required Set<String> excluding,
  });
}
