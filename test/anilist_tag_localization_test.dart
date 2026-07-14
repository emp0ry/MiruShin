import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _aniListTagCategoryLeaves = <String>[
  'Card & Board Game',
  'Sexual Content',
  'Slice of Life',
  'Main Cast',
  'Organisations',
  'Organizations',
  'Technical',
  'Demographic',
  'Universe',
  'Vehicle',
  'Fantasy',
  'Romance',
  'Comedy',
  'Action',
  'Drama',
  'Scene',
  'Traits',
  'Sci-Fi',
  'Mecha',
  'Other',
  'Sport',
  'Music',
  'Arts',
  'Game',
  'Time',
  'Cast',
  'Theme',
];

void main() {
  test('AniList tag catalog has localization keys', () {
    final List<dynamic> tags =
        jsonDecode(
              File('test/fixtures/anilist_media_tags.json').readAsStringSync(),
            )
            as List<dynamic>;

    final Set<String> expectedKeys = <String>{};
    for (final dynamic rawTag in tags) {
      final Map<String, dynamic> tag = rawTag as Map<String, dynamic>;
      expectedKeys.add(tag['name'] as String);
      expectedKeys.add(_displayTagCategory(tag['category'] as String? ?? ''));
    }

    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      final List<String> missing =
          expectedKeys.where((String key) => !arb.containsKey(key)).toList()
            ..sort();

      expect(
        missing,
        isEmpty,
        reason: 'Missing AniList tag localization keys in app_$locale.arb',
      );
    }
  });
}

String _displayTagCategory(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Other';
  for (final String leaf in _aniListTagCategoryLeaves) {
    if (trimmed == leaf || trimmed.endsWith('-$leaf')) return leaf;
  }
  final int dash = trimmed.indexOf('-');
  if (dash <= 0) return trimmed;
  final String prefix = trimmed.substring(0, dash).trim();
  final String suffix = trimmed.substring(dash + 1).trim();
  if (<String>{
        'Cast',
        'Demographic',
        'Setting',
        'Sexual Content',
        'Technical',
        'Theme',
      }.contains(prefix) &&
      suffix.isNotEmpty) {
    return suffix;
  }
  return trimmed;
}
