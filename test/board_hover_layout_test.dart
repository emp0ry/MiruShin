import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/core/widgets/media_poster_card.dart';
import 'package:mirushin/core/widgets/section_header.dart';
import 'package:mirushin/features/board/presentation/board_page.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:mirushin/features/catalog/application/catalog_repository.dart';
import 'package:mirushin/features/metadata/application/metadata_providers.dart';
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

  testWidgets('compact Board rows do not clip poster hover overflow', (
    WidgetTester tester,
  ) async {
    await _pumpBoard(
      tester,
      rails: BoardRails(recentSeries: <MediaItem>[_item()]),
    );

    final Iterable<ListView> posterRows = tester.widgetList<ListView>(
      find.byKey(const ValueKey<String>('media-section-horizontal-list')),
    );
    final SingleChildScrollView pageScrollView = tester.widget(
      find.byKey(const ValueKey<String>('board-page-scroll-view')),
    );
    expect(posterRows, isNotEmpty);
    expect(
      posterRows.every((ListView row) => row.clipBehavior == Clip.none),
      isTrue,
    );
    expect(pageScrollView.clipBehavior, Clip.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Load more appends the next page on Board without navigation', (
    WidgetTester tester,
  ) async {
    final _RecordingCatalogRepository repository =
        _RecordingCatalogRepository();
    await _pumpBoard(
      tester,
      rails: BoardRails(recentSeries: <MediaItem>[_item()]),
      repository: repository,
    );

    expect(find.byType(MediaPosterCard), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Load more'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaPosterCard), findsNWidgets(2));
    expect(repository.lastSearch, '');
    expect(repository.lastType, isNull);
    expect(repository.lastFilter, 'Popular');
    expect(repository.lastPage, 2);
    expect(repository.lastAniListKind, 'anime');
    expect(tester.takeException(), isNull);
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
  required BoardRails rails,
  CatalogRepository? repository,
  List<AniListAnimeListFolder> folders = const <AniListAnimeListFolder>[],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        boardRailsProvider.overrideWith((Ref ref) async => rails),
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
  await tester.pumpAndSettle();
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
    String? anilistKind,
  }) async {
    lastSearch = search;
    lastType = type;
    lastFilter = filter;
    lastPage = page;
    lastAniListKind = anilistKind;
    return <MediaItem>[_item(), _item(2)];
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
