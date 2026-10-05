import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/tracking/data/anilist_api_client.dart';
import 'package:mirushin/features/tracking/data/mal_api_client.dart';
import 'package:mirushin/features/tracking/data/shikimori_api_client.dart';

void main() {
  for (final provider in ['AniList', 'MAL', 'Shikimori']) {
    test(
      '$provider cancels in-flight requests during exit without retry',
      () async {
        final token = CancelToken();
        final adapter = _WaitingAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        int refreshCalls = 0;
        Future<String?> refresh() async {
          refreshCalls++;
          return 'new-token';
        }

        final Future<Object?> request = switch (provider) {
          'AniList' => AniListApiClient(
            accessToken: 'token',
            dio: dio,
            cancelToken: token,
          ).fetchViewer(),
          'MAL' => MalApiClient(
            accessToken: 'token',
            dio: dio,
            cancelToken: token,
            onRefreshToken: refresh,
          ).fetchViewer(),
          _ => ShikimoriApiClient(
            accessToken: 'token',
            userId: 1,
            dio: dio,
            cancelToken: token,
            onRefreshToken: refresh,
          ).fetchViewer(),
        };
        final expectation = expectLater(
          request,
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        await adapter.started.future;
        token.cancel('Closing MiruShin');
        await expectation;
        expect(adapter.calls, 1);
        expect(refreshCalls, 0);
        dio.close(force: true);
      },
    );
  }
}

class _WaitingAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await cancelFuture;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}
