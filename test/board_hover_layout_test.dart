import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/core/widgets/neutral_placeholder.dart';
import 'package:mirushin/core/widgets/section_header.dart';
import 'package:mirushin/features/board/presentation/board_page.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:mirushin/features/catalog/application/catalog_repository.dart';
import 'package:mirushin/features/metadata/application/metadata_providers.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/anilist_library_provider.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/calendar_item.dart';
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
      'catalog.mode': 'anilist',
      'settings.appLanguage': 'en',
    });
  });

  testWidgets(
    'compact Board clips horizontal overscroll but keeps hover room',
    (WidgetTester tester) async {
      await _pumpBoard(
        tester,
        rails: BoardRails(recentSeries: <MediaItem>[_item()]),
      );

      final Iterable<ListView> posterRows = tester.widgetList<ListView>(
        find.byKey(const ValueKey<String>('media-section-horizontal-list')),
      );
      final Iterable<ClipRect> horizontalClips = tester.widgetList<ClipRect>(
        find.byKey(const ValueKey<String>('media-section-horizontal-clip')),
      );
      final SingleChildScrollView pageScrollView = tester.widget(
        find.byKey(const ValueKey<String>('board-page-scroll-view')),
      );
      expect(posterRows, isNotEmpty);
      expect(
        posterRows.every((ListView row) => row.clipBehavior == Clip.none),
        isTrue,
      );
      expect(horizontalClips.length, posterRows.length);
      for (final ClipRect clip in horizontalClips) {
        final Rect bounds = clip.clipper!.getClip(const Size(320, 300));
        expect(bounds.left, 0);
        expect(bounds.right, 320);
        expect(bounds.top, lessThan(0));
        expect(bounds.bottom, greaterThan(300));
      }
      expect(pageScrollView.clipBehavior, Clip.none);

      final Positioned heroHairline = tester.widget<Positioned>(
        find.byKey(const ValueKey<String>('board-hero-bottom-hairline')),
      );
      final List<Positioned> posterHairlines = tester
          .widgetList<Positioned>(
            find.byKey(const ValueKey<String>('media-poster-bottom-hairline')),
          )
          .toList();
      final ClipRRect heroClip = tester.widget<ClipRRect>(
        find.byKey(const ValueKey<String>('board-hero-clip')),
      );
      final Stack heroStack = tester.widget<Stack>(
        find.byKey(const ValueKey<String>('board-hero-stack')),
      );
      final Iterable<ClipRRect> posterClips = tester.widgetList<ClipRRect>(
        find.byKey(const ValueKey<String>('media-poster-clip')),
      );
      final Iterable<Stack> posterStacks = tester.widgetList<Stack>(
        find.byKey(const ValueKey<String>('media-poster-stack')),
      );
      expect(heroClip.clipBehavior, Clip.hardEdge);
      expect(heroStack.clipBehavior, Clip.hardEdge);
      expect(posterClips, isNotEmpty);
      expect(
        posterClips.every(
          (ClipRRect clip) => clip.clipBehavior == Clip.hardEdge,
        ),
        isTrue,
      );
      expect(posterStacks, isNotEmpty);
      expect(
        posterStacks.every(
          (Stack stack) => stack.clipBehavior == Clip.hardEdge,
        ),
        isTrue,
      );
      expect(heroHairline.height, 1);
      expect(posterHairlines, isNotEmpty);
      expect(
        posterHairlines.every((Positioned hairline) => hairline.height == 1),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact Board loads the next page near the end without a button',
    (WidgetTester tester) async {
      final _RecordingCatalogRepository repository =
          _RecordingCatalogRepository();
      await _pumpBoard(
        tester,
        rails: BoardRails(
          recentSeries: List<MediaItem>.generate(
            4,
            (int index) => _item(index + 1),
          ),
        ),
        repository: repository,
      );

      ListView compactRow = tester.widget<ListView>(
        find.byKey(const ValueKey<String>('media-section-horizontal-list')),
      );
      expect(compactRow.childrenDelegate.estimatedChildCount, 7);
      expect(find.text('Load more'), findsNothing);

      await tester.drag(
        find.byKey(const ValueKey<String>('media-section-horizontal-list')),
        const Offset(-800, 0),
      );
      await tester.pumpAndSettle();

      compactRow = tester.widget<ListView>(
        find.byKey(const ValueKey<String>('media-section-horizontal-list')),
      );
      expect(compactRow.childrenDelegate.estimatedChildCount, 9);
      expect(find.text('Load more'), findsNothing);
      expect(repository.lastSearch, '');
      expect(repository.lastType, isNull);
      expect(repository.lastFilter, 'Popular');
      expect(repository.lastPage, 2);
      expect(repository.lastAniListKind, 'anime');
      expect(repository.lastPageSize, 20);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide Board defaults to grid and enables compact rows on demand',
    (WidgetTester tester) async {
      await _pumpBoard(
        tester,
        size: const Size(1600, 1000),
        rails: BoardRails(
          recentSeries: List<MediaItem>.generate(
            4,
            (int index) => _item(index + 1),
          ),
        ),
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BoardPage)),
      );
      expect(container.read(settingsProvider).compactCards, isFalse);
      expect(
        find.byKey(const ValueKey<String>('media-section-horizontal-list')),
        findsNothing,
      );
      expect(find.byType(GridView), findsWidgets);

      container.read(settingsProvider.notifier).setCompactCards(true);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).compactCards, isTrue);
      expect(
        find.byKey(const ValueKey<String>('media-section-horizontal-list')),
        findsWidgets,
      );
      expect(find.byType(GridView), findsNothing);
      expect(find.text('Load more'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide Board uses up to 8 columns and loads three rows', (
    WidgetTester tester,
  ) async {
    final _RecordingCatalogRepository repository =
        _RecordingCatalogRepository();
    await _pumpBoard(
      tester,
      size: const Size(1600, 1000),
      rails: BoardRails(
        recentSeries: List<MediaItem>.generate(
          24,
          (int index) => _item(index + 1),
        ),
      ),
      repository: repository,
    );

    GridView grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      8,
    );
    expect(grid.childrenDelegate.estimatedChildCount, 24);

    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(repository.lastPageSize, 24);

    tester.view.physicalSize = const Size(1360, 1000);
    await tester.pumpAndSettle();
    grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      7,
    );
    expect(grid.childrenDelegate.estimatedChildCount, 21);

    tester.view.physicalSize = const Size(1280, 1000);
    await tester.pumpAndSettle();
    grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      6,
    );
    expect(grid.childrenDelegate.estimatedChildCount, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Board stays empty until the first metadata arrives', (
    WidgetTester tester,
  ) async {
    final Completer<BoardRails> railsCompleter = Completer<BoardRails>();
    await _pumpBoard(tester, railsFuture: railsCompleter.future, settle: false);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(NeutralPlaceholder), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('board-page-scroll-view')),
      findsNothing,
    );
    expect(find.text('No live metadata yet'), findsNothing);

    railsCompleter.complete(BoardRails(recentSeries: <MediaItem>[_item()]));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('board-page-scroll-view')),
      findsOneWidget,
    );
    expect(find.text('Test Anime 1'), findsWidgets);
  });

  testWidgets('AniList Board shows the requested sections in order', (
    WidgetTester tester,
  ) async {
    final Map<String, List<MediaItem>> additionalSections =
        <String, List<MediaItem>>{
          'Favorites': <MediaItem>[_item(4)],
          'Airing': <MediaItem>[_item(5)],
          'Upcoming': <MediaItem>[_item(6)],
          'Finished': <MediaItem>[_item(7)],
          'Newest': <MediaItem>[_item(8)],
          'Recently Updated': <MediaItem>[_item(9)],
        };
    await _pumpBoard(
      tester,
      rails: BoardRails(
        recentMovies: <MediaItem>[_item(1)],
        recentSeries: <MediaItem>[_item(2)],
        topAnime: <MediaItem>[_item(3)],
        additionalSections: additionalSections,
      ),
      folders: <AniListAnimeListFolder>[
        AniListAnimeListFolder(
          name: 'Watching',
          status: AniListListStatus.current,
          entries: <AniListAnimeListEntry>[
            AniListAnimeListEntry(
              id: 100,
              status: AniListListStatus.current,
              progress: 1,
              mediaItem: _item(100),
            ),
          ],
        ),
      ],
    );

    const List<String> expectedTitles = <String>[
      'Continue Watching',
      'Trending',
      'Popular',
      'Top Rated',
      'Favorites',
      'Airing',
      'Upcoming',
      'Finished',
      'Newest',
      'Recently Updated',
    ];
    double previousTop = double.negativeInfinity;
    for (final String title in expectedTitles) {
      final Finder sectionTitle = find.descendant(
        of: find.widgetWithText(SectionHeader, title),
        matching: find.text(title),
      );
      expect(sectionTitle, findsOneWidget);
      final double top = tester.getTopLeft(sectionTitle).dy;
      expect(top, greaterThan(previousTop));
      previousTop = top;
    }
    expect(find.text('AniList Library'), findsNothing);
  });
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  BoardRails? rails,
  Future<BoardRails>? railsFuture,
  CatalogRepository? repository,
  List<AniListAnimeListFolder> folders = const <AniListAnimeListFolder>[],
  bool settle = true,
  Size size = const Size(390, 844),
}) async {
  assert((rails == null) != (railsFuture == null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        boardRailsProvider.overrideWith(
          (Ref ref) => railsFuture ?? Future<BoardRails>.value(rails!),
        ),
        if (repository != null)
          activeCatalogRepositoryProvider.overrideWithValue(repository),
        anilistAnimeListProvider.overrideWith(
          () => _TestAniListLibrary(folders),
        ),
      ],
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
        home: const Scaffold(body: BoardPage()),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

class _TestAniListLibrary extends AniListLibraryNotifier {
  _TestAniListLibrary(this.folders);

  final List<AniListAnimeListFolder> folders;

  @override
  Future<List<AniListAnimeListFolder>> build() async => folders;
}

class _RecordingCatalogRepository implements CatalogRepository {
  String? lastSearch;
  MediaType? lastType;
  String? lastFilter;
  int? lastPage;
  int? lastPageSize;
  String? lastAniListKind;

  @override
  CatalogMode get mode => CatalogMode.anilist;

  @override
  Future<BoardRails> boardRails() async => BoardRails.empty();

  @override
  Future<List<CalendarItem>> calendar({
    required DateTime from,
    required DateTime to,
  }) async => const <CalendarItem>[];

  @override
  Future<MediaItem?> details(String id) async => null;

  @override
  Future<List<MediaItem>> discover({
    required String search,
    required MediaType? type,
    required String filter,
    required int page,
    int pageSize = 20,
    String? anilistKind,
  }) async {
    lastSearch = search;
    lastType = type;
    lastFilter = filter;
    lastPage = page;
    lastPageSize = pageSize;
    lastAniListKind = anilistKind;
    return <MediaItem>[_item(), _item(5)];
  }
}

MediaItem _item([int index = 1]) {
  return MediaItem(
    id: 'anilist:$index',
    title: 'Test Anime $index',
    originalTitle: 'Test Anime $index',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 8,
    genres: <String>[],
    sourceProvider: 'AniList',
    externalIds: <String, String>{'anilist': '$index'},
    statusLabel: 'FINISHED',
  );
}
