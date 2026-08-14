import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/player/presentation/widgets/player_shortcuts_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets('player shortcut reference includes Z for zoom', (
    WidgetTester tester,
  ) async {
    await _pumpShortcuts(tester);

    expect(find.text('Z'), findsOneWidget);
    expect(find.text('Zoom'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shortcut reference hides app volume controls', (
    WidgetTester tester,
  ) async {
    await _pumpShortcuts(tester, volumeControlsEnabled: false);

    expect(find.text('M'), findsNothing);
    expect(find.text('Volume up'), findsNothing);
    expect(find.text('Volume down'), findsNothing);
    expect(find.text('Vertical swipe'), findsNothing);
    expect(find.text('←'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShortcuts(
  WidgetTester tester, {
  bool volumeControlsEnabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: AppTheme.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlayerShortcutsView(
            seekSeconds: 10,
            volumeControlsEnabled: volumeControlsEnabled,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
