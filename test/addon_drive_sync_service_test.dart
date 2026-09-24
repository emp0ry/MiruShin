import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/application/addon_sources_provider.dart';
import 'package:mirushin/features/addons/data/addon_drive_sync_service.dart';
import 'package:mirushin/features/addons/data/sora_addon_clipboard.dart';
import 'package:mirushin/features/addons/data/sora_addon_store.dart';
import 'package:mirushin/features/addons/domain/addon_source_models.dart';
import 'package:mirushin/features/addons/domain/addon_sync_models.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addon segment rejects a modified payload', () {
    final AddonReplicaSegment segment = AddonReplicaSegment(
      deviceId: 'device-a',
      revision: 1,
      createdAt: DateTime.utc(2026, 9, 24),
      addons: const <String, AddonSyncValue>{},
      addonTombstones: const <String, AddonSyncVersion>{},
      sources: const <String, AddonSyncValue>{},
      sourceTombstones: const <String, AddonSyncVersion>{},
    );
    final Map<String, dynamic> wrapper = Map<String, dynamic>.from(
      jsonDecode(segment.encode()) as Map,
    );
    wrapper['payload'] = '${wrapper['payload']} ';

    expect(
      () => AddonReplicaSegment.decode(jsonEncode(wrapper)),
      throwsFormatException,
    );
  });

  test(
    'online and offline addons, sources, and deletions sync across devices',
    () async {
      final Directory directoryA = await Directory.systemTemp.createTemp(
        'mirushin_addon_drive_a_',
      );
      final Directory directoryB = await Directory.systemTemp.createTemp(
        'mirushin_addon_drive_b_',
      );
      addTearDown(() => directoryA.delete(recursive: true));
      addTearDown(() => directoryB.delete(recursive: true));

      final _MemoryAddonCloud cloud = _MemoryAddonCloud();
      final _FakeAdapter adapterA = _FakeAdapter(_networkResponses);
      final SoraAddonStore storeA = SoraAddonStore(
        dio: Dio()..httpClientAdapter = adapterA,
        supportDirectoryProvider: () async => directoryA,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferencesA =
          await SharedPreferences.getInstance();

      final SoraInstalledAddon onlineA = await storeA.installFromPreview(
        await storeA.previewFromUrl(_onlineManifestUrl),
      );
      await storeA.setEnabled(onlineA.id, false);
      final SoraInstalledAddon offlineA = await storeA.installFromPreview(
        await storeA.previewFromLocalFiles(_offlineFiles()),
      );
      expect(offlineA.isLocal, isTrue);
      final AddonSource source = AddonSource(
        id: 'catalog-1',
        url: 'https://catalog.example/modules.json',
        name: 'Test catalog',
        addedAt: DateTime.utc(2026, 9, 24, 10),
      );
      await preferencesA.setString(
        AddonSourcesController.storageKey,
        jsonEncode(<Map<String, dynamic>>[source.toJson()]),
      );

      var clock = DateTime.utc(2026, 9, 24, 12);
      DateTime now() {
        clock = clock.add(const Duration(seconds: 1));
        return clock;
      }

      final AddonDriveSyncResult first = await AddonDriveSyncService(
        preferences: preferencesA,
        store: storeA,
        now: now,
      ).sync(cloud: cloud, deviceId: 'device-a');
      expect(first.pushedSegment, isTrue);
      expect(cloud.files, hasLength(1));
      final Map<String, Object> savedPreferencesA = <String, Object>{
        for (final String key in preferencesA.getKeys())
          if (preferencesA.get(key) case final Object value) key: value,
      };

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences preferencesB =
          await SharedPreferences.getInstance();
      final _FakeAdapter adapterB = _FakeAdapter(_networkResponses);
      final SoraAddonStore storeB = SoraAddonStore(
        dio: Dio()..httpClientAdapter = adapterB,
        supportDirectoryProvider: () async => directoryB,
      );
      final AddonDriveSyncResult restored = await AddonDriveSyncService(
        preferences: preferencesB,
        store: storeB,
        now: now,
      ).sync(cloud: cloud, deviceId: 'device-b');

      expect(restored.localStateChanged, isTrue);
      final List<SoraInstalledAddon> installedB = await storeB.loadInstalled();
      expect(installedB, hasLength(2));
      expect(
        installedB
            .singleWhere((SoraInstalledAddon addon) => !addon.isLocal)
            .enabled,
        isFalse,
      );
      final SoraInstalledAddon offlineB = installedB.singleWhere(
        (SoraInstalledAddon addon) => addon.isLocal,
      );
      expect(await storeB.readScript(offlineB), _offlineScript);
      expect(offlineB.manifestPath, startsWith(directoryB.path));
      expect(offlineB.manifestPath, isNot(contains(directoryA.path)));
      expect(
        jsonDecode(preferencesB.getString(AddonSourcesController.storageKey)!),
        hasLength(1),
      );

      await storeB.remove(offlineB.id);
      await preferencesB.setString(AddonSourcesController.storageKey, '[]');
      final AddonDriveSyncResult removed = await AddonDriveSyncService(
        preferences: preferencesB,
        store: storeB,
        now: now,
      ).sync(cloud: cloud, deviceId: 'device-b');
      expect(removed.pushedSegment, isTrue);
      expect(cloud.files, hasLength(2));

      SharedPreferences.setMockInitialValues(savedPreferencesA);
      final SharedPreferences restoredPreferencesA =
          await SharedPreferences.getInstance();
      final AddonDriveSyncResult mergedBack = await AddonDriveSyncService(
        preferences: restoredPreferencesA,
        store: storeA,
        now: now,
      ).sync(cloud: cloud, deviceId: 'device-a');

      expect(mergedBack.localStateChanged, isTrue);
      final List<SoraInstalledAddon> finalA = await storeA.loadInstalled();
      expect(finalA, hasLength(1));
      expect(finalA.single.isLocal, isFalse);
      expect(
        jsonDecode(
          restoredPreferencesA.getString(AddonSourcesController.storageKey)!,
        ),
        isEmpty,
      );
    },
  );
}

const String _onlineManifestUrl = 'https://example.com/addon.json';
const String _onlineScriptUrl = 'https://example.com/module.js';
const String _offlineScript = '''
async function searchResults() { return "[]"; }
async function extractDetails() { return "{}"; }
async function extractEpisodes() { return "[]"; }
async function extractStreamUrl() { return "{}"; }
''';

const Map<String, String> _networkResponses = <String, String>{
  _onlineManifestUrl: '''
{
  "sourceName": "Online test",
  "version": "1.0.0",
  "language": "en",
  "streamType": "HLS",
  "quality": "1080p",
  "baseUrl": "https://example.com",
  "searchBaseUrl": "https://example.com/search?q=%s",
  "scriptURL": "./module.js",
  "type": "anime",
  "downloadSupport": false
}
''',
  _onlineScriptUrl: _offlineScript,
};

SoraLocalAddonFiles _offlineFiles() =>
    SoraLocalAddonFiles.fromFiles(<SoraAddonClipboardFile>[
      SoraAddonClipboardFile(
        name: 'offline.json',
        bytes: Uint8List.fromList(
          utf8.encode('''
{
  "sourceName": "Offline test",
  "version": "1.0.0",
  "language": "en",
  "streamType": "HLS",
  "quality": "1080p",
  "baseUrl": "https://offline.example",
  "searchBaseUrl": "https://offline.example/search?q=%s",
  "scriptURL": "offline.js",
  "type": "anime",
  "downloadSupport": false
}
'''),
        ),
      ),
      SoraAddonClipboardFile(
        name: 'offline.js',
        bytes: Uint8List.fromList(utf8.encode(_offlineScript)),
      ),
    ]);

class _MemoryAddonCloud implements AddonCloudReplica {
  final Map<String, String> files = <String, String>{};

  @override
  Future<List<AddonReplicaSegment>> pullAddonSegments({
    required Set<String> excluding,
  }) async => files.entries
      .where((MapEntry<String, String> entry) => !excluding.contains(entry.key))
      .map(
        (MapEntry<String, String> entry) =>
            AddonReplicaSegment.decode(entry.value),
      )
      .toList(growable: false);

  @override
  Future<void> pushAddonSegment(AddonReplicaSegment segment) async {
    files.putIfAbsent(segment.fileName, segment.encode);
  }
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(Map<String, String> responses)
    : responses = Map<String, String>.from(responses);

  final Map<String, String> responses;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String? body = responses[options.uri.toString()];
    if (body == null) return ResponseBody.fromString('missing', 404);
    return ResponseBody.fromString(body, 200);
  }

  @override
  void close({bool force = false}) {}
}
