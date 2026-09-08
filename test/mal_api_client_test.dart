import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/data/mal_api_client.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  test('MAL catalog search maps ids and detail metadata', () async {
    final _FakeMalAdapter adapter = _FakeMalAdapter();
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final MalApiClient client = MalApiClient(accessToken: 'token', dio: dio);

    final List<MediaItem> search = await client.searchAnime(
      'Fullmetal Alchemist',
    );
    final MediaItem? details = await client.fetchAnimeDetails(5114);

    expect(search.single.id, 'mal:5114');
    expect(search.single.externalIds['mal'], '5114');
    expect(details?.overview, 'Two brothers search for the Philosopher Stone.');
    expect(details?.genres, <String>['Action', 'Adventure']);
    expect(details?.runtimeMinutes, 24);
    expect(details?.aliases, contains('Fullmetal Alchemist: Brotherhood'));
    expect(details?.externalIds['mal_source'], 'MANGA');
    expect(details?.externalIds['mal_nsfw'], 'white');
    expect(details?.externalIds['mal_start_date'], '2009-04-05');
    expect(adapter.authorizationHeaders, everyElement('Bearer token'));
  });

  test('MAL library maps dates and metadata used by Library filters', () async {
    final _FakeMalAdapter adapter = _FakeMalAdapter();
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final MalApiClient client = MalApiClient(accessToken: 'token', dio: dio);

    final AniListAnimeListEntry entry =
        (await client.fetchAnimeList()).single.entries.single;

    expect(entry.status, AniListListStatus.current);
    expect(entry.progress, 3);
    expect(entry.notes, 'offline note');
    expect(entry.repeat, 1);
    expect(entry.updatedAt, 1788220800);
    expect(entry.startedAt, DateTime(2026, 8, 1));
    expect(entry.completedAt, DateTime(2026, 8, 31));
    expect(entry.avgScore, 91);
    expect(entry.format, 'TV');
    expect(entry.mediaItem.genres, <String>['Action', 'Adventure']);
    expect(entry.mediaItem.statusLabel, 'FINISHED_AIRING');
  });

  test('MAL ranking uses requested type and page offset', () async {
    final _FakeMalAdapter adapter = _FakeMalAdapter();
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final MalApiClient client = MalApiClient(accessToken: 'token', dio: dio);

    await client.fetchAnimeRanking(
      rankingType: 'bypopularity',
      page: 3,
      pageSize: 20,
    );

    expect(adapter.lastQuery?['ranking_type'], 'bypopularity');
    expect(adapter.lastQuery?['offset'], 40);
    expect(adapter.lastQuery?['limit'], 20);
  });
}

class _FakeMalAdapter implements HttpClientAdapter {
  final List<String?> authorizationHeaders = <String?>[];
  Map<String, dynamic>? lastQuery;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeaders.add(options.headers['Authorization']?.toString());
    lastQuery = Map<String, dynamic>.from(options.queryParameters);
    if (options.uri.path == '/users/@me/animelist') {
      return _json(
        jsonEncode(<String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'node': _node(),
              'list_status': <String, dynamic>{
                'status': 'watching',
                'score': 9,
                'num_episodes_watched': 3,
                'comments': 'offline note',
                'num_times_rewatched': 1,
                'start_date': '2026-08-01',
                'finish_date': '2026-08-31',
                'updated_at': '2026-09-01T00:00:00Z',
              },
            },
          ],
        }),
      );
    }
    if (options.uri.path == '/anime/5114') {
      return _json(jsonEncode(_node()));
    }
    return _json(
      jsonEncode(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'node': _node()},
        ],
      }),
    );
  }

  Map<String, dynamic> _node() => <String, dynamic>{
    'id': 5114,
    'title': 'Fullmetal Alchemist: Brotherhood',
    'main_picture': <String, dynamic>{
      'medium': 'https://example.com/medium.jpg',
      'large': 'https://example.com/large.jpg',
    },
    'alternative_titles': <String, dynamic>{
      'synonyms': <String>['Hagane no Renkinjutsushi'],
      'en': 'Fullmetal Alchemist: Brotherhood',
      'ja': '鋼の錬金術師 FULLMETAL ALCHEMIST',
    },
    'start_season': <String, dynamic>{'year': 2009, 'season': 'spring'},
    'start_date': '2009-04-05',
    'mean': 9.1,
    'media_type': 'tv',
    'source': 'manga',
    'nsfw': 'white',
    'synopsis': 'Two brothers search for the Philosopher Stone.',
    'genres': <Map<String, dynamic>>[
      <String, dynamic>{'id': 1, 'name': 'Action'},
      <String, dynamic>{'id': 2, 'name': 'Adventure'},
    ],
    'status': 'finished_airing',
    'average_episode_duration': 1440,
    'num_episodes': 64,
    'pictures': <Map<String, dynamic>>[
      <String, dynamic>{'large': 'https://example.com/backdrop.jpg'},
    ],
  };

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
