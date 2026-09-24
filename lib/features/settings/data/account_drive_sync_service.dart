import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/security/app_secure_storage.dart';
import '../../../shared/models/anilist_models.dart';
import '../domain/account_sync_models.dart';

class AccountDriveSyncResult {
  const AccountDriveSyncResult({
    required this.accounts,
    required this.preferredActiveViewerId,
    required this.localStateChanged,
    required this.pulledSegments,
    required this.pushedSegment,
  });

  final List<AniListSavedAccount> accounts;
  final int? preferredActiveViewerId;
  final bool localStateChanged;
  final int pulledSegments;
  final bool pushedSegment;
}

class AccountDriveSyncService {
  AccountDriveSyncService({
    required SharedPreferences preferences,
    AppSecureStorage secureStorage = const AppSecureStorage(),
    DateTime Function()? now,
  }) : _preferences = preferences,
       _secureStorage = secureStorage,
       _now = now ?? DateTime.now;

  static const String _pendingKey = 'accounts.drive.pending.v1';
  static const String _processedKey = 'accounts.drive.processed.v1';

  final SharedPreferences _preferences;
  final AppSecureStorage _secureStorage;
  final DateTime Function() _now;

  Future<AccountDriveSyncResult> sync({
    required AccountCloudReplica cloud,
    required String deviceId,
    required List<AniListSavedAccount> localAccounts,
    required int? activeViewerId,
  }) async {
    final _LoadedAccountSnapshot loaded = await _loadSnapshot(deviceId);
    AccountReplicaSegment local = loaded.segment;
    final _AccountCaptureResult captured = _captureLocal(
      local,
      deviceId,
      localAccounts,
      activeViewerId,
      hadSnapshot: loaded.hadSnapshot,
    );
    local = captured.segment;
    bool pending = _preferences.getBool(_pendingKey) ?? false;
    pending = pending || captured.changed;

    final Set<String> processed =
        _preferences.getStringList(_processedKey)?.toSet() ?? <String>{};
    final List<AccountReplicaSegment> incoming = await cloud
        .pullAccountSegments(excluding: processed);
    final AccountReplicaSegment merged = _merge(
      <AccountReplicaSegment>[local, ...incoming],
      deviceId: deviceId,
      revision: local.revision,
    );
    final bool localStateChanged = !_sameContent(local, merged);
    local = _copySegment(
      merged,
      deviceId: deviceId,
      revision: local.revision + (localStateChanged && pending ? 1 : 0),
      createdAt: localStateChanged && pending
          ? _now().toUtc()
          : local.createdAt,
    );

    await _secureStorage.writeAccountDriveSnapshot(local.encode());
    await _preferences.setBool(_pendingKey, pending);
    processed.addAll(
      incoming.map((AccountReplicaSegment value) => value.fileName),
    );
    var pushed = false;
    if (pending) {
      await cloud.pushAccountSegment(local);
      processed.add(local.fileName);
      await _preferences.setBool(_pendingKey, false);
      pushed = true;
    }
    await _preferences.setStringList(
      _processedKey,
      processed.toList(growable: false)..sort(),
    );

    final List<AniListSavedAccount> accounts =
        local.accounts.values
            .map(
              (AccountSyncValue value) =>
                  AniListSavedAccount.fromJson(value.value),
            )
            .where((AniListSavedAccount account) => account.viewerId > 0)
            .toList(growable: false)
          ..sort(
            (AniListSavedAccount a, AniListSavedAccount b) =>
                a.viewerId.compareTo(b.viewerId),
          );
    return AccountDriveSyncResult(
      accounts: accounts,
      preferredActiveViewerId: local.selection?.viewerId,
      localStateChanged: localStateChanged,
      pulledSegments: incoming.length,
      pushedSegment: pushed,
    );
  }

  Future<_LoadedAccountSnapshot> _loadSnapshot(String deviceId) async {
    final String raw = (await _secureStorage.readAccountDriveSnapshot()) ?? '';
    if (raw.isNotEmpty) {
      try {
        return _LoadedAccountSnapshot(
          segment: _copySegment(
            AccountReplicaSegment.decode(raw),
            deviceId: deviceId,
          ),
          hadSnapshot: true,
        );
      } on Object {
        // A corrupt local snapshot is rebuilt from active settings below.
      }
    }
    return _LoadedAccountSnapshot(
      segment: AccountReplicaSegment(
        deviceId: deviceId,
        revision: 0,
        createdAt: _now().toUtc(),
        accounts: const <String, AccountSyncValue>{},
        tombstones: const <String, AccountSyncVersion>{},
      ),
      hadSnapshot: false,
    );
  }

  _AccountCaptureResult _captureLocal(
    AccountReplicaSegment previous,
    String deviceId,
    List<AniListSavedAccount> localAccounts,
    int? activeViewerId, {
    required bool hadSnapshot,
  }) {
    final Map<String, Map<String, dynamic>> current =
        <String, Map<String, dynamic>>{
          for (final AniListSavedAccount account in localAccounts)
            '${account.viewerId}': account.toJson(),
        };
    final Map<String, AccountSyncValue> values = <String, AccountSyncValue>{
      ...previous.accounts,
    };
    final Map<String, AccountSyncVersion> tombstones =
        <String, AccountSyncVersion>{...previous.tombstones};
    var changed = false;
    for (final MapEntry<String, Map<String, dynamic>> entry
        in current.entries) {
      final AccountSyncValue? existing = values[entry.key];
      if (existing == null || !_sameJson(existing.value, entry.value)) {
        final AccountSyncVersion version = AccountSyncVersion(
          changedAt: _now().toUtc(),
          deviceId: deviceId,
        );
        values[entry.key] = AccountSyncValue(
          version: version,
          value: entry.value,
        );
        tombstones.remove(entry.key);
        changed = true;
      }
    }
    for (final String key in values.keys.toList(growable: false)) {
      if (current.containsKey(key)) continue;
      values.remove(key);
      tombstones[key] = AccountSyncVersion(
        changedAt: _now().toUtc(),
        deviceId: deviceId,
      );
      changed = true;
    }

    AccountSelectionValue? selection = previous.selection;
    if ((hadSnapshot || activeViewerId != null) &&
        selection?.viewerId != activeViewerId) {
      selection = AccountSelectionValue(
        version: AccountSyncVersion(
          changedAt: _now().toUtc(),
          deviceId: deviceId,
        ),
        viewerId: activeViewerId,
      );
      changed = true;
    }
    if (!changed) {
      return _AccountCaptureResult(segment: previous, changed: false);
    }
    return _AccountCaptureResult(
      segment: AccountReplicaSegment(
        deviceId: deviceId,
        revision: previous.revision + 1,
        createdAt: _now().toUtc(),
        accounts: values,
        tombstones: tombstones,
        selection: selection,
      ),
      changed: true,
    );
  }

  AccountReplicaSegment _merge(
    List<AccountReplicaSegment> segments, {
    required String deviceId,
    required int revision,
  }) {
    final Map<String, AccountSyncValue> accounts = <String, AccountSyncValue>{};
    final Map<String, AccountSyncVersion> tombstones =
        <String, AccountSyncVersion>{};
    AccountSelectionValue? selection;
    for (final AccountReplicaSegment segment in segments) {
      for (final MapEntry<String, AccountSyncValue> entry
          in segment.accounts.entries) {
        final AccountSyncVersion? deleted = tombstones[entry.key];
        final AccountSyncValue? existing = accounts[entry.key];
        if ((deleted == null || entry.value.version.compareTo(deleted) > 0) &&
            (existing == null ||
                entry.value.version.compareTo(existing.version) > 0)) {
          accounts[entry.key] = entry.value;
          tombstones.remove(entry.key);
        }
      }
      for (final MapEntry<String, AccountSyncVersion> entry
          in segment.tombstones.entries) {
        final AccountSyncValue? existing = accounts[entry.key];
        final AccountSyncVersion? deleted = tombstones[entry.key];
        if ((existing == null ||
                entry.value.compareTo(existing.version) >= 0) &&
            (deleted == null || entry.value.compareTo(deleted) > 0)) {
          accounts.remove(entry.key);
          tombstones[entry.key] = entry.value;
        }
      }
      final AccountSelectionValue? candidate = segment.selection;
      if (candidate != null &&
          (selection == null ||
              candidate.version.compareTo(selection.version) > 0)) {
        selection = candidate;
      }
    }
    return AccountReplicaSegment(
      deviceId: deviceId,
      revision: revision,
      createdAt: _now().toUtc(),
      accounts: accounts,
      tombstones: tombstones,
      selection: selection,
    );
  }

  AccountReplicaSegment _copySegment(
    AccountReplicaSegment source, {
    required String deviceId,
    int? revision,
    DateTime? createdAt,
  }) => AccountReplicaSegment(
    deviceId: deviceId,
    revision: revision ?? source.revision,
    createdAt: createdAt ?? source.createdAt,
    accounts: source.accounts,
    tombstones: source.tombstones,
    selection: source.selection,
  );

  bool _sameContent(AccountReplicaSegment a, AccountReplicaSegment b) =>
      _sameJson(
        <String, dynamic>{
          'accounts': a.toPayload()['accounts'],
          'tombstones': a.toPayload()['tombstones'],
          'selection': a.toPayload()['selection'],
        },
        <String, dynamic>{
          'accounts': b.toPayload()['accounts'],
          'tombstones': b.toPayload()['tombstones'],
          'selection': b.toPayload()['selection'],
        },
      );

  bool _sameJson(Object? a, Object? b) =>
      jsonEncode(_stable(a)) == jsonEncode(_stable(b));

  Object? _stable(Object? value) {
    if (value is Map) {
      final Map<String, Object?> stringValues = <String, Object?>{
        for (final MapEntry<dynamic, dynamic> entry in value.entries)
          '${entry.key}': entry.value,
      };
      final List<String> keys = stringValues.keys.toList()..sort();
      return <String, dynamic>{
        for (final String key in keys) key: _stable(stringValues[key]),
      };
    }
    if (value is List) return value.map(_stable).toList(growable: false);
    return value;
  }
}

class _LoadedAccountSnapshot {
  const _LoadedAccountSnapshot({
    required this.segment,
    required this.hadSnapshot,
  });

  final AccountReplicaSegment segment;
  final bool hadSnapshot;
}

class _AccountCaptureResult {
  const _AccountCaptureResult({required this.segment, required this.changed});

  final AccountReplicaSegment segment;
  final bool changed;
}
