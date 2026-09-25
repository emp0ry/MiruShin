import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';

void main() {
  test('AniList library snapshot contains offline detail metadata', () async {
    final _AniListLibraryAdapter adapter = _AniListLibraryAdapter();
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final AniListApiClient client = AniListApiClient(
      accessToken: 'token',
      dio: dio,
    );

    final entry = (await client.fetchAnimeListCollection(
      userId: 7,
    )).single.entries.single;

    expect(adapter.query, contains('description(asHtml: false)'));
    expect(adapter.query, contains('bannerImage'));
    expect(adapter.query, contains('studios { nodes'));
    expect(adapter.query, contains('tags { name rank'));
    expect(entry.mediaItem.overview, 'Offline description');
    expect(entry.mediaItem.backdropUrl, contains('banner.jpg'));
    expect(entry.mediaItem.aliases, contains('Offline alias'));
    expect(entry.mediaItem.externalIds['anilist_format'], 'TV');
    expect(entry.mediaItem.externalIds['anilist_studios'], 'ENGI:1');
    expect(entry.mediaItem.externalIds['anilist_tags'], contains('Comedy'));
    expect(entry.mediaItem.externalIds['anilist_popularity'], '12345');
    expect(entry.mediaItem.externalIds['anilist_end_date'], '2020-09-25');
    expect(
      entry.mediaItem.externalIds['mirushin_anilist_metadata'],
      'library_v2',
    );
    expect(entry.mediaItem.trailer?.youtubeId, 'trailer-id');
  });
}

class _AniListLibraryAdapter implements HttpClientAdapter {
  String query = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Object? data = options.data;
    if (data is Map) query = '${data['query'] ?? ''}';
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'MediaListCollection': <String, dynamic>{
            'lists': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Watching',
                'status': 'CURRENT',
                'entries': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 99,
                    'status': 'CURRENT',
                    'progress': 3,
                    'score': 8,
                    'scoreRaw': 80,
                    'media': <String, dynamic>{
                      'id': 41226,
                      'idMal': 41226,
                      'type': 'ANIME',
                      'format': 'TV',
                      'title': <String, dynamic>{
                        'romaji': 'Offline Anime',
                        'english': 'Offline Anime',
                        'native': 'オフライン',
                      },
                      'description': 'Offline description',
                      'coverImage': <String, dynamic>{
                        'extraLarge': 'https://example.com/poster.jpg',
                      },
                      'bannerImage': 'https://example.com/banner.jpg',
                      'averageScore': 80,
                      'genres': <String>['Comedy'],
                      'synonyms': <String>['Offline alias'],
                      'episodes': 12,
                      'duration': 24,
                      'trailer': <String, dynamic>{
                        'id': 'trailer-id',
                        'site': 'youtube',
                        'thumbnail': 'https://example.com/trailer.jpg',
                      },
                      'status': 'FINISHED',
                      'source': 'MANGA',
                      'season': 'SUMMER',
                      'seasonYear': 2020,
                      'countryOfOrigin': 'JP',
                      'popularity': 12345,
                      'favourites': 678,
                      'startDate': <String, int>{
                        'year': 2020,
                        'month': 7,
                        'day': 10,
                      },
                      'endDate': <String, int>{
                        'year': 2020,
                        'month': 9,
                        'day': 25,
                      },
                      'studios': <String, dynamic>{
                        'nodes': <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 1,
                            'name': 'ENGI',
                            'isAnimationStudio': true,
                          },
                        ],
                      },
                      'tags': <Map<String, dynamic>>[
                        <String, dynamic>{
                          'name': 'Comedy',
                          'rank': 90,
                          'isGeneralSpoiler': false,
                          'isMediaSpoiler': false,
                          'category': 'Theme',
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          },
        },
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
