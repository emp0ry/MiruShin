import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/tracking/application/anilist_library_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads Russian aliases from the active status cache', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const MetadataCacheStore cache = MetadataCacheStore();
    await cache.write(
      'anilist.russianAliases.42.ANIME.current',
      <String, dynamic>{
        'titlesByMalId': <String, String>{'1': 'Русское название'},
        'fetchedAtByMalId': <String, String>{
          '1': DateTime(2026, 1, 1).toIso8601String(),
        },
      },
    );

    final ProviderContainer container = ProviderContainer(
      overrides: [metadataCacheStoreProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    final Map<int, String> aliases = await container.read(
      anilistRussianAliasProvider(
        AniListRussianAliasRequest(
          viewerId: 42,
          mediaType: 'ANIME',
          statusKey: 'current',
          malIds: <int>[1],
        ),
      ).future,
    );

    expect(aliases, <int, String>{1: 'Русское название'});
  });

  test('All tab aggregates cached aliases without a network load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const MetadataCacheStore cache = MetadataCacheStore();
    await cache.write(
      'anilist.russianAliases.7.ANIME.current',
      <String, dynamic>{
        'titlesByMalId': <String, String>{'11': 'Текущий тайтл'},
        'fetchedAtByMalId': <String, String>{
          '11': DateTime(2026, 1, 1).toIso8601String(),
        },
      },
    );
    await cache.write(
      'anilist.russianAliases.7.ANIME.planning',
      <String, dynamic>{
        'titlesByMalId': <String, String>{'22': 'Запланированный тайтл'},
        'fetchedAtByMalId': <String, String>{
          '22': DateTime(2026, 1, 1).toIso8601String(),
        },
      },
    );

    final ProviderContainer container = ProviderContainer(
      overrides: [metadataCacheStoreProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    final Map<int, String> aliases = await container.read(
      anilistRussianAliasProvider(
        AniListRussianAliasRequest(
          viewerId: 7,
          mediaType: 'ANIME',
          statusKey: 'all',
          malIds: <int>[11, 22],
          loadNetwork: false,
        ),
      ).future,
    );

    expect(aliases[11], 'Текущий тайтл');
    expect(aliases[22], 'Запланированный тайтл');
  });
}
