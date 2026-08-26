import 'dart:math' as math;

enum HlsPlaylistKind { master, media, unknown }

class HlsByteRange {
  const HlsByteRange({required this.length, required this.offset});

  final int length;
  final int offset;

  int get endExclusive => offset + length;

  @override
  bool operator ==(Object other) =>
      other is HlsByteRange && other.length == length && other.offset == offset;

  @override
  int get hashCode => Object.hash(length, offset);
}

class HlsEncryption {
  const HlsEncryption({
    required this.method,
    required this.keyUri,
    required this.iv,
    required this.keyFormat,
  });

  final String method;
  final Uri? keyUri;
  final String? iv;
  final String? keyFormat;

  bool get isAes128 => method.toUpperCase() == 'AES-128';
}

class HlsInitMap {
  const HlsInitMap({required this.uri, this.byteRange});

  final Uri uri;
  final HlsByteRange? byteRange;
}

class HlsMediaSegment {
  const HlsMediaSegment({
    required this.sequence,
    required this.start,
    required this.duration,
    required this.uri,
    required this.discontinuitySequence,
    this.byteRange,
    this.initMap,
    this.encryption,
  });

  final int sequence;
  final Duration start;
  final Duration duration;
  final Uri uri;
  final int discontinuitySequence;
  final HlsByteRange? byteRange;
  final HlsInitMap? initMap;
  final HlsEncryption? encryption;

  Duration get end => start + duration;
}

class HlsMediaIndex {
  const HlsMediaIndex({
    required this.playlistUri,
    required this.kind,
    required this.segments,
    required this.mediaSequence,
    required this.discontinuitySequence,
    required this.targetDuration,
    required this.hasEndList,
  });

  final Uri playlistUri;
  final HlsPlaylistKind kind;
  final List<HlsMediaSegment> segments;
  final int mediaSequence;
  final int discontinuitySequence;
  final Duration targetDuration;
  final bool hasEndList;

  Duration get duration => segments.isEmpty ? Duration.zero : segments.last.end;

  HlsMediaSegment? segmentFor(Duration position) {
    if (segments.isEmpty) return null;
    final int targetUs = position.inMicroseconds.clamp(
      0,
      duration.inMicroseconds,
    );
    int low = 0;
    int high = segments.length - 1;
    while (low < high) {
      final int middle = (low + high) >> 1;
      // A timestamp exactly on a segment boundary belongs to the following
      // segment. This prevents repeatedly decoding the final frame of the
      // previous segment while the pointer moves forward.
      if (targetUs < segments[middle].end.inMicroseconds) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return segments[low];
  }
}

HlsMediaIndex parseHlsMediaIndex(String playlist, Uri playlistUri) {
  final List<String> lines = playlist.split(RegExp(r'\r?\n'));
  final bool master = lines.any(
    (String line) =>
        line.trimLeft().toUpperCase().startsWith('#EXT-X-STREAM-INF:'),
  );
  final bool media = lines.any(
    (String line) => line.trimLeft().toUpperCase().startsWith('#EXTINF:'),
  );

  int mediaSequence = 0;
  int discontinuitySequence = 0;
  int currentDiscontinuity = 0;
  Duration targetDuration = Duration.zero;
  Duration cursor = Duration.zero;
  Duration? pendingDuration;
  _UnresolvedByteRange? pendingRange;
  HlsInitMap? currentMap;
  HlsEncryption? currentEncryption;
  bool hasEndList = false;
  final Map<Uri, int> rangeEnds = <Uri, int>{};
  final Map<Uri, int> mapRangeEnds = <Uri, int>{};
  final List<HlsMediaSegment> segments = <HlsMediaSegment>[];

  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('#')) {
      if (pendingDuration == null) continue;
      final Uri uri = playlistUri.resolve(line);
      final HlsByteRange? byteRange = pendingRange?.resolve(uri, rangeEnds);
      final Duration segmentDuration = pendingDuration;
      segments.add(
        HlsMediaSegment(
          sequence: mediaSequence + segments.length,
          start: cursor,
          duration: segmentDuration,
          uri: uri,
          discontinuitySequence: currentDiscontinuity,
          byteRange: byteRange,
          initMap: currentMap,
          encryption: currentEncryption,
        ),
      );
      cursor += segmentDuration;
      pendingDuration = null;
      pendingRange = null;
      continue;
    }

    final int colon = line.indexOf(':');
    final String tag = (colon < 0 ? line : line.substring(0, colon))
        .toUpperCase();
    final String value = colon < 0 ? '' : line.substring(colon + 1).trim();
    switch (tag) {
      case '#EXTINF':
        final String seconds = value.split(',').first.trim();
        pendingDuration = _secondsToDuration(double.tryParse(seconds) ?? 0);
        break;
      case '#EXT-X-TARGETDURATION':
        targetDuration = _secondsToDuration(double.tryParse(value) ?? 0);
        break;
      case '#EXT-X-MEDIA-SEQUENCE':
        mediaSequence = int.tryParse(value) ?? 0;
        break;
      case '#EXT-X-DISCONTINUITY-SEQUENCE':
        discontinuitySequence = int.tryParse(value) ?? 0;
        currentDiscontinuity = discontinuitySequence;
        break;
      case '#EXT-X-DISCONTINUITY':
        currentDiscontinuity += 1;
        break;
      case '#EXT-X-BYTERANGE':
        pendingRange = _UnresolvedByteRange.parse(value);
        break;
      case '#EXT-X-MAP':
        final Map<String, String> attributes = parseHlsAttributes(value);
        final String? rawUri = attributes['URI'];
        if (rawUri != null && rawUri.isNotEmpty) {
          final Uri uri = playlistUri.resolve(rawUri);
          currentMap = HlsInitMap(
            uri: uri,
            byteRange: _UnresolvedByteRange.parse(
              attributes['BYTERANGE'] ?? '',
            )?.resolve(uri, mapRangeEnds),
          );
        }
        break;
      case '#EXT-X-KEY':
        final Map<String, String> attributes = parseHlsAttributes(value);
        final String method = (attributes['METHOD'] ?? 'NONE').toUpperCase();
        if (method == 'NONE') {
          currentEncryption = null;
        } else {
          final String? rawUri = attributes['URI'];
          currentEncryption = HlsEncryption(
            method: method,
            keyUri: rawUri == null || rawUri.isEmpty
                ? null
                : playlistUri.resolve(rawUri),
            iv: attributes['IV'],
            keyFormat: attributes['KEYFORMAT'],
          );
        }
        break;
      case '#EXT-X-ENDLIST':
        hasEndList = true;
        break;
    }
  }

  return HlsMediaIndex(
    playlistUri: playlistUri,
    kind: master
        ? HlsPlaylistKind.master
        : media
        ? HlsPlaylistKind.media
        : HlsPlaylistKind.unknown,
    segments: List<HlsMediaSegment>.unmodifiable(segments),
    mediaSequence: mediaSequence,
    discontinuitySequence: discontinuitySequence,
    targetDuration: targetDuration,
    hasEndList: hasEndList,
  );
}

Map<String, String> parseHlsAttributes(String input) {
  final Map<String, String> result = <String, String>{};
  int cursor = 0;
  while (cursor < input.length) {
    while (cursor < input.length &&
        (input.codeUnitAt(cursor) == 0x20 ||
            input.codeUnitAt(cursor) == 0x2c)) {
      cursor += 1;
    }
    final int equals = input.indexOf('=', cursor);
    if (equals < 0) break;
    final String key = input.substring(cursor, equals).trim().toUpperCase();
    cursor = equals + 1;
    String value;
    if (cursor < input.length && input.codeUnitAt(cursor) == 0x22) {
      cursor += 1;
      final StringBuffer buffer = StringBuffer();
      while (cursor < input.length) {
        final int code = input.codeUnitAt(cursor);
        if (code == 0x22) {
          cursor += 1;
          break;
        }
        buffer.writeCharCode(code);
        cursor += 1;
      }
      value = buffer.toString();
      while (cursor < input.length && input.codeUnitAt(cursor) != 0x2c) {
        cursor += 1;
      }
    } else {
      final int comma = input.indexOf(',', cursor);
      final int end = comma < 0 ? input.length : comma;
      value = input.substring(cursor, end).trim();
      cursor = end;
    }
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}

Duration _secondsToDuration(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return Duration.zero;
  return Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}

class _UnresolvedByteRange {
  const _UnresolvedByteRange(this.length, this.explicitOffset);

  final int length;
  final int? explicitOffset;

  static _UnresolvedByteRange? parse(String value) {
    final RegExpMatch? match = RegExp(
      r'^(\d+)(?:@(\d+))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final int? length = int.tryParse(match.group(1)!);
    final int? offset = match.group(2) == null
        ? null
        : int.tryParse(match.group(2)!);
    if (length == null || length <= 0 || (offset != null && offset < 0)) {
      return null;
    }
    return _UnresolvedByteRange(length, offset);
  }

  HlsByteRange resolve(Uri uri, Map<Uri, int> previousEnds) {
    final int offset = explicitOffset ?? previousEnds[uri] ?? 0;
    final HlsByteRange range = HlsByteRange(
      length: length,
      offset: math.max(0, offset),
    );
    previousEnds[uri] = range.endExclusive;
    return range;
  }
}
