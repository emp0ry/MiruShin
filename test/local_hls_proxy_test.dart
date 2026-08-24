import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/local_hls_proxy.dart';

void main() {
  test(
    'rewritten playlist and segment URLs preserve provider headers',
    () async {
      final HttpServer upstream = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      late final String upstreamOrigin;
      final List<
        ({String path, String? referer, String? origin, String? acceptEncoding})
      >
      seen =
          <
            ({
              String path,
              String? referer,
              String? origin,
              String? acceptEncoding,
            })
          >[];

      upstreamOrigin = 'http://${upstream.address.address}:${upstream.port}';
      final StreamSubscription<HttpRequest> upstreamSub = upstream.listen((
        HttpRequest request,
      ) {
        seen.add((
          path: request.uri.path,
          referer: request.headers.value(HttpHeaders.refererHeader),
          origin: request.headers.value('origin'),
          acceptEncoding: request.headers.value(
            HttpHeaders.acceptEncodingHeader,
          ),
        ));

        switch (request.uri.path) {
          case '/master.m3u8':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType(
                'application',
                'vnd.apple.mpegurl',
              )
              ..write(
                '#EXTM3U\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=1000\n'
                '$upstreamOrigin/media.m3u8\n',
              );
          case '/media.m3u8':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType(
                'application',
                'vnd.apple.mpegurl',
              )
              ..write(
                '#EXTM3U\n'
                '#EXT-X-TARGETDURATION:4\n'
                '#EXTINF:4,\n'
                '$upstreamOrigin/segment.ts\n'
                '#EXT-X-ENDLIST\n',
              );
          case '/segment.ts':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.binary
              ..write('segment');
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        unawaited(request.response.close());
      });

      final LocalHlsProxy proxy = LocalHlsProxy();
      final HttpClient client = HttpClient();

      Future<String> read(Uri uri, {Map<String, String>? headers}) async {
        final HttpClientRequest request = await client.getUrl(uri);
        headers?.forEach(request.headers.set);
        final HttpClientResponse response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        return response.transform(utf8.decoder).join();
      }

      try {
        await proxy.start();
        final Uri masterUri = Uri.parse('$upstreamOrigin/master.m3u8');
        final Uri proxiedMaster = Uri.parse(
          proxy.playlistUrl(
            masterUri,
            headers: const <String, String>{
              'Referer': 'https://provider.example/watch',
              'Origin': 'https://provider.example',
            },
          ),
        );

        final String master = await read(proxiedMaster);
        final Uri proxiedMedia = Uri.parse(
          const LineSplitter()
              .convert(master)
              .firstWhere((String line) => line.startsWith('http://127.0.0.1')),
        );
        expect(proxiedMedia.queryParameters['h'], isNotNull);

        final String media = await read(
          proxiedMedia,
          headers: const <String, String>{
            'Referer': 'http://127.0.0.1/local-master.m3u8',
            'Origin': 'http://127.0.0.1',
          },
        );
        final Uri proxiedSegment = Uri.parse(
          const LineSplitter()
              .convert(media)
              .firstWhere((String line) => line.startsWith('http://127.0.0.1')),
        );
        expect(proxiedSegment.queryParameters['h'], isNotNull);

        await read(
          proxiedSegment,
          headers: const <String, String>{
            'Referer': 'http://127.0.0.1/local-media.m3u8',
            'Origin': 'http://127.0.0.1',
          },
        );

        final masterRequest = seen.singleWhere(
          (
            ({
              String path,
              String? referer,
              String? origin,
              String? acceptEncoding,
            })
            request,
          ) => request.path == '/master.m3u8',
        );
        final mediaRequest = seen.singleWhere(
          (
            ({
              String path,
              String? referer,
              String? origin,
              String? acceptEncoding,
            })
            request,
          ) => request.path == '/media.m3u8',
        );
        final segmentRequest = seen.singleWhere(
          (
            ({
              String path,
              String? referer,
              String? origin,
              String? acceptEncoding,
            })
            request,
          ) => request.path == '/segment.ts',
        );

        expect(masterRequest.acceptEncoding, 'identity');
        expect(mediaRequest.acceptEncoding, 'identity');
        expect(segmentRequest.acceptEncoding, 'identity');
        expect(mediaRequest.referer, 'https://provider.example/watch');
        expect(mediaRequest.origin, 'https://provider.example');
        expect(segmentRequest.referer, 'https://provider.example/watch');
        expect(segmentRequest.origin, 'https://provider.example');
      } finally {
        client.close(force: true);
        await proxy.stop();
        await upstreamSub.cancel();
        await upstream.close(force: true);
      }
    },
  );

  test('serves local downloaded HLS playlists and ranged segments', () async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'mirushin_local_hls_proxy_test_',
    );
    final File playlist = File('${dir.path}/index.m3u8');
    final File key = File('${dir.path}/key.bin');
    final File segment = File('${dir.path}/seg_00001.ts');

    await key.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    await segment.writeAsString('segment-bytes', flush: true);
    await playlist.writeAsString(
      '#EXTM3U\n'
      '#EXT-X-TARGETDURATION:4\n'
      '#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
      '#EXTINF:4,\n'
      'seg_00001.ts\n'
      '#EXT-X-ENDLIST\n',
      flush: true,
    );

    final LocalHlsProxy proxy = LocalHlsProxy();
    final HttpClient client = HttpClient();

    Future<HttpClientResponse> request(
      Uri uri, {
      Map<String, String> headers = const <String, String>{},
    }) async {
      final HttpClientRequest request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      return request.close();
    }

    Future<Uint8List> readBytes(HttpClientResponse response) async {
      final BytesBuilder body = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        body.add(chunk);
      }
      return body.takeBytes();
    }

    try {
      await proxy.start();
      final String rewritten = utf8.decode(
        await readBytes(
          await request(Uri.parse(proxy.playlistUrl(playlist.uri))),
        ),
      );

      final Uri proxiedKey = Uri.parse(
        RegExp(r'URI="([^"]+)"').firstMatch(rewritten)!.group(1)!,
      );
      final Uri proxiedSegment = Uri.parse(
        const LineSplitter()
            .convert(rewritten)
            .firstWhere((String line) => line.startsWith('http://127.0.0.1')),
      );

      final HttpClientResponse keyResponse = await request(proxiedKey);
      expect(keyResponse.statusCode, HttpStatus.ok);
      expect(await readBytes(keyResponse), <int>[1, 2, 3, 4]);

      final HttpClientResponse segmentResponse = await request(
        proxiedSegment,
        headers: const <String, String>{'Range': 'bytes=0-6'},
      );
      expect(segmentResponse.statusCode, HttpStatus.partialContent);
      expect(
        segmentResponse.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-6/13',
      );
      expect(utf8.decode(await readBytes(segmentResponse)), 'segment');
    } finally {
      client.close(force: true);
      await proxy.stop();
      await dir.delete(recursive: true);
    }
  });

  test(
    'remote DASH rewrites relative templates through the media proxy',
    () async {
      final HttpServer upstream = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final String origin =
          'http://${upstream.address.address}:${upstream.port}';
      final List<({String path, String? referer, String? origin})> seen =
          <({String path, String? referer, String? origin})>[];
      final StreamSubscription<HttpRequest> upstreamSub = upstream.listen((
        HttpRequest request,
      ) {
        seen.add((
          path: request.uri.path,
          referer: request.headers.value(HttpHeaders.refererHeader),
          origin: request.headers.value('origin'),
        ));
        switch (request.uri.path) {
          case '/video/stream.mpd':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType('application', 'dash+xml')
              ..write(
                '<?xml version="1.0"?>'
                '<MPD><Period><AdaptationSet><Representation id="0">'
                '<SegmentTemplate '
                'initialization="init-stream\$RepresentationID\$.m4s" '
                'media="chunk-stream\$RepresentationID\$-'
                '\$Number%05d\$.m4s" />'
                '</Representation></AdaptationSet></Period></MPD>',
              );
          case '/video/init-stream0.m4s':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType('video', 'mp4')
              ..write('init');
          case '/video/chunk-stream0-00001.m4s':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType('video', 'mp4')
              ..write('segment');
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        unawaited(request.response.close());
      });

      final LocalHlsProxy proxy = LocalHlsProxy();
      final HttpClient client = HttpClient();

      Future<String> read(Uri uri) async {
        final HttpClientResponse response = await (await client.getUrl(
          uri,
        )).close();
        expect(response.statusCode, HttpStatus.ok);
        return response.transform(utf8.decoder).join();
      }

      try {
        await proxy.start();
        final String manifest = await read(
          Uri.parse(
            proxy.dashUrl(
              Uri.parse('$origin/video/stream.mpd'),
              headers: const <String, String>{
                'Referer': 'https://provider.example/watch',
                'Origin': 'https://provider.example',
              },
            ),
          ),
        );
        final Match initialization = RegExp(
          r'initialization="([^"]+)"',
        ).firstMatch(manifest)!;
        final Match media = RegExp(r'media="([^"]+)"').firstMatch(manifest)!;
        final String initializationUrl = initialization
            .group(1)!
            .replaceAll('&amp;', '&')
            .replaceAll(r'$RepresentationID$', '0');
        final String mediaUrl = media
            .group(1)!
            .replaceAll('&amp;', '&')
            .replaceAll(r'$RepresentationID$', '0')
            .replaceAll(r'$Number%05d$', '00001');

        expect(await read(Uri.parse(initializationUrl)), 'init');
        expect(await read(Uri.parse(mediaUrl)), 'segment');

        final initRequest = seen.singleWhere(
          (request) => request.path == '/video/init-stream0.m4s',
        );
        final segmentRequest = seen.singleWhere(
          (request) => request.path == '/video/chunk-stream0-00001.m4s',
        );
        expect(initRequest.referer, 'https://provider.example/watch');
        expect(initRequest.origin, 'https://provider.example');
        expect(segmentRequest.referer, 'https://provider.example/watch');
        expect(segmentRequest.origin, 'https://provider.example');
      } finally {
        client.close(force: true);
        await proxy.stop();
        await upstreamSub.cancel();
        await upstream.close(force: true);
      }
    },
  );

  test('DASH HLS bridge serves concrete fMP4 tracks with headers', () async {
    final HttpServer upstream = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final String origin = 'http://${upstream.address.address}:${upstream.port}';
    final List<({String path, String? referer})> seen =
        <({String path, String? referer})>[];
    final StreamSubscription<HttpRequest> upstreamSub = upstream.listen((
      HttpRequest request,
    ) {
      seen.add((
        path: request.uri.path,
        referer: request.headers.value(HttpHeaders.refererHeader),
      ));
      if (request.uri.path == '/video/stream.mpd') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'dash+xml')
          ..write(r'''<MPD type="static" mediaPresentationDuration="PT4S">
<Period>
  <AdaptationSet contentType="video">
    <Representation id="0" codecs="avc1.4d4028" bandwidth="900000"
        width="1280" height="720">
      <SegmentTemplate timescale="1000"
          initialization="init-stream$RepresentationID$.m4s"
          media="chunk-stream$RepresentationID$-$Number%05d$.m4s">
        <SegmentTimeline><S d="2000" r="1" /></SegmentTimeline>
      </SegmentTemplate>
    </Representation>
  </AdaptationSet>
  <AdaptationSet contentType="audio" lang="ru">
    <Representation id="1" codecs="mp4a.40.2" bandwidth="128000">
      <SegmentTemplate timescale="1000"
          initialization="init-stream$RepresentationID$.m4s"
          media="chunk-stream$RepresentationID$-$Number%05d$.m4s">
        <SegmentTimeline><S d="2000" r="1" /></SegmentTimeline>
      </SegmentTemplate>
    </Representation>
  </AdaptationSet>
</Period>
</MPD>''');
      } else if (request.uri.path.endsWith('.m4s')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('video', 'mp4')
          ..write(request.uri.path);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      unawaited(request.response.close());
    });

    final LocalHlsProxy proxy = LocalHlsProxy();
    final HttpClient client = HttpClient();

    Future<String> read(String url) async {
      final HttpClientResponse response = await (await client.getUrl(
        Uri.parse(url.replaceAll('&amp;', '&')),
      )).close();
      expect(response.statusCode, HttpStatus.ok);
      return response.transform(utf8.decoder).join();
    }

    String mapUrl(String playlist) {
      return RegExp(
        r'#EXT-X-MAP:URI="([^"]+)"',
      ).firstMatch(playlist)!.group(1)!;
    }

    String firstSegmentUrl(String playlist) {
      return const LineSplitter()
          .convert(playlist)
          .firstWhere((String line) => line.startsWith('http://127.0.0.1'));
    }

    String firstRemoteSegmentUrl(String playlist) {
      return const LineSplitter()
          .convert(playlist)
          .firstWhere(
            (String line) =>
                line.startsWith('http://') && line.contains('/video/'),
          );
    }

    try {
      await proxy.start();
      final String masterUrl = await proxy.dashHlsUrl(
        Uri.parse('$origin/video/stream.mpd'),
        headers: const <String, String>{
          'Referer': 'https://provider.example/watch',
        },
      );
      final String master = await read(masterUrl);
      final String audioPlaylistUrl = RegExp(
        r'#EXT-X-MEDIA:[^\n]*URI="([^"]+)"',
      ).firstMatch(master)!.group(1)!;
      final String videoPlaylistUrl = const LineSplitter()
          .convert(master)
          .firstWhere((String line) => line.startsWith('http://127.0.0.1'));

      final String video = await read(videoPlaylistUrl);
      final String audio = await read(audioPlaylistUrl);
      expect(video, contains('#EXT-X-MAP'));
      expect(audio, contains('#EXT-X-MAP'));

      expect(await read(mapUrl(video)), '/video/init-stream0.m4s');
      expect(
        await read(firstSegmentUrl(video)),
        '/video/chunk-stream0-00001.m4s',
      );
      expect(await read(mapUrl(audio)), '/video/init-stream1.m4s');
      expect(
        await read(firstSegmentUrl(audio)),
        '/video/chunk-stream1-00001.m4s',
      );

      final String directMasterUrl = await proxy.dashHlsUrl(
        Uri.parse('$origin/video/stream.mpd'),
        headers: const <String, String>{
          'Referer': 'https://provider.example/watch',
        },
        proxyMedia: false,
      );
      final String directMaster = await read(directMasterUrl);
      final String directVideoPlaylistUrl = const LineSplitter()
          .convert(directMaster)
          .firstWhere((String line) => line.startsWith('http://127.0.0.1'));
      final String directVideo = await read(directVideoPlaylistUrl);
      expect(mapUrl(directVideo), '$origin/video/init-stream0.m4s');
      expect(
        firstRemoteSegmentUrl(directVideo),
        '$origin/video/chunk-stream0-00001.m4s',
      );

      for (final ({String path, String? referer}) request in seen) {
        expect(request.referer, 'https://provider.example/watch');
      }
    } finally {
      client.close(force: true);
      await proxy.stop();
      await upstreamSub.cancel();
      await upstream.close(force: true);
    }
  });
}
