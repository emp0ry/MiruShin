import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/local_hls_proxy.dart';

void main() {
  test(
    'segment retry does not abort a healthy parallel audio/video request',
    () async {
      final firstSent = Completer<void>();
      final releaseOriginal = Completer<void>();
      int aRequests = 0;
      int bRequests = 0;
      final harness = await _Harness.start((request) async {
        try {
          if (request.uri.path == '/a.ts') {
            final index = ++aRequests;
            request.response.bufferOutput = false;
            request.response.contentLength = 8;
            request.response.add([1, 2, 3, 4]);
            if (index == 1) {
              await request.response.flush();
              firstSent.complete();
              await releaseOriginal.future;
            }
            request.response.add([5, 6, 7, 8]);
          } else if (++bRequests == 1) {
            request.response.statusCode = 503;
          } else {
            request.response.add([9]);
          }
          await request.response.close();
        } on SocketException {
          // Older implementations aborted A when retrying B.
        } on HttpException {
          // The failure is asserted by the upstream request count below.
        }
      });
      try {
        final a = harness.bytes('/a.ts');
        await firstSent.future.timeout(const Duration(seconds: 3));
        expect(await harness.bytes('/b.ts'), [9]);
        expect(aRequests, 1);
        expect(bRequests, 2);
        releaseOriginal.complete();
        expect(await a, [1, 2, 3, 4, 5, 6, 7, 8]);
      } finally {
        if (!releaseOriginal.isCompleted) releaseOriginal.complete();
        await harness.close();
      }
    },
  );

  test('playlist retry does not abort an active segment', () async {
    final firstSent = Completer<void>();
    final finish = Completer<void>();
    int segmentRequests = 0;
    int playlistRequests = 0;
    final harness = await _Harness.start((request) async {
      try {
        if (request.uri.path == '/segment.ts') {
          final index = ++segmentRequests;
          request.response.bufferOutput = false;
          request.response.contentLength = 8;
          request.response.add([1, 2, 3, 4]);
          if (index == 1) {
            await request.response.flush();
            firstSent.complete();
            await finish.future;
          }
          request.response.add([5, 6, 7, 8]);
        } else if (++playlistRequests == 1) {
          request.response.statusCode = 503;
        } else {
          request.response.write('#EXTM3U\n#EXT-X-ENDLIST\n');
        }
        await request.response.close();
      } on Object {
        // Counts detect collateral cancellation without leaking server errors.
      }
    });
    try {
      final segment = harness.bytes('/segment.ts');
      await firstSent.future.timeout(const Duration(seconds: 3));
      final response = await harness.request('/media.m3u8', playlist: true);
      expect(response.statusCode, 200);
      await response.drain<void>();
      expect(segmentRequests, 1);
      expect(playlistRequests, 2);
      finish.complete();
      expect(await segment, [1, 2, 3, 4, 5, 6, 7, 8]);
    } finally {
      if (!finish.isCompleted) finish.complete();
      await harness.close();
    }
  });

  test('segment first bytes arrive before upstream EOF', () async {
    final finish = Completer<void>();
    final harness = await _Harness.start((request) async {
      request.response.bufferOutput = false;
      request.response.contentLength = 8;
      request.response.add([1, 2, 3, 4]);
      await request.response.flush();
      await finish.future;
      request.response.add([5, 6, 7, 8]);
      await request.response.close();
    });
    try {
      final response = await harness
          .request('/segment.ts')
          .timeout(const Duration(seconds: 2));
      final chunks = StreamIterator<List<int>>(response);
      expect(
        await chunks.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(chunks.current, [1, 2, 3, 4]);
      expect(finish.isCompleted, isFalse);
      finish.complete();
      final rest = <int>[];
      while (await chunks.moveNext()) {
        rest.addAll(chunks.current);
      }
      expect(rest, [5, 6, 7, 8]);
      await chunks.cancel();
    } finally {
      if (!finish.isCompleted) finish.complete();
      await harness.close();
    }
  });

  for (final knownLength in [true, false]) {
    test(
      'large ${knownLength ? 'sized' : 'chunked'} segment is streamed with one GET',
      () async {
        const total = 33 * 1024 * 1024;
        final chunk = Uint8List(64 * 1024);
        final finish = Completer<void>();
        int requests = 0;
        final harness = await _Harness.start((request) async {
          requests++;
          request.response.bufferOutput = false;
          if (knownLength) request.response.contentLength = total;
          request.response.add(chunk);
          await request.response.flush();
          await finish.future;
          for (int sent = chunk.length; sent < total; sent += chunk.length) {
            request.response.add(chunk);
            await request.response.flush();
          }
          await request.response.close();
        });
        try {
          final response = await harness
              .request('/large.ts')
              .timeout(const Duration(seconds: 2));
          final received = response.fold<int>(
            0,
            (sum, bytes) => sum + bytes.length,
          );
          finish.complete();
          expect(await received, total);
          expect(requests, 1);
        } finally {
          if (!finish.isCompleted) finish.complete();
          await harness.close();
        }
      },
    );
  }

  test(
    'Range, response metadata and HEAD survive progressive delivery',
    () async {
      final seen = <String>[];
      final harness = await _Harness.start((request) async {
        seen.add(
          '${request.method}:${request.headers.value(HttpHeaders.rangeHeader)}',
        );
        request.response
          ..statusCode = 206
          ..contentLength = 4
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 4-7/8')
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.set(HttpHeaders.etagHeader, '"entity-1"')
          ..headers.contentType = ContentType('video', 'mp4');
        if (request.method != 'HEAD') request.response.add([5, 6, 7, 8]);
        await request.response.close();
      });
      try {
        for (final method in ['GET', 'HEAD']) {
          final response = await harness.request(
            '/video.mp4',
            method: method,
            range: 'bytes=4-7',
          );
          expect(response.statusCode, 206);
          expect(response.contentLength, 4);
          expect(
            response.headers.value(HttpHeaders.contentRangeHeader),
            'bytes 4-7/8',
          );
          expect(response.headers.value(HttpHeaders.etagHeader), '"entity-1"');
          expect(response.headers.contentType?.mimeType, 'video/mp4');
          final bytes = await response.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          expect(bytes, method == 'HEAD' ? [] : [5, 6, 7, 8]);
        }
        expect(seen, ['GET:bytes=4-7', 'HEAD:bytes=4-7']);
      } finally {
        await harness.close();
      }
    },
  );

  test(
    'connection failure before first byte is retried without duplicates',
    () async {
      int requests = 0;
      final harness = await _Harness.start((request) async {
        if (++requests == 1) {
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        request.response.add([1, 2, 3, 4]);
        await request.response.close();
      });
      try {
        expect(await harness.bytes('/reconnect.ts'), [1, 2, 3, 4]);
        expect(requests, 2);
      } finally {
        await harness.close();
      }
    },
  );

  test(
    'retry cancels a slow error body instead of waiting for its EOF',
    () async {
      int requests = 0;
      final finish = Completer<void>();
      final harness = await _Harness.start((request) async {
        try {
          if (++requests == 1) {
            request.response
              ..statusCode = 503
              ..bufferOutput = false
              ..contentLength = 1000
              ..add([0]);
            await request.response.flush();
            await finish.future;
            request.response.add(List<int>.filled(999, 0));
          } else {
            request.response.add([1]);
          }
          await request.response.close();
        } on Object {
          // The error response is intentionally cancelled by the proxy.
        }
      });
      try {
        expect(
          await harness
              .bytes('/slow-error.ts')
              .timeout(const Duration(seconds: 2)),
          [1],
        );
        expect(finish.isCompleted, isFalse);
        expect(requests, 2);
      } finally {
        finish.complete();
        await harness.close();
      }
    },
  );

  test(
    'stopping a busy proxy cancels only that session and settles its read',
    () async {
      int requests = 0;
      final finish = Completer<void>();
      final harness = await _Harness.start((request) async {
        try {
          requests++;
          request.response
            ..bufferOutput = false
            ..contentLength = 8
            ..add([1, 2, 3, 4]);
          await request.response.flush();
          await finish.future;
          request.response.add([5, 6, 7, 8]);
          await request.response.close();
        } on Object {
          // Teardown intentionally disconnects the old consumer.
        }
      });
      try {
        final response = await harness.request('/busy.ts');
        final chunks = StreamIterator<List<int>>(response);
        expect(await chunks.moveNext(), isTrue);
        final pendingRead = chunks.moveNext();
        // Register the error handler before teardown closes the socket.
        final settled = pendingRead.then((_) {}, onError: (Object _) {});
        await harness.proxy.stop();
        await settled.timeout(const Duration(seconds: 2));
        expect(requests, 1);
        await chunks.cancel();
        finish.complete();
        await harness.proxy.start();
        expect(await harness.bytes('/next.ts'), [1, 2, 3, 4, 5, 6, 7, 8]);
        expect(requests, 2);
      } finally {
        if (!finish.isCompleted) finish.complete();
        await harness.close();
      }
    },
  );

  test(
    'a broken chunked transfer is an error, not a successful short segment',
    () async {
      int requests = 0;
      final disconnect = Completer<void>();
      final harness = await _Harness.start((request) async {
        requests++;
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n',
        );
        socket.write('4\r\n');
        socket.add([1, 2, 3, 4]);
        socket.write('\r\n');
        await socket.flush();
        await disconnect.future;
        socket.destroy();
      });
      try {
        final response = await harness.request('/chunked-interrupted.ts');
        final chunks = StreamIterator<List<int>>(response);
        expect(await chunks.moveNext(), isTrue);
        expect(chunks.current, [1, 2, 3, 4]);
        disconnect.complete();
        await expectLater(
          chunks.moveNext().timeout(const Duration(seconds: 2)),
          throwsA(isA<HttpException>()),
        );
        expect(requests, 1);
        await chunks.cancel();
      } finally {
        if (!disconnect.isCompleted) disconnect.complete();
        await harness.close();
      }
    },
  );

  test(
    'failure after delivered bytes never appends a second response',
    () async {
      int requests = 0;
      final disconnect = Completer<void>();
      final harness = await _Harness.start((request) async {
        requests++;
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\n',
        );
        socket.add([1, 2, 3, 4]);
        await socket.flush();
        await disconnect.future;
        socket.destroy();
      });
      try {
        final response = await harness
            .request('/interrupted.ts')
            .timeout(const Duration(seconds: 2));
        final chunks = StreamIterator<List<int>>(response);
        expect(await chunks.moveNext(), isTrue);
        expect(chunks.current, [1, 2, 3, 4]);
        disconnect.complete();
        await expectLater(chunks.moveNext(), throwsA(isA<HttpException>()));
        expect(requests, 1);
        await chunks.cancel();
      } finally {
        if (!disconnect.isCompleted) disconnect.complete();
        await harness.close();
      }
    },
  );
}

class _Harness {
  _Harness(this.server, this.subscription, this.proxy);

  final HttpServer server;
  final StreamSubscription<HttpRequest> subscription;
  final LocalHlsProxy proxy;
  final HttpClient client = HttpClient();

  static Future<_Harness> start(
    Future<void> Function(HttpRequest) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(handler);
    final proxy = LocalHlsProxy();
    await proxy.start();
    return _Harness(server, subscription, proxy);
  }

  Future<HttpClientResponse> request(
    String path, {
    bool playlist = false,
    String method = 'GET',
    String? range,
  }) async {
    final source = Uri.parse('http://127.0.0.1:${server.port}$path');
    final target = Uri.parse(
      playlist ? proxy.playlistUrl(source) : proxy.mediaUrl(source),
    );
    final request = await client.openUrl(method, target);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    return request.close();
  }

  Future<List<int>> bytes(String path) async {
    final response = await request(path);
    expect(response.statusCode, 200);
    return response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
  }

  Future<void> close() async {
    client.close(force: true);
    await proxy.stop();
    await subscription.cancel();
    await server.close(force: true);
  }
}
