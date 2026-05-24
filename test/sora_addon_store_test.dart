import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

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

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String url = options.uri.toString();
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
