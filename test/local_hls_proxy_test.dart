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
}
