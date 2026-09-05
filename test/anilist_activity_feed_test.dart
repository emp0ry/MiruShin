import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';

void main() {
  test('AniList uses the longer timeout and one-second retry delay', () {
    expect(AniListApiClient.defaultReceiveTimeout, const Duration(seconds: 30));
    expect(
      AniListApiClient.defaultTimeoutRetryDelay,
      const Duration(seconds: 1),
    );
  });

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

  test('a timed-out AniList request is retried once', () async {
    final _ActivityFeedAdapter adapter = _ActivityFeedAdapter(timeouts: 1);
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final AniListApiClient client = AniListApiClient(
      dio: dio,
      timeoutRetryDelay: Duration.zero,
    );

    final chunk = await client.fetchActivities(
      typeIn: const <String>['TEXT'],
      authenticated: false,
    );

    expect(chunk.items.single.id, 42);
    expect(adapter.requestCount, 2);
  });

  test('a second AniList timeout is returned to cache fallback', () async {
    final _ActivityFeedAdapter adapter = _ActivityFeedAdapter(timeouts: 2);
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final AniListApiClient client = AniListApiClient(
      dio: dio,
      timeoutRetryDelay: Duration.zero,
    );

    await expectLater(
      client.fetchActivities(
        typeIn: const <String>['TEXT'],
        authenticated: false,
      ),
      throwsA(
        isA<DioException>().having(
          (DioException error) => error.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );
    expect(adapter.requestCount, 2);
  });

  test('non-timeout AniList failures are not retried', () async {
    final _ActivityFeedAdapter adapter = _ActivityFeedAdapter(statusCode: 500);
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final AniListApiClient client = AniListApiClient(
      dio: dio,
      timeoutRetryDelay: Duration.zero,
    );

    await expectLater(
      client.fetchActivities(
        typeIn: const <String>['TEXT'],
        authenticated: false,
      ),
      throwsA(
        isA<DioException>().having(
          (DioException error) => error.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
    expect(adapter.requestCount, 1);
  });

  test('timed-out AniList mutations are not duplicated', () async {
    final _ActivityFeedAdapter adapter = _ActivityFeedAdapter(timeouts: 1);
    final Dio dio = Dio()..httpClientAdapter = adapter;
    final AniListApiClient client = AniListApiClient(
      accessToken: 'token',
      dio: dio,
      timeoutRetryDelay: Duration.zero,
    );

    await expectLater(
      client.toggleActivityLike(42),
      throwsA(
        isA<DioException>().having(
          (DioException error) => error.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );
    expect(adapter.requestCount, 1);
  });
}

class _ActivityFeedAdapter implements HttpClientAdapter {
  _ActivityFeedAdapter({this.timeouts = 0, this.statusCode = 200});

  final int timeouts;
  final int statusCode;
  int requestCount = 0;
  String? authorizationHeader;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount += 1;
    authorizationHeader = options.headers['Authorization']?.toString();
    if (requestCount <= timeouts) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
        message: 'AniList receive timeout',
      );
    }
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
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
