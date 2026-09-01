import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/board/presentation/board_page.dart';
import 'package:mirushin/features/metadata/application/metadata_providers.dart';
import 'package:mirushin/features/tracking/application/anilist_library_provider.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boardRailsProvider.overrideWith(
            (Ref ref) async => BoardRails(recentSeries: <MediaItem>[_item()]),
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
          home: const Scaffold(body: BoardPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Iterable<ListView> posterRows = tester.widgetList<ListView>(
      find.byKey(const ValueKey<String>('media-section-horizontal-list')),
    );
    expect(posterRows, isNotEmpty);
    expect(
      posterRows.every((ListView row) => row.clipBehavior == Clip.none),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

class _EmptyAniListLibrary extends AniListLibraryNotifier {
  @override
  Future<List<AniListAnimeListFolder>> build() async =>
      const <AniListAnimeListFolder>[];
}

MediaItem _item() {
  return const MediaItem(
    id: 'anilist:1',
    title: 'Test Anime',
    originalTitle: 'Test Anime',
    overview: '',
    type: MediaType.anime,
    year: 2026,
    posterUrl: '',
    backdropUrl: '',
    rating: 8,
    genres: <String>[],
    sourceProvider: 'AniList',
    externalIds: <String, String>{'anilist': '1'},
    statusLabel: 'FINISHED',
  );
}
