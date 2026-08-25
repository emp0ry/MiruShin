import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/downloads/application/download_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'auto-delete watched episodes defaults off and persists changes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer first = ProviderContainer();
      addTearDown(first.dispose);

      expect(await first.read(downloadSettingsProvider.future), isFalse);
      await first
          .read(downloadSettingsProvider.notifier)
          .setAutoDeleteWatchedEpisodes(true);
      expect(first.read(downloadSettingsProvider).value, isTrue);

      final ProviderContainer restored = ProviderContainer();
      addTearDown(restored.dispose);
      expect(await restored.read(downloadSettingsProvider.future), isTrue);
    },
  );

  test('auto-delete requires both the preference and watched status', () {
    expect(
      shouldAutoDeleteWatchedEpisode(enabled: false, isWatched: true),
      isFalse,
    );
    expect(
      shouldAutoDeleteWatchedEpisode(enabled: true, isWatched: false),
      isFalse,
    );
    expect(
      shouldAutoDeleteWatchedEpisode(enabled: true, isWatched: true),
      isTrue,
    );
  });

  test('download controls are translated in every supported locale', () {
    const List<String> keys = <String>[
      'Downloads',
      'No downloads yet',
      'Select all',
      'Select episodes to download.',
      'Auto-delete watched episodes',
      'Delete a downloaded episode after it is watched and the player closes.',
    ];
    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in keys) {
        expect(
          values[key],
          isA<String>().having(
            (String value) => value.trim(),
            '$locale translation for "$key"',
            isNotEmpty,
          ),
        );
      }
    }
  });
}
