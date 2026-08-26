import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_extractor_io.dart';

void main() {
  test(
    'native bridge decodes one indexed public HLS segment',
    () async {
      final NativeSeekThumbnailExtractor extractor =
          NativeSeekThumbnailExtractor();
      addTearDown(extractor.dispose);
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
      final Stopwatch stopwatch = Stopwatch()..start();
      final SeekThumbnail? thumbnail = await extractor.extract(
        source: source,
        position: const Duration(seconds: 20),
        duration: const Duration(minutes: 10),
      );
      stopwatch.stop();

      expect(thumbnail, isNotNull);
      expect(thumbnail!.width, 240);
      expect(thumbnail.height, greaterThan(0));
      expect(thumbnail.bytes, hasLength(greaterThan(4)));
      expect(thumbnail.bytes.sublist(0, 2), <int>[0xff, 0xd8]);
      // ignore: avoid_print
      print(
        'native HLS thumbnail ${thumbnail.width}x${thumbnail.height} '
        '${thumbnail.bytes.length} bytes in ${stopwatch.elapsedMilliseconds}ms',
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
      await File(
        '${directory.path}${Platform.pathSeparator}segment.ts',
      ).writeAsBytes(segmentBytes, flush: true);
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
      final NativeSeekThumbnailExtractor extractor =
          NativeSeekThumbnailExtractor();
      addTearDown(extractor.dispose);
      final Stopwatch stopwatch = Stopwatch()..start();
      final SeekThumbnail? thumbnail = await extractor.extract(
        source: SeekThumbnailSource(
          source: PlayerSource(url: video.path, streamType: StreamType.mp4),
          sourceKey: 'local-mp4-smoke-source',
          decoderKey: 'local-mp4-smoke-decoder',
          label: 'offline local media',
          isOffline: true,
          kind: SeekThumbnailSourceKind.localFile,
        ),
        position: const Duration(seconds: 1),
        duration: const Duration(seconds: 4),
      );
      stopwatch.stop();

      expect(thumbnail, isNotNull);
      expect(thumbnail!.width, 240);
      // ignore: avoid_print
      print(
        'offline local MP4 frame=${stopwatch.elapsedMicroseconds / 1000}ms',
      );
    },
    skip: Platform.environment['MIRUSHIN_NATIVE_SEEK_SMOKE'] != '1',
  );
}

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
