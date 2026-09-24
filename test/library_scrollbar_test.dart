import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/downloads/application/downloads_provider.dart';
import 'package:mirushin/features/downloads/domain/download_models.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/presentation/library_page.dart';
import 'package:mirushin/features/profile/application/anilist_user_settings_provider.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/anilist_library_provider.dart';
import 'package:mirushin/features/tracking/application/local_first_sync_engine.dart';
import 'package:mirushin/features/tracking/application/tracker_library_provider.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:mirushin/features/tracking/data/canonical_tracking_sync_store.dart';
import 'package:mirushin/features/tracking/data/tracking_sync_store.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:mirushin/features/tracking/domain/tracking_sync_models.dart';
import 'package:mirushin/features/tracking/presentation/anilist_entry_editor.dart';
import 'package:mirushin/shared/models/anilist_models.dart';
import 'package:mirushin/shared/models/media_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'anilist',
      'settings.appLanguage': 'en',
    });
  });

  testWidgets(
    'desktop Library keeps one scroll position per interactive scrollbar',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final List<AniListAnimeListFolder> folders = <AniListAnimeListFolder>[
        _folder(AniListListStatus.current, 1),
        _folder(AniListListStatus.completed, 101),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedSettings.new),
            anilistAnimeListProvider.overrideWith(
              () => _TestAniListLibrary(folders),
            ),
            anilistAnimePreviewListProvider.overrideWith(
              (Ref ref) async => folders,
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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

      expect(find.byType(NestedScrollView), findsNothing);

      await tester.tap(find.text('Watching  20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Completed  20'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView).hitTestable().first,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  test(
    'new AniList entry is visible while the initial library fetch is in flight',
    () async {
      final Completer<List<AniListAnimeListFolder>> fetch =
          Completer<List<AniListAnimeListFolder>>();
      final _DelayedAniListLibrary library = _DelayedAniListLibrary(fetch);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          anilistAnimeListProvider.overrideWith(() => library),
          anilistAnimePreviewListProvider.overrideWith(
            (Ref ref) async => const <AniListAnimeListFolder>[],
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(anilistAnimeListProvider);
      final AniListAnimeListEntry entry = _folder(
        AniListListStatus.current,
        1,
      ).entries.first;
      container
          .read(anilistAnimeListProvider.notifier)
          .replaceEntry(mediaId: 1, entry: entry);

      final AniListAnimeListEntry immediate = container
          .read(anilistAnimeListProvider)
          .requireValue
          .single
          .entries
          .single;
      expect(immediate.mediaItem.id, 'anilist:1');
      expect(immediate.status, AniListListStatus.current);

      fetch.complete(const <AniListAnimeListFolder>[]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final List<AniListAnimeListFolder> settled = container
          .read(anilistAnimeListProvider)
          .requireValue;
      expect(settled, hasLength(1));
      expect(settled.single.status, AniListListStatus.current);
      expect(settled.single.entries.single.mediaItem.id, 'anilist:1');
    },
  );

  testWidgets(
    'Library shows new local entries immediately with a secondary source',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedMalSettings.new),
            anilistAnimeListProvider.overrideWith(
              () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
            ),
            anilistAnimePreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            trackerAnimeListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryPage)),
      );
      final AniListLibraryNotifier notifier = container.read(
        anilistAnimeListProvider.notifier,
      );
      notifier.replaceEntry(
        mediaId: 901,
        entry: _newEntry(901, 'Instant Anime One'),
      );
      notifier.replaceEntry(
        mediaId: 902,
        entry: _newEntry(902, 'Instant Anime Two'),
      );
      await tester.pumpAndSettle();

      expect(find.text('All  2'), findsOneWidget);
      expect(find.text('Watching  2'), findsOneWidget);
      expect(find.text('Instant Anime One'), findsOneWidget);
      expect(find.text('Instant Anime Two'), findsOneWidget);
    },
  );

  testWidgets(
    'real MAL-only edit updates Library before network delivery completes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AniListAnimeListEntry entry = _malOnlyEntry(77, 'MAL Local First');
      final List<AniListAnimeListFolder> folders = <AniListAnimeListFolder>[
        AniListAnimeListFolder(
          name: AniListListStatus.current.label,
          status: AniListListStatus.current,
          entries: <AniListAnimeListEntry>[entry],
        ),
      ];
      final Completer<SyncDispatchResult> delivery =
          Completer<SyncDispatchResult>();
      int trackerLoads = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedMalSettings.new),
            anilistAnimeListProvider.overrideWith(
              () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
            ),
            anilistAnimePreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            trackerAnimeListProvider.overrideWith((Ref ref) async {
              trackerLoads += 1;
              return folders;
            }),
            trackerSyncCoordinatorProvider.overrideWith(
              (Ref ref) => _BlockingTrackerSyncCoordinator(
                ref,
                delivery,
                localCommitImmediate: true,
              ),
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: _LibraryEditHarness(
                entry: entry,
                draft: const AniListEntryEditDraft(
                  status: AniListListStatus.completed,
                  progress: 12,
                  score: 8,
                  notes: 'Updated locally',
                  repeat: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Watching  1'), findsOneWidget);
      expect(trackerLoads, 1);

      await tester.tap(find.byKey(const ValueKey<String>('save-entry')));
      await tester.pump();

      expect(delivery.isCompleted, isFalse);
      expect(find.text('Completed  1'), findsOneWidget);
      expect(find.text('Watching  1'), findsNothing);
      expect(find.byTooltip('Updated locally'), findsOneWidget);
      expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);

      delivery.complete(
        const SyncDispatchResult(pendingTargets: <TrackerSource>{}),
      );
      await tester.pumpAndSettle();
      expect(trackerLoads, 1);
    },
  );

  testWidgets(
    'real MAL-only add appears in Library before network delivery completes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AniListAnimeListEntry entry = _malOnlyEntry(
        78,
        'Immediate New MAL Anime',
        listEntryId: 0,
      );
      final Completer<SyncDispatchResult> delivery =
          Completer<SyncDispatchResult>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedMalSettings.new),
            anilistAnimeListProvider.overrideWith(
              () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
            ),
            anilistAnimePreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            trackerAnimeListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            trackerSyncCoordinatorProvider.overrideWith(
              (Ref ref) => _BlockingTrackerSyncCoordinator(
                ref,
                delivery,
                localCommitImmediate: true,
              ),
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: _LibraryEditHarness(
                entry: entry,
                draft: const AniListEntryEditDraft(
                  status: AniListListStatus.current,
                  progress: 1,
                  score: 7,
                  notes: 'Brand new local entry',
                  repeat: 0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('save-entry')));
      await tester.pump();

      expect(delivery.isCompleted, isFalse);
      expect(find.text('Watching  1'), findsOneWidget);
      expect(find.text('Immediate New MAL Anime'), findsOneWidget);
      expect(find.byTooltip('Brand new local entry'), findsOneWidget);

      delivery.complete(
        const SyncDispatchResult(pendingTargets: <TrackerSource>{}),
      );
      await tester.pumpAndSettle();

      expect(find.text('Watching  1'), findsOneWidget);
      expect(find.text('Immediate New MAL Anime'), findsOneWidget);
      expect(find.byTooltip('Brand new local entry'), findsOneWidget);
    },
  );

  testWidgets(
    'successful AniList save is visible when Library opens without reload',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AniListAnimeListEntry entry = _newEntry(
        906,
        'Visible After Successful Save',
      );
      final Completer<SyncDispatchResult> delivery =
          Completer<SyncDispatchResult>();
      final _CountingAniListLibrary fullLibrary = _CountingAniListLibrary(
        const <AniListAnimeListFolder>[],
      );
      int previewLoads = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedSettings.new),
            anilistAnimeListProvider.overrideWith(() => fullLibrary),
            anilistAnimePreviewListProvider.overrideWith((Ref ref) async {
              previewLoads += 1;
              return const <AniListAnimeListFolder>[];
            }),
            trackerSyncCoordinatorProvider.overrideWith(
              (Ref ref) => _BlockingTrackerSyncCoordinator(ref, delivery),
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _SaveThenShowLibraryHarness(
              entry: entry,
              draft: const AniListEntryEditDraft(
                status: AniListListStatus.current,
                progress: 1,
                score: 8,
                notes: 'Already saved locally',
                repeat: 0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final int fullLoadsBeforeSave = fullLibrary.builds;
      final int previewLoadsBeforeSave = previewLoads;

      await tester.tap(
        find.byKey(const ValueKey<String>('save-then-show-library')),
      );
      await tester.pump();
      expect(find.byType(LibraryPage), findsNothing);

      delivery.complete(
        const SyncDispatchResult(pendingTargets: <TrackerSource>{}),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.text('Watching  1'), findsOneWidget);
      expect(find.text('Visible After Successful Save'), findsOneWidget);
      expect(find.byTooltip('Already saved locally'), findsOneWidget);
      // Opening Library performs its one initial read. The completed Save must
      // not add a second provider reload on top of that read.
      expect(fullLibrary.builds, fullLoadsBeforeSave + 1);
      expect(previewLoads, previewLoadsBeforeSave + 1);
    },
  );

  testWidgets(
    'updated-newest reorder keeps every tile state attached to its anime',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'catalog.mode': 'anilist',
        'settings.appLanguage': 'en',
        'library.anilist.ANIME.All.sort': 'updatedNewest',
        'library.anilist.ANIME.current.sort': 'updatedNewest',
      });
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AniListAnimeListEntry first = _newEntry(
        920,
        'Initially First Anime',
      ).copyWith(progress: 1, notes: 'First note');
      final AniListAnimeListEntry second = _newEntry(
        921,
        'Edited Second Anime',
      ).copyWith(progress: 4, notes: 'Second note');
      final List<AniListAnimeListFolder> folders = <AniListAnimeListFolder>[
        AniListAnimeListFolder(
          name: AniListListStatus.current.label,
          status: AniListListStatus.current,
          entries: <AniListAnimeListEntry>[
            AniListAnimeListEntry(
              id: first.id,
              status: first.status,
              progress: first.progress,
              score: first.score,
              mediaItem: first.mediaItem,
              notes: first.notes,
              repeat: first.repeat,
              updatedAt: 200,
            ),
            AniListAnimeListEntry(
              id: second.id,
              status: second.status,
              progress: second.progress,
              score: second.score,
              mediaItem: second.mediaItem,
              notes: second.notes,
              repeat: second.repeat,
              updatedAt: 100,
            ),
          ],
        ),
      ];
      final Completer<SyncDispatchResult> delivery =
          Completer<SyncDispatchResult>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedSettings.new),
            anilistAnimeListProvider.overrideWith(
              () => _TestAniListLibrary(folders),
            ),
            anilistAnimePreviewListProvider.overrideWith(
              (Ref ref) async => folders,
            ),
            trackerSyncCoordinatorProvider.overrideWith(
              (Ref ref) => _BlockingTrackerSyncCoordinator(
                ref,
                delivery,
                localCommitImmediate: true,
              ),
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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

      expect(
        tester.getTopLeft(find.text('Initially First Anime')).dy,
        lessThan(tester.getTopLeft(find.text('Edited Second Anime')).dy),
      );
      final Finder secondTile = find.ancestor(
        of: find.text('Edited Second Anime'),
        matching: find.byType(Dismissible),
      );
      await tester.drag(secondTile, const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(delivery.isCompleted, isFalse);
      expect(
        tester.getTopLeft(find.text('Edited Second Anime')).dy,
        lessThan(tester.getTopLeft(find.text('Initially First Anime')).dy),
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Edited Second Anime'),
            matching: find.byType(Dismissible),
          ),
          matching: find.text('5 / 12'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Initially First Anime'),
            matching: find.byType(Dismissible),
          ),
          matching: find.text('1 / 12'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('First note'), findsOneWidget);
      expect(find.byTooltip('Second note'), findsOneWidget);

      delivery.complete(
        const SyncDispatchResult(pendingTargets: <TrackerSource>{}),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('5 / 12'), findsOneWidget);
      expect(find.text('1 / 12'), findsOneWidget);
    },
  );

  testWidgets('offline local add survives restart and Library refresh', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AniListAnimeListEntry entry = _newEntry(904, 'Durable Offline Anime');
    final CanonicalLibraryDatabase database = CanonicalLibraryDatabase(
      NativeDatabase.memory(),
    );
    addTearDown(database.close);
    final CanonicalLibraryRepository repository = CanonicalLibraryRepository(
      database,
    );
    final LocalFirstSyncEngine engine = LocalFirstSyncEngine(
      store: CanonicalTrackingSyncStore(repository: repository),
      adapters: const <TrackerSource, TrackerProviderAdapter>{},
      primary: TrackerSource.anilist,
    );
    await engine.recordMutation(
      identity: MediaIdentity.fromExternalIds(
        entry.mediaItem.externalIds,
        mediaId: entry.mediaItem.id,
      ),
      patch: UserMediaPatch(
        status: AniListListStatus.current,
        progress: 3,
        score: 8,
        notes: 'Saved while AniList is offline',
        fields: const <UserMediaField>{
          UserMediaField.status,
          UserMediaField.progress,
          UserMediaField.score,
          UserMediaField.notes,
        },
      ),
      targets: const <TrackerSource>{TrackerSource.anilist},
      mediaItem: entry.mediaItem,
      mediaTitle: entry.mediaItem.title,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          canonicalLibraryDatabaseProvider.overrideWithValue(database),
          settingsProvider.overrideWith(_ConnectedSettings.new),
          anilistAnimeListProvider.overrideWith(
            () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
          ),
          anilistAnimePreviewListProvider.overrideWith(
            (Ref ref) async => const <AniListAnimeListFolder>[],
          ),
          anilistMangaListProvider.overrideWith(
            (Ref ref) async => const <AniListAnimeListFolder>[],
          ),
          anilistMangaPreviewListProvider.overrideWith(
            (Ref ref) async => const <AniListAnimeListFolder>[],
          ),
          downloadsProvider.overrideWith(_EmptyDownloads.new),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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

    expect(find.text('Durable Offline Anime'), findsOneWidget);
    expect(find.text('Watching  1'), findsOneWidget);
    expect(find.byTooltip('Saved while AniList is offline'), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryPage)),
    );
    container.invalidate(anilistAnimeListProvider);
    container.invalidate(anilistAnimePreviewListProvider);
    await tester.pumpAndSettle();

    expect(find.text('Durable Offline Anime'), findsOneWidget);
    expect(find.text('Watching  1'), findsOneWidget);
  });

  testWidgets('save can finish safely after the calling widget is unmounted', (
    WidgetTester tester,
  ) async {
    final Completer<SyncDispatchResult> delivery =
        Completer<SyncDispatchResult>();
    final AniListAnimeListEntry entry = _newEntry(905, 'Unmount Safe Anime');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_ConnectedSettings.new),
          anilistAnimeListProvider.overrideWith(
            () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
          ),
          anilistAnimePreviewListProvider.overrideWith(
            (Ref ref) async => const <AniListAnimeListFolder>[],
          ),
          trackerSyncCoordinatorProvider.overrideWith(
            (Ref ref) => _BlockingTrackerSyncCoordinator(ref, delivery),
          ),
        ],
        child: MaterialApp(
          home: _UnmountingEditHarness(
            entry: entry,
            draft: const AniListEntryEditDraft(
              status: AniListListStatus.current,
              progress: 2,
              score: 8,
              notes: 'Must survive route pop',
              repeat: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(_UnmountingEditHarness)),
    );

    await tester.tap(find.byKey(const ValueKey<String>('save-and-unmount')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('save-and-unmount')),
      findsNothing,
    );

    delivery.complete(
      const SyncDispatchResult(pendingTargets: <TrackerSource>{}),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final List<TrackerLibraryOptimisticMutation> mutations = container.read(
      trackerLibraryOptimisticMutationsProvider,
    );
    expect(mutations, hasLength(1));
    expect(mutations.single.patch.progress, 2);
    expect(mutations.single.patch.notes, 'Must survive route pop');
  });

  testWidgets('refresh can finish safely after the caller is unmounted', (
    WidgetTester tester,
  ) async {
    final Completer<void> previewGate = Completer<void>();
    final Completer<void> refreshCompleted = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_ConnectedSettings.new),
          aniListEffectiveTitleLanguageProvider.overrideWithValue('ENGLISH'),
          anilistAnimeListProvider.overrideWith(
            () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
          ),
          anilistAnimePreviewListProvider.overrideWith((Ref ref) async {
            await previewGate.future;
            return const <AniListAnimeListFolder>[];
          }),
          trackerLocalAnimeLibraryProvider.overrideWith(
            (Ref ref) async => const TrackerLocalAnimeLibrary(
              folders: <AniListAnimeListFolder>[],
              pendingMutations: <TrackerLibraryOptimisticMutation>[],
            ),
          ),
        ],
        child: MaterialApp(
          home: _UnmountingRefreshHarness(completed: refreshCompleted),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('refresh-and-unmount')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('refresh-and-unmount')),
      findsNothing,
    );

    previewGate.complete();
    await refreshCompleted.future;
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test(
    'progress overlay preserves score and notes from the displayed entry',
    () {
      final ProviderContainer container = ProviderContainer(
        overrides: [settingsProvider.overrideWith(_ConnectedMalSettings.new)],
      );
      addTearDown(container.dispose);
      final AniListAnimeListEntry entry = AniListAnimeListEntry(
        id: 99,
        status: AniListListStatus.current,
        progress: 4,
        score: 9,
        notes: 'Keep this note',
        repeat: 2,
        mediaItem: _malOnlyEntry(99, 'Progress Patch').mediaItem,
      );
      final TrackerLibraryOptimisticController controller = container.read(
        trackerLibraryOptimisticMutationsProvider.notifier,
      );

      controller.updateProgress(
        mediaItem: entry.mediaItem,
        progress: 12,
        status: AniListListStatus.completed,
      );
      final List<AniListAnimeListFolder> result =
          applyTrackerLibraryOptimisticMutations(<AniListAnimeListFolder>[
            AniListAnimeListFolder(
              name: AniListListStatus.current.label,
              status: AniListListStatus.current,
              entries: <AniListAnimeListEntry>[entry],
            ),
          ], container.read(trackerLibraryOptimisticMutationsProvider));
      final AniListAnimeListEntry updated = result.single.entries.single;

      expect(updated.status, AniListListStatus.completed);
      expect(updated.progress, 12);
      expect(updated.score, 9);
      expect(updated.notes, 'Keep this note');
      expect(updated.repeat, 2);
    },
  );

  testWidgets(
    'real MAL-only delete disappears before network delivery completes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final AniListAnimeListEntry entry = _malOnlyEntry(
        79,
        'Delete Immediately',
      );
      final List<AniListAnimeListFolder> folders = <AniListAnimeListFolder>[
        AniListAnimeListFolder(
          name: AniListListStatus.current.label,
          status: AniListListStatus.current,
          entries: <AniListAnimeListEntry>[entry],
        ),
      ];
      final Completer<SyncDispatchResult> delivery =
          Completer<SyncDispatchResult>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_ConnectedMalSettings.new),
            anilistAnimeListProvider.overrideWith(
              () => _TestAniListLibrary(const <AniListAnimeListFolder>[]),
            ),
            anilistAnimePreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            trackerAnimeListProvider.overrideWith((Ref ref) async => folders),
            trackerSyncCoordinatorProvider.overrideWith(
              (Ref ref) => _BlockingDeleteSyncCoordinator(ref, delivery),
            ),
            anilistMangaListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            anilistMangaPreviewListProvider.overrideWith(
              (Ref ref) async => const <AniListAnimeListFolder>[],
            ),
            downloadsProvider.overrideWith(_EmptyDownloads.new),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: _LibraryDeleteHarness(entry: entry)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete Immediately'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('delete-entry')));
      await tester.pump();

      expect(delivery.isCompleted, isFalse);
      expect(find.text('Delete Immediately'), findsNothing);

      delivery.complete(
        const SyncDispatchResult(pendingTargets: <TrackerSource>{}),
      );
      await tester.pumpAndSettle();
    },
  );
}

AniListAnimeListEntry _newEntry(int mediaId, String title) {
  return AniListAnimeListEntry(
    id: 0,
    status: AniListListStatus.current,
    progress: 0,
    mediaItem: MediaItem(
      id: 'anilist:$mediaId',
      title: title,
      originalTitle: title,
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: 'AniList',
      externalIds: <String, String>{
        'anilist': '$mediaId',
        'mal': '${mediaId + 1000}',
      },
      episodeCount: 12,
      statusLabel: 'FINISHED',
    ),
  );
}

AniListAnimeListEntry _malOnlyEntry(
  int malId,
  String title, {
  int? listEntryId,
}) {
  return AniListAnimeListEntry(
    id: listEntryId ?? malId,
    status: AniListListStatus.current,
    progress: 4,
    mediaItem: MediaItem(
      id: 'mal:$malId',
      title: title,
      originalTitle: title,
      overview: '',
      type: MediaType.anime,
      year: 2026,
      posterUrl: '',
      backdropUrl: '',
      rating: 0,
      genres: const <String>[],
      sourceProvider: 'MyAnimeList',
      externalIds: <String, String>{'mal': '$malId'},
      episodeCount: 12,
      statusLabel: 'FINISHED',
    ),
  );
}

class _LibraryEditHarness extends ConsumerWidget {
  const _LibraryEditHarness({required this.entry, required this.draft});

  final AniListAnimeListEntry entry;
  final AniListEntryEditDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: <Widget>[
        FilledButton(
          key: const ValueKey<String>('save-entry'),
          onPressed: () => unawaited(
            saveAniListEntryEdit(
              context: context,
              entry: entry,
              draft: draft,
              showSuccessSnack: false,
            ),
          ),
          child: const Text('Save test entry'),
        ),
        const Expanded(child: LibraryPage()),
      ],
    );
  }
}

class _LibraryDeleteHarness extends ConsumerWidget {
  const _LibraryDeleteHarness({required this.entry});

  final AniListAnimeListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: <Widget>[
        FilledButton(
          key: const ValueKey<String>('delete-entry'),
          onPressed: () =>
              unawaited(deleteAniListEntry(context: context, entry: entry)),
          child: const Text('Delete test entry'),
        ),
        const Expanded(child: LibraryPage()),
      ],
    );
  }
}

class _UnmountingEditHarness extends StatefulWidget {
  const _UnmountingEditHarness({required this.entry, required this.draft});

  final AniListAnimeListEntry entry;
  final AniListEntryEditDraft draft;

  @override
  State<_UnmountingEditHarness> createState() => _UnmountingEditHarnessState();
}

class _SaveThenShowLibraryHarness extends StatefulWidget {
  const _SaveThenShowLibraryHarness({required this.entry, required this.draft});

  final AniListAnimeListEntry entry;
  final AniListEntryEditDraft draft;

  @override
  State<_SaveThenShowLibraryHarness> createState() =>
      _SaveThenShowLibraryHarnessState();
}

class _SaveThenShowLibraryHarnessState
    extends State<_SaveThenShowLibraryHarness> {
  bool _showLibrary = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _showLibrary
          ? const LibraryPage()
          : FilledButton(
              key: const ValueKey<String>('save-then-show-library'),
              onPressed: () async {
                final AniListEntrySaveResult result =
                    await saveAniListEntryEdit(
                      context: context,
                      entry: widget.entry,
                      draft: widget.draft,
                      showSuccessSnack: false,
                    );
                if (!mounted || result == AniListEntrySaveResult.failed) return;
                setState(() => _showLibrary = true);
              },
              child: const Text('Save then show Library'),
            ),
    );
  }
}

class _UnmountingEditHarnessState extends State<_UnmountingEditHarness> {
  bool _showButton = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _showButton
          ? _SaveThenUnmountButton(
              entry: widget.entry,
              draft: widget.draft,
              onStarted: () => setState(() => _showButton = false),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _SaveThenUnmountButton extends ConsumerWidget {
  const _SaveThenUnmountButton({
    required this.entry,
    required this.draft,
    required this.onStarted,
  });

  final AniListAnimeListEntry entry;
  final AniListEntryEditDraft draft;
  final VoidCallback onStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton(
      key: const ValueKey<String>('save-and-unmount'),
      onPressed: () {
        unawaited(
          saveAniListEntryEdit(
            context: context,
            entry: entry,
            draft: draft,
            showSuccessSnack: false,
          ),
        );
        onStarted();
      },
      child: const Text('Save and close'),
    );
  }
}

class _UnmountingRefreshHarness extends StatefulWidget {
  const _UnmountingRefreshHarness({required this.completed});

  final Completer<void> completed;

  @override
  State<_UnmountingRefreshHarness> createState() =>
      _UnmountingRefreshHarnessState();
}

class _UnmountingRefreshHarnessState extends State<_UnmountingRefreshHarness> {
  bool _showButton = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _showButton
          ? FilledButton(
              key: const ValueKey<String>('refresh-and-unmount'),
              onPressed: () {
                final ProviderContainer container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final Future<void> refresh = refreshAniListLibraryForMediaType(
                  container,
                  mediaType: 'ANIME',
                );
                setState(() => _showButton = false);
                refresh.then(
                  (_) => widget.completed.complete(),
                  onError: widget.completed.completeError,
                );
              },
              child: const Text('Refresh and close'),
            )
          : const SizedBox.shrink(),
    );
  }
}

AniListAnimeListFolder _folder(AniListListStatus status, int firstId) {
  return AniListAnimeListFolder(
    name: status.label,
    status: status,
    entries: List<AniListAnimeListEntry>.generate(20, (int index) {
      final int id = firstId + index;
      return AniListAnimeListEntry(
        id: id,
        status: status,
        progress: status == AniListListStatus.completed ? 12 : 4,
        mediaItem: MediaItem(
          id: 'anilist:$id',
          title: 'Anime $id',
          originalTitle: 'Anime $id',
          overview: '',
          type: MediaType.anime,
          year: 2026,
          posterUrl: '',
          backdropUrl: '',
          rating: 8,
          genres: const <String>[],
          sourceProvider: 'AniList',
          externalIds: <String, String>{'anilist': '$id'},
          episodeCount: 12,
          statusLabel: 'FINISHED',
        ),
      );
    }),
  );
}

class _ConnectedSettings extends SettingsController {
  @override
  SettingsState build() => SettingsState(
    anilistAccessToken: 'test-token',
    anilistExpiresAt: DateTime.utc(2100),
    anilistViewerId: 1,
  );
}

class _ConnectedMalSettings extends SettingsController {
  @override
  SettingsState build() => const SettingsState(
    primaryTrackerSource: TrackerSource.mal,
    malAccessToken: 'test-mal-token',
    malViewerId: 2,
  );
}

class _BlockingTrackerSyncCoordinator extends TrackerSyncCoordinator {
  _BlockingTrackerSyncCoordinator(
    super.ref,
    this.delivery, {
    this.localCommitImmediate = false,
  });

  final Completer<SyncDispatchResult> delivery;
  final bool localCommitImmediate;

  @override
  Future<SyncDispatchResult> pushEntryEdit({
    required Map<String, String> externalIds,
    String? mediaId,
    String? mediaTitle,
    MediaItem? mediaItem,
    AniListListStatus? status,
    int? progress,
    int? progressVolumes,
    double? score,
    String? notes,
    int? repeat,
    DateTime? startedAt,
    DateTime? completedAt,
    int? priority,
    bool? private,
    bool? hiddenFromStatusLists,
    Map<String, bool>? customLists,
    Map<String, double>? advancedScores,
    String? scoreFormat,
    int? malPriority,
    int? malRewatchValue,
    List<String>? malTags,
    Set<UserMediaField>? fields,
    Set<TrackerSource>? targets,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
    TrackingEpisodeCheckpoint? episodeCheckpoint,
  }) => localCommitImmediate
      ? Future<SyncDispatchResult>.value(
          const SyncDispatchResult(
            pendingTargets: <TrackerSource>{TrackerSource.mal},
          ),
        )
      : delivery.future;
}

class _BlockingDeleteSyncCoordinator extends TrackerSyncCoordinator {
  _BlockingDeleteSyncCoordinator(super.ref, this.delivery);

  final Completer<SyncDispatchResult> delivery;

  @override
  Future<SyncDispatchResult> deleteEntry({
    required Map<String, String> externalIds,
    String? mediaId,
    String? mediaTitle,
    Set<TrackerSource>? targets,
    Map<TrackerSource, int> providerEntryIds = const <TrackerSource, int>{},
  }) => Future<SyncDispatchResult>.value(
    const SyncDispatchResult(
      pendingTargets: <TrackerSource>{TrackerSource.mal},
    ),
  );
}

class _TestAniListLibrary extends AniListLibraryNotifier {
  _TestAniListLibrary(this.folders);

  final List<AniListAnimeListFolder> folders;

  @override
  Future<List<AniListAnimeListFolder>> build() async => folders;
}

class _CountingAniListLibrary extends AniListLibraryNotifier {
  _CountingAniListLibrary(this.folders);

  final List<AniListAnimeListFolder> folders;
  int builds = 0;

  @override
  Future<List<AniListAnimeListFolder>> build() async {
    builds += 1;
    return folders;
  }
}

class _DelayedAniListLibrary extends AniListLibraryNotifier {
  _DelayedAniListLibrary(this.fetch);

  final Completer<List<AniListAnimeListFolder>> fetch;

  @override
  Future<List<AniListAnimeListFolder>> loadLibrary() => fetch.future;
}

class _EmptyDownloads extends DownloadController {
  @override
  List<DownloadedEpisode> build() => const <DownloadedEpisode>[];
}
