import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/core/diagnostics/player_diagnostics.dart';
import 'package:mirushin/features/player/application/player_settings.dart';
import 'package:mirushin/features/player/domain/player_models.dart';
import 'package:mirushin/features/player/presentation/widgets/player_diagnostics_controls.dart';

class DisabledSettings extends PlayerSettingsController {
  @override
  Future<PlayerSettings> build() async => const PlayerSettings();
}

class EnabledSettings extends PlayerSettingsController {
  @override
  Future<PlayerSettings> build() async =>
      const PlayerSettings(diagnosticsEnabled: true);
}

class TestLocalizations extends LocalizationsDelegate<AppLocalizations> {
  const TestLocalizations();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(const AppLocalizations(Locale('en'), {}, {}));
  @override
  bool shouldReload(TestLocalizations old) => false;
}

Widget harness(bool enabled) => ProviderScope(
  overrides: [
    playerSettingsProvider.overrideWith(
      enabled ? EnabledSettings.new : DisabledSettings.new,
    ),
  ],
  child: const MaterialApp(
    localizationsDelegates: [TestLocalizations()],
    home: Scaffold(body: PlayerDiagnosticsControls()),
  ),
);

void main() {
  testWidgets(
    'disabled mode hides marker/report actions and leaves observers off',
    (tester) async {
      PlayerDiagnostics.instance.setEnabled(false);
      await tester.pumpWidget(harness(false));
      await tester.pumpAndSettle();
      expect(find.text('Playback diagnostics'), findsOneWidget);
      expect(find.text('Save diagnostic report'), findsNothing);
      expect(
        find.text('Press D in the player to mark a micro-pause.'),
        findsNothing,
      );
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(PlayerDiagnostics.instance.observing, isFalse);
    },
  );

  testWidgets('enabled mode offers report and D hint without marker buttons', (
    tester,
  ) async {
    PlayerDiagnostics.instance.setEnabled(true);
    await tester.pumpWidget(harness(true));
    await tester.pumpAndSettle();
    expect(find.text('Save diagnostic report'), findsOneWidget);
    expect(
      find.text('Press D in the player to mark a micro-pause.'),
      findsOneWidget,
    );
    expect(find.text('Mark micro-pause'), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
    final events =
        jsonDecode(PlayerDiagnostics.instance.report())['events'] as List;
    expect(events.any((event) => event['type'] == 'user.microPause'), isFalse);
    expect(events.any((event) => event['type'] == 'engine.command'), isFalse);
    PlayerDiagnostics.instance.setEnabled(false);
  });

  const labels = [
    'Playback diagnostics',
    'Mark micro-pause',
    'Mark micro-pause (D)',
    'Press D in the player to mark a micro-pause.',
    'Micro-pause marked',
    'Save diagnostic report',
    'Record the last ten minutes on this device. Does not change playback or upload reports.',
    'Some entries were skipped',
    'Skipped {count} entries with missing or ambiguous provider IDs.',
    'Exports the Local Library in MyAnimeList XML format. Works offline.',
    'Exports the Local Library in Shikimori JSON format. Works offline.',
  ];
  for (final locale in ['en', 'ru', 'ja']) {
    test('export/diagnostic text is translated in $locale', () {
      final values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map;
      for (final label in labels) {
        expect(values[label], isA<String>(), reason: '$locale: $label');
        expect((values[label] as String).trim(), isNotEmpty);
      }
      expect(
        values['Skipped {count} entries with missing or ambiguous provider IDs.'],
        contains('{count}'),
      );
    });
  }
}
