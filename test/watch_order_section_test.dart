import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/media_details/application/watch_order_provider.dart';
import 'package:mirushin/features/media_details/domain/watch_order.dart';
import 'package:mirushin/features/media_details/domain/watch_order_resolver.dart';
import 'package:mirushin/features/media_details/presentation/watch_order_section.dart';
import 'package:mirushin/features/profile/application/anilist_user_settings_provider.dart';
import 'package:mirushin/features/tracking/application/anilist_favorite_provider.dart';
import 'package:mirushin/features/tracking/application/anilist_library_provider.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';

import 'support/watch_order_fixtures.dart';

class TestLibrary extends AniListLibraryNotifier {
  @override
  Future<List<AniListAnimeListFolder>> build() async => [];

  void setProgress(
    int progress,
    AniListListStatus status, {
    double? score,
    bool favorite = false,
  }) {
    final MediaItem item = watchMedia(1).item;
    state = AsyncData([
      AniListAnimeListFolder(
        name: 'Watching',
        status: status,
        entries: [
          AniListAnimeListEntry(
            id: 1,
            status: status,
            progress: progress,
            score: score,
            mediaItem: item.copyWith(
              externalIds: <String, String>{
                ...item.externalIds,
                'anilist_is_favourite': '$favorite',
              },
            ),
          ),
        ],
      ),
    ]);
  }
}

class TestFavoriteController extends AniListFavoriteController {
  @override
  Map<String, bool> build() => const <String, bool>{};
}

WatchOrder sampleOrder() => const WatchOrderResolver().resolve([
  watchMedia(1, year: 2000, relations: [relation(2, 'SIDE_STORY')]),
  watchMedia(2, year: 2020, format: 'OVA'),
  watchMedia(3, year: 2010),
]);

WatchOrderMedia malWatchMedia(int malId, {String? title}) => WatchOrderMedia(
  id: malId,
  malId: malId,
  format: 'TV',
  startDate: const WatchOrderDate(year: 2020),
  item: MediaItem(
    id: 'mal:$malId',
    title: title ?? 'MAL Anime $malId',
    originalTitle: '',
    overview: '',
    type: MediaType.anime,
    year: 2020,
    posterUrl: '',
    backdropUrl: '',
    rating: 8,
    genres: const <String>[],
    sourceProvider: 'MyAnimeList',
    externalIds: <String, String>{'mal': '$malId'},
    episodeCount: 12,
    statusLabel: 'FINISHED_AIRING',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets(
    'mobile section displays live status, main filter and current title',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = TestLibrary();
      var fetches = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            watchOrderProvider(101).overrideWith((ref) async {
              fetches++;
              return sampleOrder();
            }),
            anilistAnimeListProvider.overrideWith(() => library),
            anilistAnimePreviewListProvider.overrideWith((ref) async => []),
            anilistFavoriteProvider.overrideWith(TestFavoriteController.new),
            aniListEffectiveScoreFormatProvider.overrideWithValue(
              'POINT_10_DECIMAL',
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate],
            home: Scaffold(
              body: SingleChildScrollView(
                child: WatchOrderSection(item: watchMedia(1).item),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Watch Order'), findsOneWidget);
      expect(find.textContaining('Current title'), findsOneWidget);
      expect(find.text('Anime 2'), findsOneWidget);
      final Finder currentShell = find.byKey(
        const ValueKey<String>('watch-order-shell-1'),
      );
      final BoxDecoration decoration =
          tester.widget<Container>(currentShell).decoration! as BoxDecoration;
      final Border border = decoration.border! as Border;
      expect(
        border.top.color,
        Theme.of(tester.element(currentShell)).colorScheme.primary,
      );
      expect(border.top.width, 2);
      library.setProgress(7, AniListListStatus.current);
      await tester.pumpAndSettle();
      expect(find.text('Watching · 7 / 12'), findsOneWidget);
      library.setProgress(
        12,
        AniListListStatus.completed,
        score: 8.5,
        favorite: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Completed · 12 / 12'), findsOneWidget);
      expect(find.text('8.5'), findsOneWidget);
      Icon favoriteIcon = tester.widget<Icon>(
        find.byKey(const ValueKey<String>('watch-order-favorite-1')),
      );
      expect(favoriteIcon.icon, Icons.favorite_rounded);
      expect(
        favoriteIcon.color,
        Theme.of(tester.element(currentShell)).colorScheme.primary,
      );
      expect(find.text('·'), findsNWidgets(2));
      for (final Text separator in tester.widgetList<Text>(find.text('·'))) {
        expect(
          separator.style?.color,
          Theme.of(tester.element(currentShell)).colorScheme.primary,
        );
      }
      library.setProgress(12, AniListListStatus.completed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('watch-order-favorite-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('watch-order-score')),
        findsNothing,
      );
      expect(find.text('·'), findsNothing);
      expect(fetches, 1);
      await tester.tap(find.text('Main story only'));
      await tester.pumpAndSettle();
      expect(find.text('Anime 2'), findsNothing);
      expect(find.text('Anime 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('entry opens existing media-details route with AniList media', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: WatchOrderSection(item: watchMedia(1).item),
            ),
          ),
        ),
        GoRoute(
          path: '/media/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOrderProvider(101).overrideWith((ref) async => sampleOrder()),
          anilistAnimeListProvider.overrideWith(TestLibrary.new),
          anilistAnimePreviewListProvider.overrideWith((ref) async => []),
          anilistFavoriteProvider.overrideWith(TestFavoriteController.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [AppLocalizations.delegate],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anime 3'));
    await tester.pumpAndSettle();
    expect(find.text('Opened anilist:3'), findsOneWidget);
  });

  testWidgets('MAL fallback card shows Watch Order and MAL-matched progress', (
    tester,
  ) async {
    final TestLibrary library = TestLibrary();
    final WatchOrder order = const WatchOrderResolver().resolve(
      <WatchOrderMedia>[
        malWatchMedia(101, title: 'Current MAL title'),
        malWatchMedia(102),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOrderProvider(101).overrideWith((ref) async => order),
          anilistAnimeListProvider.overrideWith(() => library),
          anilistAnimePreviewListProvider.overrideWith(
            (ref) async => const <AniListAnimeListFolder>[],
          ),
          anilistFavoriteProvider.overrideWith(TestFavoriteController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: WatchOrderSection(
                item: malWatchMedia(101, title: 'Current MAL title').item,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    library.setProgress(7, AniListListStatus.current);
    await tester.pumpAndSettle();

    expect(find.text('Watch Order'), findsOneWidget);
    expect(find.textContaining('Current title'), findsOneWidget);
    expect(find.text('Watching · 7 / 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed loading has a working retry', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOrderProvider(101).overrideWith((ref) async {
            if (++requests == 1) throw StateError('offline');
            return sampleOrder();
          }),
          anilistAnimeListProvider.overrideWith(TestLibrary.new),
          anilistAnimePreviewListProvider.overrideWith((ref) async => []),
          anilistFavoriteProvider.overrideWith(TestFavoriteController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: SingleChildScrollView(
              child: WatchOrderSection(item: watchMedia(1).item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Watch order could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Anime 3'), findsOneWidget);
    expect(requests, 2);
  });

  testWidgets('missing MAL and manga do not fetch a watch order', (
    tester,
  ) async {
    var requests = 0;
    for (final ids in [
      <String, String>{},
      {'mal': '101', 'anilist_type': 'MANGA'},
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            watchOrderProvider(101).overrideWith((ref) async {
              requests++;
              return sampleOrder();
            }),
          ],
          child: MaterialApp(
            home: WatchOrderSection(
              item: watchMedia(1).item.copyWith(externalIds: ids),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Watch Order'), findsNothing);
    }
    expect(requests, 0);
  });

  testWidgets('large franchise is initially bounded and can show more', (
    tester,
  ) async {
    final order = const WatchOrderResolver().resolve(
      List.generate(14, (i) => watchMedia(i + 1)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOrderProvider(101).overrideWith((ref) async => order),
          anilistAnimeListProvider.overrideWith(TestLibrary.new),
          anilistAnimePreviewListProvider.overrideWith((ref) async => []),
          anilistFavoriteProvider.overrideWith(TestFavoriteController.new),
        ],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Scaffold(
            body: SingleChildScrollView(
              child: WatchOrderSection(item: watchMedia(1).item),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Anime 13'), findsNothing);
    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Anime 14'), findsOneWidget);
  });
}
