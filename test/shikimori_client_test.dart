import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/metadata/data/shikimori_client.dart';

void main() {
  test('batchRussianTitles fetches large libraries in chunks', () async {
    final _FakeShikimoriAdapter adapter = _FakeShikimoriAdapter();
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ShikiMoriClient client = ShikiMoriClient(dio: dio);

    final Map<int, String> titles = await client.batchRussianTitles(
      List<int>.generate(55, (int index) => index + 1),
    );

    expect(titles, hasLength(55));
    expect(titles[1], 'Русское название 1');
    expect(titles[55], 'Русское название 55');
    expect(adapter.requestedIdChunks, hasLength(2));
    expect(adapter.requestedIdChunks.first, hasLength(50));
    expect(adapter.requestedIdChunks.last, hasLength(5));
  });

  test(
    'details lookup falls back from MAL id to Shikimori search id',
    () async {
      final _FakeShikimoriAdapter adapter = _FakeShikimoriAdapter()
        ..detailsById[999] = <String, Object>{
          'id': 999,
          'id_mal': 1,
          'russian': 'Неправильный тайтл',
          'description': 'Wrong match',
        }
        ..searchResults['Real Title'] = <Map<String, Object>>[
          <String, Object>{
            'id': 321,
            'id_mal': 999,
            'russian': 'Правильный тайтл',
            'name': 'real-title',
          },
        ]
        ..detailsById[321] = <String, Object>{
          'id': 321,
          'id_mal': 999,
          'russian': 'Правильный тайтл',
          'description': '[b]Русское описание[/b]',
        };
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final ShikiMoriClient client = ShikiMoriClient(dio: dio);

      final ({String title, String description})? details = await client
          .getRussianDetailsForMedia(
            malId: 999,
            queries: <String>['Real Title'],
          );

      expect(details?.title, 'Правильный тайтл');
      expect(details?.description, 'Русское описание');
    },
  );
}

class _FakeShikimoriAdapter implements HttpClientAdapter {
  final List<List<int>> requestedIdChunks = <List<int>>[];
  final Map<int, Map<String, Object>> detailsById =
      <int, Map<String, Object>>{};
  final Map<String, List<Map<String, Object>>> searchResults =
      <String, List<Map<String, Object>>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final RegExpMatch? detailMatch = RegExp(
      r'/api/animes/(\d+)$',
    ).firstMatch(options.uri.path);
    if (detailMatch != null) {
      final int id = int.parse(detailMatch.group(1)!);
      return _json(jsonEncode(detailsById[id] ?? <String, Object>{}));
    }

    final String search = options.queryParameters['search']?.toString() ?? '';
    if (search.isNotEmpty) {
      return _json(
        jsonEncode(searchResults[search] ?? const <Map<String, Object>>[]),
      );
    }

    final String ids = options.queryParameters['ids']?.toString() ?? '';
    final List<int> parsedIds = ids
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    requestedIdChunks.add(parsedIds);

    final String body = jsonEncode(
      parsedIds
          .map(
            (int id) => <String, Object>{
              'id_mal': id,
              'russian': 'Русское название $id',
            },
          )
          .toList(growable: false),
    );
    return _json(body);
  }

  ResponseBody _json(String body) {
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
