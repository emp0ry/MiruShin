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

      final ShikimoriRussianDetails? details = await client
          .getRussianDetailsForMedia(
            malId: 999,
            queries: <String>['Real Title'],
          );

      expect(details?.title, 'Правильный тайтл');
      expect(details?.description, 'Русское описание');
    },
  );

  test('details lookup extracts russian YouTube trailer from videos', () async {
    final _FakeShikimoriAdapter adapter = _FakeShikimoriAdapter()
      ..detailsById[10] = <String, Object>{
        'id': 10,
        'id_mal': 10,
        'russian': 'Русский тайтл',
        'description': 'Описание',
        'videos': <Map<String, Object>>[
          <String, Object>{
            'url': 'https://vimeo.com/123',
            'hosting': 'vimeo',
            'kind': 'pv',
            'name': 'Трейлер',
          },
          <String, Object>{
            'url': 'https://www.youtube.com/watch?v=official',
            'hosting': 'youtube',
            'kind': 'op',
            'name': 'Opening',
          },
          <String, Object>{
            'url': 'https://youtu.be/unmarked-russian-trailer',
            'hosting': 'youtube',
            'kind': 'pv',
            'name': 'Русский трейлер',
          },
          <String, Object>{
            'url': 'https://youtu.be/bTccQKVzVlk',
            'player_url': 'http://youtube.com/embed/bTccQKVzVlk',
            'hosting': 'youtube',
            'kind': 'pv',
            'name': 'PV1 (AniMeow) Субтитры',
          },
          <String, Object>{
            'url': 'https://youtu.be/oXJrZUYWLcQ',
            'player_url': 'http://youtube.com/embed/oXJrZUYWLcQ',
            'hosting': 'youtube',
            'kind': 'pv',
            'name': 'Тизер (Shaman & Лизавета) Озвучка',
          },
        ],
      };
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ShikiMoriClient client = ShikiMoriClient(dio: dio);

    final ShikimoriRussianDetails? details = await client
        .getRussianDetailsForMedia(malId: 10);

    expect(details?.youtubeTrailerUrl, 'https://youtu.be/oXJrZUYWLcQ');
  });

  test(
    'details lookup accepts Shikimori player_url trailer fallback',
    () async {
      final _FakeShikimoriAdapter adapter = _FakeShikimoriAdapter()
        ..detailsById[20] = <String, Object>{
          'id': 20,
          'id_mal': 20,
          'russian': 'Русский тайтл',
          'description': 'Описание',
          'videos': <Map<String, Object>>[
            <String, Object>{
              'url': '',
              'player_url': 'http://youtube.com/embed/oXJrZUYWLcQ',
              'hosting': 'youtube',
              'kind': 'pv',
              'name': 'Тизер (Shaman & Лизавета)',
              'description': 'Озвучка',
            },
          ],
        };
      final Dio dio = Dio()..httpClientAdapter = adapter;
      final ShikiMoriClient client = ShikiMoriClient(dio: dio);

      final ShikimoriRussianDetails? details = await client
          .getRussianDetailsForMedia(malId: 20);

      expect(
        details?.youtubeTrailerUrl,
        'http://youtube.com/embed/oXJrZUYWLcQ',
      );
    },
  );

  test('details lookup ignores non-YouTube Shikimori voice trailer', () async {
    final _FakeShikimoriAdapter adapter = _FakeShikimoriAdapter()
      ..detailsById[61839] = <String, Object>{
        'id': 61839,
        'myanimelist_id': 61839,
        'russian': 'Я хочу закончить эту игру любви',
        'description': 'Описание',
        'videos': <Map<String, Object>>[
          <String, Object>{
            'name': 'Тизер',
            'kind': 'pv',
            'hosting': 'vk',
            'url': 'https://vk.com/video-34484100_456249277',
            'player_url':
                'https://vk.com/video_ext.php?oid=-34484100&id=456249277&hash=79f82f593a54bc2f',
          },
          <String, Object>{
            'name': 'Тизер (Silver AniAge) Озвучка',
            'kind': 'pv',
            'hosting': 'vk',
            'url': 'https://vk.com/video-200497484_456241464',
            'player_url':
                'https://vk.com/video_ext.php?oid=-200497484&id=456241464&hash=6a6ded50fdbc368d',
          },
        ],
      };
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final ShikiMoriClient client = ShikiMoriClient(dio: dio);

    final ShikimoriRussianDetails? details = await client
        .getRussianDetailsForMedia(malId: 61839);

    expect(details?.youtubeTrailerUrl, isEmpty);
  });
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
