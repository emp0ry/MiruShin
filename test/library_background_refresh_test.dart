import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/downloads/application/downloads_provider.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
import 'package:mirushin/features/library/application/google_drive_sync_controller.dart';
import 'package:mirushin/features/library/application/library_refresh_controller.dart';
import 'package:mirushin/features/library/presentation/library_page.dart';
import 'package:mirushin/features/profile/application/anilist_user_settings_provider.dart';
import 'package:mirushin/features/profile/domain/anilist_profile_models.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/tracker_library_provider.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuditSettings extends SettingsController {
  @override
  SettingsState build() => SettingsState(
    anilistViewerId: 7,
    anilistAccessToken: 'audit',
    anilistExpiresAt: DateTime.utc(2100),
  );
}

class AuditUserSettings extends AniListUserSettingsController {
  @override
  Future<AniListUserSettings> build() async => const AniListUserSettings();
}

class IdleDrive extends GoogleDriveSyncController {
  @override
  Future<GoogleDriveSyncState> build() async =>
      const GoogleDriveSyncState(configured: false, connected: false);
  @override
  Future<void> syncNow({
    bool background = false,
    bool localChangesOnly = false,
    bool remoteChangesOnly = false,
    bool automaticRetry = false,
  }) async {}
}

class EmptyDownloads extends DownloadController {
  @override
  List<DownloadedEpisode> build() => [];
}

class Revision extends Notifier<int> {
  @override
  int build() => 0;
  void change() => state++;
}

final revision = NotifierProvider<Revision, int>(Revision.new);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Watching keeps content and scroll while local data reloads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'catalog.mode': 'anilist',
      'settings.appLanguage': 'en',
    });
    await tester.runAsync(() => AppLocalizations.load(const Locale('en')));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gate = Completer<void>();
    final folders = [
      AniListAnimeListFolder(
        name: 'Watching',
        status: AniListListStatus.current,
        entries: List.generate(
          40,
          (index) => AniListAnimeListEntry(
            id: index + 1,
            status: AniListListStatus.current,
            progress: 3,
            mediaItem: MediaItem(
              id: 'anilist:${index + 1}',
              title: 'Anime $index',
              originalTitle: 'Anime $index',
              overview: '',
              type: MediaType.anime,
              year: 2026,
              posterUrl: '',
              backdropUrl: '',
              rating: 8,
              genres: [],
              sourceProvider: 'AniList',
              externalIds: {'anilist': '${index + 1}'},
              episodeCount: 12,
              statusLabel: 'FINISHED',
            ),
          ),
        ),
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        libraryRefreshControllerProvider.overrideWithValue(
          LibraryRefreshController(
            (_, _) async =>
                const TrackerLibrarySnapshot(folders: [], fromCache: false),
          ),
        ),
        settingsProvider.overrideWith(AuditSettings.new),
        aniListUserSettingsProvider.overrideWith(AuditUserSettings.new),
        googleDriveSyncControllerProvider.overrideWith(IdleDrive.new),
        downloadsProvider.overrideWith(EmptyDownloads.new),
        trackerLocalAnimeLibraryProvider.overrideWith((ref) async {
          final value = ref.watch(revision);
          if (value > 0) await gate.future;
          return TrackerLocalAnimeLibrary(
            folders: folders,
            pendingMutations: const [],
            canonical: true,
          );
        }),
        trackerLocalMangaLibraryProvider.overrideWith(
          (ref) async =>
              const TrackerLocalAnimeLibrary(folders: [], pendingMutations: []),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watching  40'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).hitTestable().first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView).hitTestable().first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    expect(before, greaterThan(0));
    container.read(revision.notifier).change();
    await tester.pump();
    expect(find.text('Reading the local library database.'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView).hitTestable().first,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    expect(after, before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
