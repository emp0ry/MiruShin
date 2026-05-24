import '../domain/player_models.dart';

class SubtitleParser {
  const SubtitleParser();

  List<SubtitleCue> parse(String input) {
    final String normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
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
