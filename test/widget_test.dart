import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/app.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/media_details/presentation/media_details_page.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'desktop navigation adds Profile only after switching to AniList',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: MiruShinApp()));
      await tester.pumpAndSettle();

      expect(find.text('Board'), findsWidgets);
      expect(find.text('Discovery'), findsWidgets);
      expect(find.text('Library'), findsWidgets);
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('Addons'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Profile'), findsNothing);

      await tester.tap(find.text('MiruShin').first);
      await tester.pump();

      expect(find.text('Switched to AniList'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'compact navigation keeps Profile inside More only in AniList mode',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: MiruShinApp()));
      await tester.pumpAndSettle();

      final Finder navBar = find.byType(NavigationBar);
      expect(
        find.descendant(of: navBar, matching: find.text('Board')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('Discovery')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('Library')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: navBar, matching: find.text('More')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: navBar, matching: find.text('More')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('Addons'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Profile'), findsNothing);

      await tester.tap(find.text('Switch Catalog Mode').last);
      await tester.pump();
      expect(find.text('Switched to AniList'), findsOneWidget);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: navBar, matching: find.text('More')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'TMDB settings show sign-in placeholder and hide AniList controls',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: MiruShinApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('Default Library page'), findsNothing);
      expect(find.text('Score format'), findsNothing);
      expect(find.text('Show adult content'), findsNothing);
      expect(find.text('Theme mode'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AniList settings hide TMDB-only metadata language', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MiruShinApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MiruShin').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    expect(find.text('App language'), findsWidgets);
    expect(find.text('Metadata language'), findsNothing);
    expect(find.text('Region / country preference'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'AniList profile shows signed-out placeholder when not connected',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: MiruShinApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('MiruShin').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').first);
      await tester.pumpAndSettle();

      expect(find.text('AniList not connected'), findsWidgets);
      expect(find.text('Sign in'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Media details page lays out on desktop and compact sizes', (
    WidgetTester tester,
  ) async {
    const MediaItem item = MediaItem(
      id: 'tmdb:movie:1',
      title: 'A Very Long Cinematic Movie Title That Still Needs To Fit',
      originalTitle: 'Original Cinematic Title',
      overview:
          'A metadata-only overview for a media item. It should be readable, polished, and never imply playback, streaming, scraping, or downloads.',
      type: MediaType.movie,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.4,
      genres: <String>[
        'Drama',
        'Science Fiction',
        'Adventure',
        'Mystery',
        'Thriller',
        'Fantasy',
        'Family',
        'Animation',
        'Action',
        'Comedy',
      ],
      sourceProvider: 'TMDB',
      externalIds: <String, String>{'tmdb': '1'},
      runtimeMinutes: 126,
      statusLabel: 'Released',
    );

    Future<void> pumpDetails(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const MediaDetailsPage(id: 'tmdb:movie:1', initialItem: item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add to Library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDetails(const Size(1280, 900));
    await pumpDetails(const Size(390, 844));
  });
}
