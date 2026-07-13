import '../domain/player_models.dart';

class SubtitleParser {
  const SubtitleParser();

  List<SubtitleCue> parse(String input) {
    final String normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    if (_looksLikeAss(normalized)) {
      return _parseAss(normalized);
    }
    final List<String> blocks = normalized.split(RegExp(r'\n\s*\n'));
    final List<SubtitleCue> cues = <SubtitleCue>[];
    for (final String block in blocks) {
      final List<String> lines = block
          .split('\n')
          .map((String e) => e.trim())
          .where((String e) => e.isNotEmpty && e != 'WEBVTT')
          .toList();
      if (lines.isEmpty) continue;
      final int timingIndex = lines.indexWhere(
        (String line) => line.contains('-->'),
      );
      if (timingIndex < 0) continue;
      final List<String> parts = lines[timingIndex].split('-->');
      if (parts.length != 2) continue;
      final Duration? start = _parseTime(parts[0].trim());
      final Duration? end = _parseTime(
        parts[1].trim().split(RegExp(r'\s+')).first,
      );
      if (start == null || end == null) continue;
      final String text = lines
          .skip(timingIndex + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(start: start, end: end, text: text));
    }
    return cues
      ..sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
  }

  bool _looksLikeAss(String input) {
    return input.contains('[Events]') ||
        input.split('\n').any((String line) {
          final String lower = line.trimLeft().toLowerCase();
          return lower.startsWith('dialogue:') || lower.startsWith('format:');
        });
  }

  List<SubtitleCue> _parseAss(String input) {
    final List<SubtitleCue> cues = <SubtitleCue>[];
    List<String> format = const <String>[
      'layer',
      'start',
      'end',
      'style',
      'name',
      'marginl',
      'marginr',
      'marginv',
      'effect',
      'text',
    ];
    bool inEvents = false;

    for (final String rawLine in input.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';')) continue;

      final String lower = line.toLowerCase();
      if (lower == '[events]') {
        inEvents = true;
        continue;
      }
      if (line.startsWith('[') && lower != '[events]') {
        inEvents = false;
        continue;
      }
      if (!inEvents && !lower.startsWith('dialogue:')) continue;

      if (lower.startsWith('format:')) {
        format = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((String value) => value.trim().toLowerCase())
            .toList(growable: false);
        continue;
      }
      if (!lower.startsWith('dialogue:')) continue;

      final String data = line.substring(line.indexOf(':') + 1).trimLeft();
      final List<String> fields = _splitAssFields(data, format.length);
      final int startIndex = format.indexOf('start');
      final int endIndex = format.indexOf('end');
      final int textIndex = format.indexOf('text');
      if (startIndex < 0 ||
          endIndex < 0 ||
          textIndex < 0 ||
          fields.length <= startIndex ||
          fields.length <= endIndex ||
          fields.length <= textIndex) {
        continue;
      }

      final Duration? start = _parseTime(fields[startIndex].trim());
      final Duration? end = _parseTime(fields[endIndex].trim());
      if (start == null || end == null) continue;
      final String text = _cleanAssText(fields[textIndex]);
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    return cues
      ..sort((SubtitleCue a, SubtitleCue b) => a.start.compareTo(b.start));
  }

  List<String> _splitAssFields(String value, int fieldCount) {
    if (fieldCount <= 1) return <String>[value];
    final List<String> fields = <String>[];
    int start = 0;
    for (int i = 0; i < fieldCount - 1; i += 1) {
      final int comma = value.indexOf(',', start);
      if (comma < 0) break;
      fields.add(value.substring(start, comma));
      start = comma + 1;
    }
    fields.add(value.substring(start));
    return fields;
  }

  String _cleanAssText(String value) {
    return value
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\h', ' ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  Duration? _parseTime(String value) {
    final String clean = value.replaceAll(',', '.');
    final List<String> parts = clean.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final String secPart = parts.last;
    final List<String> secondParts = secPart.split('.');
    final int? seconds = int.tryParse(secondParts.first);
    if (seconds == null) return null;
    final int millis = secondParts.length > 1
        ? int.tryParse(secondParts[1].padRight(3, '0').substring(0, 3)) ?? 0
        : 0;
    final int? minutes = int.tryParse(parts[parts.length - 2]);
    final int hours = parts.length == 3 ? int.tryParse(parts.first) ?? 0 : 0;
    if (minutes == null) return null;
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }
}
