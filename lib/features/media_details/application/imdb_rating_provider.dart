import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/metadata_cache_store.dart';
import '../../../shared/models/media_item.dart';
import '../../metadata/application/metadata_cache_provider.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/data/tmdb_metadata_provider.dart';
import '../../metadata/domain/tmdb_media_identity.dart';
import '../data/imdb_ratings_client.dart';

typedef ResolveAnimeTmdbIdentity =
    Future<TmdbMediaIdentity?> Function(MediaItem item);
typedef ResolveTmdbImdbId =
    Future<String?> Function(TmdbMediaIdentity identity);

class ImdbIdentityResolver {
  const ImdbIdentityResolver({
    this.resolveAnimeTmdbIdentity,
    this.resolveTmdbImdbId,
  });

  final ResolveAnimeTmdbIdentity? resolveAnimeTmdbIdentity;
  final ResolveTmdbImdbId? resolveTmdbImdbId;

  Future<String?> resolve(MediaItem item) async {
    final String existingImdbId = (item.externalIds['imdb'] ?? '').trim();
    if (_isImdbId(existingImdbId)) return existingImdbId;
    if (item.externalIds['anilist_type'] == 'MANGA') return null;

    TmdbMediaIdentity? identity = TmdbMediaIdentity.fromMediaItem(item);
    if (identity == null && item.type == MediaType.anime) {
      identity = await resolveAnimeTmdbIdentity?.call(item);
    }
    if (identity == null) return null;

    final String? imdbId = await resolveTmdbImdbId?.call(identity);
    return _isImdbId(imdbId) ? imdbId!.trim() : null;
  }
}

class ImdbRatingRepository {
  ImdbRatingRepository({
    required ImdbIdentityResolver identityResolver,
    required ImdbRatingsClient client,
    required MetadataCacheStore cache,
  }) : _identityResolver = identityResolver,
       _client = client,
       _cache = cache;

  final ImdbIdentityResolver _identityResolver;
  final ImdbRatingsClient _client;
  final MetadataCacheStore _cache;
  final Map<String, Future<double?>> _requests = <String, Future<double?>>{};

  Future<double?> ratingFor(MediaItem item) {
    final Future<double?> request = _requests.putIfAbsent(
      item.id,
      () => _load(item),
    );
    return request.whenComplete(() {
      if (identical(_requests[item.id], request)) _requests.remove(item.id);
    });
  }

  Future<double?> _load(MediaItem item) async {
    final String identityCacheKey = 'imdb.identity.v1.${item.id}';
    final Map<String, dynamic>? cachedIdentity = await _cache.read(
      identityCacheKey,
    );
    String? imdbId = _validImdbId(cachedIdentity?['imdbId']);
    if (imdbId == null) {
      try {
        imdbId = await _identityResolver.resolve(item);
      } catch (_) {
        return null;
      }
      if (imdbId == null) return null;
      await _cache.write(identityCacheKey, <String, dynamic>{'imdbId': imdbId});
    }

    final String ratingCacheKey = 'imdb.rating.v1.$imdbId';
    final Map<String, dynamic>? cachedRating = await _cache.read(
      ratingCacheKey,
    );
    final double? rating = _validRating(cachedRating?['rating']);
    if (rating != null) {
      unawaited(_refresh(imdbId, ratingCacheKey));
      return rating;
    }
    return _refresh(imdbId, ratingCacheKey);
  }

  Future<double?> _refresh(String imdbId, String cacheKey) async {
    try {
      final double? rating = await _client.fetchRating(imdbId);
      if (rating != null) {
        await _cache.write(cacheKey, <String, dynamic>{'rating': rating});
      }
      return rating;
    } catch (_) {
      return null;
    }
  }
}

class ImdbRatingRequest {
  const ImdbRatingRequest(this.item);

  final MediaItem item;

  @override
  bool operator ==(Object other) {
    return other is ImdbRatingRequest && other.item.id == item.id;
  }

  @override
  int get hashCode => item.id.hashCode;
}

final Provider<ImdbRatingsClient> imdbRatingsClientProvider =
    Provider<ImdbRatingsClient>((Ref ref) => ImdbRatingsClient());

final Provider<ImdbRatingRepository?> imdbRatingRepositoryProvider =
    Provider<ImdbRatingRepository?>((Ref ref) {
      final TmdbMetadataProvider? tmdb = ref.watch(tmdbProviderProvider);
      if (tmdb == null) return null;
      return ImdbRatingRepository(
        identityResolver: ImdbIdentityResolver(
          resolveAnimeTmdbIdentity: tmdb.resolveAnimeTmdbIdentity,
          resolveTmdbImdbId: tmdb.imdbIdForTmdbMedia,
        ),
        client: ref.watch(imdbRatingsClientProvider),
        cache: ref.watch(metadataCacheStoreProvider),
      );
    });

final imdbRatingProvider = FutureProvider.family<double?, ImdbRatingRequest>((
  Ref ref,
  ImdbRatingRequest request,
) async {
  final ImdbRatingRepository? repository = ref.watch(
    imdbRatingRepositoryProvider,
  );
  if (repository == null) return null;
  return repository.ratingFor(request.item);
});

bool _isImdbId(String? value) {
  return value != null && RegExp(r'^tt\d+$').hasMatch(value.trim());
}

String? _validImdbId(Object? value) {
  return value is String && _isImdbId(value) ? value.trim() : null;
}

double? _validRating(Object? value) {
  final double? rating = switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };
  return rating != null && rating > 0 && rating <= 10 ? rating : null;
}
