import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/watch_party/presentation/self_hosted_relay_info_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets('relay info button opens the self-hosting guide', (
    WidgetTester tester,
  ) async {
    String? openedUrl;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SelfHostedRelayInfoButton(
            openUrl: (String url) async {
              openedUrl = url;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Setup guide'));
    await tester.pump();

    expect(openedUrl, selfHostedRelayGuideUrl);
    expect(find.text('Setup guide'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('relay info button reports when the guide cannot be opened', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SelfHostedRelayInfoButton(openUrl: (String _) async => false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Setup guide'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the self-hosting guide.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
