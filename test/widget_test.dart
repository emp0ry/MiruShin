import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/app.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/media_details/presentation/media_details_page.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(binding.platformDispatcher.clearLocaleTestValue);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'tmdb',
      'settings.appLanguage': 'en',
    });
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

  testWidgets('TMDB settings hide sign-in and AniList-only controls', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: MiruShinApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Default Library page'), findsNothing);
    expect(find.text('Score format'), findsNothing);
    expect(find.text('Show adult content'), findsNothing);
    expect(find.text('Theme mode'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

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
      posterUrl: 'https://example.invalid/details-poster.jpg',
      backdropUrl: 'https://example.invalid/details-backdrop.jpg',
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
      trailer: MediaTrailer(id: 'demo-trailer', site: 'YouTube'),
    );

    Future<void> pumpDetails(
      Size size, {
      bool expectCompactPoster = false,
      bool forceCompactMode = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(
              body: MediaDetailsPage(id: 'tmdb:movie:1', initialItem: item),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (forceCompactMode) {
        ProviderScope.containerOf(
          tester.element(find.byType(MediaDetailsPage)),
        ).read(settingsProvider.notifier).setCompactMode(true);
        await tester.pumpAndSettle();
      }
      expect(find.text('Edit'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('details-watch-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('details-trailer-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('details-edit-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('details-poster-open')),
        findsOneWidget,
      );
      final Finder posterButton = find.byKey(
        const ValueKey<String>('details-poster-open'),
      );
      final Finder detailsHero = find.byKey(
        const ValueKey<String>('details-hero'),
      );
      final Finder heroOverview = find.descendant(
        of: detailsHero,
        matching: find.text(item.overview),
      );
      expect(
        find.descendant(of: detailsHero, matching: posterButton),
        findsOneWidget,
      );
      expect(heroOverview, findsOneWidget);
      expect(
        find.ancestor(of: posterButton, matching: find.byType(Tooltip)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: posterButton,
          matching: find.byIcon(Icons.fullscreen_rounded),
        ),
        findsNothing,
      );
      expect(tester.widget<InkWell>(posterButton).onTap, isNotNull);
      final Finder backdropButton = find.byKey(
        const ValueKey<String>('details-backdrop-open'),
      );
      expect(backdropButton, findsOneWidget);
      expect(
        find.ancestor(of: backdropButton, matching: find.byType(Tooltip)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: backdropButton,
          matching: find.byIcon(Icons.fullscreen_rounded),
        ),
        findsNothing,
      );
      expect(tester.widget<GestureDetector>(backdropButton).onTap, isNotNull);
      final Size watchSize = tester.getSize(
        find.byKey(const ValueKey<String>('details-watch-action')),
      );
      final Size trailerSize = tester.getSize(
        find.byKey(const ValueKey<String>('details-trailer-action')),
      );
      final Size editSize = tester.getSize(
        find.byKey(const ValueKey<String>('details-edit-action')),
      );
      final Rect posterRect = tester.getRect(posterButton);
      final Finder heroTitle = find.text(item.title);
      final Rect titleRect = tester.getRect(heroTitle);
      final Rect overviewRect = tester.getRect(heroOverview);
      expect(watchSize.height, 58);
      expect(watchSize.width, greaterThan(trailerSize.width));
      if (expectCompactPoster) {
        expect(posterRect.width, lessThan(188));
        expect(posterRect.right, lessThan(titleRect.left));
        expect(posterRect.right, lessThan(overviewRect.left));
      }
      if (size.width < 600) {
        expect(tester.widget<Text>(heroTitle).style?.fontSize, lessThan(32));
        expect(tester.widget<Text>(heroOverview).style?.fontSize, lessThan(16));
        expect(trailerSize.height, 54);
        expect(editSize.height, 54);
        expect(trailerSize.width, closeTo(editSize.width, 0.01));
      } else {
        expect(trailerSize.width, greaterThan(editSize.width));
      }
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDetails(const Size(1280, 900));
    await pumpDetails(const Size(390, 844), expectCompactPoster: true);

    await pumpDetails(
      const Size(1280, 900),
      expectCompactPoster: true,
      forceCompactMode: true,
    );
  });

  testWidgets('AniList stats wrap without overflowing narrow details cards', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'anilist',
      'settings.appLanguage': 'en',
    });
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const MediaItem item = MediaItem(
      id: 'anilist:1',
      title: 'Narrow Anime',
      originalTitle: 'Narrow Anime',
      overview: 'Anime details used to verify the responsive statistics row.',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 8.2,
      genres: <String>[],
      sourceProvider: 'AniList',
      externalIds: <String, String>{
        'anilist': '1',
        'anilist_type': 'ANIME',
        'anilist_popularity': '142000',
        'anilist_favourites': '4300',
      },
      statusLabel: 'Releasing',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.dark(),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            body: MediaDetailsPage(id: 'anilist:1', initialItem: item),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('142K'), findsOneWidget);
    expect(find.text('watching'), findsOneWidget);
    expect(find.text('4.3K'), findsOneWidget);
    expect(find.text('favorites'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
