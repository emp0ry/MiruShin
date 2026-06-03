import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/cache/metadata_cache_store.dart';
import 'package:mirushin/features/metadata/application/metadata_providers.dart';
import 'package:mirushin/features/metadata/domain/anime_episode_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads cached episode metadata without network loading', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const MetadataCacheStore cache = MetadataCacheStore();
    await cache.write('anilist.episodeMetadata.123.en', <String, dynamic>{
      'anilistId': 123,
      'languageCode': 'en',
      'episodes': <String, dynamic>{
        '1': <String, dynamic>{
          'aniZipImage': 'https://example.test/one.jpg',
          'aniZipTitle': 'Cached episode',
          'aniListThumbnail': '',
          'aniListTitle': '',
          'tvdbTitle': '',
        },
      },
    });

    final ProviderContainer container = ProviderContainer(
      overrides: [metadataCacheStoreProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    final AnimeEpisodeMetadataBundle bundle = await container.read(
      animeEpisodeMetadataProvider(
        const AnimeEpisodeMetadataRequest(
          anilistId: 123,
          languageCode: 'en',
          loadNetwork: false,
        ),
      ).future,
    );

    expect(bundle.forNumber(1)?.aniZipTitle, 'Cached episode');
    expect(bundle.forNumber(1)?.aniZipImage, 'https://example.test/one.jpg');
  });
}
