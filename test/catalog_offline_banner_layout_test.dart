import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/app/theme/app_spacing.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:mirushin/features/catalog/application/catalog_status.dart';
import 'package:mirushin/features/catalog/presentation/catalog_offline_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local SQLite error is not presented as an AniList outage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'catalog.mode': 'anilist'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final marker = Provider((ref) => ref);
    markCatalogOffline(
      container.read(marker),
      mode: CatalogMode.anilist,
      sourceName: 'AniList',
      operation: 'library',
      usingCache: true,
      fallbackSourceName: 'MyAnimeList',
      error: SqliteException(
        extendedResultCode: 2067,
        message: 'UNIQUE constraint failed',
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CatalogOfflineBanner())),
      ),
    );
    await tester.pump();
    expect(find.text('Library sync needs attention'), findsOneWidget);
    expect(find.text('AniList is temporarily unavailable'), findsNothing);
    expect(find.text('AniList Discord'), findsNothing);
    expect(find.textContaining('while AniList is unavailable'), findsNothing);
    expect(find.textContaining('database error (2067)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone catalog banner applies the Library side inset', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'anilist',
    });
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(catalogOfflineNoticeProvider.notifier)
        .show(
          CatalogOfflineNotice(
            mode: CatalogMode.anilist,
            sourceName: 'AniList',
            operation: 'library',
            usingCache: true,
            occurredAt: DateTime(2026),
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: CatalogOfflineBanner(horizontalInset: AppSpacing.lg),
          ),
        ),
      ),
    );
    await tester.pump();

    final Padding padding = tester.widget<Padding>(
      find.byKey(const ValueKey<String>('catalog-offline-banner-padding')),
    );
    expect(
      padding.padding,
      const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: AppSpacing.lg,
      ),
    );
    expect(find.text('AniList is temporarily unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AniList fallback banner names MAL and can be dismissed', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'anilist',
    });
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(catalogOfflineNoticeProvider.notifier)
        .show(
          CatalogOfflineNotice(
            mode: CatalogMode.anilist,
            sourceName: 'AniList',
            operation: 'library',
            usingCache: false,
            occurredAt: DateTime(2026),
            fallbackSourceName: 'MyAnimeList',
          ),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CatalogOfflineBanner())),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'MiruShin is temporarily using MyAnimeList while AniList is unavailable.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('catalog-offline-banner-dismiss')),
    );
    await tester.pump();

    expect(find.text('AniList is temporarily unavailable'), findsNothing);
    expect(container.read(catalogOfflineNoticeProvider), isNull);
    expect(tester.takeException(), isNull);
  });
}
