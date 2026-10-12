import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/localization/app_localizations.dart';
import 'package:mirushin/features/library/application/canonical_library_repository.dart';
import 'package:mirushin/features/library/data/canonical_library_database.dart';
import 'package:mirushin/features/library/domain/library_export_snapshot.dart';
import 'package:mirushin/features/settings/application/settings_state.dart';
import 'package:mirushin/features/settings/presentation/widgets/library_export_section.dart';

class OfflineSettings extends SettingsController {
  @override
  SettingsState build() => const SettingsState();
}

class TestLocalizations extends LocalizationsDelegate<AppLocalizations> {
  const TestLocalizations();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(const AppLocalizations(Locale('en'), {}, {}));
  @override
  bool shouldReload(TestLocalizations old) => false;
}

class EmptySnapshotRepository extends CanonicalLibraryRepository {
  EmptySnapshotRepository(super.database);
  int exports = 0;
  @override
  Future<LibraryExportSnapshot> buildExportSnapshot() async {
    exports++;
    return LibraryExportSnapshot(workspaceId: 'local', entries: const []);
  }
}

void main() {
  for (final provider in ['MyAnimeList', 'Shikimori']) {
    testWidgets('Settings exports $provider without an AniList session', (
      tester,
    ) async {
      final database = CanonicalLibraryDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = EmptySnapshotRepository(database);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(OfflineSettings.new),
            canonicalLibraryRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            localizationsDelegates: [TestLocalizations()],
            home: Scaffold(
              body: SingleChildScrollView(child: LibraryExportSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('MyAnimeList'), findsOneWidget);
      expect(find.text('Shikimori'), findsOneWidget);
      expect(
        find.text(
          'Exports the Local Library in MyAnimeList XML format. Works offline.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(provider));
      await tester.pumpAndSettle();
      expect(find.text('Anime'), findsOneWidget);
      expect(find.text('Manga'), findsOneWidget);
      await tester.tap(find.text('Anime'));
      await tester.pumpAndSettle();
      expect(repository.exports, 1);
      expect(find.text('Nothing to export'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
