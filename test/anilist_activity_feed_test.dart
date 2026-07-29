import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';

void main() {
  test('public activity feed parses results without an access token', () async {
    final _ActivityFeedAdapter adapter = _ActivityFeedAdapter();
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final AniListApiClient client = AniListApiClient(dio: dio);

    final chunk = await client.fetchActivities(
      typeIn: const <String>['TEXT', 'ANIME_LIST', 'MANGA_LIST'],
      authenticated: false,
    );

    expect(chunk.items, hasLength(1));
    expect(chunk.items.single.id, 42);
    expect(chunk.items.single.primaryUser.name, 'Feed User');
    expect(chunk.items.single.text, 'Hello from AniList');
    expect(chunk.hasNextPage, isTrue);
    expect(adapter.authorizationHeader, isNull);
  });
}

class _ActivityFeedAdapter implements HttpClientAdapter {
  String? authorizationHeader;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeader = options.headers['Authorization']?.toString();
    return ResponseBody.fromString(
      jsonEncode(<String, Object>{
        'data': <String, Object>{
          'Page': <String, Object>{
            'pageInfo': <String, Object>{'hasNextPage': true, 'total': 5000},
            'activities': <Object>[
              <String, Object>{
                'id': 42,
                'type': 'TEXT',
                'replyCount': 2,
                'likeCount': 3,
                'isLiked': false,
                'isSubscribed': false,
                'isPinned': false,
                'createdAt': 1700000000,
                'siteUrl': 'https://anilist.co/activity/42',
                'text': '<b>Hello from AniList</b>',
                'user': <String, Object>{
                  'id': 7,
                  'name': 'Feed User',
                  'avatar': <String, Object>{
                    'large': 'https://example.com/avatar.jpg',
                  },
                },
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
