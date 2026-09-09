import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/core/constants/app_constants.dart';
import 'package:mirushin/features/settings/presentation/widgets/support_mirushin_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets('support card is explicit and opens Buy Me a Coffee', (
    WidgetTester tester,
  ) async {
    String? openedUrl;
    await tester.pumpWidget(
      _testApp(
        SupportMiruShinCard(
          openUrl: (String url) async {
            openedUrl = url;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Support MiruShin'), findsOneWidget);
    expect(find.text('Buy me a coffee'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('support-mirushin-button')),
    );
    await tester.pump();

    expect(openedUrl, AppConstants.supportUrl);
    expect(openedUrl, 'https://buymeacoffee.com/emp0ry');
    expect(tester.takeException(), isNull);
  });

  testWidgets('support card reports a browser opening failure', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(SupportMiruShinCard(openUrl: (String _) async => false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buy me a coffee'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the support page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('support card strings are translated in every locale', () {
    for (final String locale in <String>['en', 'ru', 'ja']) {
      final Map<String, dynamic> values =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final String key in <String>[
        'Support MiruShin',
        'Support development and help MiruShin keep getting better.',
        'Buy me a coffee',
        'Could not open the support page.',
      ]) {
        expect(
          (values[key] as String?)?.trim(),
          isNotEmpty,
          reason: '$locale: $key',
        );
      }
    }
  });
}

Widget _testApp(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}
