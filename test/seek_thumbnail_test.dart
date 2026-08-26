import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_hls.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_source.dart';
import 'package:mirushin/shared/models/media_item.dart';

void main() {
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

  group('seek thumbnail service', () {
    test('broken low qualities fall upward and remember the success', () async {
      final _FakeExtractor extractor = _FakeExtractor(
        failingUrls: <String>{
          'https://cdn.example/144p/index.m3u8',
          'https://cdn.example/240p/index.m3u8',
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
      expect(extractor.urls, <String>[
        'https://cdn.example/144p/index.m3u8',
        'https://cdn.example/240p/index.m3u8',
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
  _FakeExtractor({this.failingUrls = const <String>{}, this.gate});

  final Set<String> failingUrls;
  final Completer<void>? gate;
  final List<String> urls = <String>[];
  int disposeCount = 0;

  @override
  Future<SeekThumbnail?> extract({
    required PlayerSource source,
    required Duration position,
    required Duration duration,
    required String sourceKey,
  }) async {
    urls.add(source.url);
    await gate?.future;
    if (failingUrls.contains(source.url)) return null;
    return SeekThumbnail(
      bytes: Uint8List.fromList(<int>[position.inSeconds & 0xff, 1, 2]),
      position: position,
      width: 320,
      height: 180,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}
