import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/media_item.dart';
import '../domain/player_models.dart';
import '../engine/local_hls_proxy.dart';

final youtubeTrailerResolverProvider = Provider<YoutubeTrailerResolver>(
  (Ref ref) => YoutubeTrailerResolver(),
);

class YoutubeTrailerException implements Exception {
  const YoutubeTrailerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class YoutubeTrailerResolver {
  YoutubeTrailerResolver({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 18),
            ),
          );

  static const String _fallbackApiKey =
      'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _fallbackClientVersion = '2.20240510.00.00';
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36 MiruShin/1.0';
  static bool get _enableGeneratedDash => false;

  final Dio _dio;

  Future<MediaPlaybackItem> resolve(MediaItem item) async {
    final MediaTrailer? trailer = item.trailer;
    final String videoId = trailer?.youtubeId ?? '';
    if (trailer == null || videoId.isEmpty) {
      throw const YoutubeTrailerException('No trailer is available.');
    }
    if (!trailer.isYouTube) {
      throw YoutubeTrailerException(
        'Trailer site is not supported: ${trailer.site}.',
      );
    }

    final String title = trailer.title.trim().isNotEmpty
        ? trailer.title.trim()
        : 'Trailer';
    final String posterUrl = trailer.thumbnailUrl.trim().isNotEmpty
        ? trailer.thumbnailUrl.trim()
        : item.posterUrl;

    return MediaPlaybackItem(
      id: '${item.id}:trailer:$videoId',
      title: item.title,
      mediaType: item.type,
      originalTitle: item.originalTitle,
      subtitle: title,
      posterUrl: posterUrl,
      backdropUrl: item.backdropUrl.isNotEmpty ? item.backdropUrl : posterUrl,
      externalIds: <String, String>{
        ...item.externalIds,
        'mirushin_trailer': 'true',
        'youtube': videoId,
      },
      servers: <MediaServer>[
        MediaServer(
          id: 'youtube-trailer',
          name: 'YouTube Trailer',
          sourceName: 'YouTube',
          url: _youtubeEmbedUrl(videoId),
        ),
      ],
      seasonNumber: 0,
      episodeNumber: 0,
      ignoreProgress: true,
    );
  }

  static String _youtubeEmbedUrl(String videoId) {
    return Uri.https('www.youtube.com', '/embed/$videoId').toString();
  }

  // Kept as a best-effort raw stream extractor for future native playback work.
  // Current YouTube trailer playback uses the official embed because raw
  // googlevideo formats increasingly require client attestation that the
  // native demuxers cannot provide.
  // ignore: unused_element
  Future<_ResolvedYoutubeTrailer> _resolve(String videoId) async {
    final _YoutubeBootstrap bootstrap = await _bootstrap(videoId);
    final List<_YoutubeClientConfig> clients = <_YoutubeClientConfig>[
      _YoutubeClientConfig(
        name: 'IOS',
        version: '20.10.4',
        apiKey: bootstrap.apiKey,
        userAgent:
            'com.google.ios.youtube/20.10.4 '
            '(iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)',
        clientFields: <String, Object>{
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone16,2',
          'osName': 'iOS',
          'osVersion': '17.5.1',
          'platform': 'MOBILE',
        },
      ),
      _YoutubeClientConfig(
        name: 'MWEB',
        version: bootstrap.clientVersion,
        apiKey: bootstrap.apiKey,
        userAgent:
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) '
            'Version/17.5 Mobile/15E148 Safari/604.1',
        clientFields: <String, Object>{
          'deviceMake': 'Apple',
          'deviceModel': 'iPhone',
          'osName': 'iOS',
          'osVersion': '17.5.1',
          'platform': 'MOBILE',
        },
        useWebOrigin: true,
      ),
      _YoutubeClientConfig(
        name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        version: '2.0',
        apiKey: bootstrap.apiKey,
        embedUrl: 'https://www.youtube.com/embed/$videoId',
        userAgent:
            'Mozilla/5.0 (SMART-TV; LINUX; Tizen 7.0) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'SamsungBrowser/4.0 TV Safari/537.36',
        clientFields: <String, Object>{
          'clientScreen': 'EMBED',
          'deviceMake': 'Samsung',
          'deviceModel': 'SmartTV',
          'osName': 'Tizen',
          'osVersion': '7.0',
          'platform': 'TV',
        },
        useWebOrigin: true,
      ),
      _YoutubeClientConfig(
        name: 'ANDROID',
        version: '20.10.38',
        apiKey: bootstrap.apiKey,
        userAgent:
            'com.google.android.youtube/20.10.38 '
            '(Linux; U; Android 14) gzip',
        clientFields: <String, Object>{
          'androidSdkVersion': 34,
          'osName': 'Android',
          'osVersion': '14',
          'platform': 'MOBILE',
        },
      ),
      _YoutubeClientConfig(
        name: 'WEB_EMBEDDED_PLAYER',
        version: bootstrap.clientVersion,
        apiKey: bootstrap.apiKey,
        embedUrl: 'https://www.youtube.com/embed/$videoId',
        useWebOrigin: true,
      ),
      _YoutubeClientConfig(
        name: 'WEB',
        version: bootstrap.clientVersion,
        apiKey: bootstrap.apiKey,
        useWebOrigin: true,
      ),
    ];

    final List<_ResolvedYoutubeTrailer> candidates =
        <_ResolvedYoutubeTrailer>[];
    for (final _YoutubeClientConfig client in clients) {
      try {
        final Map<String, dynamic> response = await _playerResponse(
          videoId,
          client,
        );
        final _ResolvedYoutubeTrailer? resolved =
            await _resolvedFromPlayerResponse(response, videoId, client);
        if (resolved != null) {
          candidates.add(resolved);
        }
      } on Object {
        continue;
      }
    }

    final Map<String, dynamic>? initial = bootstrap.initialPlayerResponse;
    if (initial != null) {
      final _ResolvedYoutubeTrailer? resolved =
          await _resolvedFromPlayerResponse(initial, videoId, clients.last);
      if (resolved != null) {
        candidates.add(resolved);
      }
    }

    if (candidates.isNotEmpty) {
      candidates.sort(_compareResolvedTrailers);
      return candidates.first;
    }

    throw const YoutubeTrailerException(
      'Could not resolve a playable trailer stream.',
    );
  }

  Future<_YoutubeBootstrap> _bootstrap(String videoId) async {
    try {
      final Response<String> response = await _dio.get<String>(
        'https://www.youtube.com/watch',
        queryParameters: <String, String>{
          'v': videoId,
          'bpctr': '9999999999',
          'has_verified': '1',
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: _watchHeaders(videoId),
        ),
      );
      final String html = response.data ?? '';
      return _YoutubeBootstrap(
        apiKey: _firstMatch(
          html,
          RegExp(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"'),
          fallback: _fallbackApiKey,
        ),
        clientVersion: _firstMatch(
          html,
          RegExp(r'"INNERTUBE_CONTEXT_CLIENT_VERSION"\s*:\s*"([^"]+)"'),
          fallback: _fallbackClientVersion,
        ),
        initialPlayerResponse: _initialPlayerResponse(html),
      );
    } on Object {
      return const _YoutubeBootstrap(
        apiKey: _fallbackApiKey,
        clientVersion: _fallbackClientVersion,
      );
    }
  }

  Future<Map<String, dynamic>> _playerResponse(
    String videoId,
    _YoutubeClientConfig client,
  ) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      'https://www.youtube.com/youtubei/v1/player',
      queryParameters: <String, String>{'key': client.apiKey},
      data: <String, dynamic>{
        'context': <String, dynamic>{
          'client': <String, dynamic>{
            'clientName': client.name,
            'clientVersion': client.version,
            'hl': 'en',
            'gl': 'US',
            ...client.clientFields,
          },
          if (client.embedUrl != null)
            'thirdParty': <String, dynamic>{'embedUrl': client.embedUrl},
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
        'playbackContext': <String, dynamic>{
          'contentPlaybackContext': <String, dynamic>{
            'html5Preference': 'HTML5_PREF_WANTS',
          },
        },
      },
      options: Options(
        headers: <String, String>{
          ..._watchHeaders(videoId, userAgent: client.userAgent),
          'Content-Type': 'application/json',
          if (client.useWebOrigin) 'Origin': 'https://www.youtube.com',
        },
      ),
    );
    final Map<String, dynamic>? data = _jsonMap(response.data);
    if (data == null) {
      throw const YoutubeTrailerException('YouTube returned invalid metadata.');
    }
    return data;
  }

  Future<_ResolvedYoutubeTrailer?> _resolvedFromPlayerResponse(
    Map<String, dynamic> response,
    String videoId,
    _YoutubeClientConfig client,
  ) async {
    final Object? streamingDataValue = response['streamingData'];
    if (streamingDataValue is! Map<String, dynamic>) {
      return null;
    }
    final List<SubtitleTrack> subtitles = _captionTracks(response, videoId);
    final Map<String, String> headers = _playbackHeaders(
      videoId,
      userAgent: client.userAgent,
    );

    final List<_ResolvedYoutubeTrailer> candidates =
        <_ResolvedYoutubeTrailer>[];
    final String hls = _string(streamingDataValue['hlsManifestUrl']);
    if (hls.isNotEmpty) {
      final List<StreamQuality> qualities = await _hlsQualities(hls, headers);
      candidates.add(
        _ResolvedYoutubeTrailer(
          url: hls,
          headers: headers,
          streamType: StreamType.hls,
          qualities: qualities,
          maxHeight: _bestQualityHeightFromList(qualities),
          subtitles: subtitles,
        ),
      );
    }

    final List<_YoutubeFormat> formats = <_YoutubeFormat>[
      ..._formats(streamingDataValue['formats'], videoId, client),
      ..._formats(streamingDataValue['adaptiveFormats'], videoId, client),
    ];
    final List<_YoutubeFormat> progressive = formats
        .where((_YoutubeFormat format) => format.hasVideo && format.hasAudio)
        .toList(growable: false);
    _ResolvedYoutubeTrailer? progressiveCandidate;
    if (progressive.isNotEmpty) {
      final List<_YoutubeFormat> ranked = progressive.toList()
        ..sort(_compareFormats);
      final List<_YoutubeFormat> playable = <_YoutubeFormat>[];
      for (final _YoutubeFormat format in ranked) {
        if (await _canOpen(format.url, format.headers)) {
          playable.add(format);
        }
      }
      if (playable.isNotEmpty) {
        final _YoutubeFormat selected = playable.first;
        final List<StreamQuality> qualities = _dedupeQualities(
          playable.map(
            (_YoutubeFormat format) => StreamQuality(
              id: format.itag,
              label: format.label,
              url: format.url,
              headers: format.headers,
              height: format.height,
              bitrate: format.bitrate,
            ),
          ),
        );
        candidates.add(
          _ResolvedYoutubeTrailer(
            url: selected.url,
            headers: selected.headers,
            streamType: selected.streamType,
            subtitles: subtitles,
            qualities: qualities,
            maxHeight: selected.height,
          ),
        );
        progressiveCandidate = candidates.last;
      }
    }

    final _ResolvedYoutubeTrailer? adaptiveDash = _enableGeneratedDash
        ? await _adaptiveDashFromFormats(formats, subtitles)
        : null;
    if (adaptiveDash != null) {
      final List<StreamQuality> qualities = _dedupeQualities(<StreamQuality>[
        StreamQuality.auto,
        ...adaptiveDash.qualities,
        if (progressiveCandidate != null) ...progressiveCandidate.qualities,
      ]);
      if (progressiveCandidate != null) {
        candidates.remove(progressiveCandidate);
      }
      candidates.add(
        adaptiveDash.copyWith(qualities: qualities, preferAsDefault: true),
      );
    }

    final String dash = _enableGeneratedDash
        ? _string(streamingDataValue['dashManifestUrl'])
        : '';
    if (dash.isNotEmpty) {
      candidates.add(
        _ResolvedYoutubeTrailer(
          url: dash,
          headers: headers,
          streamType: StreamType.dash,
          maxHeight: await _dashMaxHeight(dash, headers),
          subtitles: subtitles,
        ),
      );
    }

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(_compareResolvedTrailers);
    return candidates.first;
  }

  Future<_ResolvedYoutubeTrailer?> _adaptiveDashFromFormats(
    List<_YoutubeFormat> formats,
    List<SubtitleTrack> subtitles,
  ) async {
    final List<_YoutubeFormat> videoFormats = formats
        .where((_YoutubeFormat format) => format.hasVideo && !format.hasAudio)
        .where((_YoutubeFormat format) => format.height != null)
        .where((_YoutubeFormat format) => format.hasSegmentBase)
        .toList(growable: false);
    final List<_YoutubeFormat> audioFormats = formats
        .where((_YoutubeFormat format) => format.hasAudio && !format.hasVideo)
        .where((_YoutubeFormat format) => format.hasSegmentBase)
        .toList(growable: false);
    if (videoFormats.isEmpty || audioFormats.isEmpty) {
      return null;
    }

    final _YoutubeFormat? audio = await _bestOpenAudioFormat(audioFormats);
    if (audio == null) {
      return null;
    }
    final List<_YoutubeFormat> videos = _bestVideoFormatsByHeight(videoFormats);
    if (videos.isEmpty) {
      return null;
    }

    final List<StreamQuality> qualities = <StreamQuality>[];
    for (final _YoutubeFormat video in videos) {
      if (!await _canOpen(video.url, video.headers)) {
        continue;
      }
      final String manifest = _dashManifest(video: video, audio: audio);
      qualities.add(
        StreamQuality(
          id: 'dash-${video.itag}-${audio.itag}',
          label: video.label,
          url: LocalHlsProxy.inlineDashSourceUrl(manifest),
          headers: <String, String>{...video.headers, ...audio.headers},
          height: video.height,
          bitrate: (video.bitrate ?? 0) + (audio.bitrate ?? 0),
        ),
      );
    }
    if (qualities.isEmpty) {
      return null;
    }

    final StreamQuality best = qualities.first;
    return _ResolvedYoutubeTrailer(
      url: best.url,
      headers: best.headers,
      streamType: StreamType.dash,
      qualities: qualities,
      maxHeight: best.height,
      preferAsDefault: false,
      subtitles: subtitles,
    );
  }

  List<_YoutubeFormat> _bestVideoFormatsByHeight(List<_YoutubeFormat> formats) {
    final Map<int, _YoutubeFormat> bestByHeight = <int, _YoutubeFormat>{};
    for (final _YoutubeFormat format in formats) {
      final int? height = format.height;
      if (height == null || height <= 0) {
        continue;
      }
      final _YoutubeFormat? current = bestByHeight[height];
      if (current == null || _compareAdaptiveVideo(format, current) < 0) {
        bestByHeight[height] = format;
      }
    }
    final List<_YoutubeFormat> ranked = bestByHeight.values.toList()
      ..sort(_compareAdaptiveVideo);
    return ranked;
  }

  Future<_YoutubeFormat?> _bestOpenAudioFormat(
    List<_YoutubeFormat> formats,
  ) async {
    final List<_YoutubeFormat> ranked = formats.toList()
      ..sort(_compareAdaptiveAudio);
    for (final _YoutubeFormat format in ranked) {
      if (await _canOpen(format.url, format.headers)) {
        return format;
      }
    }
    return null;
  }

  String _dashManifest({
    required _YoutubeFormat video,
    required _YoutubeFormat audio,
  }) {
    final int durationMs = video.durationMs ?? audio.durationMs ?? 0;
    final String duration = durationMs > 0
        ? ' mediaPresentationDuration="${_xmlEscape(_isoDuration(durationMs))}"'
        : '';
    final String videoFrameRate = video.fps == null
        ? ''
        : ' frameRate="${video.fps}"';
    final String audioSampleRate = audio.audioSampleRate == null
        ? ''
        : ' audioSamplingRate="${audio.audioSampleRate}"';
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" type="static"$duration minBufferTime="PT1.500S" profiles="urn:mpeg:dash:profile:isoff-main:2011" xsi:schemaLocation="urn:mpeg:dash:schema:mpd:2011 http://standards.iso.org/ittf/PubliclyAvailableStandards/MPEG-DASH_schema_files/DASH-MPD.xsd">
  <Period id="0">
    <AdaptationSet id="0" contentType="video" mimeType="${_xmlEscape(video.mediaMimeType)}" startWithSAP="1" subsegmentAlignment="true" segmentAlignment="true" maxPlayoutRate="1"$videoFrameRate>
      <Representation id="${_xmlEscape(video.itag)}" bandwidth="${video.bitrate ?? 1}" width="${video.width ?? 0}" height="${video.height ?? 0}"${video.codecs.isEmpty ? '' : ' codecs="${_xmlEscape(video.codecs)}"'}$videoFrameRate>
        <BaseURL>${_xmlEscape(video.url)}</BaseURL>
${_segmentBase(video)}
      </Representation>
    </AdaptationSet>
    <AdaptationSet id="1" contentType="audio" mimeType="${_xmlEscape(audio.mediaMimeType)}" startWithSAP="1" subsegmentAlignment="true" segmentAlignment="true"$audioSampleRate>
      <Representation id="${_xmlEscape(audio.itag)}" bandwidth="${audio.bitrate ?? 1}"${audio.codecs.isEmpty ? '' : ' codecs="${_xmlEscape(audio.codecs)}"'}$audioSampleRate>
        <BaseURL>${_xmlEscape(audio.url)}</BaseURL>
${_segmentBase(audio)}
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';
  }

  String _segmentBase(_YoutubeFormat format) {
    final _ByteRange? index = format.indexRange;
    final _ByteRange? init = format.initRange;
    if (index == null || init == null) {
      return '';
    }
    return '        <SegmentBase indexRange="${index.start}-${index.end}">\n'
        '          <Initialization range="${init.start}-${init.end}"/>\n'
        '        </SegmentBase>';
  }

  Future<bool> _canOpen(String url, Map<String, String> headers) async {
    if (url.trim().isEmpty) {
      return false;
    }
    try {
      final Response<List<int>> response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 400,
          headers: <String, String>{...headers, 'Range': 'bytes=0-1'},
        ),
      );
      final int? status = response.statusCode;
      return status != null && status >= 200 && status < 400;
    } on Object {
      return false;
    }
  }

  Future<List<StreamQuality>> _hlsQualities(
    String manifestUrl,
    Map<String, String> headers,
  ) async {
    try {
      final Response<String> response = await _dio.get<String>(
        manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 400,
          headers: headers,
        ),
      );
      final List<StreamQuality> variants = _parseHlsVariants(
        manifestUrl,
        response.data ?? '',
        headers,
      );
      if (variants.isEmpty) {
        return const <StreamQuality>[];
      }
      return <StreamQuality>[StreamQuality.auto, ...variants];
    } on Object {
      return const <StreamQuality>[];
    }
  }

  Future<int?> _dashMaxHeight(
    String manifestUrl,
    Map<String, String> headers,
  ) async {
    try {
      final Response<String> response = await _dio.get<String>(
        manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (int? status) =>
              status != null && status >= 200 && status < 400,
          headers: headers,
        ),
      );
      int best = 0;
      for (final RegExpMatch match in RegExp(
        r'\bheight="(\d+)"',
        caseSensitive: false,
      ).allMatches(response.data ?? '')) {
        final int height = int.tryParse(match.group(1) ?? '') ?? 0;
        if (height > best) {
          best = height;
        }
      }
      return best > 0 ? best : null;
    } on Object {
      return null;
    }
  }

  List<StreamQuality> _parseHlsVariants(
    String manifestUrl,
    String playlist,
    Map<String, String> headers,
  ) {
    final Uri baseUri = Uri.parse(manifestUrl);
    final List<String> lines = const LineSplitter().convert(playlist);
    final Set<String> seenUrls = <String>{};
    final List<StreamQuality> variants = <StreamQuality>[];

    for (int i = 0; i < lines.length; i += 1) {
      final String line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) {
        continue;
      }
      final String attributes = line.substring('#EXT-X-STREAM-INF:'.length);
      String? uriLine;
      for (int j = i + 1; j < lines.length; j += 1) {
        final String candidate = lines[j].trim();
        if (candidate.isEmpty) {
          continue;
        }
        if (candidate.startsWith('#')) {
          break;
        }
        uriLine = candidate;
        i = j;
        break;
      }
      if (uriLine == null || uriLine.isEmpty) {
        continue;
      }

      final String url = baseUri.resolve(uriLine).toString();
      if (!seenUrls.add(url)) {
        continue;
      }
      final int? height = _hlsVariantHeight(attributes);
      final int? bitrate = _hlsVariantBitrate(attributes);
      final String label = height != null
          ? '${height}p'
          : bitrate != null
          ? _bitrateLabel(bitrate)
          : 'Variant ${variants.length + 1}';
      variants.add(
        StreamQuality(
          id: height != null
              ? 'hls-${height}p-${variants.length + 1}'
              : 'hls-${variants.length + 1}',
          label: label,
          url: url,
          headers: headers,
          height: height,
          bitrate: bitrate,
        ),
      );
    }

    variants.sort((StreamQuality a, StreamQuality b) {
      final int height = (b.height ?? 0).compareTo(a.height ?? 0);
      if (height != 0) {
        return height;
      }
      final int bitrate = (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
      if (bitrate != 0) {
        return bitrate;
      }
      return a.label.compareTo(b.label);
    });
    return _dedupeQualities(variants);
  }

  List<_YoutubeFormat> _formats(
    Object? value,
    String videoId,
    _YoutubeClientConfig client,
  ) {
    if (value is! List<dynamic>) {
      return const <_YoutubeFormat>[];
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> json) => _format(json, videoId, client))
        .whereType<_YoutubeFormat>()
        .toList(growable: false);
  }

  _YoutubeFormat? _format(
    Map<String, dynamic> json,
    String videoId,
    _YoutubeClientConfig client,
  ) {
    final String url = _formatUrl(json);
    if (url.isEmpty) {
      return null;
    }
    final String mimeType = _string(json['mimeType']);
    final String mediaMimeType = _mediaMimeType(mimeType);
    final String codecs = _codecs(mimeType);
    final int width = _int(json['width']);
    final int height = _int(json['height']);
    final int bitrate = _int(json['bitrate']);
    final int fps = _int(json['fps']);
    final int audioSampleRate = _int(json['audioSampleRate']);
    final bool hasAudio =
        _string(json['audioQuality']).isNotEmpty ||
        audioSampleRate > 0 ||
        mediaMimeType.startsWith('audio/');
    final bool hasVideo =
        mediaMimeType.startsWith('video/') || height > 0 || width > 0;
    if (!hasAudio && !hasVideo) {
      return null;
    }
    final String quality = _string(
      json['qualityLabel'],
      fallback: height > 0 ? '${height}p' : _string(json['quality']),
    );
    return _YoutubeFormat(
      itag: _string(json['itag'], fallback: quality),
      label: quality.isEmpty ? 'Auto' : quality,
      url: url,
      headers: _playbackHeaders(videoId, userAgent: client.userAgent),
      streamType: _streamTypeFor(url, mediaMimeType),
      mediaMimeType: mediaMimeType,
      codecs: codecs,
      height: height == 0 ? null : height,
      width: width == 0 ? null : width,
      bitrate: bitrate == 0 ? null : bitrate,
      fps: fps == 0 ? null : fps,
      audioSampleRate: audioSampleRate == 0 ? null : audioSampleRate,
      durationMs: _int(json['approxDurationMs']) == 0
          ? null
          : _int(json['approxDurationMs']),
      initRange: _byteRange(json['initRange']),
      indexRange: _byteRange(json['indexRange']),
      hasAudio: hasAudio,
      hasVideo: hasVideo,
    );
  }

  _ByteRange? _byteRange(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final int start = _int(value['start']);
    final int end = _int(value['end']);
    if (end < start || end <= 0) {
      return null;
    }
    return _ByteRange(start: start, end: end);
  }

  String _formatUrl(Map<String, dynamic> json) {
    final String direct = _string(json['url']);
    if (direct.isNotEmpty) {
      return direct;
    }

    final String cipher = _string(
      json['signatureCipher'],
      fallback: _string(json['cipher']),
    );
    if (cipher.isEmpty) {
      return '';
    }

    final Map<String, String> params = Uri.splitQueryString(cipher);
    final String? encodedUrl = params['url'];
    if (encodedUrl == null || encodedUrl.isEmpty) {
      return '';
    }
    if ((params['s'] ?? '').isNotEmpty) {
      return '';
    }

    final String? signature = params['sig'] ?? params['signature'];
    if (signature == null || signature.isEmpty) {
      return encodedUrl;
    }
    final String signatureParam = (params['sp'] ?? 'signature').trim().isEmpty
        ? 'signature'
        : params['sp']!;
    final Uri uri = Uri.parse(encodedUrl);
    return uri
        .replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            signatureParam: signature,
          },
        )
        .toString();
  }

  List<SubtitleTrack> _captionTracks(
    Map<String, dynamic> response,
    String videoId,
  ) {
    final Object? tracksValue = _nested(response, const <String>[
      'captions',
      'playerCaptionsTracklistRenderer',
      'captionTracks',
    ]);
    if (tracksValue is! List<dynamic>) {
      return const <SubtitleTrack>[];
    }

    final List<SubtitleTrack> tracks = <SubtitleTrack>[];
    for (final Map<String, dynamic> track
        in tracksValue.whereType<Map<String, dynamic>>()) {
      final String baseUrl = _string(track['baseUrl']);
      if (baseUrl.isEmpty) {
        continue;
      }
      final String language = _string(track['languageCode']);
      final String label = _captionLabel(track);
      final bool autoGenerated = _string(track['kind']) == 'asr';
      final String id = _string(
        track['vssId'],
        fallback: language.isEmpty ? baseUrl : language,
      );
      tracks.add(
        SubtitleTrack(
          id: id,
          label: autoGenerated && !label.toLowerCase().contains('auto')
              ? '$label (auto)'
              : label,
          url: _vttCaptionUrl(baseUrl),
          language: language,
          format: SubtitleFormat.vtt,
          headers: _watchHeaders(videoId),
        ),
      );
    }
    return tracks;
  }

  String _captionLabel(Map<String, dynamic> track) {
    final Object? name = track['name'];
    if (name is Map<String, dynamic>) {
      final String simple = _string(name['simpleText']);
      if (simple.isNotEmpty) {
        return simple;
      }
      final Object? runs = name['runs'];
      if (runs is List<dynamic>) {
        final String text = runs
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> run) => _string(run['text']))
            .where((String value) => value.isNotEmpty)
            .join();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    final String language = _string(track['languageCode']);
    return language.isEmpty ? 'Captions' : language;
  }

  String _vttCaptionUrl(String baseUrl) {
    final Uri uri = Uri.parse(baseUrl);
    return uri
        .replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'fmt': 'vtt',
          },
        )
        .toString();
  }

  static int _compareFormats(_YoutubeFormat a, _YoutubeFormat b) {
    final int height = (b.height ?? 0).compareTo(a.height ?? 0);
    if (height != 0) {
      return height;
    }
    final int bitrate = (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    if (bitrate != 0) {
      return bitrate;
    }
    return a.label.compareTo(b.label);
  }

  static int _compareAdaptiveVideo(_YoutubeFormat a, _YoutubeFormat b) {
    final int height = (b.height ?? 0).compareTo(a.height ?? 0);
    if (height != 0) {
      return height;
    }
    final int compatibility = _videoCompatibilityScore(
      b,
    ).compareTo(_videoCompatibilityScore(a));
    if (compatibility != 0) {
      return compatibility;
    }
    final int bitrate = (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    if (bitrate != 0) {
      return bitrate;
    }
    return a.itag.compareTo(b.itag);
  }

  static int _compareAdaptiveAudio(_YoutubeFormat a, _YoutubeFormat b) {
    final int compatibility = _audioCompatibilityScore(
      b,
    ).compareTo(_audioCompatibilityScore(a));
    if (compatibility != 0) {
      return compatibility;
    }
    final int bitrate = (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    if (bitrate != 0) {
      return bitrate;
    }
    return a.itag.compareTo(b.itag);
  }

  static int _videoCompatibilityScore(_YoutubeFormat format) {
    int score = 0;
    if (format.mediaMimeType == 'video/mp4') score += 100;
    if (format.codecs.startsWith('avc1')) score += 50;
    if (format.codecs.startsWith('hev1') || format.codecs.startsWith('hvc1')) {
      score += 35;
    }
    if (format.codecs.startsWith('av01')) score += 20;
    if (format.mediaMimeType == 'video/webm') score += 10;
    return score;
  }

  static int _audioCompatibilityScore(_YoutubeFormat format) {
    int score = 0;
    if (format.mediaMimeType == 'audio/mp4') score += 100;
    if (format.codecs.startsWith('mp4a')) score += 50;
    if (format.mediaMimeType == 'audio/webm') score += 10;
    return score;
  }

  static int _compareResolvedTrailers(
    _ResolvedYoutubeTrailer a,
    _ResolvedYoutubeTrailer b,
  ) {
    final int defaultSafety = _defaultSafetyRank(
      b,
    ).compareTo(_defaultSafetyRank(a));
    if (defaultSafety != 0) {
      return defaultSafety;
    }
    final int aHeight = _bestQualityHeight(a);
    final int bHeight = _bestQualityHeight(b);
    if (aHeight != bHeight) {
      return bHeight.compareTo(aHeight);
    }
    final int streamType = _streamTypeRank(
      b.streamType,
    ).compareTo(_streamTypeRank(a.streamType));
    if (streamType != 0) {
      return streamType;
    }
    return b.qualities.length.compareTo(a.qualities.length);
  }

  static int _defaultSafetyRank(_ResolvedYoutubeTrailer trailer) {
    return trailer.preferAsDefault ? 1 : 0;
  }

  static int _streamTypeRank(StreamType streamType) {
    switch (streamType) {
      case StreamType.hls:
        return 4;
      case StreamType.dash:
        return 3;
      case StreamType.mp4:
        return 2;
      case StreamType.unknown:
        return 1;
    }
  }

  static int _bestQualityHeight(_ResolvedYoutubeTrailer trailer) {
    final int? maxHeight = trailer.maxHeight;
    if (maxHeight != null && maxHeight > 0) {
      return maxHeight;
    }
    return _bestQualityHeightFromList(trailer.qualities);
  }

  static int _bestQualityHeightFromList(List<StreamQuality> qualities) {
    int best = 0;
    for (final StreamQuality quality in qualities) {
      final int height = quality.height ?? 0;
      if (height > best) {
        best = height;
      }
    }
    return best;
  }

  static List<StreamQuality> _dedupeQualities(
    Iterable<StreamQuality> qualities,
  ) {
    final List<StreamQuality> result = <StreamQuality>[];
    final Set<String> seen = <String>{};
    bool hasAuto = false;

    for (final StreamQuality quality in qualities) {
      if (quality.isAuto) {
        if (!hasAuto) {
          result.add(quality);
          seen.add(_qualityDedupeKey(quality));
          hasAuto = true;
        }
        continue;
      }

      final String key = _qualityDedupeKey(quality);
      if (seen.add(key)) {
        result.add(quality);
      }
    }

    return result;
  }

  static String _qualityDedupeKey(StreamQuality quality) {
    final String label = quality.label.trim().toLowerCase();
    if (label.isNotEmpty) {
      return 'label:$label';
    }

    final int? height = quality.height;
    if (height != null && height > 0) {
      return 'height:$height';
    }

    final String url = quality.url.trim();
    if (url.isNotEmpty) {
      return 'url:$url';
    }

    return 'id:${quality.id}';
  }

  static int? _hlsVariantHeight(String attributes) {
    final RegExpMatch? match = RegExp(
      r'(?:^|,)RESOLUTION=\d+x(\d+)(?:,|$)',
      caseSensitive: false,
    ).firstMatch(attributes);
    if (match == null) {
      return null;
    }
    final int? height = int.tryParse(match.group(1) ?? '');
    return height != null && height > 0 ? height : null;
  }

  static int? _hlsVariantBitrate(String attributes) {
    final RegExpMatch? average = RegExp(
      r'(?:^|,)AVERAGE-BANDWIDTH=(\d+)(?:,|$)',
      caseSensitive: false,
    ).firstMatch(attributes);
    final RegExpMatch? bandwidth = RegExp(
      r'(?:^|,)BANDWIDTH=(\d+)(?:,|$)',
      caseSensitive: false,
    ).firstMatch(attributes);
    final String value = average?.group(1) ?? bandwidth?.group(1) ?? '';
    final int? bitrate = int.tryParse(value);
    return bitrate != null && bitrate > 0 ? bitrate : null;
  }

  static String _bitrateLabel(int bitrate) {
    if (bitrate >= 1000000) {
      final double mbps = bitrate / 1000000;
      return '${mbps.toStringAsFixed(mbps >= 10 ? 0 : 1)} Mbps';
    }
    return '${(bitrate / 1000).round()} Kbps';
  }

  static StreamType _streamTypeFor(String url, String mimeType) {
    final String lowerUrl = url.toLowerCase();
    final String lowerMime = mimeType.toLowerCase();
    if (lowerUrl.contains('.m3u8') ||
        lowerMime.contains('mpegurl') ||
        lowerMime.contains('x-mpegurl')) {
      return StreamType.hls;
    }
    if (lowerUrl.contains('.mpd') || lowerMime.contains('dash')) {
      return StreamType.dash;
    }
    if (lowerUrl.contains('.mp4') || lowerMime.contains('mp4')) {
      return StreamType.mp4;
    }
    return StreamType.unknown;
  }

  static String _mediaMimeType(String mimeType) {
    final int separator = mimeType.indexOf(';');
    return (separator < 0 ? mimeType : mimeType.substring(0, separator))
        .trim()
        .toLowerCase();
  }

  static String _codecs(String mimeType) {
    final RegExpMatch? match = RegExp(
      r'codecs="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(mimeType);
    return match?.group(1)?.trim() ?? '';
  }

  static String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _isoDuration(int milliseconds) {
    final double seconds = milliseconds / 1000;
    return 'PT${seconds.toStringAsFixed(3)}S';
  }

  static Map<String, String> _watchHeaders(
    String videoId, {
    String? userAgent,
  }) {
    return <String, String>{
      'User-Agent': userAgent ?? _userAgent,
      'Accept': '*/*',
      'Referer': 'https://www.youtube.com/watch?v=$videoId',
    };
  }

  static Map<String, String> _playbackHeaders(
    String videoId, {
    String? userAgent,
  }) {
    return _watchHeaders(videoId, userAgent: userAgent);
  }

  static String _firstMatch(
    String value,
    RegExp pattern, {
    required String fallback,
  }) {
    final RegExpMatch? match = pattern.firstMatch(value);
    return match == null ? fallback : _decodeJsonString(match.group(1)!);
  }

  static String _decodeJsonString(String value) {
    try {
      return jsonDecode('"$value"') as String;
    } on Object {
      return value;
    }
  }

  static Map<String, dynamic>? _initialPlayerResponse(String html) {
    final int marker = html.indexOf('ytInitialPlayerResponse');
    if (marker < 0) {
      return null;
    }
    final int start = html.indexOf('{', marker);
    if (start < 0) {
      return null;
    }
    final int end = _matchingBraceEnd(html, start);
    if (end <= start) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(html.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  static int _matchingBraceEnd(String source, int start) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < source.length; i += 1) {
      final int code = source.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
      } else if (code == 0x7b) {
        depth += 1;
      } else if (code == 0x7d) {
        depth -= 1;
        if (depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  static Map<String, dynamic>? _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? mapValue) =>
            MapEntry<String, dynamic>(key.toString(), mapValue),
      );
    }
    if (value is String) {
      final Object? decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    }
    return null;
  }

  static Object? _nested(Map<String, dynamic> json, List<String> keys) {
    Object? current = json;
    for (final String key in keys) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[key];
    }
    return current;
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class _YoutubeBootstrap {
  const _YoutubeBootstrap({
    required this.apiKey,
    required this.clientVersion,
    this.initialPlayerResponse,
  });

  final String apiKey;
  final String clientVersion;
  final Map<String, dynamic>? initialPlayerResponse;
}

class _YoutubeClientConfig {
  const _YoutubeClientConfig({
    required this.name,
    required this.version,
    required this.apiKey,
    this.embedUrl,
    this.userAgent,
    this.clientFields = const <String, Object>{},
    this.useWebOrigin = false,
  });

  final String name;
  final String version;
  final String apiKey;
  final String? embedUrl;
  final String? userAgent;
  final Map<String, Object> clientFields;
  final bool useWebOrigin;
}

class _ResolvedYoutubeTrailer {
  const _ResolvedYoutubeTrailer({
    required this.url,
    required this.headers,
    required this.streamType,
    this.maxHeight,
    this.preferAsDefault = true,
    this.qualities = const <StreamQuality>[],
    this.subtitles = const <SubtitleTrack>[],
  });

  final String url;
  final Map<String, String> headers;
  final StreamType streamType;
  final int? maxHeight;
  final bool preferAsDefault;
  final List<StreamQuality> qualities;
  final List<SubtitleTrack> subtitles;

  _ResolvedYoutubeTrailer copyWith({
    bool? preferAsDefault,
    List<StreamQuality>? qualities,
  }) {
    return _ResolvedYoutubeTrailer(
      url: url,
      headers: headers,
      streamType: streamType,
      maxHeight: maxHeight,
      preferAsDefault: preferAsDefault ?? this.preferAsDefault,
      qualities: qualities ?? this.qualities,
      subtitles: subtitles,
    );
  }
}

class _YoutubeFormat {
  const _YoutubeFormat({
    required this.itag,
    required this.label,
    required this.url,
    required this.headers,
    required this.streamType,
    required this.mediaMimeType,
    required this.codecs,
    required this.hasAudio,
    required this.hasVideo,
    this.width,
    this.height,
    this.bitrate,
    this.fps,
    this.audioSampleRate,
    this.durationMs,
    this.initRange,
    this.indexRange,
  });

  final String itag;
  final String label;
  final String url;
  final Map<String, String> headers;
  final StreamType streamType;
  final String mediaMimeType;
  final String codecs;
  final bool hasAudio;
  final bool hasVideo;
  final int? width;
  final int? height;
  final int? bitrate;
  final int? fps;
  final int? audioSampleRate;
  final int? durationMs;
  final _ByteRange? initRange;
  final _ByteRange? indexRange;

  bool get hasSegmentBase => initRange != null && indexRange != null;
}

class _ByteRange {
  const _ByteRange({required this.start, required this.end});

  final int start;
  final int end;
}
