import 'dart:convert';

import 'package:crypto/crypto.dart';

class AccountSyncVersion implements Comparable<AccountSyncVersion> {
  const AccountSyncVersion({required this.changedAt, required this.deviceId});

  factory AccountSyncVersion.fromJson(Map<String, dynamic> json) =>
      AccountSyncVersion(
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
  int compareTo(AccountSyncVersion other) {
    final int time = changedAt.compareTo(other.changedAt);
    return time != 0 ? time : deviceId.compareTo(other.deviceId);
  }
}

class AccountSyncValue {
  const AccountSyncValue({required this.version, required this.value});

  factory AccountSyncValue.fromJson(Map<String, dynamic> json) {
    final Object? rawVersion = json['version'];
    final Object? rawValue = json['value'];
    return AccountSyncValue(
      version: AccountSyncVersion.fromJson(
        rawVersion is Map
            ? Map<String, dynamic>.from(rawVersion)
            : const <String, dynamic>{},
      ),
      value: rawValue is Map
          ? Map<String, dynamic>.from(rawValue)
          : const <String, dynamic>{},
    );
  }

  final AccountSyncVersion version;
  final Map<String, dynamic> value;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version.toJson(),
    'value': value,
  };
}

class AccountSelectionValue {
  const AccountSelectionValue({required this.version, this.viewerId});

  factory AccountSelectionValue.fromJson(Map<String, dynamic> json) {
    final Object? rawVersion = json['version'];
    return AccountSelectionValue(
      version: AccountSyncVersion.fromJson(
        rawVersion is Map
            ? Map<String, dynamic>.from(rawVersion)
            : const <String, dynamic>{},
      ),
      viewerId: (json['viewerId'] as num?)?.toInt(),
    );
  }

  final AccountSyncVersion version;
  final int? viewerId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version.toJson(),
    'viewerId': viewerId,
  };
}

class AccountReplicaSegment {
  const AccountReplicaSegment({
    required this.deviceId,
    required this.revision,
    required this.createdAt,
    required this.accounts,
    required this.tombstones,
    this.selection,
  });

  factory AccountReplicaSegment.fromPayload(Map<String, dynamic> json) {
    final Object? rawAccounts = json['accounts'];
    final Object? rawTombstones = json['tombstones'];
    final Object? rawSelection = json['selection'];
    return AccountReplicaSegment(
      deviceId: '${json['deviceId'] ?? ''}',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      accounts: rawAccounts is Map
          ? <String, AccountSyncValue>{
              for (final MapEntry<dynamic, dynamic> entry
                  in rawAccounts.entries)
                '${entry.key}': AccountSyncValue.fromJson(
                  entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : const <String, dynamic>{},
                ),
            }
          : const <String, AccountSyncValue>{},
      tombstones: rawTombstones is Map
          ? <String, AccountSyncVersion>{
              for (final MapEntry<dynamic, dynamic> entry
                  in rawTombstones.entries)
                '${entry.key}': AccountSyncVersion.fromJson(
                  entry.value is Map
                      ? Map<String, dynamic>.from(entry.value as Map)
                      : const <String, dynamic>{},
                ),
            }
          : const <String, AccountSyncVersion>{},
      selection: rawSelection is Map
          ? AccountSelectionValue.fromJson(
              Map<String, dynamic>.from(rawSelection),
            )
          : null,
    );
  }

  factory AccountReplicaSegment.decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Account replica must be an object.');
    }
    final Map<String, dynamic> wrapper = Map<String, dynamic>.from(decoded);
    final String payload = '${wrapper['payload'] ?? ''}';
    final String expected = '${wrapper['checksum'] ?? ''}';
    final String actual = sha256.convert(utf8.encode(payload)).toString();
    if (payload.isEmpty || expected.isEmpty || expected != actual) {
      throw const FormatException('Account replica checksum mismatch.');
    }
    final Object? payloadJson = jsonDecode(payload);
    if (payloadJson is! Map) {
      throw const FormatException('Account replica payload must be an object.');
    }
    return AccountReplicaSegment.fromPayload(
      Map<String, dynamic>.from(payloadJson),
    );
  }

  final String deviceId;
  final int revision;
  final DateTime createdAt;
  final Map<String, AccountSyncValue> accounts;
  final Map<String, AccountSyncVersion> tombstones;
  final AccountSelectionValue? selection;

  String get fileName =>
      'mirushin.accounts.segment.$deviceId.$revision.v1.json';

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'schemaVersion': 1,
    'deviceId': deviceId,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'accounts': <String, dynamic>{
      for (final MapEntry<String, AccountSyncValue> entry in accounts.entries)
        entry.key: entry.value.toJson(),
    },
    'tombstones': <String, dynamic>{
      for (final MapEntry<String, AccountSyncVersion> entry
          in tombstones.entries)
        entry.key: entry.value.toJson(),
    },
    if (selection != null) 'selection': selection!.toJson(),
  };

  String encode() {
    final String payload = jsonEncode(toPayload());
    return jsonEncode(<String, dynamic>{
      'payload': payload,
      'checksum': sha256.convert(utf8.encode(payload)).toString(),
    });
  }
}

abstract interface class AccountCloudReplica {
  Future<void> pushAccountSegment(AccountReplicaSegment segment);

  Future<List<AccountReplicaSegment>> pullAccountSegments({
    required Set<String> excluding,
  });
}
