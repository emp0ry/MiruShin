class HlsVideoVariant {
  const HlsVideoVariant({
    required this.uri,
    required this.height,
    required this.bandwidth,
  });

  final Uri uri;
  final int? height;
  final int? bandwidth;
}

HlsVideoVariant? lowestVideoHlsVariant(String playlist, Uri playlistUri) {
  final List<String> lines = playlist.split(RegExp(r'\r?\n'));
  final List<HlsVideoVariant> variants = <HlsVideoVariant>[];
  for (int index = 0; index < lines.length; index++) {
    final String line = lines[index].trim();
    if (!line.toUpperCase().startsWith('#EXT-X-STREAM-INF:')) continue;
    final Map<String, String> attributes = _attributes(
      line.substring(line.indexOf(':') + 1),
    );
    String? rawUri;
    for (int next = index + 1; next < lines.length; next++) {
      final String candidate = lines[next].trim();
      if (candidate.isEmpty) continue;
      if (candidate.startsWith('#')) break;
      rawUri = candidate;
      break;
    }
    if (rawUri == null || rawUri.isEmpty) continue;

    final String codecs = (attributes['CODECS'] ?? '').toLowerCase();
    final bool hasResolution = (attributes['RESOLUTION'] ?? '').contains('x');
    final bool hasVideoGroup = (attributes['VIDEO'] ?? '').isNotEmpty;
    final bool knownVideoCodec = RegExp(
      r'(^|,)(avc1|avc3|hvc1|hev1|vp8|vp9|vp09|av01|dvhe|dvh1|theora)',
    ).hasMatch(codecs.replaceAll(' ', ''));
    final bool knownAudioCodec =
        codecs.isNotEmpty &&
        RegExp(
          r'(^|,)(mp4a|aac|opus|ac-3|ec-3|vorbis|mp3)',
        ).hasMatch(codecs.replaceAll(' ', ''));
    if (!hasResolution &&
        !hasVideoGroup &&
        !knownVideoCodec &&
        knownAudioCodec) {
      continue;
    }

    int? height;
    final RegExpMatch? resolution = RegExp(
      r'\d+x(\d+)',
      caseSensitive: false,
    ).firstMatch(attributes['RESOLUTION'] ?? '');
    if (resolution != null) height = int.tryParse(resolution.group(1)!);
    final int? bandwidth = int.tryParse(
      attributes['AVERAGE-BANDWIDTH'] ?? attributes['BANDWIDTH'] ?? '',
    );
    variants.add(
      HlsVideoVariant(
        uri: playlistUri.resolve(rawUri),
        height: height,
        bandwidth: bandwidth,
      ),
    );
  }
  if (variants.isEmpty) return null;
  variants.sort((HlsVideoVariant a, HlsVideoVariant b) {
    final int height = (a.height ?? 1 << 30).compareTo(b.height ?? 1 << 30);
    if (height != 0) return height;
    return (a.bandwidth ?? 1 << 30).compareTo(b.bandwidth ?? 1 << 30);
  });
  return variants.first;
}

Map<String, String> _attributes(String input) {
  final Map<String, String> result = <String, String>{};
  final RegExp pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  for (final RegExpMatch match in pattern.allMatches(input.toUpperCase())) {
    String value = match.group(2) ?? '';
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    result[match.group(1)!] = value;
  }
  return result;
}
