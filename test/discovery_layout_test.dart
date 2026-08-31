import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:mirushin/features/catalog/application/catalog_repository.dart';
import 'package:mirushin/features/discovery/presentation/discovery_page.dart';
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

  testWidgets(
    'Discovery adds wide columns without changing smaller grid counts',
    (WidgetTester tester) async {
      await _pumpDiscovery(tester, const Size(1600, 1000));
      expect(_gridColumns(tester), 8);

      tester.view.physicalSize = const Size(1280, 1000);
      await tester.pumpAndSettle();
      expect(_gridColumns(tester), 6);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(_gridColumns(tester), 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Anime and Manga sit left of Filters on the lower filter row', (
    WidgetTester tester,
  ) async {
    await _pumpDiscovery(tester, const Size(1600, 1000));

    final Rect controls = tester.getRect(
      find.byKey(const ValueKey<String>('discovery-primary-controls')),
    );
    final Rect anime = tester.getRect(find.widgetWithText(ChoiceChip, 'Anime'));
    final Rect manga = tester.getRect(find.widgetWithText(ChoiceChip, 'Manga'));
    final Rect trending = tester.getRect(
      find.widgetWithText(FilterChip, 'Trending'),
    );
    final Rect filters = tester.getRect(
      find.byKey(const ValueKey<String>('discovery-filters-button')),
    );

    expect(filters.center.dy, closeTo(manga.center.dy, 0.1));
    expect(anime.left, closeTo(controls.left, 0.1));
    expect(filters.right, closeTo(controls.right, 0.1));
    expect(filters.left - manga.right, greaterThan(100));
    expect(anime.top, greaterThan(trending.bottom));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDiscovery(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeCatalogRepositoryProvider.overrideWithValue(
          const _DiscoveryCatalogRepository(),
        ),
        anilistAnimeListProvider.overrideWith(_EmptyAniListLibrary.new),
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
        home: const Scaffold(body: DiscoveryPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _gridColumns(WidgetTester tester) {
  final Finder grid = find.descendant(
    of: find.byKey(const ValueKey<String>('discovery-grid')),
    matching: find.byType(GridView),
  );
  final GridView widget = tester.widget<GridView>(grid);
  return (widget.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
      .crossAxisCount;
}

class _EmptyAniListLibrary extends AniListLibraryNotifier {
  @override
  Future<List<AniListAnimeListFolder>> build() async =>
      const <AniListAnimeListFolder>[];
}

class _DiscoveryCatalogRepository implements CatalogRepository {
  const _DiscoveryCatalogRepository();

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
    if (page != 1) return const <MediaItem>[];
    return List<MediaItem>.generate(
      16,
      (int index) => MediaItem(
        id: 'anilist:$index',
        title: 'Title $index',
        originalTitle: 'Title $index',
        overview: '',
        type: MediaType.anime,
        year: 2026,
        posterUrl: '',
        backdropUrl: '',
        rating: 8,
        genres: const <String>[],
        sourceProvider: 'AniList',
        externalIds: <String, String>{'anilist': '$index'},
        statusLabel: 'FINISHED',
      ),
      growable: false,
    );
  }
}
