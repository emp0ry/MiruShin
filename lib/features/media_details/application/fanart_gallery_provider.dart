import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/metadata_cache_store.dart';
import '../../../shared/models/media_item.dart';
import '../../metadata/application/metadata_cache_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/data/tmdb_metadata_provider.dart';
import '../../metadata/domain/tmdb_media_identity.dart';
import '../../settings/application/settings_state.dart';
import '../data/fanart_tv_client.dart';
import '../domain/fanart_gallery.dart';

typedef ResolveAnimeTmdbIdentity =
    Future<TmdbMediaIdentity?> Function(MediaItem item);
typedef ResolveTmdbTvdbId = Future<int?> Function(int tmdbId);

class FanartIdentityResolver {
  const FanartIdentityResolver({
    this.resolveAnimeTmdbIdentity,
    this.resolveTmdbTvdbId,
  });

  final ResolveAnimeTmdbIdentity? resolveAnimeTmdbIdentity;
  final ResolveTmdbTvdbId? resolveTmdbTvdbId;

  Future<FanartIdentity?> resolve(MediaItem item) async {
    TmdbMediaIdentity? tmdb = TmdbMediaIdentity.fromMediaItem(item);
    if (tmdb == null && item.type == MediaType.anime) {
      tmdb = await resolveAnimeTmdbIdentity?.call(item);
    }
    if (tmdb == null) return null;

    if (tmdb.kind == TmdbMediaKind.movie) {
      return FanartIdentity(id: tmdb.id, kind: FanartMediaKind.movie);
    }

    final int? existingTvdb = int.tryParse(item.externalIds['tvdb'] ?? '');
    final int? tvdbId = existingTvdb != null && existingTvdb > 0
        ? existingTvdb
        : await resolveTmdbTvdbId?.call(tmdb.id);
    if (tvdbId == null || tvdbId <= 0) return null;
    return FanartIdentity(id: tvdbId, kind: FanartMediaKind.tv);
  }
}

class FanartGalleryRepository {
  FanartGalleryRepository({
    required FanartIdentityResolver identityResolver,
    required FanartTvClient client,
    required MetadataCacheStore cache,
  }) : _identityResolver = identityResolver,
       _client = client,
       _cache = cache;

  final FanartIdentityResolver _identityResolver;
  final FanartTvClient _client;
  final MetadataCacheStore _cache;
  final Map<String, Future<FanartGallery>> _requests =
      <String, Future<FanartGallery>>{};

  Future<FanartGallery> galleryFor(MediaItem item) {
    return _requests.putIfAbsent(item.id, () => _load(item));
  }

  Future<FanartGallery> _load(MediaItem item) async {
    final String cacheKey = 'fanart.gallery.v2.${item.id}';
    final Map<String, dynamic>? cached = await _cache.read(cacheKey);
    if (cached != null) {
      try {
        final FanartGallery gallery = FanartGallery.fromJson(cached);
        if (gallery.isNotEmpty) return gallery;
      } catch (_) {
        // Ignore a malformed old entry and replace it from the network.
      }
    }

    final FanartIdentity? identity = await _identityResolver.resolve(item);
    if (identity == null) return FanartGallery.empty;
    final FanartGallery gallery = await _client.fetchGallery(identity);
    if (gallery.isNotEmpty) await _cache.write(cacheKey, gallery.toJson());
    return gallery;
  }
}

class FanartGalleryRequest {
  const FanartGalleryRequest(this.item);

  final MediaItem item;

  @override
  bool operator ==(Object other) {
    return other is FanartGalleryRequest && other.item.id == item.id;
  }

  @override
  int get hashCode => item.id.hashCode;
}

final Provider<FanartTvClient?> fanartTvClientProvider =
    Provider<FanartTvClient?>((Ref ref) {
      final String apiKey = ref.watch(
        settingsProvider.select(
          (SettingsState settings) => settings.effectiveFanartTvApiKey,
        ),
      );
      if (apiKey.isEmpty) return null;
      return FanartTvClient(apiKey: apiKey);
    });

final Provider<FanartIdentityResolver> fanartIdentityResolverProvider =
    Provider<FanartIdentityResolver>((Ref ref) {
      final TmdbMetadataProvider? tmdb = ref.watch(tmdbProviderProvider);
      return FanartIdentityResolver(
        resolveAnimeTmdbIdentity: tmdb?.resolveAnimeTmdbIdentity,
        resolveTmdbTvdbId: tmdb?.tvdbIdForTmdbTv,
      );
    });

final Provider<FanartGalleryRepository?> fanartGalleryRepositoryProvider =
    Provider<FanartGalleryRepository?>((Ref ref) {
      final FanartTvClient? client = ref.watch(fanartTvClientProvider);
      if (client == null) return null;
      return FanartGalleryRepository(
        identityResolver: ref.watch(fanartIdentityResolverProvider),
        client: client,
        cache: ref.watch(metadataCacheStoreProvider),
      );
    });

final fanartGalleryProvider =
    FutureProvider.family<FanartGallery, FanartGalleryRequest>((
      Ref ref,
      FanartGalleryRequest request,
    ) async {
      final FanartGalleryRepository? repository = ref.watch(
        fanartGalleryRepositoryProvider,
      );
      if (repository == null) return FanartGallery.empty;
      try {
        return await repository.galleryFor(request.item);
      } catch (_) {
        return FanartGallery.empty;
      }
    });
