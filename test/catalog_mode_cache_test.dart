import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog mode defaults to AniList and persists changes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(catalogModeProvider), CatalogMode.anilist);

    await container
        .read(catalogModeProvider.notifier)
        .setMode(CatalogMode.tmdb);

    expect(container.read(catalogModeProvider), CatalogMode.tmdb);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('catalog.mode'), 'tmdb');
  });

  test('catalog mode loads persisted value asynchronously', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'tmdb',
    });
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(catalogModeProvider), CatalogMode.anilist);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(catalogModeProvider), CatalogMode.tmdb);
  });

  test('metadata cache reads, overwrites, and clears by mode prefix', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const MetadataCacheStore store = MetadataCacheStore();

    await store.write('tmdb.details.demo', <String, dynamic>{'value': 'tmdb'});
    await store.write('anilist.details.demo', <String, dynamic>{
      'value': 'anilist',
    });

    expect(await store.read('tmdb.details.demo'), <String, dynamic>{
      'value': 'tmdb',
    });

    await store.write('tmdb.details.demo', <String, dynamic>{'value': 'new'});
    expect(await store.read('tmdb.details.demo'), <String, dynamic>{
      'value': 'new',
    });

    await store.removeByPrefix('tmdb');

    expect(await store.read('tmdb.details.demo'), isNull);
    expect(await store.read('anilist.details.demo'), <String, dynamic>{
      'value': 'anilist',
    });
  });

  test('metadata cache remains available across store instances', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const MetadataCacheStore first = MetadataCacheStore();
    const MetadataCacheStore restored = MetadataCacheStore();

    await first.write('tmdb.always-on.demo', <String, dynamic>{
      'value': 'cached',
    });

    expect(await restored.read('tmdb.always-on.demo'), <String, dynamic>{
      'value': 'cached',
    });
  });
}
