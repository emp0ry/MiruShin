import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/data/subtitle_parser.dart';

void main() {
  test('parses ASS dialogue subtitles', () {
    const String input = '''
[Script Info]
Title: Example

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.20,0:00:03.45,Default,,0,0,0,,{\\an8}Hello\\Nworld
Dialogue: 0,0:00:04.00,0:00:05.50,Default,,0,0,0,,Comma, inside text
''';

    final cues = const SubtitleParser().parse(input);

    expect(cues, hasLength(2));
    expect(cues.first.start, const Duration(milliseconds: 1200));
    expect(cues.first.end, const Duration(milliseconds: 3450));
    expect(cues.first.text, 'Hello\nworld');
    expect(cues.last.text, 'Comma, inside text');
  });
}
