import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/catalog/application/catalog_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog mode defaults to TMDB and persists changes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(catalogModeProvider), CatalogMode.tmdb);

    await container
        .read(catalogModeProvider.notifier)
        .setMode(CatalogMode.anilist);

    expect(container.read(catalogModeProvider), CatalogMode.anilist);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('catalog.mode'), 'anilist');
  });

  test('catalog mode loads persisted value asynchronously', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'catalog.mode': 'anilist',
    });
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(catalogModeProvider), CatalogMode.tmdb);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(catalogModeProvider), CatalogMode.anilist);
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

  test('metadata cache can be disabled without clearing stored data', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const MetadataCacheStore enabled = MetadataCacheStore();
    const MetadataCacheStore disabled = MetadataCacheStore(enabled: false);

    await enabled.write('tmdb.disabled-toggle.demo', <String, dynamic>{
      'value': 'cached',
    });

    expect(await disabled.read('tmdb.disabled-toggle.demo'), isNull);
    await disabled.write('tmdb.disabled-toggle.demo', <String, dynamic>{
      'value': 'ignored',
    });
    expect(await enabled.read('tmdb.disabled-toggle.demo'), <String, dynamic>{
      'value': 'cached',
    });
  });
}
