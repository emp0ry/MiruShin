import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/data/sora_addon_clipboard.dart';
import 'package:mirushin/features/addons/data/sora_addon_store.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';

void main() {
  test(
    'store installs, updates, removes, and preserves old copy on failure',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'sora_store_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final _FakeAdapter adapter = _FakeAdapter(<String, String>{
        'https://example.com/addon.json': _manifest(version: '1.0.0'),
        'https://example.com/module.js':
            'async function searchResults() { return "[]"; }',
      });
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final SoraAddonStore store = SoraAddonStore(
        dio: dio,
        supportDirectoryProvider: () async => temp,
      );

      final SoraAddonPreview preview = await store.previewFromUrl(
        'https://example.com/addon.json',
      );
      expect(preview.manifest.scriptUrl, './module.js');

      final SoraInstalledAddon installed = await store.installFromPreview(
        preview,
      );
      final String remoteExport = await store.exportInstalledJson();
      final Map<String, dynamic> remoteDocument = Map<String, dynamic>.from(
        jsonDecode(remoteExport) as Map,
      );
      final Map<String, dynamic> exportedAddon = Map<String, dynamic>.from(
        (remoteDocument['addons'] as List<dynamic>).single as Map,
      );
      expect(exportedAddon['manifestUrl'], 'https://example.com/addon.json');
      expect(exportedAddon.containsKey('localFiles'), isFalse);
      expect(exportedAddon.containsKey('manifestPath'), isFalse);
      expect(exportedAddon.containsKey('scriptPath'), isFalse);
      expect(
        await File(installed.scriptPath).readAsString(),
        contains('searchResults'),
      );
      expect(await store.loadInstalled(), hasLength(1));

      adapter.responses['https://example.com/addon.json'] = _manifest(
        version: '2.0.0',
      );
      adapter.responses['https://example.com/module.js'] =
          'async function searchResults() { return JSON.stringify([{title:"New",href:"/new"}]); }';

      final SoraInstalledAddon updated = await store.update(installed);
      expect(updated.manifest.version, '2.0.0');
      expect(updated.lastError, isNull);
      expect(await File(updated.scriptPath).readAsString(), contains('/new'));

      adapter.failUrls.add('https://example.com/addon.json');
      final SoraInstalledAddon failed = await store.update(updated);
      expect(failed.manifest.version, '2.0.0');
      expect(failed.lastError, isNotNull);
      expect(await File(failed.scriptPath).readAsString(), contains('/new'));

      await store.remove(failed.id);
      expect(await store.loadInstalled(), isEmpty);
    },
  );

  test(
    'local clipboard files install the copied script without network access',
    () async {
      final Directory temp = await Directory.systemTemp.createTemp(
        'sora_local_store_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final _FakeAdapter adapter = _FakeAdapter(<String, String>{});
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final SoraAddonStore store = SoraAddonStore(
        dio: dio,
        supportDirectoryProvider: () async => temp,
      );
      const String script = '''
async function searchResults() { return "[]"; }
async function extractDetails() { return "{}"; }
async function extractEpisodes() { return "[]"; }
async function extractStreamUrl() { return "{}"; }
''';
      final SoraLocalAddonFiles files =
          SoraLocalAddonFiles.fromFiles(<SoraAddonClipboardFile>[
            SoraAddonClipboardFile(
              name: 'yummyanime.json',
              bytes: Uint8List.fromList(utf8.encode(_yummyAnimeManifest)),
            ),
            SoraAddonClipboardFile(
              name: 'yummyanime.js',
              bytes: Uint8List.fromList(utf8.encode(script)),
            ),
          ]);

      final SoraAddonPreview preview = await store.previewFromLocalFiles(files);

      expect(preview.manifest.sourceName, 'YummyAnime');
      expect(
        preview.manifest.scriptUrl,
        'https://git.luna-app.eu/50n50/sources/raw/branch/main/'
        'yummyanime/yummyanime.js',
      );
      expect(preview.scriptUrl, 'yummyanime.js');
      expect(adapter.requestedUrls, isEmpty);

      final SoraInstalledAddon installed = await store.installFromPreview(
        preview,
      );

      expect(installed.isLocal, isTrue);
      expect(
        await File(installed.manifestPath).readAsString(),
        _yummyAnimeManifest,
      );
      expect(await File(installed.scriptPath).readAsString(), script);
      expect(await store.readScript(installed), script);
      expect(adapter.requestedUrls, isEmpty);

      final SoraInstalledAddon updated = await store.update(installed);
      expect(updated, same(installed));
      expect(adapter.requestedUrls, isEmpty);

      await store.setEnabled(installed.id, false);
      final String localExport = await store.exportInstalledJson();
      final Map<String, dynamic> localDocument = Map<String, dynamic>.from(
        jsonDecode(localExport) as Map,
      );
      final Map<String, dynamic> exportedAddon = Map<String, dynamic>.from(
        (localDocument['addons'] as List<dynamic>).single as Map,
      );
      final Map<String, dynamic> exportedFiles = Map<String, dynamic>.from(
        exportedAddon['localFiles'] as Map,
      );
      final Map<String, dynamic> exportedManifest = Map<String, dynamic>.from(
        exportedFiles['manifest'] as Map,
      );
      final Map<String, dynamic> exportedScript = Map<String, dynamic>.from(
        exportedFiles['script'] as Map,
      );
      expect(exportedAddon['enabled'], isFalse);
      expect(exportedAddon.containsKey('manifestPath'), isFalse);
      expect(exportedAddon.containsKey('scriptPath'), isFalse);
      expect(exportedManifest['name'], 'YummyAnime.json');
      expect(exportedManifest['content'], _yummyAnimeManifest);
      expect(exportedScript['name'], 'YummyAnime.js');
      expect(exportedScript['content'], script);
      expect(localDocument['remoteModules'], isEmpty);

      final Directory restoredTemp = await Directory.systemTemp.createTemp(
        'sora_local_export_restore_',
      );
      addTearDown(() => restoredTemp.delete(recursive: true));
      final _FakeAdapter restoredAdapter = _FakeAdapter(<String, String>{});
      final SoraAddonStore restoredStore = SoraAddonStore(
        dio: Dio()..httpClientAdapter = restoredAdapter,
        supportDirectoryProvider: () async => restoredTemp,
      );
      final SoraAddonImportResult importResult = await restoredStore
          .importInstalledJson(localExport);
      expect(importResult.installed, 1);
      expect(importResult.failed, 0);
      final SoraInstalledAddon restored =
          (await restoredStore.loadInstalled()).single;
      expect(restored.isLocal, isTrue);
      expect(restored.enabled, isFalse);
      expect(await restoredStore.readScript(restored), script);
      expect(restoredAdapter.requestedUrls, isEmpty);
    },
  );
}

const String _yummyAnimeManifest = '''{
  "sourceName": "YummyAnime",
  "iconUrl": "https://site.yummyani.me/img/icon/yummy-192.png",
  "author": {
    "name": "emp0ry",
    "icon": "https://avatars.githubusercontent.com/u/64217088"
  },
  "version": "1.0.4",
  "language": "Russian",
  "streamType": "HLS",
  "quality": "1080p",
  "baseUrl": "https://api.yani.tv",
  "searchBaseUrl": "https://api.yani.tv/search?limit=30&q=%s",
  "scriptUrl": "https://git.luna-app.eu/50n50/sources/raw/branch/main/yummyanime/yummyanime.js",
  "asyncJS": true,
  "streamAsyncJS": true,
  "softsub": false,
  "type": "anime",
  "downloadSupport": false,
  "supportsMojuru": true,
  "supportsDartotsu": true,
  "supportsSora": true,
  "supportsLuna": true
}
''';

String _manifest({required String version}) {
  return '''
{
  "sourceName": "Demo Sora",
  "iconUrl": "https://example.com/icon.png",
  "author": {"name": "Tester", "icon": "https://example.com/author.png"},
  "version": "$version",
  "language": "en",
  "streamType": "HLS",
  "quality": "1080p",
  "baseUrl": "https://example.com",
  "searchBaseUrl": "https://example.com/search",
  "scriptURL": "./module.js",
  "type": "anime",
  "downloadSupport": false
}
''';
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses);

  final Map<String, String> responses;
  final Set<String> failUrls = <String>{};
  final List<String> requestedUrls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String url = options.uri.toString();
    requestedUrls.add(url);
    if (failUrls.contains(url)) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'network down',
      );
    }
    final String? body = responses[url];
    if (body == null) {
      return ResponseBody.fromString('missing', 404);
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
