import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/core/utils/settings_preferences.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/settings/presentation/widgets/google_drive_library_sync_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [375.0, 900.0]) {
    testWidgets(
      'Russian full-library switch persists and fits at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() => AppLocalizations.load(const Locale('ru')));
        final container = ProviderContainer(
          overrides: [settingsProvider.overrideWith(_Settings.new)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              locale: Locale('ru'),
              supportedLocales: [Locale('ru')],
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: GoogleDriveLibrarySyncRow(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Синхронизировать полную библиотеку'), findsOneWidget);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(
          container.read(settingsProvider).googleDriveLibrarySyncEnabled,
          isTrue,
        );
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getBool(
            SettingsPreferences.googleDriveLibrarySyncEnabledKey,
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
