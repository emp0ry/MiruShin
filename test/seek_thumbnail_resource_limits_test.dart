import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/bounded_byte_cache.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_media_loader_io.dart';

const _playlist =
    '#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5,\n'
    'segment.ts\n#EXT-X-ENDLIST\n';
const _rangedPlaylist =
    '#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5,\n'
    '#EXT-X-BYTERANGE:4@4\nsegment.ts\n#EXT-X-ENDLIST\n';

Future<HttpServer> _server(Future<void> Function(HttpRequest) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) async {
    try {
      await handle(request);
      await request.response.close();
    } on SocketException {
      // The bounded reader deliberately cancels unwanted response tails.
    } on HttpException {
      // HttpServer can report the same cancellation as an HttpException.
    }
  });
  addTearDown(() async {
    await server.close(force: true);
    await subscription.cancel();
  });
  return server;
}

SeekThumbnailSource _source(HttpServer server, {String key = 'source'}) =>
    SeekThumbnailSource(
      source: PlayerSource(
        url: 'http://127.0.0.1:${server.port}/$key.m3u8',
        streamType: StreamType.hls,
      ),
      sourceKey: key,
      decoderKey: key,
      label: 'test',
      isOffline: false,
      kind: SeekThumbnailSourceKind.networkHls,
    );

void main() {
  group('backing-memory cache budget', () {
    test('a tiny sublist cannot pin its large backing allocation', () {
      final cache = BoundedByteCache<String>(
        maximumBytes: 8,
        maximumEntries: 2,
      );
      final backing = Uint8List(1024 * 1024);
      backing[4] = 7;
      cache.put('range', Uint8List.sublistView(backing, 4, 8));
      final value = cache.get('range')!;
      expect(value, [7, 0, 0, 0]);
      expect(value.buffer.lengthInBytes, 4);
      expect(cache.byteCount, 4);
      backing[4] = 9;
      expect(value.first, 7);
    });

    test('byte and entry budgets use LRU, replacement and clear', () {
      final cache = BoundedByteCache<String>(
        maximumBytes: 8,
        maximumEntries: 2,
      );
      cache.put('a', Uint8List(4));
      cache.put('b', Uint8List(4));
      cache.get('a');
      cache.put('c', Uint8List(4));
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), isNotNull);
      cache.put('a', Uint8List(20));
      expect(cache.get('a'), isNull);
      expect(cache.byteCount, 4);
      cache.clear();
      expect(cache.byteCount, 0);
      expect(cache.entryCount, 0);
    });
  });

  test(
    'ignored Range stops after the span without waiting for movie EOF',
    () async {
      final releaseTail = Completer<void>();
      addTearDown(() {
        if (!releaseTail.isCompleted) releaseTail.complete();
      });
      String? range;
      int mediaRequests = 0;
      final server = await _server((request) async {
        if (request.uri.path.endsWith('.m3u8')) {
          request.response.write(_rangedPlaylist);
        } else {
          mediaRequests++;
          range = request.headers.value(HttpHeaders.rangeHeader);
          request.response.bufferOutput = false;
          // This body has not ended when prepare must complete.
          request.response.add(List.generate(16, (i) => i));
          await request.response.flush();
          await releaseTail.future;
        }
      });
      final loader = SeekThumbnailMediaLoader();
      addTearDown(loader.dispose);
      final input = await loader
          .prepare(_source(server), Duration.zero)
          .timeout(const Duration(seconds: 2));
      expect(range, 'bytes=4-7');
      expect(loader.cachedResourceBytes, 4);
      final segment = File('${input!.temporaryDirectory!.path}/segment-0.ts');
      expect(await segment.readAsBytes(), [4, 5, 6, 7]);
      await input.dispose();
      final cached = await loader.prepare(_source(server), Duration.zero);
      await cached!.dispose();
      expect(mediaRequests, 1);
    },
  );

  for (final knownLength in [false, true]) {
    test(
      'oversized ${knownLength ? 'declared' : 'chunked'} body is bounded',
      () async {
        final server = await _server((request) async {
          if (request.uri.path.endsWith('.m3u8')) {
            request.response.write(_playlist);
          } else {
            if (knownLength) request.response.contentLength = 4096;
            request.response.add(Uint8List(4096));
          }
        });
        final loader = SeekThumbnailMediaLoader(maximumResourceBytes: 64);
        addTearDown(loader.dispose);
        await expectLater(
          loader.prepare(_source(server), Duration.zero),
          throwsA(
            isA<SeekThumbnailLoadException>().having(
              (error) => error.failure.reason,
              'reason',
              SeekThumbnailFailureReason.resourceLimit,
            ),
          ),
        );
        expect(loader.cachedResourceBytes, 0);
      },
    );
  }

  test('playlist bodies have a separate small limit', () async {
    final server = await _server((request) async {
      request.response.write('#EXTM3U\n${'x' * 1024}');
    });
    final loader = SeekThumbnailMediaLoader(maximumPlaylistBytes: 64);
    addTearDown(loader.dispose);
    await expectLater(
      loader.warm(_source(server)),
      throwsA(isA<SeekThumbnailLoadException>()),
    );
  });

  test('oversized chunked body fails before a never-ending tail', () async {
    final finish = Completer<void>();
    addTearDown(() {
      if (!finish.isCompleted) finish.complete();
    });
    final server = await _server((request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(_playlist);
      } else {
        request.response.bufferOutput = false;
        request.response.add(Uint8List(4096));
        await request.response.flush();
        await finish.future;
      }
    });
    final loader = SeekThumbnailMediaLoader(maximumResourceBytes: 64);
    addTearDown(loader.dispose);
    await expectLater(
      loader
          .prepare(_source(server), Duration.zero)
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<SeekThumbnailLoadException>().having(
          (error) => error.failure.reason,
          'reason',
          SeekThumbnailFailureReason.resourceLimit,
        ),
      ),
    );
  });

  test('ignored distant Range fails without scanning the video', () async {
    final server = await _server((request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(
          _rangedPlaylist.replaceFirst('4@4', '4@4000000'),
        );
      } else {
        request.response.contentLength = 8000000;
        request.response.add(Uint8List(16));
        // A server need not send the rest before the loader rejects this.
      }
    });
    final loader = SeekThumbnailMediaLoader();
    addTearDown(loader.dispose);
    await expectLater(
      loader.prepare(_source(server), Duration.zero),
      throwsA(
        isA<SeekThumbnailLoadException>().having(
          (error) => error.failure.reason,
          'reason',
          SeekThumbnailFailureReason.rangeUnsupported,
        ),
      ),
    );
  });

  for (final mode in ['correct', 'wrong range', 'short']) {
    test('206 range validation: $mode', () async {
      final server = await _server((request) async {
        if (request.uri.path.endsWith('.m3u8')) {
          request.response.write(_rangedPlaylist);
        } else {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            mode == 'wrong range' ? 'bytes 8-11/16' : 'bytes 4-7/16',
          );
          request.response.add(mode == 'short' ? [4, 5] : [4, 5, 6, 7]);
        }
      });
      final loader = SeekThumbnailMediaLoader();
      addTearDown(loader.dispose);
      final pending = loader.prepare(_source(server), Duration.zero);
      if (mode == 'correct') {
        final input = await pending;
        expect(loader.cachedResourceBytes, 4);
        await input!.dispose();
      } else {
        await expectLater(pending, throwsA(isA<SeekThumbnailLoadException>()));
        expect(loader.cachedResourceBytes, 0);
      }
    });
  }

  test(
    'source churn shares one global resource budget and bounds indexes',
    () async {
      int mediaRequests = 0;
      final server = await _server((request) async {
        if (request.uri.path.endsWith('.m3u8')) {
          request.response.write(_playlist);
        } else {
          mediaRequests++;
          request.response.add(Uint8List(8));
        }
      });
      final loader = SeekThumbnailMediaLoader(
        maximumSourceSessions: 2,
        maximumCacheBytes: 12,
      );
      addTearDown(loader.dispose);
      for (int i = 0; i < 40; i++) {
        final input = await loader.prepare(
          _source(server, key: 's$i'),
          Duration.zero,
        );
        await input!.dispose();
        expect(loader.cachedResourceBytes, lessThanOrEqualTo(12));
        expect(loader.cachedSourceSessions, lessThanOrEqualTo(2));
      }
      expect(mediaRequests, 40);
      await loader.dispose();
      expect(loader.cachedResourceBytes, 0);
      expect(loader.cachedSourceSessions, 0);
    },
  );

  test('cancelling an active body leaves no cached resource', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    addTearDown(() {
      if (!finish.isCompleted) finish.complete();
    });
    final server = await _server((request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write(_playlist);
      } else {
        request.response.add(Uint8List(8));
        await request.response.flush();
        if (!started.isCompleted) started.complete();
        await finish.future;
      }
    });
    final loader = SeekThumbnailMediaLoader();
    addTearDown(loader.dispose);
    final pending = loader.prepare(_source(server), Duration.zero);
    final failed = expectLater(
      pending,
      throwsA(isA<SeekThumbnailLoadException>()),
    );
    await started.future;
    loader.cancelPending();
    finish.complete();
    await failed;
    expect(loader.cachedResourceBytes, 0);
  });
}
