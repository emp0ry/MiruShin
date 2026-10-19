import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/utils/lazy_mapped_list.dart';

void main() {
  test('projects only visited rows and does not cache expanded history', () {
    var conversions = 0;
    final rows = LazyMappedList(List.generate(10000, (i) => i), (i) {
      conversions++;
      return {'id': i};
    });
    expect(rows.length, 10000);
    expect(conversions, 0);
    final first = rows[0];
    final again = rows[0];
    expect(first, again);
    expect(identical(first, again), isFalse);
    expect(conversions, 2);
    expect(rows.take(2).toList(), [
      {'id': 0},
      {'id': 1},
    ]);
    expect(conversions, 4);
    expect(() => rows[0] = {}, throwsUnsupportedError);
    expect(() => rows.length = 0, throwsUnsupportedError);
    expect(() => rows[-1], throwsRangeError);
    expect(() => rows[10000], throwsRangeError);
  });

  test('UTF-8 encoding preserves the exact normal List JSON bytes', () {
    final source = List.generate(
      500,
      (i) => jsonEncode({
        'id': i,
        'before': {'title': 'Привет 日本語 $i', 'score': 75.0},
        'after': {'title': '😀 $i', 'progress': i},
      }),
    );
    final projected = LazyMappedList<String, dynamic>(source, jsonDecode);
    final expected = source.map(jsonDecode).toList();
    expect(
      jsonEncode({'operations': projected}),
      jsonEncode({'operations': expected}),
    );
    expect(
      JsonUtf8Encoder().convert({'operations': projected}),
      JsonUtf8Encoder().convert({'operations': expected}),
    );
  });
}
