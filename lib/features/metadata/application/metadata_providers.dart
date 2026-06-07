import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/metadata_cache_store.dart';
import '../../../shared/models/media_item.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../catalog/application/catalog_repository.dart';
import '../../catalog/application/catalog_status.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../../settings/presentation/settings_state.dart';
import '../data/anime_episode_metadata_client.dart';
import '../data/shikimori_client.dart';
import '../data/tmdb_metadata_provider.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../domain/anime_episode_metadata.dart';
import '../domain/metadata_provider.dart';
import 'media_catalog.dart';

export 'media_catalog.dart' show BoardRails, MediaCatalog;

// ─── TMDB (primary) ──────────────────────────────────────────────────────────

final tmdbProviderProvider = Provider<TmdbMetadataProvider?>((Ref ref) {
  final SettingsState settings = ref.watch(settingsProvider);
  if (!settings.tmdbEnabled || settings.tmdbReadAccessToken.trim().isEmpty) {
    return null;
  }
  return TmdbMetadataProvider(
    readAccessToken: settings.tmdbReadAccessToken,
    language: settings.effectiveTmdbLanguage,
    region: settings.tmdbRegion,
  );
});

// ─── Shikimori ───────────────────────────────────────────────────────────────

final _shikimoriClientProvider = Provider<ShikiMoriClient>(
  (Ref ref) => ShikiMoriClient(),
);

// ─── AniList ─────────────────────────────────────────────────────────────────

final anilistApiClientProvider = Provider<AniListApiClient>((Ref ref) {
  final SettingsState settings = ref.watch(settingsProvider);
  final String token = settings.anilistAccessToken.trim();
  return AniListApiClient(
    accessToken: token.isEmpty ? null : token,
    titleLanguage: ref.watch(aniListEffectiveTitleLanguageProvider),
    showAdultContent: ref.watch(aniListEffectiveAdultContentProvider),
    shikimori: ref.watch(_shikimoriClientProvider),
  );
});

final _animeEpisodeMetadataClientProvider =
    Provider<AnimeEpisodeMetadataClient>(
      (Ref ref) => AnimeEpisodeMetadataClient(),
    );

// ─── Catalog Mode Routing ────────────────────────────────────────────────────

final mediaCatalogProvider = Provider<MediaCatalog?>((Ref ref) {
  final TmdbMetadataProvider? tmdb = ref.watch(tmdbProviderProvider);
  if (tmdb == null) return null;
  return MediaCatalog(tmdb: tmdb);
});

final activeCatalogRepositoryProvider = Provider<CatalogRepository?>((Ref ref) {
  final MetadataCacheStore cache = ref.watch(metadataCacheStoreProvider);
  final SettingsState settings = ref.watch(settingsProvider);
  final CatalogMode mode = ref.watch(catalogModeProvider);
  final String aniListTitleLanguage = ref.watch(
    aniListEffectiveTitleLanguageProvider,
  );
  final bool aniListAdultContent = ref.watch(
    aniListEffectiveAdultContentProvider,
  );
  CatalogOfflineCallback offlineCallback(CatalogMode mode, String sourceName) {
    return (
      Object error, {
      required String operation,
      required bool usingCache,
    }) {
      markCatalogOffline(
        ref,
        mode: mode,
        sourceName: sourceName,
        operation: operation,
        usingCache: usingCache,
        error: error,
      );
    };
  }

  CatalogOnlineCallback onlineCallback(CatalogMode mode) {
    return ({required String operation}) {
      markCatalogOnline(ref, mode);
    };
  }

  return switch (mode) {
    CatalogMode.tmdb => switch (ref.watch(tmdbProviderProvider)) {
      final TmdbMetadataProvider tmdb => TmdbCatalogRepository(
        tmdb: tmdb,
        cache: cache,
        cacheScope:
            'tmdb.${settings.effectiveTmdbLanguage}.${settings.tmdbRegion}',
        onOffline: offlineCallback(CatalogMode.tmdb, 'TMDB'),
        onOnline: onlineCallback(CatalogMode.tmdb),
      ),
      null => null,
    },
    CatalogMode.anilist => AniListCatalogRepository(
      client: ref.watch(anilistApiClientProvider),
      cache: cache,
      cacheScope:
          'anilist.$aniListTitleLanguage.${aniListAdultContent ? 'adult' : 'safe'}',
      tmdb: ref.watch(tmdbProviderProvider),
      viewerId: settings.anilistViewerId,
      hasAccessToken: settings.anilistAccessToken.trim().isNotEmpty,
      onOffline: offlineCallback(CatalogMode.anilist, 'AniList'),
      onOnline: onlineCallback(CatalogMode.anilist),
    ),
  };
});

// ─── MetadataRepository (search + details) ───────────────────────────────────

final metadataRepositoryProvider = Provider<MetadataRepository>((Ref ref) {
  final TmdbMetadataProvider? tmdb = ref.watch(tmdbProviderProvider);
  return MetadataRepository(providers: <MetadataProvider>[?tmdb]);
});

// ─── Riverpod FutureProviders consumed by UI ─────────────────────────────────

final boardRailsProvider = FutureProvider<BoardRails>((Ref ref) async {
  final CatalogRepository? catalog = ref.watch(activeCatalogRepositoryProvider);
  if (catalog == null) return BoardRails.empty();
  try {
    return catalog.boardRails();
  } catch (_) {
    return BoardRails.empty();
  }
});

final discoveryMetadataProvider =
    FutureProvider.family<List<MediaItem>, DiscoveryMetadataQuery>((
      Ref ref,
      DiscoveryMetadataQuery query,
    ) async {
      final CatalogRepository? repository = ref.watch(
        activeCatalogRepositoryProvider,
      );
      if (repository == null) return const <MediaItem>[];
      try {
        return repository.discover(
          search: query.search,
          type: query.type,
          filter: query.filter,
          page: query.page,
          anilistKind: query.anilistKind,
        );
      } catch (_) {
        return const <MediaItem>[];
      }
    });

final mediaDetailsProvider = FutureProvider.family<MediaItem?, String>((
  Ref ref,
  String id,
) async {
  final CatalogMode mode = ref.watch(catalogModeProvider);
  if (!mediaIdBelongsToMode(id, mode)) return null;
  final CatalogRepository? repository = ref.watch(
    activeCatalogRepositoryProvider,
  );
  if (repository == null) return null;
  try {
    return repository.details(id);
  } catch (_) {
    return null;
  }
});

final animeEpisodeMetadataProvider =
    FutureProvider.family<
      AnimeEpisodeMetadataBundle,
      AnimeEpisodeMetadataRequest
    >((Ref ref, AnimeEpisodeMetadataRequest request) async {
      if (request.anilistId <= 0) return AnimeEpisodeMetadataBundle.empty;
      final MetadataCacheStore cache = ref.watch(metadataCacheStoreProvider);
      final String cacheKey =
          'anilist.episodeMetadata.${request.anilistId}.${request.languageCode}';
      final Map<String, dynamic>? cached = await cache.read(cacheKey);
      if (cached != null) return _episodeMetadataFromJson(cached);
      if (!request.loadNetwork) return AnimeEpisodeMetadataBundle.empty;

      final AnimeEpisodeMetadataBundle bundle = await ref
          .watch(_animeEpisodeMetadataClientProvider)
          .fetch(
            anilistId: request.anilistId,
            languageCode: request.languageCode,
          );
      if (!bundle.isEmpty) {
        await cache.write(cacheKey, _episodeMetadataToJson(bundle));
      }
      return bundle;
    });

class AnimeEpisodeMetadataRequest {
  const AnimeEpisodeMetadataRequest({
    required this.anilistId,
    required this.languageCode,
    this.loadNetwork = true,
  });

  final int anilistId;
  final String languageCode;
  final bool loadNetwork;

  @override
  bool operator ==(Object other) {
    return other is AnimeEpisodeMetadataRequest &&
        other.anilistId == anilistId &&
        other.languageCode == languageCode &&
        other.loadNetwork == loadNetwork;
  }

  @override
  int get hashCode => Object.hash(anilistId, languageCode, loadNetwork);
}

class DiscoveryMetadataQuery {
  const DiscoveryMetadataQuery({
    required this.search,
    required this.type,
    this.filter = 'Trending',
    this.page = 1,
    this.anilistKind,
  });

  final String search;
  final MediaType? type;
  final String filter;
  final int page;
  final String? anilistKind;

  @override
  bool operator ==(Object other) {
    return other is DiscoveryMetadataQuery &&
        other.search == search &&
        other.type == type &&
        other.filter == filter &&
        other.page == page &&
        other.anilistKind == anilistKind;
  }

  @override
  int get hashCode => Object.hash(search, type, filter, page, anilistKind);
}

Map<String, dynamic> _episodeMetadataToJson(AnimeEpisodeMetadataBundle bundle) {
  return <String, dynamic>{
    'anilistId': bundle.anilistId,
    'languageCode': bundle.languageCode,
    'episodes': bundle.episodes.map(
      (int number, AnimeEpisodeMetadata metadata) =>
          MapEntry<String, dynamic>(number.toString(), <String, dynamic>{
            'aniZipImage': metadata.aniZipImage,
            'aniZipTitle': metadata.aniZipTitle,
            'aniListThumbnail': metadata.aniListThumbnail,
            'aniListTitle': metadata.aniListTitle,
            'tvdbTitle': metadata.tvdbTitle,
          }),
    ),
  };
}

AnimeEpisodeMetadataBundle _episodeMetadataFromJson(Map<String, dynamic> json) {
  final Object? episodes = json['episodes'];
  final Map<int, AnimeEpisodeMetadata> parsed = <int, AnimeEpisodeMetadata>{};
  if (episodes is Map) {
    episodes.forEach((Object? key, Object? value) {
      final int? number = int.tryParse(key.toString());
      if (number == null || value is! Map) return;
      parsed[number] = AnimeEpisodeMetadata(
        aniZipImage: value['aniZipImage']?.toString() ?? '',
        aniZipTitle: value['aniZipTitle']?.toString() ?? '',
        aniListThumbnail: value['aniListThumbnail']?.toString() ?? '',
        aniListTitle: value['aniListTitle']?.toString() ?? '',
        tvdbTitle: value['tvdbTitle']?.toString() ?? '',
      );
    });
  }
  return AnimeEpisodeMetadataBundle(
    anilistId: int.tryParse(json['anilistId']?.toString() ?? '') ?? 0,
    languageCode: json['languageCode']?.toString() ?? '',
    episodes: Map<int, AnimeEpisodeMetadata>.unmodifiable(parsed),
  );
}
