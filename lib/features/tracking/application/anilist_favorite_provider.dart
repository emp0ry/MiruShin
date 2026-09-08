import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/media_item.dart';
import '../../settings/application/settings_state.dart';
import '../data/anilist_api_client.dart';
import '../domain/tracking_sync_models.dart';
import 'anilist_library_provider.dart';
import 'tracker_sync_coordinator.dart';

final anilistFavoriteProvider =
    NotifierProvider<AniListFavoriteController, Map<String, bool>>(
      AniListFavoriteController.new,
    );

final anilistMediaFavoriteStatusProvider = FutureProvider.autoDispose
    .family<bool?, int>((Ref ref, int mediaId) async {
      final SettingsState settings = ref.watch(settingsProvider);
      final String token = settings.anilistAccessToken.trim();
      if (token.isEmpty) return null;
      return AniListApiClient(
        accessToken: token,
      ).fetchMediaFavouriteStatus(mediaId);
    });

class AniListFavoriteController extends Notifier<Map<String, bool>> {
  bool _loadingPersisted = false;

  @override
  Map<String, bool> build() {
    if (!_loadingPersisted) {
      _loadingPersisted = true;
      unawaited(_loadPersisted());
    }
    return const <String, bool>{};
  }

  Future<void> _loadPersisted() async {
    final List<LocalMediaFavoriteState> favorites = await ref
        .read(trackingSyncStoreProvider)
        .loadFavorites();
    state = <String, bool>{
      for (final LocalMediaFavoriteState favorite in favorites)
        for (final String key in favoriteIdentityKeys(favorite.identity))
          key: favorite.favorite,
      ...state,
    };
  }

  Future<void> toggle({required MediaItem item, required bool current}) async {
    final MediaIdentity identity = MediaIdentity.fromExternalIds(
      item.externalIds,
      mediaId: item.id,
    );
    final bool next = !current;
    final Map<String, bool> previous = state;
    state = <String, bool>{
      ...state,
      for (final String key in favoriteIdentityKeys(identity)) key: next,
    };

    try {
      await ref
          .read(trackerSyncCoordinatorProvider)
          .pushFavorite(mediaItem: item, favorite: next);
      // Keep the local desired value while an offline AniList delivery is
      // pending. The adapter checks server state before toggling, so replay is
      // idempotent even if the first response was lost.
      final bool isManga = isAniListMangaItem(item);
      if (isManga) {
        invalidateAniListMangaLibraryProviders(ref.invalidate);
      } else {
        invalidateAniListAnimeLibraryProviders(ref.invalidate);
      }
      final int? mediaId = aniListMediaIdOf(item);
      if (mediaId != null) {
        ref.invalidate(anilistMediaFavoriteStatusProvider(mediaId));
      }
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

Iterable<String> favoriteIdentityKeys(MediaIdentity identity) sync* {
  yield identity.localId;
  if (identity.anilistId != null) yield 'anilist:${identity.anilistId}';
  if (identity.malId != null) yield 'mal:${identity.malId}';
  if (identity.shikimoriId != null) {
    yield 'shikimori:${identity.shikimoriId}';
  }
}

bool? localFavoriteFor(Map<String, bool> favorites, MediaIdentity identity) {
  for (final String key in favoriteIdentityKeys(identity)) {
    final bool? value = favorites[key];
    if (value != null) return value;
  }
  return null;
}

int? aniListMediaIdOf(MediaItem item) {
  final String? externalId = item.externalIds['anilist'];
  final int? parsedExternal = int.tryParse(externalId ?? '');
  if (parsedExternal != null) return parsedExternal;

  final List<String> parts = item.id.split(':');
  if (parts.length >= 2 && parts.first == 'anilist') {
    return int.tryParse(parts.last);
  }
  return null;
}

bool isAniListMangaItem(MediaItem item) {
  return item.externalIds['anilist_type'] == 'MANGA' ||
      item.id.toLowerCase().startsWith('anilist:manga:');
}

bool aniListItemIsFavourite(MediaItem item) {
  return item.externalIds['anilist_is_favourite'] == 'true';
}
