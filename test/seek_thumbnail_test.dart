import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/direct_frame_decoder.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_extractor_io.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_hls.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_hls_index.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_media_loader_io.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_source.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
  group('thumbnail display geometry', () {
    test('preserves common square-pixel display ratios', () {
      expect(
        thumbnailDisplaySize(codedWidth: 1920, codedHeight: 1080).height,
        135,
      );
      expect(
        thumbnailDisplaySize(codedWidth: 1280, codedHeight: 720).height,
        135,
      );
      expect(
        thumbnailDisplaySize(codedWidth: 640, codedHeight: 480).height,
        180,
      );
      expect(
        thumbnailDisplaySize(codedWidth: 1080, codedHeight: 1920).height,
        427,
      );
    });

    test('applies sample aspect ratio before sizing', () {
      expect(
        thumbnailDisplaySize(
          codedWidth: 640,
          codedHeight: 480,
          sampleAspectRatioNumerator: 4,
          sampleAspectRatioDenominator: 3,
        ).height,
        135,
      );
      expect(
        thumbnailDisplaySize(
          codedWidth: 720,
          codedHeight: 480,
          sampleAspectRatioNumerator: 32,
          sampleAspectRatioDenominator: 27,
        ).height,
        135,
      );
    });

    test('swaps display axes for quarter-turn rotation', () {
      final ThumbnailDisplaySize size = thumbnailDisplaySize(
        codedWidth: 1920,
        codedHeight: 1080,
        rotationDegrees: 90,
      );

      expect(size.height, 427);
      expect(size.displayAspectRatio, closeTo(0.5625, 0.0001));
    });
  });

  group('seek thumbnail quantization', () {
    test('uses deterministic five-second floor buckets', () {
      expect(quantizeSeekThumbnailPosition(Duration.zero), Duration.zero);
      expect(
        quantizeSeekThumbnailPosition(const Duration(seconds: 2)),
        Duration.zero,
      );
      expect(
        quantizeSeekThumbnailPosition(const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
      expect(
        quantizeSeekThumbnailPosition(const Duration(seconds: 7)),
        const Duration(seconds: 5),
      );
      expect(
        quantizeSeekThumbnailPosition(const Duration(seconds: 10)),
        const Duration(seconds: 10),
      );
    });
  });

  group('progressive seek thumbnail scheduling', () {
    test('covers the timeline in percentage and midpoint passes', () {
      final List<Duration> positions = progressiveSeekThumbnailPositions(
        const Duration(seconds: 100),
      ).toList(growable: false);

      expect(positions.take(6), <Duration>[
        Duration.zero,
        const Duration(seconds: 20),
        const Duration(seconds: 40),
        const Duration(seconds: 60),
        const Duration(seconds: 80),
        const Duration(seconds: 100),
      ]);
      expect(positions.skip(6).take(5), <Duration>[
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        const Duration(seconds: 50),
        const Duration(seconds: 70),
        const Duration(seconds: 90),
      ]);
      expect(positions.skip(11), <Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: 15),
        const Duration(seconds: 25),
        const Duration(seconds: 35),
        const Duration(seconds: 45),
        const Duration(seconds: 55),
        const Duration(seconds: 65),
        const Duration(seconds: 75),
        const Duration(seconds: 85),
        const Duration(seconds: 95),
      ]);
    });

    test('finishes with no decoder-bucket gap wider than six seconds', () {
      const Duration duration = Duration(minutes: 24);
      final List<Duration> buckets =
          progressiveSeekThumbnailPositions(duration)
              .map(
                (Duration target) =>
                    quantizeSeekThumbnailPosition(target, duration: duration),
              )
              .toSet()
              .toList()
            ..sort();

      expect(buckets.first, Duration.zero);
      expect(
        buckets.last,
        quantizeSeekThumbnailPosition(duration, duration: duration),
      );
      for (int index = 1; index < buckets.length; index++) {
        expect(
          buckets[index] - buckets[index - 1],
          lessThanOrEqualTo(progressiveSeekThumbnailTargetInterval),
        );
      }
    });

    test('runs only for online progressive plans', () {
      const SeekThumbnailSource onlineSource = SeekThumbnailSource(
        source: PlayerSource(url: 'https://cdn.example/video.m3u8'),
        sourceKey: 'online',
        decoderKey: 'online',
        label: '144p',
        isOffline: false,
      );
      const SeekThumbnailSource offlineSource = SeekThumbnailSource(
        source: PlayerSource(url: 'C:/downloads/video.mp4'),
        sourceKey: 'offline',
        decoderKey: 'offline',
        label: 'Downloaded',
        isOffline: true,
      );
      const SeekThumbnailPlan onlinePlan = SeekThumbnailPlan(
        sessionKey: 'online-session',
        candidates: <SeekThumbnailSource>[onlineSource],
        isOffline: false,
      );
      const SeekThumbnailPlan offlinePlan = SeekThumbnailPlan(
        sessionKey: 'offline-session',
        candidates: <SeekThumbnailSource>[offlineSource],
        isOffline: true,
      );

      expect(
        shouldProgressivelyGenerateSeekThumbnails(
          mode: SeekPreviewMode.progressive,
          plan: onlinePlan,
        ),
        isTrue,
      );
      expect(
        shouldProgressivelyGenerateSeekThumbnails(
          mode: SeekPreviewMode.progressive,
          plan: offlinePlan,
        ),
        isFalse,
      );
      expect(
        shouldProgressivelyGenerateSeekThumbnails(
          mode: SeekPreviewMode.onDemand,
          plan: onlinePlan,
        ),
        isFalse,
      );
    });
  });

  group('seek thumbnail source selection', () {
    test('online playback uses the lowest explicit video quality', () {
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('1080p', 1080),
        _quality('720p', 720),
        _quality('480p', 480),
        _quality('144p', 144),
      ]);

      final SeekThumbnailPlan from1080 = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities[0],
      );
      final SeekThumbnailPlan from720 = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities[1],
      );

      expect(from1080.candidates.first.label, '144p');
      expect(from720.candidates.first.label, '144p');
      expect(from1080.candidates.first.source.url, contains('/144p/'));
      expect(from1080.candidates.first.inspectMasterPlaylist, isFalse);
      expect(
        from1080.candidates.first.kind,
        SeekThumbnailSourceKind.networkHls,
      );
      expect(from720.sessionKey, from1080.sessionKey);
    });

    test('single online quality uses the same playable stream', () {
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('1080p', 1080),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.single,
      );

      expect(plan.candidates, hasLength(1));
      expect(plan.candidates.single.source.url, contains('/1080p/'));
    });

    test('audio-only quality is excluded', () {
      final MediaServer server = _onlineServer(<StreamQuality>[
        const StreamQuality(
          id: 'audio',
          label: 'Audio AAC',
          url: 'https://cdn.example/audio.m4a',
          bitrate: 64000,
        ),
        _quality('360p', 360),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.last,
      );

      expect(plan.candidates.first.label, '360p');
      expect(
        plan.candidates.any((SeekThumbnailSource c) => c.label == 'Audio AAC'),
        isFalse,
      );
    });

    test('quality headers win and server headers are the fallback', () {
      const Map<String, String> serverHeaders = <String, String>{
        'Referer': 'https://server.example/',
      };
      const StreamQuality ownHeaders = StreamQuality(
        id: '144p',
        label: '144p',
        url: 'https://cdn.example/144p/index.m3u8',
        headers: <String, String>{'Cookie': 'quality-cookie'},
        height: 144,
      );
      const StreamQuality fallbackHeaders = StreamQuality(
        id: '360p',
        label: '360p',
        url: 'https://cdn.example/360p/index.m3u8',
        height: 360,
      );
      final MediaServer server = _onlineServer(const <StreamQuality>[
        ownHeaders,
        fallbackHeaders,
      ], headers: serverHeaders);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: fallbackHeaders,
      );

      expect(plan.candidates[0].source.headers, ownHeaders.headers);
      expect(plan.candidates[1].source.headers, serverHeaders);
    });

    test('offline playback uses only the exact local media', () {
      final MediaServer server = _offlineServer(
        'file:///downloads/show/episode/video.mp4',
      );
      final MediaPlaybackItem item = _item(
        server,
        externalIds: const <String, String>{
          'mirushin_offline_download_id': 'episode-1',
          'mirushin_offline_media_path': 'show/episode/video.mp4',
          'mirushin_offline_quality': '1080p',
        },
      );
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: item,
        server: server,
        activeQuality: StreamQuality.auto,
      );

      expect(plan.isOffline, isTrue);
      expect(plan.candidates, hasLength(1));
      expect(plan.candidates.single.label, 'offline local media');
      expect(plan.candidates.single.source.url, server.url);
      expect(plan.candidates.single.source.streamType, StreamType.mp4);
      expect(plan.candidates.single.kind, SeekThumbnailSourceKind.localFile);
    });

    test('unknown single HLS source is eligible for one master inspection', () {
      final MediaServer server = MediaServer(
        id: 'server-1',
        name: 'Server',
        sourceName: 'addon',
        url: 'https://cdn.example/master.m3u8',
        streamType: StreamType.hls,
      );
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: StreamQuality.auto,
      );

      expect(plan.candidates, hasLength(1));
      expect(plan.candidates.single.inspectMasterPlaylist, isTrue);
      expect(plan.candidates.single.kind, SeekThumbnailSourceKind.networkHls);
    });

    test('extensionless declared HLS stays ambiguous until probed', () {
      const StreamQuality dynamicQuality = StreamQuality(
        id: '144p',
        label: '144p',
        url: 'https://vd123.okcdn.example/?expires=1&id=2',
        height: 144,
      );
      final MediaServer server = _onlineServer(const <StreamQuality>[
        dynamicQuality,
      ]);

      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: dynamicQuality,
      );

      expect(plan.candidates, hasLength(1));
      expect(
        plan.candidates.single.kind,
        SeekThumbnailSourceKind.networkUnknown,
      );
      expect(plan.candidates.single.source.streamType, StreamType.unknown);
      expect(plan.candidates.single.declaredStreamType, StreamType.hls);
    });

    test('proven main direct route bypasses ambiguous HTTP probing', () {
      const StreamQuality dynamicQuality = StreamQuality(
        id: '144p',
        label: '144p',
        url: 'https://vd752.okcdn.example/?expires=1&id=2',
        headers: <String, String>{'Referer': 'https://provider.test/'},
        height: 144,
      );
      final MediaServer server = _onlineServer(const <StreamQuality>[
        dynamicQuality,
      ]);

      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: dynamicQuality,
        preferDirectNetwork: true,
      );

      expect(plan.candidates, isNotEmpty);
      expect(
        plan.candidates.every(
          (SeekThumbnailSource source) =>
              source.kind == SeekThumbnailSourceKind.networkDirect,
        ),
        isTrue,
      );
      expect(plan.candidates.first.source.url, dynamicQuality.url);
      expect(plan.candidates.first.source.headers, dynamicQuality.headers);
    });

    test('offline identity survives an absolute root path change', () {
      const Map<String, String> ids = <String, String>{
        'mirushin_offline_download_id': 'episode-1',
        'mirushin_offline_media_path': 'show/episode/index.m3u8',
        'mirushin_offline_quality': '1080p',
      };
      final MediaServer oldRoot = _offlineServer(
        'file:///old-container/show/episode/index.m3u8',
        streamType: StreamType.dash,
      );
      final MediaServer newRoot = _offlineServer(
        'file:///new-container/show/episode/index.m3u8',
        streamType: StreamType.dash,
      );
      final SeekThumbnailPlan oldPlan = buildSeekThumbnailPlan(
        item: _item(oldRoot, externalIds: ids),
        server: oldRoot,
        activeQuality: StreamQuality.auto,
      );
      final SeekThumbnailPlan newPlan = buildSeekThumbnailPlan(
        item: _item(newRoot, externalIds: ids),
        server: newRoot,
        activeQuality: StreamQuality.auto,
      );

      expect(newPlan.sessionKey, oldPlan.sessionKey);
      expect(
        newPlan.candidates.single.sourceKey,
        oldPlan.candidates.single.sourceKey,
      );
      expect(newPlan.candidates.single.source.streamType, StreamType.dash);
      expect(
        newPlan.candidates.single.decoderKey,
        isNot(oldPlan.candidates.single.decoderKey),
      );
    });

    test('rotating CDN credentials keep cache identity but reopen decoder', () {
      const StreamQuality oldQuality = StreamQuality(
        id: '144p',
        label: '144p',
        url: 'https://cdn.example/video.mp4?episode=7&token=old&expires=1',
        headers: <String, String>{'Authorization': 'Bearer old'},
        height: 144,
      );
      const StreamQuality newQuality = StreamQuality(
        id: '144p',
        label: '144p',
        url: 'https://cdn.example/video.mp4?episode=7&token=new&expires=2',
        headers: <String, String>{'Authorization': 'Bearer new'},
        height: 144,
      );
      final MediaServer oldServer = _onlineServer(const <StreamQuality>[
        oldQuality,
      ]);
      final MediaServer newServer = _onlineServer(const <StreamQuality>[
        newQuality,
      ]);
      final SeekThumbnailPlan oldPlan = buildSeekThumbnailPlan(
        item: _item(oldServer),
        server: oldServer,
        activeQuality: oldQuality,
      );
      final SeekThumbnailPlan newPlan = buildSeekThumbnailPlan(
        item: _item(newServer),
        server: newServer,
        activeQuality: newQuality,
      );
      final SeekThumbnailSource oldSource = oldPlan.candidates.firstWhere(
        (SeekThumbnailSource source) => source.label == '144p',
      );
      final SeekThumbnailSource newSource = newPlan.candidates.firstWhere(
        (SeekThumbnailSource source) => source.label == '144p',
      );

      expect(newPlan.sessionKey, oldPlan.sessionKey);
      expect(newSource.sourceKey, oldSource.sourceKey);
      expect(newSource.decoderKey, isNot(oldSource.decoderKey));
    });

    test('semantic query parameters remain part of cache identity', () {
      final PlayerSource episodeSeven = const PlayerSource(
        url: 'https://cdn.example/video.mp4?episode=7&token=old',
        streamType: StreamType.mp4,
      );
      final PlayerSource episodeEight = const PlayerSource(
        url: 'https://cdn.example/video.mp4?episode=8&token=new',
        streamType: StreamType.mp4,
      );

      expect(
        seekThumbnailSourceFingerprint(episodeSeven),
        isNot(seekThumbnailSourceFingerprint(episodeEight)),
      );
    });
  });

  group('HLS video variant selection', () {
    test('selects the lowest video and excludes lower-bandwidth audio', () {
      const String master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
audio/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=250000,RESOLUTION=256x144,CODECS="avc1.42c00c,mp4a.40.2"
144/index.m3u8
''';
      final HlsVideoVariant? variant = lowestVideoHlsVariant(
        master,
        Uri.parse('https://cdn.example/master.m3u8'),
      );

      expect(variant, isNotNull);
      expect(variant!.height, 144);
      expect(variant.uri.toString(), 'https://cdn.example/144/index.m3u8');
    });
  });

  group('HLS media timeline index', () {
    test('requires the HLS signature before parsing playlist structure', () {
      expect(hasHlsPlaylistSignature('\uFEFF  #EXTM3U\n#EXTINF:5,'), isTrue);
      expect(hasHlsPlaylistSignature('binary media payload'), isFalse);

      final HlsMediaIndex index = parseHlsMediaIndex(
        'binary media payload\n#EXTINF:5,\nsegment.ts',
        Uri.parse('https://cdn.example/dynamic'),
      );
      expect(index.kind, HlsPlaylistKind.unknown);
      expect(index.segments, isEmpty);
    });

    test('uses variable durations and advances on exact boundaries', () {
      const String playlist = '''
#EXTM3U
#EXT-X-TARGETDURATION:7
#EXT-X-MEDIA-SEQUENCE:41
#EXTINF:4.25,
segment-41.ts
#EXTINF:6.5,
segment-42.ts
#EXTINF:3.25,
segment-43.ts
#EXT-X-ENDLIST
''';
      final HlsMediaIndex index = parseHlsMediaIndex(
        playlist,
        Uri.parse('https://cdn.example/show/video/index.m3u8'),
      );

      expect(index.kind, HlsPlaylistKind.media);
      expect(index.mediaSequence, 41);
      expect(index.targetDuration, const Duration(seconds: 7));
      expect(index.hasEndList, isTrue);
      expect(index.duration, const Duration(seconds: 14));
      expect(index.segmentFor(Duration.zero)!.sequence, 41);
      expect(
        index.segmentFor(const Duration(milliseconds: 4249))!.sequence,
        41,
      );
      expect(
        index.segmentFor(const Duration(milliseconds: 4250))!.sequence,
        42,
      );
      expect(
        index.segmentFor(const Duration(milliseconds: 10750))!.sequence,
        43,
      );
    });

    test('resolves explicit and implicit byte ranges per resource', () {
      const String playlist = '''
#EXTM3U
#EXT-X-MAP:URI="media.mp4",BYTERANGE="100@0"
#EXTINF:5,
#EXT-X-BYTERANGE:500@100
media.mp4
#EXTINF:5,
#EXT-X-BYTERANGE:450
media.mp4
#EXTINF:5,
#EXT-X-BYTERANGE:50
other.mp4
''';
      final HlsMediaIndex index = parseHlsMediaIndex(
        playlist,
        Uri.parse('file:///downloads/episode/index.m3u8'),
      );

      expect(
        index.segments[0].initMap!.byteRange,
        const HlsByteRange(length: 100, offset: 0),
      );
      expect(
        index.segments[0].byteRange,
        const HlsByteRange(length: 500, offset: 100),
      );
      expect(
        index.segments[1].byteRange,
        const HlsByteRange(length: 450, offset: 600),
      );
      expect(
        index.segments[2].byteRange,
        const HlsByteRange(length: 50, offset: 0),
      );
    });

    test('preserves key, IV, map, and discontinuity metadata', () {
      const String playlist = '''
#EXTM3U
#EXT-X-DISCONTINUITY-SEQUENCE:3
#EXT-X-KEY:METHOD=AES-128,URI="Keys/Token.BIN",IV=0x0000000000000000000000000000002A
#EXT-X-MAP:URI="Init.MP4",BYTERANGE="800@20"
#EXTINF:5,
part-1.m4s
#EXT-X-DISCONTINUITY
#EXTINF:5,
part-2.m4s
#EXT-X-KEY:METHOD=NONE
#EXTINF:5,
part-3.m4s
''';
      final HlsMediaIndex index = parseHlsMediaIndex(
        playlist,
        Uri.parse('https://cdn.example/Video/Index.m3u8'),
      );

      expect(index.segments[0].discontinuitySequence, 3);
      expect(index.segments[1].discontinuitySequence, 4);
      expect(index.segments[0].encryption!.method, 'AES-128');
      expect(
        index.segments[0].encryption!.keyUri.toString(),
        'https://cdn.example/Video/Keys/Token.BIN',
      );
      expect(
        index.segments[0].encryption!.iv,
        '0x0000000000000000000000000000002A',
      );
      expect(
        index.segments[0].initMap!.uri.toString(),
        'https://cdn.example/Video/Init.MP4',
      );
      expect(index.segments[2].encryption, isNull);
    });

    test('recognises master playlists without treating them as media', () {
      const String playlist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=250000,RESOLUTION=256x144
144/index.m3u8
''';
      final HlsMediaIndex index = parseHlsMediaIndex(
        playlist,
        Uri.parse('https://cdn.example/master.m3u8'),
      );

      expect(index.kind, HlsPlaylistKind.master);
      expect(index.segments, isEmpty);
    });

    test('expands backward without crossing a discontinuity', () {
      const String playlist = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10,
segment-0.ts
#EXTINF:10,
segment-1.ts
#EXT-X-DISCONTINUITY
#EXTINF:10,
segment-2.ts
#EXTINF:10,
segment-3.ts
#EXTINF:10,
segment-4.ts
#EXT-X-ENDLIST
''';
      final HlsMediaIndex index = parseHlsMediaIndex(
        playlist,
        Uri.parse('https://cdn.example/show/index.m3u8'),
      );

      expect(
        index
            .decodeWindowFor(const Duration(seconds: 45), maxSegments: 4)
            .map((HlsMediaSegment segment) => segment.sequence),
        <int>[2, 3, 4],
      );
      expect(
        index
            .decodeWindowFor(const Duration(seconds: 35), maxSegments: 2)
            .map((HlsMediaSegment segment) => segment.sequence),
        <int>[2, 3],
      );
    });

    test('caps backward context by time as well as segment count', () {
      const String playlist = '''
#EXTM3U
#EXT-X-TARGETDURATION:15
#EXTINF:15,
segment-0.ts
#EXTINF:15,
segment-1.ts
#EXTINF:15,
segment-2.ts
#EXTINF:15,
segment-3.ts
#EXT-X-ENDLIST
''';
      final HlsMediaIndex index = parseHlsMediaIndex(
        playlist,
        Uri.parse('https://cdn.example/show/index.m3u8'),
      );

      expect(
        index
            .decodeWindowFor(
              const Duration(seconds: 50),
              maxSegments: 6,
              maxBackward: const Duration(seconds: 20),
            )
            .map((HlsMediaSegment segment) => segment.sequence),
        <int>[2, 3],
      );
    });
  });

  group('seek thumbnail segment loader', () {
    test('offline HLS reads exact local map and target ranges', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mirushin_seek_loader_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await File(
        '${directory.path}${Platform.pathSeparator}media.bin',
      ).writeAsBytes(List<int>.generate(24, (int index) => index));
      final File playlist = File(
        '${directory.path}${Platform.pathSeparator}index.m3u8',
      );
      await playlist.writeAsString('''
#EXTM3U
#EXT-X-MAP:URI="media.bin",BYTERANGE="4@0"
#EXTINF:5,
#EXT-X-BYTERANGE:5@4
media.bin
#EXTINF:5,
#EXT-X-BYTERANGE:5@9
media.bin
#EXT-X-ENDLIST
''');
      final SeekThumbnailMediaLoader loader = SeekThumbnailMediaLoader();
      addTearDown(loader.dispose);
      final SeekThumbnailSource source = SeekThumbnailSource(
        source: PlayerSource(
          url: playlist.uri.toString(),
          streamType: StreamType.hls,
        ),
        sourceKey: 'offline-source',
        decoderKey: 'offline-decoder',
        label: 'offline local media',
        isOffline: true,
        kind: SeekThumbnailSourceKind.localHls,
      );

      final PreparedThumbnailInput? prepared = await loader.prepare(
        source,
        const Duration(seconds: 5),
      );
      expect(prepared, isNotNull);
      final Directory requestDirectory = prepared!.temporaryDirectory!;
      final String localPlaylist = await File(prepared.input).readAsString();
      expect(localPlaylist, contains('BYTERANGE="4@0"'));
      expect(localPlaylist, contains('#EXT-X-BYTERANGE:5@9'));
      expect(localPlaylist, contains('../media.bin'));
      expect(requestDirectory.parent.path, directory.path);
      expect(
        await File(
          '${requestDirectory.path}${Platform.pathSeparator}segment-0.m4s',
        ).exists(),
        isFalse,
      );
      await prepared.dispose();
    });

    test(
      'online HLS reuses headers and fetches only target resources',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        final List<String> requests = <String>[];
        final List<String?> ranges = <String?>[];
        final Completer<void> serving = Completer<void>();
        unawaited(() async {
          try {
            await for (final HttpRequest request in server) {
              requests.add(request.uri.path);
              ranges.add(request.headers.value(HttpHeaders.rangeHeader));
              expect(request.headers.value('X-Preview-Test'), 'allowed');
              switch (request.uri.path) {
                case '/media.m3u8':
                  request.response.write('''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x00000000000000000000000000000001
#EXT-X-MAP:URI="init.mp4",BYTERANGE="4@2"
#EXTINF:5,
segment-0.ts
#EXTINF:5,
#EXT-X-BYTERANGE:4@4
blob.bin
#EXT-X-ENDLIST
''');
                  break;
                case '/init.mp4':
                  request.response.statusCode = HttpStatus.partialContent;
                  request.response.add(<int>[2, 3, 4, 5]);
                  break;
                case '/blob.bin':
                  request.response.statusCode = HttpStatus.partialContent;
                  request.response.add(<int>[4, 5, 6, 7]);
                  break;
                case '/segment-0.ts':
                  request.response.add(<int>[8, 9, 10, 11]);
                  break;
                case '/key.bin':
                  request.response.add(List<int>.generate(16, (int i) => i));
                  break;
                default:
                  request.response.statusCode = HttpStatus.notFound;
              }
              await request.response.close();
            }
            serving.complete();
          } on Object catch (error, stackTrace) {
            serving.completeError(error, stackTrace);
          }
        }());
        final SeekThumbnailMediaLoader loader = SeekThumbnailMediaLoader();
        addTearDown(loader.dispose);
        final SeekThumbnailSource source = SeekThumbnailSource(
          source: PlayerSource(
            url: 'http://${server.address.address}:${server.port}/media.m3u8',
            headers: const <String, String>{'X-Preview-Test': 'allowed'},
            streamType: StreamType.hls,
          ),
          sourceKey: 'network-source',
          decoderKey: 'network-decoder',
          label: '144p',
          isOffline: false,
          kind: SeekThumbnailSourceKind.networkHls,
        );

        final PreparedThumbnailInput? prepared = await loader.prepare(
          source,
          const Duration(seconds: 7),
        );
        expect(prepared, isNotNull);
        expect(
          requests,
          containsAll(<String>[
            '/media.m3u8',
            '/blob.bin',
            '/init.mp4',
            '/key.bin',
          ]),
        );
        expect(ranges[requests.indexOf('/media.m3u8')], isNull);
        expect(requests, isNot(contains('/segment-0.ts')));
        expect(ranges[requests.indexOf('/blob.bin')], 'bytes=4-7');
        expect(ranges[requests.indexOf('/init.mp4')], 'bytes=2-5');
        await prepared!.dispose();

        requests.clear();
        ranges.clear();
        final PreparedThumbnailInput? fallback = await loader.prepare(
          source,
          const Duration(seconds: 7),
          windowSegments: 2,
        );
        expect(fallback, isNotNull);
        expect(requests, contains('/segment-0.ts'));
        expect(requests, isNot(contains('/blob.bin')));
        expect(requests, isNot(contains('/media.m3u8')));
        final String fallbackPlaylist = await File(
          fallback!.input,
        ).readAsString();
        expect(fallbackPlaylist, contains('#EXT-X-MEDIA-SEQUENCE:0'));
        expect(fallbackPlaylist, contains('segment-0.ts'));
        expect(fallbackPlaylist, contains('segment-1.m4s'));
        expect(fallback.position, const Duration(seconds: 7));
        await fallback.dispose();
        await server.close(force: true);
        await serving.future;
      },
    );

    test(
      'extensionless declared HLS probes direct media and decodes the original URL',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        final List<String?> ranges = <String?>[];
        final Completer<void> serving = Completer<void>();
        unawaited(() async {
          try {
            await for (final HttpRequest request in server) {
              ranges.add(request.headers.value(HttpHeaders.rangeHeader));
              expect(
                request.headers.value('Referer'),
                'https://provider.test/',
              );
              request.response
                ..statusCode = HttpStatus.partialContent
                ..headers.contentType = ContentType('video', 'mp4')
                ..headers.set(
                  HttpHeaders.contentRangeHeader,
                  'bytes 0-15/1000000',
                )
                ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
                ..add(<int>[
                  0,
                  0,
                  0,
                  24,
                  0x66,
                  0x74,
                  0x79,
                  0x70,
                  0x69,
                  0x73,
                  0x6f,
                  0x6d,
                  0,
                  0,
                  0,
                  0,
                ]);
              await request.response.close();
            }
            serving.complete();
          } on Object catch (error, stackTrace) {
            serving.completeError(error, stackTrace);
          }
        }());
        final String dynamicUrl =
            'http://${server.address.address}:${server.port}/dynamic?id=2';
        final StreamQuality quality = StreamQuality(
          id: '144p',
          label: '144p',
          url: dynamicUrl,
          headers: const <String, String>{
            'Referer': 'https://provider.test/',
            'Authorization': 'Bearer preview-test',
          },
          height: 144,
        );
        final MediaServer mediaServer = _onlineServer(<StreamQuality>[quality]);
        final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
          item: _item(mediaServer),
          server: mediaServer,
          activeQuality: quality,
        );
        final _CapturingDecoder decoder = _CapturingDecoder();
        final NativeSeekThumbnailExtractor extractor =
            NativeSeekThumbnailExtractor(decoder: decoder);
        addTearDown(extractor.dispose);

        final SeekThumbnailExtractionResult result = await extractor.extract(
          source: plan.candidates.first,
          position: const Duration(seconds: 42),
          duration: const Duration(minutes: 20),
        );

        expect(result.thumbnail, isNotNull);
        expect(
          plan.candidates.first.kind,
          SeekThumbnailSourceKind.networkUnknown,
        );
        expect(decoder.requests, hasLength(1));
        expect(decoder.requests.single.input, dynamicUrl);
        expect(decoder.requests.single.headers, quality.headers);
        expect(decoder.requests.single.reuseSession, isTrue);
        expect(ranges, <String?>['bytes=0-65535']);
        await server.close(force: true);
        await serving.future;
      },
    );

    test('Range rejection falls back to a bounded normal GET', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String?> ranges = <String?>[];
      unawaited(() async {
        await for (final HttpRequest request in server) {
          final String? range = request.headers.value(HttpHeaders.rangeHeader);
          ranges.add(range);
          if (range != null) {
            request.response.statusCode =
                HttpStatus.requestedRangeNotSatisfiable;
          } else {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType('video', 'mp4')
              ..add(<int>[
                0,
                0,
                0,
                24,
                0x66,
                0x74,
                0x79,
                0x70,
                0x69,
                0x73,
                0x6f,
                0x6d,
              ]);
          }
          await request.response.close();
        }
      }());
      final String url =
          'http://${server.address.address}:${server.port}/dynamic?id=2';
      final StreamQuality quality = StreamQuality(
        id: '144p',
        label: '144p',
        url: url,
        height: 144,
      );
      final MediaServer mediaServer = _onlineServer(<StreamQuality>[quality]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(mediaServer),
        server: mediaServer,
        activeQuality: quality,
      );
      final _CapturingDecoder decoder = _CapturingDecoder();
      final NativeSeekThumbnailExtractor extractor =
          NativeSeekThumbnailExtractor(decoder: decoder);
      addTearDown(extractor.dispose);

      final SeekThumbnailExtractionResult result = await extractor.extract(
        source: plan.candidates.first,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 20),
      );

      expect(result.thumbnail, isNotNull);
      expect(ranges, <String?>['bytes=0-65535', null]);
      expect(decoder.requests.single.input, url);
    });

    test('failed Range and normal probes still attempt direct libav', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String?> ranges = <String?>[];
      unawaited(() async {
        await for (final HttpRequest request in server) {
          ranges.add(request.headers.value(HttpHeaders.rangeHeader));
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
        }
      }());
      final String url =
          'http://${server.address.address}:${server.port}/dynamic?id=3';
      final StreamQuality quality = StreamQuality(
        id: '144p',
        label: '144p',
        url: url,
        headers: const <String, String>{
          'Referer': 'https://provider.test/',
          'Authorization': 'Bearer preview-test',
        },
        height: 144,
      );
      final MediaServer mediaServer = _onlineServer(<StreamQuality>[quality]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(mediaServer),
        server: mediaServer,
        activeQuality: quality,
      );
      final _CapturingDecoder decoder = _CapturingDecoder();
      final NativeSeekThumbnailExtractor extractor =
          NativeSeekThumbnailExtractor(decoder: decoder);
      addTearDown(extractor.dispose);

      final SeekThumbnailExtractionResult result = await extractor.extract(
        source: plan.candidates.first,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 20),
      );

      expect(result.thumbnail, isNotNull);
      expect(ranges, <String?>['bytes=0-65535', null]);
      expect(decoder.requests, hasLength(1));
      expect(decoder.requests.single.input, url);
      expect(decoder.requests.single.headers, quality.headers);
    });

    test('Range rejection is remembered across quality fallback', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String?> ranges = <String?>[];
      unawaited(() async {
        await for (final HttpRequest request in server) {
          final String? range = request.headers.value(HttpHeaders.rangeHeader);
          ranges.add(range);
          request.response.statusCode = range == null
              ? HttpStatus.forbidden
              : HttpStatus.requestedRangeNotSatisfiable;
          await request.response.close();
        }
      }());
      final String origin = 'http://${server.address.address}:${server.port}';
      final List<StreamQuality> qualities = <StreamQuality>[
        StreamQuality(
          id: '144p',
          label: '144p',
          url: '$origin/144?id=1',
          height: 144,
        ),
        StreamQuality(
          id: '240p',
          label: '240p',
          url: '$origin/240?id=2',
          height: 240,
        ),
      ];
      final MediaServer mediaServer = _onlineServer(qualities);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(mediaServer),
        server: mediaServer,
        activeQuality: qualities.first,
      );
      final _FirstOpenFailsDecoder decoder = _FirstOpenFailsDecoder();
      final SeekThumbnailService service = SeekThumbnailService(
        extractorFactory: (_) => NativeSeekThumbnailExtractor(decoder: decoder),
      );
      addTearDown(service.dispose);

      final SeekThumbnail? thumbnail = await service.request(
        plan: plan,
        backend: PlayerBackend.fvp,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 20),
      );

      expect(thumbnail, isNotNull);
      expect(decoder.requests, hasLength(2));
      expect(ranges, <String?>['bytes=0-65535', null, null]);
    });

    test(
      'extensionless HLS is probed then uses indexed segment extraction',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        final List<({String path, String? range})> requests =
            <({String path, String? range})>[];
        final Completer<void> serving = Completer<void>();
        const String playlist = '''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5,
segment.ts
#EXT-X-ENDLIST
''';
        unawaited(() async {
          try {
            await for (final HttpRequest request in server) {
              final String? range = request.headers.value(
                HttpHeaders.rangeHeader,
              );
              requests.add((path: request.uri.path, range: range));
              if (request.uri.path == '/dynamic') {
                final List<int> bytes = utf8.encode(playlist);
                request.response.headers.contentType = ContentType(
                  'application',
                  'vnd.apple.mpegurl',
                );
                if (range != null) {
                  request.response
                    ..statusCode = HttpStatus.partialContent
                    ..headers.set(
                      HttpHeaders.contentRangeHeader,
                      'bytes 0-${bytes.length - 1}/${bytes.length}',
                    )
                    ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
                }
                request.response.add(bytes);
              } else if (request.uri.path == '/segment.ts') {
                request.response.add(<int>[1, 2, 3, 4]);
              } else {
                request.response.statusCode = HttpStatus.notFound;
              }
              await request.response.close();
            }
            serving.complete();
          } on Object catch (error, stackTrace) {
            serving.completeError(error, stackTrace);
          }
        }());
        final String dynamicUrl =
            'http://${server.address.address}:${server.port}/dynamic';
        final StreamQuality quality = StreamQuality(
          id: '144p',
          label: '144p',
          url: dynamicUrl,
          height: 144,
        );
        final MediaServer mediaServer = _onlineServer(<StreamQuality>[quality]);
        final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
          item: _item(mediaServer),
          server: mediaServer,
          activeQuality: quality,
        );
        final _WindowAwareDecoder decoder = _WindowAwareDecoder(
          requiredSegments: 1,
        );
        final NativeSeekThumbnailExtractor extractor =
            NativeSeekThumbnailExtractor(decoder: decoder);
        addTearDown(extractor.dispose);

        final SeekThumbnailExtractionResult result = await extractor.extract(
          source: plan.candidates.first,
          position: const Duration(seconds: 2),
          duration: const Duration(seconds: 5),
        );

        expect(result.thumbnail, isNotNull);
        expect(decoder.windowSizes, <int>[1]);
        expect(
          requests
              .where((request) => request.path == '/dynamic')
              .map((request) => request.range),
          containsAll(<String?>['bytes=0-65535', null]),
        );
        expect(
          requests.any((request) => request.path == '/segment.ts'),
          isTrue,
        );
        await server.close(force: true);
        await serving.future;
      },
    );

    test('explicit m3u8 rejects binary content before HLS parsing', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Completer<void> serving = Completer<void>();
      unawaited(() async {
        try {
          await for (final HttpRequest request in server) {
            request.response
              ..headers.contentType = ContentType('video', 'mp4')
              ..add(<int>[0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]);
            await request.response.close();
          }
          serving.complete();
        } on Object catch (error, stackTrace) {
          serving.completeError(error, stackTrace);
        }
      }());
      final SeekThumbnailMediaLoader loader = SeekThumbnailMediaLoader();
      addTearDown(loader.dispose);
      final SeekThumbnailSource source = SeekThumbnailSource(
        source: PlayerSource(
          url: 'http://${server.address.address}:${server.port}/playlist.m3u8',
          streamType: StreamType.hls,
        ),
        sourceKey: 'binary-hls-source',
        decoderKey: 'binary-hls-decoder',
        label: '144p',
        isOffline: false,
        kind: SeekThumbnailSourceKind.networkHls,
      );

      await expectLater(
        loader.prepare(source, Duration.zero),
        throwsA(
          isA<SeekThumbnailLoadException>().having(
            (SeekThumbnailLoadException error) => error.failure.reason,
            'reason',
            SeekThumbnailFailureReason.notHlsPlaylist,
          ),
        ),
      );
      await server.close(force: true);
      await serving.future;
    });

    test('extractor expands from one segment until context decodes', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mirushin_seek_window_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final File playlist = File(
        '${directory.path}${Platform.pathSeparator}index.m3u8',
      );
      for (int index = 0; index < 4; index += 1) {
        await File(
          '${directory.path}${Platform.pathSeparator}segment-$index.ts',
        ).writeAsBytes(<int>[index]);
      }
      await playlist.writeAsString('''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5,
segment-0.ts
#EXTINF:5,
segment-1.ts
#EXTINF:5,
segment-2.ts
#EXTINF:5,
segment-3.ts
#EXT-X-ENDLIST
''');
      final _WindowAwareDecoder decoder = _WindowAwareDecoder(
        requiredSegments: 3,
      );
      final NativeSeekThumbnailExtractor extractor =
          NativeSeekThumbnailExtractor(decoder: decoder);
      addTearDown(extractor.dispose);
      final SeekThumbnailSource source = SeekThumbnailSource(
        source: PlayerSource(
          url: playlist.uri.toString(),
          streamType: StreamType.hls,
        ),
        sourceKey: 'offline-window-source',
        decoderKey: 'offline-window-decoder',
        label: 'offline local media',
        isOffline: true,
        kind: SeekThumbnailSourceKind.localHls,
      );

      final SeekThumbnailExtractionResult result = await extractor.extract(
        source: source,
        position: const Duration(seconds: 17),
        duration: const Duration(seconds: 20),
      );

      expect(result.thumbnail, isNotNull);
      expect(decoder.windowSizes, <int>[1, 2, 3]);
    });

    test('extractor stops after the bounded four-segment context', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mirushin_seek_window_bound_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final File playlist = File(
        '${directory.path}${Platform.pathSeparator}index.m3u8',
      );
      for (int index = 0; index < 6; index += 1) {
        await File(
          '${directory.path}${Platform.pathSeparator}segment-$index.ts',
        ).writeAsBytes(<int>[index]);
      }
      await playlist.writeAsString('''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5,
segment-0.ts
#EXTINF:5,
segment-1.ts
#EXTINF:5,
segment-2.ts
#EXTINF:5,
segment-3.ts
#EXTINF:5,
segment-4.ts
#EXTINF:5,
segment-5.ts
#EXT-X-ENDLIST
''');
      final _WindowAwareDecoder decoder = _WindowAwareDecoder(
        requiredSegments: 5,
      );
      final NativeSeekThumbnailExtractor extractor =
          NativeSeekThumbnailExtractor(decoder: decoder);
      addTearDown(extractor.dispose);
      final SeekThumbnailSource source = SeekThumbnailSource(
        source: PlayerSource(
          url: playlist.uri.toString(),
          streamType: StreamType.hls,
        ),
        sourceKey: 'offline-bounded-source',
        decoderKey: 'offline-bounded-decoder',
        label: 'offline local media',
        isOffline: true,
        kind: SeekThumbnailSourceKind.localHls,
      );

      final SeekThumbnailExtractionResult result = await extractor.extract(
        source: source,
        position: const Duration(seconds: 27),
        duration: const Duration(seconds: 30),
      );

      expect(result.thumbnail, isNull);
      expect(
        result.failure?.reason,
        SeekThumbnailFailureReason.missingRandomAccessContext,
      );
      expect(decoder.windowSizes, <int>[1, 2, 3, 4]);
    });
  });

  group('seek thumbnail service', () {
    test('each new bucket retries the lowest quality first', () async {
      final _FakeExtractor extractor = _FakeExtractor(
        failingBuckets: <String, Set<int>>{
          'https://cdn.example/144p/index.m3u8': <int>{5},
        },
      );
      final SeekThumbnailService service = _service(extractor);
      addTearDown(service.dispose);
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('360p', 360),
        _quality('240p', 240),
        _quality('144p', 144),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.first,
      );

      expect(
        await service.request(
          plan: plan,
          backend: PlayerBackend.mpv,
          position: Duration.zero,
          duration: const Duration(minutes: 24),
        ),
        isNotNull,
      );
      expect(extractor.urls, <String>['https://cdn.example/144p/index.m3u8']);

      extractor.urls.clear();
      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 24),
      );
      expect(extractor.urls, <String>[
        'https://cdn.example/144p/index.m3u8',
        'https://cdn.example/240p/index.m3u8',
      ]);

      extractor.urls.clear();
      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 24),
      );
      expect(extractor.urls, <String>['https://cdn.example/144p/index.m3u8']);
    });

    test('only permanent source evidence skips a quality later', () async {
      final _FakeExtractor extractor = _FakeExtractor(
        permanentUrls: <String>{'https://cdn.example/144p/index.m3u8'},
      );
      final SeekThumbnailService service = _service(extractor);
      addTearDown(service.dispose);
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('360p', 360),
        _quality('144p', 144),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.first,
      );

      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: Duration.zero,
        duration: const Duration(minutes: 24),
      );
      expect(extractor.urls, <String>[
        'https://cdn.example/144p/index.m3u8',
        'https://cdn.example/360p/index.m3u8',
      ]);

      extractor.urls.clear();
      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 24),
      );
      expect(extractor.urls, <String>['https://cdn.example/360p/index.m3u8']);
    });

    test('a one-off 403 does not poison later buckets', () async {
      final _FakeExtractor extractor = _FakeExtractor(
        bucketFailures: <String, Map<int, SeekThumbnailFailure>>{
          'https://cdn.example/144p/index.m3u8': <int, SeekThumbnailFailure>{
            0: const SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.transient,
              reason: SeekThumbnailFailureReason.httpForbidden,
            ),
          },
        },
      );
      final SeekThumbnailService service = _service(extractor);
      addTearDown(service.dispose);
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('360p', 360),
        _quality('144p', 144),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.first,
      );

      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: Duration.zero,
        duration: const Duration(minutes: 24),
      );
      extractor.urls.clear();
      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 24),
      );

      expect(extractor.urls.first, 'https://cdn.example/144p/index.m3u8');
    });

    test('two independent 404 buckets can mark a source unavailable', () async {
      const SeekThumbnailFailure missing = SeekThumbnailFailure(
        scope: SeekThumbnailFailureScope.transient,
        reason: SeekThumbnailFailureReason.httpNotFound,
      );
      final _FakeExtractor extractor = _FakeExtractor(
        bucketFailures: <String, Map<int, SeekThumbnailFailure>>{
          'https://cdn.example/144p/index.m3u8': <int, SeekThumbnailFailure>{
            0: missing,
            5: missing,
          },
        },
      );
      final SeekThumbnailService service = _service(extractor);
      addTearDown(service.dispose);
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('360p', 360),
        _quality('144p', 144),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.first,
      );

      for (final int second in <int>[0, 5]) {
        await service.request(
          plan: plan,
          backend: PlayerBackend.mpv,
          position: Duration(seconds: second),
          duration: const Duration(minutes: 24),
        );
      }
      extractor.urls.clear();
      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 10),
        duration: const Duration(minutes: 24),
      );

      expect(extractor.urls, <String>['https://cdn.example/360p/index.m3u8']);
    });

    test('a timed-out bucket retries the lowest quality next time', () async {
      final _FakeExtractor extractor = _FakeExtractor(
        bucketDelays: <String, Map<int, Duration>>{
          'https://cdn.example/144p/index.m3u8': <int, Duration>{
            0: const Duration(milliseconds: 30),
          },
        },
      );
      final SeekThumbnailService service = SeekThumbnailService(
        extractorFactory: (_) => extractor,
        extractionTimeout: const Duration(milliseconds: 5),
        onlineRequestTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(service.dispose);
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('360p', 360),
        _quality('144p', 144),
      ]);
      final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities.first,
      );

      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: Duration.zero,
        duration: const Duration(minutes: 24),
      );
      extractor.urls.clear();
      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 24),
      );

      expect(extractor.cancelCount, greaterThanOrEqualTo(1));
      expect(extractor.urls.first, 'https://cdn.example/144p/index.m3u8');
    });

    test(
      'the total fallback deadline bounds a failing quality chain',
      () async {
        final _FakeExtractor extractor = _FakeExtractor(
          defaultDelay: const Duration(milliseconds: 100),
        );
        final SeekThumbnailService service = SeekThumbnailService(
          extractorFactory: (_) => extractor,
          extractionTimeout: const Duration(milliseconds: 20),
          onlineRequestTimeout: const Duration(milliseconds: 45),
        );
        addTearDown(service.dispose);
        final MediaServer server = _onlineServer(<StreamQuality>[
          _quality('360p', 360),
          _quality('240p', 240),
          _quality('144p', 144),
        ]);
        final SeekThumbnailPlan plan = buildSeekThumbnailPlan(
          item: _item(server),
          server: server,
          activeQuality: server.qualities.first,
        );
        final Stopwatch stopwatch = Stopwatch()..start();

        final SeekThumbnail? result = await service.request(
          plan: plan,
          backend: PlayerBackend.mpv,
          position: Duration.zero,
          duration: const Duration(minutes: 24),
        );
        stopwatch.stop();

        expect(result, isNull);
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
        expect(extractor.cancelCount, greaterThanOrEqualTo(2));
      },
    );

    test('same source and bucket share a cache key', () {
      const SeekThumbnailCacheKey first = SeekThumbnailCacheKey(
        sourceKey: 'source-a',
        bucket: Duration(seconds: 10),
      );
      const SeekThumbnailCacheKey same = SeekThumbnailCacheKey(
        sourceKey: 'source-a',
        bucket: Duration(seconds: 10),
      );
      const SeekThumbnailCacheKey different = SeekThumbnailCacheKey(
        sourceKey: 'source-b',
        bucket: Duration(seconds: 10),
      );

      expect(first, same);
      expect(first, isNot(different));
    });

    test('LRU evicts the oldest unused thumbnail', () async {
      final _FakeExtractor extractor = _FakeExtractor();
      final SeekThumbnailService service = _service(
        extractor,
        maxCacheEntries: 2,
      );
      addTearDown(service.dispose);
      final SeekThumbnailPlan plan = _singlePlan();
      for (final int second in <int>[0, 5, 10]) {
        await service.request(
          plan: plan,
          backend: PlayerBackend.mpv,
          position: Duration(seconds: second),
          duration: const Duration(minutes: 1),
        );
      }
      expect(service.cacheEntryCount, 2);
      expect(extractor.urls, hasLength(3));

      await service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: Duration.zero,
        duration: const Duration(minutes: 1),
      );
      expect(extractor.urls, hasLength(4));
    });

    test(
      'progressive lookup exposes a coarse frame across the timeline',
      () async {
        final _FakeExtractor extractor = _FakeExtractor();
        final SeekThumbnailService service = _service(extractor);
        addTearDown(service.dispose);
        final SeekThumbnailPlan plan = _singlePlan();
        const Duration duration = Duration(seconds: 100);

        await service.request(
          plan: plan,
          backend: PlayerBackend.mpv,
          position: Duration.zero,
          duration: duration,
        );

        expect(
          service.nearestCachedFor(
            plan,
            const Duration(seconds: 90),
            duration: duration,
          ),
          isNull,
        );
        expect(
          service.nearestCachedFor(
            plan,
            const Duration(seconds: 90),
            duration: duration,
            maxDistance: duration,
          ),
          isNotNull,
        );
      },
    );

    test('identical simultaneous requests are coalesced', () async {
      final Completer<void> gate = Completer<void>();
      final _FakeExtractor extractor = _FakeExtractor(gate: gate);
      final SeekThumbnailService service = _service(extractor);
      addTearDown(service.dispose);
      final SeekThumbnailPlan plan = _singlePlan();

      final Future<SeekThumbnail?> first = service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 7),
        duration: const Duration(minutes: 1),
      );
      final Future<SeekThumbnail?> second = service.request(
        plan: plan,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 9),
        duration: const Duration(minutes: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(extractor.urls, hasLength(1));
      gate.complete();
      final List<SeekThumbnail?> results = await Future.wait(
        <Future<SeekThumbnail?>>[first, second],
      );

      expect(results[0], same(results[1]));
      expect(extractor.urls, hasLength(1));
    });

    test('superseded preview work is forwarded to the extractor', () async {
      final _FakeExtractor extractor = _FakeExtractor();
      final SeekThumbnailService service = _service(extractor);
      addTearDown(service.dispose);
      await service.activate(_singlePlan(), PlayerBackend.mpv);

      service.cancelPending();

      expect(extractor.cancelCount, 1);
    });

    test('quality change keeps the low-quality decoder context', () async {
      final _FakeExtractor extractor = _FakeExtractor();
      int factoryCalls = 0;
      final SeekThumbnailService service = SeekThumbnailService(
        extractorFactory: (_) {
          factoryCalls++;
          return extractor;
        },
      );
      addTearDown(service.dispose);
      final MediaServer server = _onlineServer(<StreamQuality>[
        _quality('1080p', 1080),
        _quality('720p', 720),
        _quality('144p', 144),
      ]);
      final SeekThumbnailPlan from1080 = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities[0],
      );
      final SeekThumbnailPlan from720 = buildSeekThumbnailPlan(
        item: _item(server),
        server: server,
        activeQuality: server.qualities[1],
      );

      await service.activate(from1080, PlayerBackend.mpv);
      await service.request(
        plan: from1080,
        backend: PlayerBackend.mpv,
        position: Duration.zero,
        duration: const Duration(minutes: 24),
      );
      await service.activate(from720, PlayerBackend.mpv);
      await service.request(
        plan: from720,
        backend: PlayerBackend.mpv,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 24),
      );

      expect(from720.sessionKey, from1080.sessionKey);
      expect(from720.candidates.first.label, '144p');
      expect(factoryCalls, 1);
      expect(extractor.disposeCount, 0);
    });
  });

  group('stale completion guards', () {
    test('older requests cannot replace the latest bucket', () {
      final SeekThumbnailRequestTracker tracker = SeekThumbnailRequestTracker();
      final int old = tracker.begin('episode-a', const Duration(seconds: 120));
      final int latest = tracker.begin(
        'episode-a',
        const Duration(seconds: 480),
      );

      expect(
        tracker.accepts(old, 'episode-a', const Duration(seconds: 120)),
        isFalse,
      );
      expect(
        tracker.accepts(latest, 'episode-a', const Duration(seconds: 480)),
        isTrue,
      );
    });

    test('an old episode cannot update a new episode', () {
      final SeekThumbnailRequestTracker tracker = SeekThumbnailRequestTracker();
      final int old = tracker.begin('episode-a', const Duration(seconds: 10));
      tracker.begin('episode-b', const Duration(seconds: 10));

      expect(
        tracker.accepts(old, 'episode-a', const Duration(seconds: 10)),
        isFalse,
      );
    });
  });
}

SeekThumbnailService _service(
  _FakeExtractor extractor, {
  int maxCacheEntries = 120,
}) {
  return SeekThumbnailService(
    extractorFactory: (_) => extractor,
    maxCacheEntries: maxCacheEntries,
  );
}

SeekThumbnailPlan _singlePlan() {
  const PlayerSource source = PlayerSource(
    url: 'https://cdn.example/144p/index.m3u8',
    streamType: StreamType.hls,
  );
  return const SeekThumbnailPlan(
    sessionKey: 'episode-a',
    candidates: <SeekThumbnailSource>[
      SeekThumbnailSource(
        source: source,
        sourceKey: 'source-a',
        decoderKey: 'decoder-a',
        label: '144p',
        isOffline: false,
      ),
    ],
    isOffline: false,
  );
}

StreamQuality _quality(String label, int height) {
  return StreamQuality(
    id: label,
    label: label,
    url: 'https://cdn.example/$label/index.m3u8',
    height: height,
  );
}

MediaServer _onlineServer(
  List<StreamQuality> qualities, {
  Map<String, String> headers = const <String, String>{},
}) {
  return MediaServer(
    id: 'server-1',
    name: 'Server',
    sourceName: 'addon',
    url: qualities.first.url,
    headers: headers,
    streamType: StreamType.hls,
    qualities: qualities,
  );
}

MediaServer _offlineServer(
  String url, {
  StreamType streamType = StreamType.mp4,
}) {
  return MediaServer(
    id: 'offline',
    name: 'Downloaded',
    sourceName: 'addon',
    url: url,
    streamType: streamType,
  );
}

MediaPlaybackItem _item(
  MediaServer server, {
  Map<String, String> externalIds = const <String, String>{},
}) {
  return MediaPlaybackItem(
    id: 'media-1',
    title: 'Title',
    mediaType: MediaType.anime,
    servers: <MediaServer>[server],
    externalIds: externalIds,
    currentEpisodeId: '1_1',
    seasonNumber: 1,
    episodeNumber: 1,
  );
}

class _FakeExtractor implements SeekThumbnailExtractor {
  _FakeExtractor({
    this.failingBuckets = const <String, Set<int>>{},
    this.bucketFailures = const <String, Map<int, SeekThumbnailFailure>>{},
    this.bucketDelays = const <String, Map<int, Duration>>{},
    this.defaultDelay = Duration.zero,
    this.permanentUrls = const <String>{},
    this.gate,
  });

  final Map<String, Set<int>> failingBuckets;
  final Map<String, Map<int, SeekThumbnailFailure>> bucketFailures;
  final Map<String, Map<int, Duration>> bucketDelays;
  final Duration defaultDelay;
  final Set<String> permanentUrls;
  final Completer<void>? gate;
  final List<String> urls = <String>[];
  int disposeCount = 0;
  int cancelCount = 0;

  @override
  void cancelPending() {
    cancelCount++;
  }

  @override
  Future<void> warm(SeekThumbnailSource source) async {}

  @override
  Future<SeekThumbnailExtractionResult> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
  }) async {
    urls.add(source.source.url);
    await gate?.future;
    final Duration delay =
        bucketDelays[source.source.url]?[position.inSeconds] ?? defaultDelay;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (permanentUrls.contains(source.source.url)) {
      return const SeekThumbnailExtractionResult.failure(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.permanentSource,
          reason: SeekThumbnailFailureReason.noVideoTrack,
        ),
      );
    }
    final SeekThumbnailFailure? explicitFailure =
        bucketFailures[source.source.url]?[position.inSeconds];
    if (explicitFailure != null) {
      return SeekThumbnailExtractionResult.failure(explicitFailure);
    }
    if (failingBuckets[source.source.url]?.contains(position.inSeconds) ??
        false) {
      return const SeekThumbnailExtractionResult.failure(
        SeekThumbnailFailure(
          scope: SeekThumbnailFailureScope.bucketSpecific,
          reason: SeekThumbnailFailureReason.decodeFailure,
        ),
      );
    }
    return SeekThumbnailExtractionResult.success(
      SeekThumbnail(
        bytes: Uint8List.fromList(<int>[position.inSeconds & 0xff, 1, 2]),
        position: position,
        width: 320,
        height: 180,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _WindowAwareDecoder implements DirectFrameDecoder {
  _WindowAwareDecoder({required this.requiredSegments});

  final int requiredSegments;
  final List<int> windowSizes = <int>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> warm() async {}

  @override
  void cancelPending() {}

  @override
  Future<DirectFrameDecodeResult> decode(
    DirectFrameDecodeRequest request,
  ) async {
    final String playlist = await File(request.input).readAsString();
    final int count = RegExp(
      r'^#EXTINF:',
      multiLine: true,
    ).allMatches(playlist).length;
    windowSizes.add(count);
    if (count < requiredSegments) {
      return const DirectFrameDecodeResult.failure(
        DirectFrameFailureKind.noFrame,
      );
    }
    return DirectFrameDecodeResult.success(
      DirectFrame(
        jpegBytes: Uint8List.fromList(<int>[1, 2, 3]),
        position: request.position,
        width: 240,
        height: 135,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _CapturingDecoder implements DirectFrameDecoder {
  final List<DirectFrameDecodeRequest> requests = <DirectFrameDecodeRequest>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> warm() async {}

  @override
  void cancelPending() {}

  @override
  Future<DirectFrameDecodeResult> decode(
    DirectFrameDecodeRequest request,
  ) async {
    requests.add(request);
    return DirectFrameDecodeResult.success(
      DirectFrame(
        jpegBytes: Uint8List.fromList(<int>[1, 2, 3]),
        position: request.position,
        width: 240,
        height: 135,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _FirstOpenFailsDecoder extends _CapturingDecoder {
  @override
  Future<DirectFrameDecodeResult> decode(
    DirectFrameDecodeRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const DirectFrameDecodeResult.failure(
        DirectFrameFailureKind.openInput,
      );
    }
    return DirectFrameDecodeResult.success(
      DirectFrame(
        jpegBytes: Uint8List.fromList(<int>[1, 2, 3]),
        position: request.position,
        width: 240,
        height: 135,
      ),
    );
  }
}
