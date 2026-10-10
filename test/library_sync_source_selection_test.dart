import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/core/utils/settings_preferences.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/settings/presentation/widgets/library_sync_source_row.dart';
import 'package:mirushin/features/tracking/domain/tracker_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('AniList is the default inbound source without automatic fallback', () {
    expect(const SettingsState().primaryTrackerSource, TrackerSource.anilist);
    expect(
      const SettingsState(
        malAccessToken: 'connected',
        malViewerId: 2,
      ).effectivePrimaryTrackerSource,
      TrackerSource.anilist,
    );
    expect(
      const SettingsState(
        primaryTrackerSource: TrackerSource.shikimori,
      ).effectivePrimaryTrackerSource,
      TrackerSource.shikimori,
    );
  });

  for (final width in [375.0, 900.0]) {
    testWidgets('source selection is visible and persisted at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => AppLocalizations.load(const Locale('ru')));
      final container = ProviderContainer(
        overrides: [settingsProvider.overrideWith(_Settings.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('ru'),
            supportedLocales: [Locale('ru')],
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: LibrarySyncSourceRow(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Источник синхронизации библиотеки'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<TrackerSource>>(
              find.byType(DropdownButton<TrackerSource>),
            )
            .value,
        TrackerSource.anilist,
      );
      for (final source in [
        TrackerSource.mal,
        TrackerSource.shikimori,
        TrackerSource.anilist,
      ]) {
        await tester.tap(find.byType(DropdownButton<TrackerSource>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(source.label).last);
        await tester.pumpAndSettle();
        expect(container.read(settingsProvider).primaryTrackerSource, source);
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString(SettingsPreferences.primaryTrackerSourceKey),
          source.name,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}
