import 'dart:math' as math;

import 'package:xml/xml.dart';

/// A static MPEG-DASH presentation expressed as HLS playlists.
///
/// FVP's bundled Windows FFmpeg does not contain the libxml2-backed MPEG-DASH
/// demuxer, but it does contain both HLS and fragmented-MP4 support. Converting
/// the MPD metadata to HLS lets FVP consume the original, unmodified .m4s
/// initialization and media segments without remuxing or transcoding them.
class DashHlsPresentation {
  const DashHlsPresentation({
    required this.masterPlaylist,
    required this.mediaPlaylists,
  });

  final String masterPlaylist;
  final Map<String, String> mediaPlaylists;
}

DashHlsPresentation buildDashHlsPresentation({
  required String manifest,
  required Uri manifestUri,
  required String Function(Uri mediaUri) mediaUrlFor,
  required String Function(String playlistId) mediaPlaylistUrlFor,
}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(manifest);
  } on XmlParserException catch (error) {
    throw FormatException('Invalid DASH XML: ${error.message}');
  }

  final XmlElement mpd = document.rootElement;
  if (mpd.name.local.toLowerCase() != 'mpd') {
    throw const FormatException('The response is not an MPEG-DASH MPD.');
  }
  if ((mpd.getAttribute('type') ?? 'static').toLowerCase() != 'static') {
    throw UnsupportedError(
      'The FVP DASH compatibility bridge currently supports static/VOD MPDs.',
    );
  }

  final List<XmlElement> periods = _childrenNamed(mpd, 'Period');
  if (periods.length != 1) {
    throw UnsupportedError(
      'The FVP DASH compatibility bridge requires exactly one Period '
      '(found ${periods.length}).',
    );
  }
  final XmlElement period = periods.single;
  final double? presentationDuration = _parseIsoDuration(
    period.getAttribute('duration') ??
        mpd.getAttribute('mediaPresentationDuration'),
  );

  final List<_DashHlsTrack> videos = <_DashHlsTrack>[];
  final List<_DashHlsTrack> audios = <_DashHlsTrack>[];
  int videoIndex = 0;
  int audioIndex = 0;

  for (final XmlElement adaptation in _childrenNamed(period, 'AdaptationSet')) {
    for (final XmlElement representation in _childrenNamed(
      adaptation,
      'Representation',
    )) {
      final _DashTrackKind? kind = _trackKind(adaptation, representation);
      if (kind == null) continue;
      final String playlistId = kind == _DashTrackKind.video
          ? 'video${videoIndex++}'
          : 'audio${audioIndex++}';
      final _DashHlsTrack track = _buildTrack(
        mpd: mpd,
        period: period,
        adaptation: adaptation,
        representation: representation,
        kind: kind,
        playlistId: playlistId,
        manifestUri: manifestUri,
        presentationDuration: presentationDuration,
        mediaUrlFor: mediaUrlFor,
      );
      if (kind == _DashTrackKind.video) {
        videos.add(track);
      } else {
        audios.add(track);
      }
    }
  }

  if (videos.isEmpty && audios.isEmpty) {
    throw UnsupportedError(
      'The DASH MPD does not contain a supported audio or video Representation.',
    );
  }

  final Map<String, String> mediaPlaylists = <String, String>{
    for (final _DashHlsTrack track in <_DashHlsTrack>[...videos, ...audios])
      track.playlistId: _mediaPlaylist(track),
  };
  return DashHlsPresentation(
    masterPlaylist: _masterPlaylist(
      videos: videos,
      audios: audios,
      mediaPlaylistUrlFor: mediaPlaylistUrlFor,
    ),
    mediaPlaylists: Map<String, String>.unmodifiable(mediaPlaylists),
  );
}

enum _DashTrackKind { video, audio }

class _DashHlsSegment {
  const _DashHlsSegment({required this.duration, required this.url});

  final double duration;
  final String url;
}

class _DashHlsTrack {
  const _DashHlsTrack({
    required this.kind,
    required this.playlistId,
    required this.name,
    required this.language,
    required this.codecs,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.initializationUrl,
    required this.segments,
  });

  final _DashTrackKind kind;
  final String playlistId;
  final String name;
  final String? language;
  final String codecs;
  final int bandwidth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String initializationUrl;
  final List<_DashHlsSegment> segments;
}

_DashHlsTrack _buildTrack({
  required XmlElement mpd,
  required XmlElement period,
  required XmlElement adaptation,
  required XmlElement representation,
  required _DashTrackKind kind,
  required String playlistId,
  required Uri manifestUri,
  required double? presentationDuration,
  required String Function(Uri mediaUri) mediaUrlFor,
}) {
  final List<XmlElement> hierarchy = <XmlElement>[
    mpd,
    period,
    adaptation,
    representation,
  ];
  final List<XmlElement> templates = <XmlElement>[
    for (final XmlElement node in hierarchy)
      ..._childrenNamed(node, 'SegmentTemplate'),
  ];
  if (templates.isEmpty) {
    throw UnsupportedError(
      'DASH Representation ${representation.getAttribute('id') ?? playlistId} '
      'does not use SegmentTemplate.',
    );
  }

  final Map<String, String> attributes = <String, String>{};
  XmlElement? timeline;
  for (final XmlElement template in templates) {
    for (final XmlAttribute attribute in template.attributes) {
      attributes[attribute.name.local] = attribute.value;
    }
    final List<XmlElement> timelines = _childrenNamed(
      template,
      'SegmentTimeline',
    );
    if (timelines.isNotEmpty) timeline = timelines.first;
  }

  final String? initializationTemplate = attributes['initialization'];
  final String? mediaTemplate = attributes['media'];
  if (initializationTemplate == null || mediaTemplate == null) {
    throw UnsupportedError(
      'DASH Representation ${representation.getAttribute('id') ?? playlistId} '
      'must provide initialization and media SegmentTemplate URLs.',
    );
  }

  final int timescale = _positiveInt(attributes['timescale']) ?? 1;
  final int startNumber = _positiveInt(attributes['startNumber']) ?? 1;
  final String representationId =
      representation.getAttribute('id') ?? playlistId;
  final int bandwidth =
      _positiveInt(representation.getAttribute('bandwidth')) ?? 1;
  final Uri baseUri = _resolveBaseUri(manifestUri, hierarchy);

  Uri resolveTemplate(
    String template, {
    required int number,
    required int time,
  }) {
    final String expanded = _expandDashTemplate(
      template,
      representationId: representationId,
      bandwidth: bandwidth,
      number: number,
      time: time,
    );
    return baseUri.resolve(expanded);
  }

  final String initializationUrl = mediaUrlFor(
    resolveTemplate(initializationTemplate, number: startNumber, time: 0),
  );
  final List<_DashHlsSegment> segments = <_DashHlsSegment>[];

  if (timeline != null) {
    final List<XmlElement> entries = _childrenNamed(timeline, 'S');
    int number = startNumber;
    int currentTime = 0;
    for (int entryIndex = 0; entryIndex < entries.length; entryIndex++) {
      final XmlElement entry = entries[entryIndex];
      final int? duration = _positiveInt(entry.getAttribute('d'));
      if (duration == null) {
        throw const FormatException(
          'DASH SegmentTimeline entry has no duration.',
        );
      }
      currentTime = int.tryParse(entry.getAttribute('t') ?? '') ?? currentTime;
      final int repeat = int.tryParse(entry.getAttribute('r') ?? '0') ?? 0;
      final int count;
      if (repeat >= 0) {
        count = repeat + 1;
      } else {
        final int? nextStart = entryIndex + 1 < entries.length
            ? int.tryParse(entries[entryIndex + 1].getAttribute('t') ?? '')
            : null;
        final double? endSeconds = nextStart == null
            ? presentationDuration
            : nextStart / timescale;
        if (endSeconds == null) {
          throw UnsupportedError(
            'An open-ended DASH SegmentTimeline requires a presentation duration.',
          );
        }
        final int endTime = (endSeconds * timescale).round();
        count = math.max(0, ((endTime - currentTime) / duration).ceil());
      }

      for (int repeated = 0; repeated < count; repeated++) {
        segments.add(
          _DashHlsSegment(
            duration: duration / timescale,
            url: mediaUrlFor(
              resolveTemplate(mediaTemplate, number: number, time: currentTime),
            ),
          ),
        );
        number++;
        currentTime += duration;
      }
    }
  } else {
    final int? duration = _positiveInt(attributes['duration']);
    if (duration == null || presentationDuration == null) {
      throw UnsupportedError(
        'A DASH SegmentTemplate without SegmentTimeline requires duration metadata.',
      );
    }
    final int count = (presentationDuration * timescale / duration).ceil();
    for (int index = 0; index < count; index++) {
      segments.add(
        _DashHlsSegment(
          duration: math.min(
            duration / timescale,
            presentationDuration - (index * duration / timescale),
          ),
          url: mediaUrlFor(
            resolveTemplate(
              mediaTemplate,
              number: startNumber + index,
              time: index * duration,
            ),
          ),
        ),
      );
    }
  }

  if (segments.isEmpty) {
    throw const FormatException(
      'The DASH Representation has no media segments.',
    );
  }

  final String codecs =
      representation.getAttribute('codecs') ??
      adaptation.getAttribute('codecs') ??
      '';
  final String? language =
      representation.getAttribute('lang') ?? adaptation.getAttribute('lang');
  final XmlElement? role = _childrenNamed(adaptation, 'Role').firstOrNull;
  final String name =
      role?.getAttribute('value') ??
      (language?.isNotEmpty == true ? language! : representationId);
  return _DashHlsTrack(
    kind: kind,
    playlistId: playlistId,
    name: name,
    language: language,
    codecs: codecs,
    bandwidth: bandwidth,
    width: _positiveInt(
      representation.getAttribute('width') ?? adaptation.getAttribute('width'),
    ),
    height: _positiveInt(
      representation.getAttribute('height') ??
          adaptation.getAttribute('height'),
    ),
    frameRate: _parseFrameRate(
      representation.getAttribute('frameRate') ??
          adaptation.getAttribute('frameRate'),
    ),
    initializationUrl: initializationUrl,
    segments: List<_DashHlsSegment>.unmodifiable(segments),
  );
}

String _masterPlaylist({
  required List<_DashHlsTrack> videos,
  required List<_DashHlsTrack> audios,
  required String Function(String playlistId) mediaPlaylistUrlFor,
}) {
  final StringBuffer output = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:7')
    ..writeln('#EXT-X-INDEPENDENT-SEGMENTS');

  for (int index = 0; index < audios.length; index++) {
    final _DashHlsTrack audio = audios[index];
    final List<String> attributes = <String>[
      'TYPE=AUDIO',
      'GROUP-ID="audio"',
      'NAME="${_hlsQuoted(audio.name)}"',
      if (audio.language?.isNotEmpty == true)
        'LANGUAGE="${_hlsQuoted(audio.language!)}"',
      'DEFAULT=${index == 0 ? 'YES' : 'NO'}',
      'AUTOSELECT=YES',
      'URI="${_hlsQuoted(mediaPlaylistUrlFor(audio.playlistId))}"',
    ];
    output.writeln('#EXT-X-MEDIA:${attributes.join(',')}');
  }

  if (videos.isNotEmpty) {
    final _DashHlsTrack? defaultAudio = audios.firstOrNull;
    final int audioBandwidth = defaultAudio?.bandwidth ?? 0;
    for (final _DashHlsTrack video in videos) {
      final List<String> codecs = <String>[
        if (video.codecs.isNotEmpty) video.codecs,
        if (defaultAudio?.codecs.isNotEmpty == true) defaultAudio!.codecs,
      ];
      final List<String> attributes = <String>[
        'BANDWIDTH=${math.max(1, video.bandwidth + audioBandwidth)}',
        if (codecs.isNotEmpty) 'CODECS="${codecs.join(',')}"',
        if (video.width != null && video.height != null)
          'RESOLUTION=${video.width}x${video.height}',
        if (video.frameRate != null)
          'FRAME-RATE=${video.frameRate!.toStringAsFixed(3)}',
        if (audios.isNotEmpty) 'AUDIO="audio"',
      ];
      output
        ..writeln('#EXT-X-STREAM-INF:${attributes.join(',')}')
        ..writeln(mediaPlaylistUrlFor(video.playlistId));
    }
  } else {
    for (final _DashHlsTrack audio in audios) {
      output
        ..writeln(
          '#EXT-X-STREAM-INF:BANDWIDTH=${math.max(1, audio.bandwidth)}'
          '${audio.codecs.isEmpty ? '' : ',CODECS="${audio.codecs}"'}',
        )
        ..writeln(mediaPlaylistUrlFor(audio.playlistId));
    }
  }
  return output.toString();
}

String _mediaPlaylist(_DashHlsTrack track) {
  final int targetDuration = track.segments
      .map((_DashHlsSegment segment) => segment.duration.ceil())
      .fold<int>(1, math.max);
  final StringBuffer output = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:7')
    ..writeln('#EXT-X-TARGETDURATION:$targetDuration')
    ..writeln('#EXT-X-PLAYLIST-TYPE:VOD')
    ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
    ..writeln('#EXT-X-MAP:URI="${_hlsQuoted(track.initializationUrl)}"');
  for (final _DashHlsSegment segment in track.segments) {
    output
      ..writeln('#EXTINF:${segment.duration.toStringAsFixed(6)},')
      ..writeln(segment.url);
  }
  output.writeln('#EXT-X-ENDLIST');
  return output.toString();
}

_DashTrackKind? _trackKind(XmlElement adaptation, XmlElement representation) {
  final String value = <String>[
    representation.getAttribute('contentType') ?? '',
    representation.getAttribute('mimeType') ?? '',
    adaptation.getAttribute('contentType') ?? '',
    adaptation.getAttribute('mimeType') ?? '',
  ].join(' ').toLowerCase();
  if (value.contains('video')) return _DashTrackKind.video;
  if (value.contains('audio')) return _DashTrackKind.audio;
  return null;
}

Uri _resolveBaseUri(Uri manifestUri, List<XmlElement> hierarchy) {
  Uri result = manifestUri;
  for (final XmlElement element in hierarchy) {
    final XmlElement? base = _childrenNamed(element, 'BaseURL').firstOrNull;
    final String value = base?.innerText.trim() ?? '';
    if (value.isNotEmpty) result = result.resolve(value);
  }
  return result;
}

String _expandDashTemplate(
  String template, {
  required String representationId,
  required int bandwidth,
  required int number,
  required int time,
}) {
  const String escapedDollar = '__MIRUSHIN_DOLLAR__';
  String output = template.replaceAll(r'$$', escapedDollar);
  output = output.replaceAllMapped(
    RegExp(r'\$(RepresentationID|Bandwidth|Number|Time)(?:%0(\d+)d)?\$'),
    (Match match) {
      final String name = match.group(1)!;
      final String raw = switch (name) {
        'RepresentationID' => representationId,
        'Bandwidth' => bandwidth.toString(),
        'Number' => number.toString(),
        'Time' => time.toString(),
        _ => throw StateError('Unexpected DASH template variable: $name'),
      };
      final int? width = int.tryParse(match.group(2) ?? '');
      return width == null ? raw : raw.padLeft(width, '0');
    },
  );
  if (RegExp(r'\$[^$]+\$').hasMatch(output)) {
    throw UnsupportedError('Unsupported DASH URL template: $template');
  }
  return output.replaceAll(escapedDollar, r'$');
}

List<XmlElement> _childrenNamed(XmlElement element, String localName) {
  return element.childElements
      .where(
        (XmlElement child) =>
            child.name.local.toLowerCase() == localName.toLowerCase(),
      )
      .toList(growable: false);
}

int? _positiveInt(String? value) {
  final int? parsed = int.tryParse(value ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _parseFrameRate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final List<String> parts = value.trim().split('/');
  if (parts.length == 1) return double.tryParse(parts.single);
  if (parts.length != 2) return null;
  final double? numerator = double.tryParse(parts[0]);
  final double? denominator = double.tryParse(parts[1]);
  if (numerator == null || denominator == null || denominator == 0) return null;
  return numerator / denominator;
}

double? _parseIsoDuration(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final RegExpMatch? match = RegExp(
    r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?'
    r'(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;
  final double days = double.tryParse(match.group(1) ?? '') ?? 0;
  final double hours = double.tryParse(match.group(2) ?? '') ?? 0;
  final double minutes = double.tryParse(match.group(3) ?? '') ?? 0;
  final double seconds = double.tryParse(match.group(4) ?? '') ?? 0;
  return days * 86400 + hours * 3600 + minutes * 60 + seconds;
}

String _hlsQuoted(String value) {
  return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
