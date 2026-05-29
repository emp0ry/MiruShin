import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/media_item.dart';
import '../../settings/presentation/settings_state.dart';
import '../data/anilist_api_client.dart';
import 'anilist_library_provider.dart';

final anilistFavoriteProvider =
    NotifierProvider<AniListFavoriteController, Map<int, bool>>(
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

class AniListFavoriteController extends Notifier<Map<int, bool>> {
  @override
  Map<int, bool> build() => const <int, bool>{};

  Future<void> toggle({
    required int mediaId,
    required bool isManga,
    required bool current,
  }) async {
    final bool next = !current;
    state = <int, bool>{...state, mediaId: next};

    final SettingsState settings = ref.read(settingsProvider);
    final String token = settings.anilistAccessToken.trim();
    try {
      await AniListApiClient(
        accessToken: token,
      ).toggleFavouriteMedia(mediaId: mediaId, isManga: isManga);
      // Keep the optimistic value (next). Do not re-read from the API here —
      // AniList often returns the pre-toggle state immediately after the
      // mutation, which would silently revert the visual update.
      if (isManga) {
        invalidateAniListMangaLibraryProviders(ref.invalidate);
      } else {
        invalidateAniListAnimeLibraryProviders(ref.invalidate);
      }
      ref.invalidate(anilistMediaFavoriteStatusProvider(mediaId));
    } catch (_) {
      state = <int, bool>{...state, mediaId: current};
      rethrow;
    }
  }
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
