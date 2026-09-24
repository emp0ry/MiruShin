import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../application/addon_sources_provider.dart';
import '../domain/addon_source_models.dart';
import '../domain/addon_sync_models.dart';
import 'sora_addon_store.dart';

class AddonDriveSyncResult {
  const AddonDriveSyncResult({
    required this.localStateChanged,
    required this.pulledSegments,
    required this.pushedSegment,
  });

  final bool localStateChanged;
  final int pulledSegments;
  final bool pushedSegment;
}

class AddonDriveSyncService {
  AddonDriveSyncService({
    required SharedPreferences preferences,
    required SoraAddonStore store,
    DateTime Function()? now,
  }) : _preferences = preferences,
       _store = store,
       _now = now ?? DateTime.now;

  static const String _snapshotKey = 'addons.drive.snapshot.v1';
  static const String _pendingKey = 'addons.drive.pending.v1';
  static const String _processedKey = 'addons.drive.processed.v1';

  final SharedPreferences _preferences;
  final SoraAddonStore _store;
  final DateTime Function() _now;

  Future<AddonDriveSyncResult> sync({
    required AddonCloudReplica cloud,
    required String deviceId,
  }) async {
    AddonReplicaSegment local = _loadSnapshot(deviceId);
    final _CaptureResult captured = await _captureLocal(local, deviceId);
    local = captured.segment;
    bool pending = _preferences.getBool(_pendingKey) ?? false;
    pending = pending || captured.changed;

    final Set<String> processed =
        _preferences.getStringList(_processedKey)?.toSet() ?? <String>{};
    final List<AddonReplicaSegment> incoming = await cloud.pullAddonSegments(
      excluding: processed,
    );
    final AddonReplicaSegment merged = _merge(
      <AddonReplicaSegment>[local, ...incoming],
      deviceId: deviceId,
      revision: local.revision,
    );
    final bool mergeChanged = !_sameContent(local, merged);
    if (mergeChanged && pending) {
      local = _copySegment(
        merged,
        deviceId: deviceId,
        revision: local.revision + 1,
        createdAt: _now().toUtc(),
      );
    } else {
      local = _copySegment(
        merged,
        deviceId: deviceId,
        revision: local.revision,
        createdAt: local.createdAt,
      );
    }

    final bool localStateChanged = await _apply(local);
    await _saveSnapshot(local, pending: pending);
    processed.addAll(
      incoming.map((AddonReplicaSegment value) => value.fileName),
    );

    var pushed = false;
    if (pending) {
      await cloud.pushAddonSegment(local);
      processed.add(local.fileName);
      await _preferences.setBool(_pendingKey, false);
      pushed = true;
    }
    await _preferences.setStringList(
      _processedKey,
      processed.toList(growable: false)..sort(),
    );
    return AddonDriveSyncResult(
      localStateChanged: localStateChanged,
      pulledSegments: incoming.length,
      pushedSegment: pushed,
    );
  }

  AddonReplicaSegment _loadSnapshot(String deviceId) {
    final String raw = _preferences.getString(_snapshotKey) ?? '';
    if (raw.isNotEmpty) {
      try {
        final AddonReplicaSegment stored = AddonReplicaSegment.decode(raw);
        return _copySegment(stored, deviceId: deviceId);
      } on Object {
        // Rebuild from the current addon registry below.
      }
    }
    return AddonReplicaSegment(
      deviceId: deviceId,
      revision: 0,
      createdAt: _now().toUtc(),
      addons: const <String, AddonSyncValue>{},
      addonTombstones: const <String, AddonSyncVersion>{},
      sources: const <String, AddonSyncValue>{},
      sourceTombstones: const <String, AddonSyncVersion>{},
    );
  }

  Future<_CaptureResult> _captureLocal(
    AddonReplicaSegment previous,
    String deviceId,
  ) async {
    final Map<String, Map<String, dynamic>> currentAddons =
        await _currentAddons();
    final Map<String, Map<String, dynamic>> currentSources = _currentSources();
    final Map<String, AddonSyncValue> addons = <String, AddonSyncValue>{
      ...previous.addons,
    };
    final Map<String, AddonSyncVersion> addonTombstones =
        <String, AddonSyncVersion>{...previous.addonTombstones};
    final Map<String, AddonSyncValue> sources = <String, AddonSyncValue>{
      ...previous.sources,
    };
    final Map<String, AddonSyncVersion> sourceTombstones =
        <String, AddonSyncVersion>{...previous.sourceTombstones};
    var changed = false;

    void capture(
      Map<String, Map<String, dynamic>> current,
      Map<String, AddonSyncValue> values,
      Map<String, AddonSyncVersion> tombstones,
    ) {
      for (final MapEntry<String, Map<String, dynamic>> entry
          in current.entries) {
        final AddonSyncValue? existing = values[entry.key];
        if (existing == null || !_sameJson(existing.value, entry.value)) {
          final AddonSyncVersion version = AddonSyncVersion(
            changedAt: _now().toUtc(),
            deviceId: deviceId,
          );
          values[entry.key] = AddonSyncValue(
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
        tombstones[key] = AddonSyncVersion(
          changedAt: _now().toUtc(),
          deviceId: deviceId,
        );
        changed = true;
      }
    }

    capture(currentAddons, addons, addonTombstones);
    capture(currentSources, sources, sourceTombstones);
    if (!changed) return _CaptureResult(segment: previous, changed: false);
    return _CaptureResult(
      segment: AddonReplicaSegment(
        deviceId: deviceId,
        revision: previous.revision + 1,
        createdAt: _now().toUtc(),
        addons: addons,
        addonTombstones: addonTombstones,
        sources: sources,
        sourceTombstones: sourceTombstones,
      ),
      changed: true,
    );
  }

  AddonReplicaSegment _merge(
    List<AddonReplicaSegment> segments, {
    required String deviceId,
    required int revision,
  }) {
    final Map<String, AddonSyncValue> addons = <String, AddonSyncValue>{};
    final Map<String, AddonSyncVersion> addonTombstones =
        <String, AddonSyncVersion>{};
    final Map<String, AddonSyncValue> sources = <String, AddonSyncValue>{};
    final Map<String, AddonSyncVersion> sourceTombstones =
        <String, AddonSyncVersion>{};

    void mergeValues(
      Map<String, AddonSyncValue> incomingValues,
      Map<String, AddonSyncVersion> incomingTombstones,
      Map<String, AddonSyncValue> values,
      Map<String, AddonSyncVersion> tombstones,
    ) {
      for (final MapEntry<String, AddonSyncValue> entry
          in incomingValues.entries) {
        final AddonSyncVersion? deleted = tombstones[entry.key];
        final AddonSyncValue? existing = values[entry.key];
        if ((deleted == null || entry.value.version.compareTo(deleted) > 0) &&
            (existing == null ||
                entry.value.version.compareTo(existing.version) > 0)) {
          values[entry.key] = entry.value;
          tombstones.remove(entry.key);
        }
      }
      for (final MapEntry<String, AddonSyncVersion> entry
          in incomingTombstones.entries) {
        final AddonSyncValue? existing = values[entry.key];
        final AddonSyncVersion? deleted = tombstones[entry.key];
        if ((existing == null ||
                entry.value.compareTo(existing.version) >= 0) &&
            (deleted == null || entry.value.compareTo(deleted) > 0)) {
          values.remove(entry.key);
          tombstones[entry.key] = entry.value;
        }
      }
    }

    for (final AddonReplicaSegment segment in segments) {
      mergeValues(
        segment.addons,
        segment.addonTombstones,
        addons,
        addonTombstones,
      );
      mergeValues(
        segment.sources,
        segment.sourceTombstones,
        sources,
        sourceTombstones,
      );
    }
    return AddonReplicaSegment(
      deviceId: deviceId,
      revision: revision,
      createdAt: _now().toUtc(),
      addons: addons,
      addonTombstones: addonTombstones,
      sources: sources,
      sourceTombstones: sourceTombstones,
    );
  }

  Future<bool> _apply(AddonReplicaSegment desired) async {
    final Map<String, Map<String, dynamic>> currentAddons =
        await _currentAddons();
    final Map<String, Map<String, dynamic>> desiredAddons =
        <String, Map<String, dynamic>>{
          for (final MapEntry<String, AddonSyncValue> entry
              in desired.addons.entries)
            entry.key: entry.value.value,
        };
    final Map<String, Map<String, dynamic>> currentSources = _currentSources();
    final Map<String, Map<String, dynamic>> desiredSources =
        <String, Map<String, dynamic>>{
          for (final MapEntry<String, AddonSyncValue> entry
              in desired.sources.entries)
            entry.key: entry.value.value,
        };
    var changed = false;
    if (!_sameJson(currentAddons, desiredAddons)) {
      final List<Map<String, dynamic>> ordered = desiredAddons.values.toList()
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              ((a['order'] as num?)?.toInt() ?? 0).compareTo(
                (b['order'] as num?)?.toInt() ?? 0,
              ),
        );
      final SoraAddonImportResult result = await _store.reconcileInstalledJson(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'format': 'mirushin.sora.addons.v1',
          'addons': ordered,
        }),
      );
      if (result.hasFailures) {
        throw StateError(
          'Could not restore ${result.failed} synced addon(s): '
          '${result.failures.take(3).join('; ')}',
        );
      }
      changed = true;
    }
    if (!_sameJson(currentSources, desiredSources)) {
      final List<Map<String, dynamic>> ordered = desiredSources.values.toList()
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              '${a['addedAt'] ?? ''}'.compareTo('${b['addedAt'] ?? ''}'),
        );
      await _preferences.setString(
        AddonSourcesController.storageKey,
        jsonEncode(ordered),
      );
      changed = true;
    }
    return changed;
  }

  Future<Map<String, Map<String, dynamic>>> _currentAddons() async {
    final Object? decoded = jsonDecode(await _store.exportInstalledJson());
    final Object? rawAddons = decoded is Map ? decoded['addons'] : null;
    if (rawAddons is! List) return <String, Map<String, dynamic>>{};
    final Map<String, Map<String, dynamic>> result =
        <String, Map<String, dynamic>>{};
    for (final Object? raw in rawAddons) {
      if (raw is! Map) continue;
      final Map<String, dynamic> addon = Map<String, dynamic>.from(raw);
      addon.remove('installedAt');
      addon.remove('updatedAt');
      addon.remove('lastCheckedAt');
      addon.remove('lastError');
      final String key = _addonKey(addon);
      if (key.isNotEmpty) result[key] = addon;
    }
    return result;
  }

  Map<String, Map<String, dynamic>> _currentSources() {
    final String raw =
        _preferences.getString(AddonSourcesController.storageKey) ?? '[]';
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <String, Map<String, dynamic>>{};
      return <String, Map<String, dynamic>>{
        for (final Object? value in decoded)
          if (value is Map)
            _sourceKey(Map<String, dynamic>.from(value)): AddonSource.fromJson(
              Map<String, dynamic>.from(value),
            ).toJson(),
      }..removeWhere((String key, Map<String, dynamic> _) => key.isEmpty);
    } on Object {
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<void> _saveSnapshot(
    AddonReplicaSegment segment, {
    required bool pending,
  }) async {
    await _preferences.setString(_snapshotKey, segment.encode());
    await _preferences.setBool(_pendingKey, pending);
  }

  String _addonKey(Map<String, dynamic> value) {
    final String url = '${value['manifestUrl'] ?? ''}'.trim().toLowerCase();
    if (url.isNotEmpty) return url;
    return '${value['id'] ?? ''}'.trim().toLowerCase();
  }

  String _sourceKey(Map<String, dynamic> value) =>
      '${value['url'] ?? ''}'.trim().toLowerCase();

  bool _sameContent(AddonReplicaSegment a, AddonReplicaSegment b) => _sameJson(
    <String, dynamic>{
      'addons': a.toPayload()['addons'],
      'addonTombstones': a.toPayload()['addonTombstones'],
      'sources': a.toPayload()['sources'],
      'sourceTombstones': a.toPayload()['sourceTombstones'],
    },
    <String, dynamic>{
      'addons': b.toPayload()['addons'],
      'addonTombstones': b.toPayload()['addonTombstones'],
      'sources': b.toPayload()['sources'],
      'sourceTombstones': b.toPayload()['sourceTombstones'],
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

  AddonReplicaSegment _copySegment(
    AddonReplicaSegment source, {
    required String deviceId,
    int? revision,
    DateTime? createdAt,
  }) => AddonReplicaSegment(
    deviceId: deviceId,
    revision: revision ?? source.revision,
    createdAt: createdAt ?? source.createdAt,
    addons: source.addons,
    addonTombstones: source.addonTombstones,
    sources: source.sources,
    sourceTombstones: source.sourceTombstones,
  );
}

class _CaptureResult {
  const _CaptureResult({required this.segment, required this.changed});

  final AddonReplicaSegment segment;
  final bool changed;
}
