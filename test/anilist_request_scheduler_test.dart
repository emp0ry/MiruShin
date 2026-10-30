import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/network/anilist_request_scheduler.dart';

class _Adapter implements HttpClientAdapter {
  final List<String> paths = [];
  ResponseBody Function(int index)? respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    paths.add(options.uri.toString());
    return respond?.call(paths.length) ?? response(200);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody response(
  int status, {
  Map<String, List<String>> headers = const {},
  Object? body,
}) => ResponseBody.fromString(
  jsonEncode(body ?? {'data': {}}),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

Dio _client(AniListRequestScheduler scheduler, _Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://graphql.anilist.co'))
    ..httpClientAdapter = adapter;
  scheduler.install(dio);
  addTearDown(() => dio.close(force: true));
  return dio;
}

void main() {
  testWidgets(
    'independent clients share spacing and the rolling request budget',
    (tester) async {
      final scheduler = AniListRequestScheduler(
        requestLimit: 2,
        window: const Duration(seconds: 10),
        minimumSpacing: const Duration(seconds: 1),
        now: tester.binding.clock.now,
      );
      final adapter = _Adapter();
      final first = _client(scheduler, adapter);
      final second = _client(scheduler, adapter);
      final a = first.post('/a');
      final b = second.post('/b');
      final c = first.post('/c');
      await tester.pump(Duration.zero);
      expect(adapter.paths, hasLength(1));
      await tester.pump(const Duration(milliseconds: 999));
      expect(adapter.paths, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(adapter.paths, hasLength(2));
      await tester.pump(const Duration(seconds: 8));
      expect(adapter.paths, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(adapter.paths, hasLength(3));
      await Future.wait([a, b, c]);
    },
  );

  testWidgets('429 pauses all clients until Retry-After and reset expire', (
    tester,
  ) async {
    final now = tester.binding.clock.now();
    final scheduler = AniListRequestScheduler(
      minimumSpacing: Duration.zero,
      now: tester.binding.clock.now,
    );
    final adapter = _Adapter()
      ..respond = (index) => index == 1
          ? response(
              429,
              headers: {
                'retry-after': ['1'],
                'x-ratelimit-reset': [
                  '${now.add(const Duration(seconds: 3)).millisecondsSinceEpoch ~/ 1000}',
                ],
              },
            )
          : response(200);
    final first = _client(scheduler, adapter);
    final second = _client(scheduler, adapter);
    final rejected = expectLater(
      first.post('/limited'),
      throwsA(isA<DioException>()),
    );
    final next = second.post('/next');
    await tester.pump(Duration.zero);
    await rejected;
    await tester.pump(const Duration(seconds: 2));
    expect(adapter.paths, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(adapter.paths, hasLength(2));
    await next;
  });

  testWidgets(
    'a cancelled queued request leaves the budget available to its successor',
    (tester) async {
      final scheduler = AniListRequestScheduler(
        minimumSpacing: const Duration(seconds: 2),
        now: tester.binding.clock.now,
      );
      final adapter = _Adapter();
      final dio = _client(scheduler, adapter);
      final first = dio.post('/first');
      final token = CancelToken();
      final cancelled = expectLater(
        dio.post('/cancelled', cancelToken: token),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      final last = dio.post('/last');
      await tester.pump(Duration.zero);
      token.cancel('account switched');
      await tester.pump(Duration.zero);
      await cancelled;
      expect(adapter.paths, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      await Future.wait([first, last]);
      expect(adapter.paths.map((url) => Uri.parse(url).path), [
        '/first',
        '/last',
      ]);
    },
  );

  testWidgets(
    'GraphQL 429 and exhausted success headers also pause the queue',
    (tester) async {
      final scheduler = AniListRequestScheduler(
        window: const Duration(seconds: 2),
        minimumSpacing: Duration.zero,
        now: tester.binding.clock.now,
      );
      final adapter = _Adapter()
        ..respond = (index) => index == 1
            ? response(
                200,
                body: {
                  'errors': [
                    {'status': 429},
                  ],
                },
              )
            : index == 2
            ? response(
                200,
                headers: {
                  'x-ratelimit-remaining': ['0'],
                  'retry-after': ['1'],
                },
              )
            : response(200);
      final dio = _client(scheduler, adapter);
      final reads = [
        dio.post('/first'),
        dio.post('/second'),
        dio.post('/third'),
      ];
      await tester.pump(Duration.zero);
      expect(adapter.paths, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      expect(adapter.paths, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(adapter.paths, hasLength(3));
      await Future.wait(reads);
    },
  );

  testWidgets('other hosts remain usable during an AniList cooldown', (
    tester,
  ) async {
    final scheduler = AniListRequestScheduler(now: tester.binding.clock.now);
    final adapter = _Adapter()
      ..respond = (index) => index == 1 ? response(429) : response(200);
    final dio = _client(scheduler, adapter);
    final rejected = expectLater(
      dio.post('/limited'),
      throwsA(isA<DioException>()),
    );
    await tester.pump(Duration.zero);
    await rejected;
    final other = dio.get('https://shikimori.one/api/animes');
    await tester.pump(Duration.zero);
    await other;
    expect(adapter.paths, hasLength(2));
  });
}
