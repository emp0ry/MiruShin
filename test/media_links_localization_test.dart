import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media-link dialog text is translated in every supported locale', () {
    const List<String> keys = <String>[
      'Media links',
      'AniList link',
      'TMDB link',
      'MiruShin link',
      'Copy link',
      'Link copied',
      'Share the MiruShin link to open this title directly in the app.',
    ];

    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in keys) {
        expect(values[key], isA<String>(), reason: '$locale is missing "$key"');
        expect((values[key] as String).trim(), isNotEmpty);
        if (locale != 'en') {
          expect(values[key], isNot(key));
        }
      }
    }
  });
}
