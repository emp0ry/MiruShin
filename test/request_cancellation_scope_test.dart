import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/network/request_cancellation_scope.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:mirushin/features/tracking/data/mal_api_client.dart';
import 'package:mirushin/features/tracking/data/shikimori_api_client.dart';

void main() {
  test(
    'lifecycle bridge retires completed tokens and cancels active ones',
    () async {
      final parent = CancelToken();
      final scope = RequestCancellationScope.linkedTo(parent);
      expect(RequestCancellationScope.linkedTo(parent), same(scope));
      final completed = <CancelToken>[];
      for (var i = 0; i < 1000; i++) {
        await scope.run<void>((token) async => completed.add(token));
      }
      expect(scope.activeRequestCount, 0);
      final pending = scope.run<void>((token) async {
        await token.whenCancel;
        throw token.cancelError!;
      });
      final expectation = expectLater(pending, throwsA(_cancelled));
      parent.cancel('closing');
      await expectation;
      expect(scope.isCancelled, isTrue);
      expect(scope.activeRequestCount, 0);
      expect(completed.every((token) => !token.isCancelled), isTrue);
    },
  );

  test('already cancelled parent rejects a request before it starts', () async {
    final parent = CancelToken()..cancel('closed');
    final scope = RequestCancellationScope.linkedTo(parent);
    var started = false;
    await expectLater(
      scope.run<void>((_) async {
        started = true;
      }),
      throwsA(_cancelled),
    );
    expect(started, isFalse);
  });

  test(
    'completed and failed requests leave no lifetime token references',
    () async {
      final scope = RequestCancellationScope();
      final tokens = <CancelToken>{};
      for (var i = 0; i < 1000; i++) {
        await scope.run((token) async {
          expect(scope.activeRequestCount, 1);
          expect(token.isCancelled, isFalse);
          expect(tokens.add(token), isTrue);
        });
        expect(scope.activeRequestCount, 0);
      }
      await expectLater(
        scope.run<void>((_) async => throw StateError('failed')),
        throwsStateError,
      );
      expect(scope.activeRequestCount, 0);
      scope.cancel('closing');
      // Completed requests must not receive a late abort on process shutdown.
      expect(tokens.every((token) => !token.isCancelled), isTrue);
    },
  );

  test('cancels only active requests and rejects new work', () async {
    final scope = RequestCancellationScope();
    final requests = <Future<void>>[];
    for (var i = 0; i < 3; i++) {
      requests.add(
        scope.run((token) async {
          await token.whenCancel;
          throw token.cancelError!;
        }),
      );
    }
    final expectations = requests
        .map((request) => expectLater(request, throwsA(_cancelled)))
        .toList();
    expect(scope.activeRequestCount, 3);
    scope.cancel('closing');
    scope.cancel('again');
    await Future.wait(expectations);
    expect(scope.activeRequestCount, 0);
    bool called = false;
    await expectLater(
      scope.run<void>((_) async {
        called = true;
      }),
      throwsA(_cancelled),
    );
    expect(called, isFalse);
  });

  test(
    'one workspace cancellation does not affect another workspace',
    () async {
      final first = RequestCancellationScope();
      final second = RequestCancellationScope();
      final finishSecond = Completer<int>();
      final firstRequest = first.run<void>((token) async {
        await token.whenCancel;
        throw token.cancelError!;
      });
      final firstExpectation = expectLater(firstRequest, throwsA(_cancelled));
      final secondRequest = second.run<int>((token) async {
        await finishSecond.future;
        expect(token.isCancelled, isFalse);
        return 2;
      });
      first.cancel('switch account');
      await firstExpectation;
      expect(second.isCancelled, isFalse);
      expect(second.activeRequestCount, 1);
      finishSecond.complete(2);
      expect(await secondRequest, 2);
      expect(second.activeRequestCount, 0);
    },
  );

  for (final provider in ['AniList', 'MAL', 'Shikimori']) {
    test(
      '$provider uses a fresh token per HTTP request and cancels on exit',
      () async {
        final scope = RequestCancellationScope();
        final adapter = _Adapter(provider);
        final dio = Dio()..httpClientAdapter = adapter;
        final fetch = _viewer(provider, dio, scope);
        for (var i = 0; i < 100; i++) {
          await fetch();
          expect(scope.activeRequestCount, 0);
        }
        expect(adapter.tokens.toSet(), hasLength(100));
        expect(
          adapter.tokens.every((token) => token != null && !token.isCancelled),
          isTrue,
        );
        adapter.wait = true;
        final pending = fetch();
        final expectation = expectLater(pending, throwsA(_cancelled));
        await adapter.started.future;
        scope.cancel('closing');
        await expectation;
        expect(scope.activeRequestCount, 0);
        expect(adapter.calls, 101);
        await expectLater(fetch(), throwsA(_cancelled));
        expect(adapter.calls, 101);
        dio.close(force: true);
      },
    );
  }
}

final _cancelled = isA<DioException>().having(
  (error) => error.type,
  'type',
  DioExceptionType.cancel,
);

Future<Object?> Function() _viewer(
  String provider,
  Dio dio,
  RequestCancellationScope scope,
) {
  return switch (provider) {
    'AniList' => AniListApiClient(
      accessToken: 'test',
      dio: dio,
      cancellationScope: scope,
    ).fetchViewer,
    'MAL' => MalApiClient(
      accessToken: 'test',
      dio: dio,
      cancellationScope: scope,
    ).fetchViewer,
    _ => ShikimoriApiClient(
      accessToken: 'test',
      userId: 1,
      dio: dio,
      cancellationScope: scope,
    ).fetchViewer,
  };
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.provider);
  final String provider;
  final tokens = <CancelToken?>[];
  final started = Completer<void>();
  bool wait = false;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    tokens.add(options.cancelToken);
    if (wait) {
      started.complete();
      await cancelFuture;
      throw options.cancelToken!.cancelError!;
    }
    final viewer = {'id': 1, 'name': 'Test', 'nickname': 'Test'};
    return ResponseBody.fromString(
      jsonEncode(
        provider == 'AniList'
            ? {
                'data': {'Viewer': viewer},
              }
            : viewer,
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
