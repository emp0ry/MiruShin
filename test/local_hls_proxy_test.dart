import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      final List<({String path, String? referer, String? origin})> seen =
          <({String path, String? referer, String? origin})>[];

      upstreamOrigin = 'http://${upstream.address.address}:${upstream.port}';
      final StreamSubscription<HttpRequest> upstreamSub = upstream.listen((
        HttpRequest request,
      ) {
        seen.add((
          path: request.uri.path,
          referer: request.headers.value(HttpHeaders.refererHeader),
          origin: request.headers.value('origin'),
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

        final mediaRequest = seen.singleWhere(
          (({String path, String? referer, String? origin}) request) =>
              request.path == '/media.m3u8',
        );
        final segmentRequest = seen.singleWhere(
          (({String path, String? referer, String? origin}) request) =>
              request.path == '/segment.ts',
        );

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
}
