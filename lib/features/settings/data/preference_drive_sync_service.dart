import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/security/app_secure_storage.dart';
import '../../../core/utils/settings_preferences.dart';
import '../domain/preference_sync_models.dart';
import 'workspace_preferences_store.dart';

class PreferenceDriveSyncResult {
  const PreferenceDriveSyncResult({
    required this.localStateChanged,
    required this.changedKeys,
    required this.pulledSegments,
    required this.pushedSegment,
  });

  final bool localStateChanged;
  final Set<String> changedKeys;
  final int pulledSegments;
  final bool pushedSegment;
}

class PreferenceDriveSyncService {
  PreferenceDriveSyncService({
    required SharedPreferences preferences,
    AppSecureStorage secureStorage = const AppSecureStorage(),
    DateTime Function()? now,
  }) : _preferences = preferences,
       _secureStorage = secureStorage,
       _now = now ?? DateTime.now;

  static const String pendingKey = 'preferences.drive.pending.v1';
  static const String processedKey = 'preferences.drive.processed.v1';
  static const String watchConnectionKey = 'mirushin.watch_party.connection.v1';
  static const String trustedRelaysKey =
      'mirushin.watch_party.trusted_relays.v1';

  static const String tmdbTokenField = 'secure.tmdb.readAccessToken';
  static const String fanartKeyField = 'secure.fanart.apiKey';
  static const String tvdbKeyField = 'secure.tvdb.apiKey';
  static const String tvdbPinField = 'secure.tvdb.subscriberPin';

  static const Set<String> globalPreferenceKeys = <String>{
    SettingsPreferences.tmdbUseCustomKeyKey,
    SettingsPreferences.tmdbLanguageKey,
    SettingsPreferences.tmdbRegionKey,
    SettingsPreferences.tmdbShowAdultContentKey,
    SettingsPreferences.tvdbEnabledKey,
    SettingsPreferences.soraWebProxyUrlKey,
    SettingsPreferences.anilistMobileClientIdKey,
    SettingsPreferences.anilistDesktopClientIdKey,
    SettingsPreferences.anilistDesktopPortKey,
    watchConnectionKey,
    trustedRelaysKey,
  };

  final SharedPreferences _preferences;
  final AppSecureStorage _secureStorage;
  final DateTime Function() _now;

  Future<PreferenceDriveSyncResult> sync({
    required PreferenceCloudReplica cloud,
    required String deviceId,
  }) async {
    final _LoadedPreferenceSnapshot loaded = await _loadSnapshot(deviceId);
    PreferenceReplicaSegment local = loaded.segment;
    final Map<String, Object?> current = await _readCurrentValues();
    final _PreferenceCaptureResult captured = _captureLocal(
      previous: local,
      current: current,
      deviceId: deviceId,
    );
    local = captured.segment;
    bool pending =
        (_preferences.getBool(pendingKey) ?? false) || captured.changed;

    final Set<String> processed =
        _preferences.getStringList(processedKey)?.toSet() ?? <String>{};
    final List<PreferenceReplicaSegment> incoming = await cloud
        .pullPreferenceSegments(excluding: processed);
    final PreferenceReplicaSegment merged = _merge(
      <PreferenceReplicaSegment>[local, ...incoming],
      deviceId: deviceId,
      revision: local.revision,
    );
    final bool localStateChanged = !_sameContent(local, merged);
    final Set<String> changedKeys = localStateChanged
        ? await _applyMerged(current, merged)
        : <String>{};
    local = _copySegment(
      merged,
      deviceId: deviceId,
      revision: local.revision,
      createdAt: localStateChanged ? _now().toUtc() : local.createdAt,
    );

    await _secureStorage.writePreferencesDriveSnapshot(local.encode());
    processed.addAll(
      incoming.map((PreferenceReplicaSegment value) => value.fileName),
    );
    var pushed = false;
    if (pending) {
      await cloud.pushPreferenceSegment(local);
      processed.add(local.fileName);
      pending = false;
      pushed = true;
    }
    await _preferences.setBool(pendingKey, pending);
    await _preferences.setStringList(
      processedKey,
      processed.toList(growable: false)..sort(),
    );
    return PreferenceDriveSyncResult(
      localStateChanged: localStateChanged,
      changedKeys: changedKeys,
      pulledSegments: incoming.length,
      pushedSegment: pushed,
    );
  }

  Future<_LoadedPreferenceSnapshot> _loadSnapshot(String deviceId) async {
    final String raw =
        (await _secureStorage.readPreferencesDriveSnapshot()) ?? '';
    if (raw.isNotEmpty) {
      try {
        return _LoadedPreferenceSnapshot(
          segment: _copySegment(
            PreferenceReplicaSegment.decode(raw),
            deviceId: deviceId,
          ),
        );
      } on Object {
        // Rebuild only this independent replica from the selected keys.
      }
    }
    return _LoadedPreferenceSnapshot(
      segment: PreferenceReplicaSegment(
        deviceId: deviceId,
        revision: 0,
        createdAt: _now().toUtc(),
        values: const <String, PreferenceSyncValue>{},
        tombstones: const <String, PreferenceSyncVersion>{},
      ),
    );
  }

  Future<Map<String, Object?>> _readCurrentValues() async {
    final Map<String, Object?> result = <String, Object?>{};
    for (final String key in _preferences.getKeys()) {
      if (globalPreferenceKeys.contains(key) ||
          key.startsWith(workspacePreferencePrefix)) {
        final Object? value = _preferences.get(key);
        if (_isSupported(value)) {
          result[key] = value is List
              ? value.cast<String>().toList(growable: false)
              : value;
        }
      }
    }
    final Map<String, String?> secrets = <String, String?>{
      tmdbTokenField: await _secureStorage.readTmdbReadAccessToken(),
      fanartKeyField: await _secureStorage.readFanartTvApiKey(),
      tvdbKeyField: await _secureStorage.readTvdbApiKey(),
      tvdbPinField: await _secureStorage.readTvdbSubscriberPin(),
    };
    for (final MapEntry<String, String?> entry in secrets.entries) {
      final String value = entry.value?.trim() ?? '';
      if (value.isNotEmpty) result[entry.key] = value;
    }
    return result;
  }

  _PreferenceCaptureResult _captureLocal({
    required PreferenceReplicaSegment previous,
    required Map<String, Object?> current,
    required String deviceId,
  }) {
    final Map<String, PreferenceSyncValue> values =
        <String, PreferenceSyncValue>{...previous.values};
    final Map<String, PreferenceSyncVersion> tombstones =
        <String, PreferenceSyncVersion>{...previous.tombstones};
    var changed = false;
    for (final MapEntry<String, Object?> entry in current.entries) {
      final PreferenceSyncValue? old = values[entry.key];
      if (old == null || !_sameJson(old.value, entry.value)) {
        final PreferenceSyncVersion version = PreferenceSyncVersion(
          changedAt: _now().toUtc(),
          deviceId: deviceId,
        );
        values[entry.key] = PreferenceSyncValue(
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
      tombstones[key] = PreferenceSyncVersion(
        changedAt: _now().toUtc(),
        deviceId: deviceId,
      );
      changed = true;
    }
    if (!changed) {
      return _PreferenceCaptureResult(segment: previous, changed: false);
    }
    return _PreferenceCaptureResult(
      segment: PreferenceReplicaSegment(
        deviceId: deviceId,
        revision: previous.revision + 1,
        createdAt: _now().toUtc(),
        values: values,
        tombstones: tombstones,
      ),
      changed: true,
    );
  }

  PreferenceReplicaSegment _merge(
    Iterable<PreferenceReplicaSegment> segments, {
    required String deviceId,
    required int revision,
  }) {
    final Map<String, PreferenceSyncValue> values =
        <String, PreferenceSyncValue>{};
    final Map<String, PreferenceSyncVersion> tombstones =
        <String, PreferenceSyncVersion>{};
    for (final PreferenceReplicaSegment segment in segments) {
      for (final MapEntry<String, PreferenceSyncValue> entry
          in segment.values.entries) {
        final PreferenceSyncValue? existing = values[entry.key];
        final PreferenceSyncVersion? deleted = tombstones[entry.key];
        if ((existing == null ||
                entry.value.version.compareTo(existing.version) > 0) &&
            (deleted == null || entry.value.version.compareTo(deleted) > 0)) {
          values[entry.key] = entry.value;
          tombstones.remove(entry.key);
        }
      }
      for (final MapEntry<String, PreferenceSyncVersion> entry
          in segment.tombstones.entries) {
        final PreferenceSyncValue? existing = values[entry.key];
        final PreferenceSyncVersion? deleted = tombstones[entry.key];
        if ((existing == null ||
                entry.value.compareTo(existing.version) >= 0) &&
            (deleted == null || entry.value.compareTo(deleted) > 0)) {
          values.remove(entry.key);
          tombstones[entry.key] = entry.value;
        }
      }
    }
    return PreferenceReplicaSegment(
      deviceId: deviceId,
      revision: revision,
      createdAt: _now().toUtc(),
      values: values,
      tombstones: tombstones,
    );
  }

  Future<Set<String>> _applyMerged(
    Map<String, Object?> current,
    PreferenceReplicaSegment merged,
  ) async {
    final Set<String> changed = <String>{};
    for (final MapEntry<String, PreferenceSyncValue> entry
        in merged.values.entries) {
      if (_sameJson(current[entry.key], entry.value.value)) continue;
      await _writeValue(entry.key, entry.value.value);
      changed.add(entry.key);
    }
    for (final String key in merged.tombstones.keys) {
      if (!current.containsKey(key)) continue;
      await _removeValue(key);
      changed.add(key);
    }
    return changed;
  }

  Future<void> _writeValue(String key, Object? value) async {
    if (key == tmdbTokenField) {
      return _secureStorage.writeTmdbReadAccessToken('$value');
    }
    if (key == fanartKeyField) {
      return _secureStorage.writeFanartTvApiKey('$value');
    }
    if (key == tvdbKeyField) {
      return _secureStorage.writeTvdbApiKey('$value');
    }
    if (key == tvdbPinField) {
      return _secureStorage.writeTvdbSubscriberPin('$value');
    }
    if (value is String) {
      await _preferences.setString(key, value);
      return;
    }
    if (value is bool) {
      await _preferences.setBool(key, value);
      return;
    }
    if (value is int) {
      await _preferences.setInt(key, value);
      return;
    }
    if (value is double) {
      await _preferences.setDouble(key, value);
      return;
    }
    if (value is List) {
      await _preferences.setStringList(
        key,
        value.map((Object? item) => '$item').toList(growable: false),
      );
      return;
    }
    throw FormatException('Unsupported Drive preference value for $key.');
  }

  Future<void> _removeValue(String key) async {
    if (key == tmdbTokenField) {
      return _secureStorage.writeTmdbReadAccessToken('');
    }
    if (key == fanartKeyField) {
      return _secureStorage.writeFanartTvApiKey('');
    }
    if (key == tvdbKeyField) return _secureStorage.writeTvdbApiKey('');
    if (key == tvdbPinField) {
      return _secureStorage.writeTvdbSubscriberPin('');
    }
    await _preferences.remove(key);
  }

  PreferenceReplicaSegment _copySegment(
    PreferenceReplicaSegment source, {
    required String deviceId,
    int? revision,
    DateTime? createdAt,
  }) => PreferenceReplicaSegment(
    deviceId: deviceId,
    revision: revision ?? source.revision,
    createdAt: createdAt ?? source.createdAt,
    values: source.values,
    tombstones: source.tombstones,
  );

  bool _sameContent(PreferenceReplicaSegment a, PreferenceReplicaSegment b) =>
      _sameJson(
        <String, dynamic>{
          'values': a.toPayload()['values'],
          'tombstones': a.toPayload()['tombstones'],
        },
        <String, dynamic>{
          'values': b.toPayload()['values'],
          'tombstones': b.toPayload()['tombstones'],
        },
      );

  bool _sameJson(Object? a, Object? b) =>
      jsonEncode(_stable(a)) == jsonEncode(_stable(b));

  Object? _stable(Object? value) {
    if (value is Map) {
      final List<String> keys = value.keys.map((Object? key) => '$key').toList()
        ..sort();
      return <String, Object?>{
        for (final String key in keys) key: _stable(value[key]),
      };
    }
    if (value is List) return value.map(_stable).toList(growable: false);
    return value;
  }

  bool _isSupported(Object? value) =>
      value is String ||
      value is bool ||
      value is int ||
      value is double ||
      (value is List && value.every((Object? item) => item is String));
}

class _LoadedPreferenceSnapshot {
  const _LoadedPreferenceSnapshot({required this.segment});
  final PreferenceReplicaSegment segment;
}

class _PreferenceCaptureResult {
  const _PreferenceCaptureResult({
    required this.segment,
    required this.changed,
  });
  final PreferenceReplicaSegment segment;
  final bool changed;
}
