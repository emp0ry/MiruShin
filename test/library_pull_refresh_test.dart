import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/app/theme/app_theme.dart';
import 'package:mirushin/features/library/application/google_drive_sync_controller.dart';
import 'package:mirushin/features/library/application/library_refresh_controller.dart';
import 'package:mirushin/features/library/presentation/library_page.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/tracking/application/tracker_library_provider.dart';
import 'package:mirushin/features/tracking/application/tracker_sync_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppLocalizations.load(const Locale('en')));
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets(
      'empty Library supports pull refresh and retry after failure ($platform)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'catalog.mode': 'anilist',
          'settings.appLanguage': 'en',
        });
        tester.view.physicalSize = const Size(900, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gate = Completer<TrackerLibrarySnapshot>();
        final calls = <String>[];
        final controller = LibraryRefreshController((kind, force) {
          expect(force, isTrue);
          calls.add(kind);
          return gate.future;
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              googleDriveSyncControllerProvider.overrideWith(_IdleDrive.new),
              libraryRefreshControllerProvider.overrideWithValue(controller),
              trackerLocalAnimeLibraryProvider.overrideWith(
                (ref) async => const TrackerLocalAnimeLibrary(
                  folders: [],
                  pendingMutations: [],
                ),
              ),
              trackerLocalMangaLibraryProvider.overrideWith(
                (ref) async => const TrackerLocalAnimeLibrary(
                  folders: [],
                  pendingMutations: [],
                ),
              ),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              theme: AppTheme.dark().copyWith(platform: platform),
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
        final scroll = find.byType(CustomScrollView).hitTestable().first;
        await tester.drag(scroll, const Offset(0, 450));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(calls, ['anime']);
        expect(find.text('Library is empty'), findsOneWidget);
        gate.complete(
          const TrackerLibrarySnapshot(folders: [], fromCache: true),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Could not refresh library. Your saved library is still available.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Refresh library',
                ),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('Manga'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Refresh library'));
        await tester.pumpAndSettle();
        expect(calls.last, 'manga');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Settings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

class _IdleDrive extends GoogleDriveSyncController {
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
