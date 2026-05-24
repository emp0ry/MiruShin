import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/media_item.dart';
import '../../metadata/data/shikimori_client.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../domain/anilist_profile_models.dart';
import 'anilist_user_settings_provider.dart';

final aniListSignedInProvider = Provider<bool>((Ref ref) {
  return ref.watch(
    settingsProvider.select(
      (SettingsState settings) => settings.hasAniListSession,
    ),
  );
});

final aniListViewerIdProvider = Provider<int?>((Ref ref) {
  return ref.watch(
    settingsProvider.select(
      (SettingsState settings) => settings.anilistViewerId,
    ),
  );
});

final aniListProfileClientProvider = Provider<AniListApiClient>((Ref ref) {
  final SettingsState settings = ref.watch(settingsProvider);
  final String token = settings.anilistAccessToken.trim();
  return AniListApiClient(
    accessToken: token.isEmpty ? null : token,
    titleLanguage: ref.watch(aniListEffectiveTitleLanguageProvider),
    showAdultContent: ref.watch(aniListEffectiveAdultContentProvider),
    shikimori: ShikiMoriClient(),
  );
});

final aniListViewerProfileProvider = FutureProvider<AniListUserProfile?>((
  Ref ref,
) async {
  final bool signedIn = ref.watch(aniListSignedInProvider);
  final int? viewerId = ref.watch(aniListViewerIdProvider);
  if (!signedIn || viewerId == null) return null;
  return ref
      .watch(aniListProfileClientProvider)
      .fetchUserProfile(userId: viewerId);
});

final aniListUserProfileProvider =
    FutureProvider.family<AniListUserProfile?, int>((
      Ref ref,
      int userId,
    ) async {
      final bool signedIn = ref.watch(aniListSignedInProvider);
      if (!signedIn) return null;
      return ref
          .watch(aniListProfileClientProvider)
          .fetchUserProfile(userId: userId);
    });

final aniListActivitiesProvider =
    FutureProvider.family<
      AniListPagedChunk<AniListActivity>,
      AniListActivitiesQuery
    >((Ref ref, AniListActivitiesQuery query) async {
      return ref
          .watch(aniListProfileClientProvider)
          .fetchActivities(
            userId: query.userId,
            userIdNot: query.userIdNot,
            isFollowing: query.isFollowing,
            hasRepliesOrText: query.hasRepliesOrText,
            typeIn: query.typeIn,
            page: query.page,
          );
    });

final aniListFavouritesProvider =
    FutureProvider.family<AniListPagedChunk<MediaItem>, AniListFavouriteQuery>((
      Ref ref,
      AniListFavouriteQuery query,
    ) async {
      return ref
          .watch(aniListProfileClientProvider)
          .fetchFavouritePage(
            userId: query.userId,
            kind: query.kind,
            page: query.page,
          );
    });

final aniListSocialUsersProvider =
    FutureProvider.family<
      AniListPagedChunk<AniListUserSnippet>,
      AniListSocialUsersQuery
    >((Ref ref, AniListSocialUsersQuery query) async {
      return ref
          .watch(aniListProfileClientProvider)
          .fetchSocialUsers(
            userId: query.userId,
            following: query.following,
            page: query.page,
          );
    });

final aniListReviewsProvider =
    FutureProvider.family<
      AniListPagedChunk<AniListReviewItem>,
      AniListReviewsQuery
    >((Ref ref, AniListReviewsQuery query) async {
      return ref
          .watch(aniListProfileClientProvider)
          .fetchUserReviews(
            userId: query.userId,
            page: query.page,
            mediaType: query.mediaType,
            sort: query.sort,
          );
    });

final aniListSocialThreadsProvider =
    FutureProvider.family<
      AniListPagedChunk<AniListForumThread>,
      AniListSocialContentQuery
    >((Ref ref, AniListSocialContentQuery query) async {
      return ref
          .watch(aniListProfileClientProvider)
          .fetchSocialThreads(userId: query.userId, page: query.page);
    });

final aniListSocialCommentsProvider =
    FutureProvider.family<
      AniListPagedChunk<AniListForumComment>,
      AniListSocialContentQuery
    >((Ref ref, AniListSocialContentQuery query) async {
      return ref
          .watch(aniListProfileClientProvider)
          .fetchSocialComments(userId: query.userId, page: query.page);
    });

class AniListActivitiesQuery {
  const AniListActivitiesQuery({
    this.userId,
    this.userIdNot,
    this.isFollowing,
    this.hasRepliesOrText = true,
    this.typeIn,
    this.page = 1,
  });

  final int? userId;
  final int? userIdNot;
  final bool? isFollowing;
  final bool hasRepliesOrText;
  final List<String>? typeIn;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is AniListActivitiesQuery &&
        other.userId == userId &&
        other.userIdNot == userIdNot &&
        other.isFollowing == isFollowing &&
        other.hasRepliesOrText == hasRepliesOrText &&
        other.page == page &&
        _listEquals(other.typeIn, typeIn);
  }

  @override
  int get hashCode => Object.hash(
    userId,
    userIdNot,
    isFollowing,
    hasRepliesOrText,
    page,
    Object.hashAll(typeIn ?? const <String>[]),
  );
}

class AniListFavouriteQuery {
  const AniListFavouriteQuery({
    required this.userId,
    required this.kind,
    this.page = 1,
  });

  final int userId;
  final AniListFavouriteKind kind;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is AniListFavouriteQuery &&
        other.userId == userId &&
        other.kind == kind &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(userId, kind, page);
}

class AniListSocialUsersQuery {
  const AniListSocialUsersQuery({
    required this.userId,
    required this.following,
    this.page = 1,
  });

  final int userId;
  final bool following;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is AniListSocialUsersQuery &&
        other.userId == userId &&
        other.following == following &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(userId, following, page);
}

class AniListReviewsQuery {
  const AniListReviewsQuery({
    required this.userId,
    this.page = 1,
    this.mediaType,
    this.sort = 'CREATED_AT_DESC',
  });

  final int userId;
  final int page;
  final String? mediaType;
  final String sort;

  @override
  bool operator ==(Object other) {
    return other is AniListReviewsQuery &&
        other.userId == userId &&
        other.page == page &&
        other.mediaType == mediaType &&
        other.sort == sort;
  }

  @override
  int get hashCode => Object.hash(userId, page, mediaType, sort);
}

class AniListSocialContentQuery {
  const AniListSocialContentQuery({required this.userId, this.page = 1});

  final int userId;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is AniListSocialContentQuery &&
        other.userId == userId &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(userId, page);
}

bool _listEquals(List<String>? left, List<String>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return left == right;
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
