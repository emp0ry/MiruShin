import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/theme/app_theme.dart';

void main() {
  test('all app themes use a particle-free press ripple', () {
    final List<ThemeData> themes = <ThemeData>[
      AppTheme.light(),
      AppTheme.dark(),
      AppTheme.oled(),
    ];

    for (final ThemeData theme in themes) {
      expect(theme.splashFactory, same(InkRipple.splashFactory));
      expect(theme.splashFactory, isNot(same(InkSparkle.splashFactory)));
    }
  });
}
