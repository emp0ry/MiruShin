import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/direct_frame_decoder.dart';
import 'package:mirushin/features/player/engine/direct_frame_decoder_io.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_extractor_io.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'native geometry uses SAR and rotation for display size',
    () {
      final DynamicLibrary library = Platform.isWindows
          ? DynamicLibrary.open('mirushin_seek_thumbnail.dll')
          : Platform.isLinux || Platform.isAndroid
          ? DynamicLibrary.open('libmirushin_seek_thumbnail.so')
          : DynamicLibrary.process();
      final _OutputSizeDart outputSize = library
          .lookup<NativeFunction<_OutputSizeNative>>(
            'mirushin_seek_thumbnail_output_size',
          )
          .asFunction<_OutputSizeDart>();
      final Pointer<Int32> width = calloc<Int32>();
      final Pointer<Int32> height = calloc<Int32>();
      final Pointer<Double> aspect = calloc<Double>();
      try {
        expect(outputSize(640, 480, 4, 3, 0, 240, width, height, aspect), 0);
        expect(width.value, 240);
        expect(height.value, 135);
        expect(aspect.value, closeTo(16 / 9, 0.0001));

        expect(outputSize(1920, 1080, 1, 1, 90, 240, width, height, aspect), 0);
        expect(width.value, 240);
        expect(height.value, 427);
        expect(aspect.value, closeTo(9 / 16, 0.0001));
      } finally {
        calloc.free(width);
        calloc.free(height);
        calloc.free(aspect);
      }
    },
    skip: Platform.environment['MIRUSHIN_NATIVE_SEEK_SMOKE'] != '1',
  );

  test(
    'native bridge decodes one indexed public HLS segment',
    () async {
      final SeekThumbnailSource source = SeekThumbnailSource(
        source: const PlayerSource(
          url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
          streamType: StreamType.hls,
        ),
        sourceKey: 'smoke-source',
        decoderKey: 'smoke-decoder',
        label: 'public smoke stream',
        isOffline: false,
        kind: SeekThumbnailSourceKind.networkHls,
        inspectMasterPlaylist: true,
      );
      final SeekThumbnailPlan plan = SeekThumbnailPlan(
        sessionKey: 'online-hls-smoke-session',
        candidates: <SeekThumbnailSource>[source],
        isOffline: false,
      );
      final SeekThumbnailService service = SeekThumbnailService(
        extractorFactory: (_) => NativeSeekThumbnailExtractor(),
      );
      addTearDown(service.dispose);
      final Stopwatch first = Stopwatch()..start();
      final SeekThumbnail? firstThumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.auto,
        position: const Duration(seconds: 20),
        duration: const Duration(minutes: 10),
      );
      first.stop();
      final Stopwatch warm = Stopwatch()..start();
      final SeekThumbnail? warmThumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.auto,
        position: const Duration(seconds: 25),
        duration: const Duration(minutes: 10),
      );
      warm.stop();
      final Stopwatch cached = Stopwatch()..start();
      final SeekThumbnail? cachedThumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.auto,
        position: const Duration(seconds: 25),
        duration: const Duration(minutes: 10),
      );
      cached.stop();

      expect(firstThumbnail, isNotNull);
      expect(warmThumbnail, isNotNull);
      expect(cachedThumbnail, same(warmThumbnail));
      expect(firstThumbnail!.width, 240);
      expect(firstThumbnail.height, greaterThan(0));
      expect(firstThumbnail.bytes, hasLength(greaterThan(4)));
      expect(firstThumbnail.bytes.sublist(0, 2), <int>[0xff, 0xd8]);
      // ignore: avoid_print
      print(
        'online HLS first=${first.elapsedMicroseconds / 1000}ms '
        'warm=${warm.elapsedMicroseconds / 1000}ms '
        'cached=${cached.elapsedMicroseconds / 1000}ms '
        'output=${firstThumbnail.width}x${firstThumbnail.height}',
      );
    },
    skip: Platform.environment['MIRUSHIN_NATIVE_SEEK_SMOKE'] != '1',
  );

  test(
    'native bridge decodes and caches an offline local HLS segment',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mirushin_native_local_hls_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final List<int> segmentBytes = await _download(
        Uri.parse(
          'https://test-streams.mux.dev/x36xhzz/url_2/url_526/'
          '193039199_mp4_h264_aac_ld_7.ts',
        ),
      );
      final File localSegment = File(
        '${directory.path}${Platform.pathSeparator}segment.ts',
      );
      await localSegment.writeAsBytes(segmentBytes, flush: true);
      final File playlist = File(
        '${directory.path}${Platform.pathSeparator}index.m3u8',
      );
      await playlist.writeAsString('''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10,
segment.ts
#EXT-X-ENDLIST
''', flush: true);

      final SeekThumbnailSource source = SeekThumbnailSource(
        source: PlayerSource(
          url: playlist.uri.toString(),
          streamType: StreamType.hls,
        ),
        sourceKey: 'local-hls-smoke-source',
        decoderKey: 'local-hls-smoke-decoder',
        label: 'offline local media',
        isOffline: true,
        kind: SeekThumbnailSourceKind.localHls,
      );
      final SeekThumbnailPlan plan = SeekThumbnailPlan(
        sessionKey: 'local-hls-smoke-session',
        candidates: <SeekThumbnailSource>[source],
        isOffline: true,
      );
      final SeekThumbnailService service = SeekThumbnailService(
        extractorFactory: (_) => NativeSeekThumbnailExtractor(),
      );
      addTearDown(service.dispose);

      final Stopwatch index = Stopwatch()..start();
      await service.warm(plan, PlayerBackend.auto);
      index.stop();
      final Stopwatch first = Stopwatch()..start();
      final SeekThumbnail? firstThumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.auto,
        position: const Duration(seconds: 2),
        duration: const Duration(seconds: 10),
      );
      first.stop();
      final Stopwatch nearby = Stopwatch()..start();
      final SeekThumbnail? nearbyThumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.auto,
        position: const Duration(seconds: 7),
        duration: const Duration(seconds: 10),
      );
      nearby.stop();
      final Stopwatch cached = Stopwatch()..start();
      final SeekThumbnail? cachedThumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.auto,
        position: const Duration(seconds: 7),
        duration: const Duration(seconds: 10),
      );
      cached.stop();

      expect(firstThumbnail, isNotNull);
      expect(nearbyThumbnail, isNotNull);
      expect(cachedThumbnail, same(nearbyThumbnail));
      await service.dispose();
      expect(
        await directory
            .list()
            .where(
              (FileSystemEntity entity) => p.basename(
                entity.path,
              ).startsWith('.mirushin_seek_preview_'),
            )
            .isEmpty,
        isTrue,
      );
      await localSegment.delete();
      expect(await localSegment.exists(), isFalse);
      // Fixture download is complete before timing; all preview inputs above
      // are file URIs and require no provider, CDN, or loopback HTTP access.
      // ignore: avoid_print
      print(
        'offline local HLS index=${index.elapsedMicroseconds / 1000}ms '
        'first=${first.elapsedMicroseconds / 1000}ms '
        'nearby=${nearby.elapsedMicroseconds / 1000}ms '
        'cached=${cached.elapsedMicroseconds / 1000}ms',
      );
    },
    skip: Platform.environment['MIRUSHIN_NATIVE_SEEK_SMOKE'] != '1',
  );

  test(
    'native bridge seeks an offline local MP4',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mirushin_native_local_mp4_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final File video = File(
        '${directory.path}${Platform.pathSeparator}video.mp4',
      );
      await video.writeAsBytes(
        await _download(
          Uri.parse(
            'https://flutter.github.io/assets-for-api-docs/assets/videos/'
            'bee.mp4',
          ),
        ),
        flush: true,
      );
      final NativeDirectFrameDecoder decoder = NativeDirectFrameDecoder();
      addTearDown(decoder.dispose);
      const String sessionKey = 'local-mp4-smoke-decoder';
      final Stopwatch first = Stopwatch()..start();
      final DirectFrameDecodeResult firstResult = await decoder.decode(
        DirectFrameDecodeRequest(
          input: video.path,
          position: const Duration(seconds: 1),
          sessionKey: sessionKey,
          reuseSession: true,
        ),
      );
      first.stop();
      final Stopwatch warm = Stopwatch()..start();
      final DirectFrameDecodeResult warmResult = await decoder.decode(
        DirectFrameDecodeRequest(
          input: video.path,
          position: const Duration(seconds: 2),
          sessionKey: sessionKey,
          reuseSession: true,
        ),
      );
      warm.stop();

      expect(firstResult.frame, isNotNull);
      expect(warmResult.frame, isNotNull);
      expect(firstResult.frame!.sessionReused, isFalse);
      expect(warmResult.frame!.sessionReused, isTrue);
      expect(warmResult.frame!.width, 240);
      // ignore: avoid_print
      print(
        'offline local MP4 first=${first.elapsedMicroseconds / 1000}ms '
        'warm=${warm.elapsedMicroseconds / 1000}ms '
        'decode=${warmResult.frame!.nativeDecodeMicroseconds / 1000}ms '
        'encode=${warmResult.frame!.encodeMicroseconds / 1000}ms',
      );
    },
    skip: Platform.environment['MIRUSHIN_NATIVE_SEEK_SMOKE'] != '1',
  );

  test(
    'native cancellation interrupts IO and the next decode still works',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mirushin_native_cancel_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final File video = File(
        '${directory.path}${Platform.pathSeparator}video.mp4',
      );
      await video.writeAsBytes(
        await _download(
          Uri.parse(
            'https://flutter.github.io/assets-for-api-docs/assets/videos/'
            'bee.mp4',
          ),
        ),
        flush: true,
      );
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Completer<HttpRequest> received = Completer<HttpRequest>();
      server.listen((HttpRequest request) {
        if (!received.isCompleted) received.complete(request);
      });
      final NativeDirectFrameDecoder decoder = NativeDirectFrameDecoder();
      addTearDown(decoder.dispose);
      final Future<DirectFrameDecodeResult> blocked = decoder.decode(
        DirectFrameDecodeRequest(
          input: 'http://${server.address.address}:${server.port}/video.mp4',
          position: Duration.zero,
          sessionKey: 'cancelled-network-session',
          reuseSession: true,
        ),
      );
      await received.future.timeout(const Duration(seconds: 2));
      final Stopwatch cancellation = Stopwatch()..start();
      decoder.cancelPending();
      final DirectFrameDecodeResult cancelled = await blocked.timeout(
        const Duration(seconds: 2),
      );
      cancellation.stop();

      expect(cancelled.failure, DirectFrameFailureKind.cancelled);
      final DirectFrameDecodeResult recovered = await decoder.decode(
        DirectFrameDecodeRequest(
          input: video.path,
          position: const Duration(seconds: 1),
          sessionKey: 'recovery-local-session',
          reuseSession: true,
        ),
      );
      expect(recovered.frame, isNotNull);
      // ignore: avoid_print
      print(
        'native cancellation=${cancellation.elapsedMicroseconds / 1000}ms '
        'recovery=${recovered.frame!.width}x${recovered.frame!.height}',
      );
    },
    skip: Platform.environment['MIRUSHIN_NATIVE_SEEK_SMOKE'] != '1',
  );
}

typedef _OutputSizeNative =
    Int32 Function(
      Int32 codedWidth,
      Int32 codedHeight,
      Int32 sarNum,
      Int32 sarDen,
      Int32 rotationDegrees,
      Int32 targetWidth,
      Pointer<Int32> outputWidth,
      Pointer<Int32> outputHeight,
      Pointer<Double> displayAspectRatio,
    );
typedef _OutputSizeDart =
    int Function(
      int codedWidth,
      int codedHeight,
      int sarNum,
      int sarDen,
      int rotationDegrees,
      int targetWidth,
      Pointer<Int32> outputWidth,
      Pointer<Int32> outputHeight,
      Pointer<Double> displayAspectRatio,
    );

Future<List<int>> _download(Uri uri) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientResponse response = await (await client.getUrl(
      uri,
    )).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Fixture returned HTTP ${response.statusCode}.');
    }
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    client.close(force: true);
  }
}
