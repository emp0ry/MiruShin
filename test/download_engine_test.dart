import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/downloads/data/download_engine.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';

void main() {
  test('finds richer current URLs in an arbitrary source descriptor', () {
    const String failed = 'https://media.invalid/show/episode.m3u8?region=one';
    const String current =
        'https://media.invalid/show/episode.m3u8?region=one&mode=full';
    final Map<String, String> replacements = findMediaUrlReplacements(
      <String, Object?>{
        'unrelated': 'https://media.invalid/poster.jpg',
        'nested': <Object?>[
          <String, String>{'anything': current},
        ],
      },
      const <String>[failed],
    );

    expect(replacements, <String, String>{failed: current});
  });

  test('does not replace media with a different authority or path', () {
    const String failed = 'https://media.invalid/show/episode.m3u8?token=old';
    final Map<String, String> replacements = findMediaUrlReplacements(
      const <String, Object?>{
        'otherAuthority': 'https://other.invalid/show/episode.m3u8?token=new',
        'otherPath': 'https://media.invalid/show/replacement.m3u8?token=new',
      },
      const <String>[failed],
    );

    expect(replacements, isEmpty);
  });

  test('switching download quality clears only incompatible media', () async {
    final Directory output = await Directory.systemTemp.createTemp(
      'mirushin-download-attempt-',
    );
    addTearDown(() async {
      if (output.existsSync()) await output.delete(recursive: true);
    });
    final DownloadEngine engine = DownloadEngine();
    final File segment = File(
      '${output.path}${Platform.pathSeparator}seg_00001.ts',
    );
    final File subtitle = File(
      '${output.path}${Platform.pathSeparator}sub_en.vtt',
    );

    await engine.prepareMediaAttempt(
      dirPath: output.path,
      candidateKey: 'server|1080p',
    );
    await segment.writeAsBytes(<int>[1, 2, 3]);
    await subtitle.writeAsString('WEBVTT');
    await engine.prepareMediaAttempt(
      dirPath: output.path,
      candidateKey: 'server|1080p',
    );
    expect(segment.existsSync(), isTrue);

    await engine.prepareMediaAttempt(
      dirPath: output.path,
      candidateKey: 'server|720p',
    );
    expect(segment.existsSync(), isFalse);
    expect(subtitle.existsSync(), isTrue);
  });

  test('HLS segment downloads retry transient server failures', () async {
    final Directory output = await Directory.systemTemp.createTemp(
      'mirushin-download-engine-',
    );
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async {
      await server.close(force: true);
      if (output.existsSync()) await output.delete(recursive: true);
    });

    int segmentRequests = 0;
    server.listen((HttpRequest request) async {
      if (request.uri.path == '/index.m3u8') {
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
            'segment.ts\n'
            '#EXT-X-ENDLIST\n',
          );
      } else if (request.uri.path == '/segment.ts') {
        segmentRequests += 1;
        if (segmentRequests == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(<int>[0x47, 1, 2, 3]);
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    await DownloadEngine().downloadHls(
      playlistUrl: 'http://${server.address.address}:${server.port}/index.m3u8',
      headers: const <String, String>{},
      dirPath: output.path,
      cancelToken: CancelToken(),
    );

    expect(segmentRequests, 2);
    expect(
      File('${output.path}${Platform.pathSeparator}index.m3u8').existsSync(),
      isTrue,
    );
    expect(
      File('${output.path}${Platform.pathSeparator}seg_00001.ts').existsSync(),
      isTrue,
    );
  });

  test('HLS segment downloads follow redirects with safe headers', () async {
    final Directory output = await Directory.systemTemp.createTemp(
      'mirushin-download-redirect-',
    );
    final HttpServer sourceServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final HttpServer mediaServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async {
      await sourceServer.close(force: true);
      await mediaServer.close(force: true);
      if (output.existsSync()) await output.delete(recursive: true);
    });

    HttpHeaders? redirectedHeaders;
    mediaServer.listen((HttpRequest request) async {
      redirectedHeaders = request.headers;
      request.response
        ..statusCode = HttpStatus.ok
        ..add(<int>[0x47, 1, 2, 3]);
      await request.response.close();
    });
    sourceServer.listen((HttpRequest request) async {
      if (request.uri.path == '/index.m3u8') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:4\n'
            '#EXTINF:4,\n'
            'segment.ts\n'
            '#EXT-X-ENDLIST\n',
          );
        await request.response.close();
      } else if (request.uri.path == '/segment.ts') {
        await request.response.redirect(
          Uri.parse(
            'http://${mediaServer.address.address}:${mediaServer.port}/bytes',
          ),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    await DownloadEngine().downloadHls(
      playlistUrl:
          'http://${sourceServer.address.address}:${sourceServer.port}'
          '/index.m3u8',
      headers: const <String, String>{
        'X-Media-Token': 'keep-me',
        'Referer': 'https://page.invalid/watch',
        'Authorization': 'remove-me',
        'Cookie': 'remove-me',
      },
      dirPath: output.path,
      cancelToken: CancelToken(),
    );

    expect(redirectedHeaders?.value('x-media-token'), 'keep-me');
    expect(
      redirectedHeaders?.value(HttpHeaders.refererHeader),
      'https://page.invalid/watch',
    );
    expect(redirectedHeaders?.value(HttpHeaders.authorizationHeader), isNull);
    expect(redirectedHeaders?.value(HttpHeaders.cookieHeader), isNull);
    expect(
      File('${output.path}${Platform.pathSeparator}index.m3u8').existsSync(),
      isTrue,
    );
  });

  test('downloads DASH video and external audio as local HLS', () async {
    final Directory output = await Directory.systemTemp.createTemp(
      'mirushin-download-dash-',
    );
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async {
      await server.close(force: true);
      if (output.existsSync()) await output.delete(recursive: true);
    });

    final String origin =
        'http://${server.address.address}:${server.port}/media/';
    final String manifest =
        '''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static"
    mediaPresentationDuration="PT4S">
  <Period>
    <AdaptationSet contentType="video">
      <Representation id="video" mimeType="video/mp4"
          codecs="avc1.4d4028" bandwidth="900000" width="1280" height="720">
        <BaseURL>$origin</BaseURL>
        <SegmentTemplate timescale="1" duration="2" startNumber="1"
            initialization="video-init.m4s" media="video-\$Number\$.m4s" />
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio" lang="en">
      <Representation id="audio" mimeType="audio/mp4"
          codecs="mp4a.40.2" bandwidth="128000">
        <BaseURL>$origin</BaseURL>
        <SegmentTemplate timescale="1" duration="2" startNumber="1"
            initialization="audio-init.m4s" media="audio-\$Number\$.m4s" />
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';

    server.listen((HttpRequest request) async {
      if (request.uri.path == '/stream.mpd') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'dash+xml')
          ..write(manifest);
      } else if (request.uri.path.startsWith('/media/') &&
          request.uri.path.endsWith('.m4s')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..add(<int>[0, 0, 0, 4, 0x6d, 0x64, 0x61, 0x74]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final DownloadEngine engine = DownloadEngine();
    final String manifestUrl =
        'http://${server.address.address}:${server.port}/stream.mpd';
    expect(
      await engine.sniffKind(
        url: manifestUrl,
        headers: const <String, String>{},
        streamTypeHint: 'DASH',
        cancelToken: CancelToken(),
      ),
      DownloadKind.dash,
    );

    int totalSegments = 0;
    int doneSegments = 0;
    await engine.downloadDash(
      manifestUrl: manifestUrl,
      headers: const <String, String>{},
      dirPath: output.path,
      cancelToken: CancelToken(),
      onPlaylistParsed: (int total) => totalSegments = total,
      onProgress: (int done, int _, int _) => doneSegments = done,
    );

    final String localMaster = await File(
      '${output.path}${Platform.pathSeparator}index.m3u8',
    ).readAsString();
    expect(localMaster, contains('audio/index.m3u8'));
    expect(localMaster, contains('video/index.m3u8'));
    expect(totalSegments, 4);
    expect(doneSegments, 4);
    expect(
      File(
        '${output.path}${Platform.pathSeparator}video'
        '${Platform.pathSeparator}seg_00001.m4s',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${output.path}${Platform.pathSeparator}audio'
        '${Platform.pathSeparator}seg_00001.m4s',
      ).existsSync(),
      isTrue,
    );
  });
}
