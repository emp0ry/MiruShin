import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/responsive/responsive_scaffold.dart';
import '../features/addons/presentation/addons_page.dart';
import '../features/addons/presentation/sources_page.dart';
import '../features/board/presentation/board_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/discovery/presentation/discovery_page.dart';
import '../features/downloads/presentation/offline_title_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/media_details/presentation/media_details_page.dart';
import '../features/player/domain/player_models.dart';
import '../features/player/presentation/player_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/startup_update_popup.dart';
import '../features/watch/domain/normalized_models.dart';
import '../features/watch/presentation/watch_page.dart';
import '../features/watch_party/presentation/create_room_screen.dart';
import '../features/watch_party/presentation/join_room_screen.dart';
import '../features/watch_party/presentation/watch_party_screen.dart';
import '../shared/models/media_item.dart';
import 'app_routes.dart';
import 'navigation/app_page_transition.dart';
import 'theme/app_animations.dart';

/// Root navigator key, so context-less services (e.g. the Cloudflare challenge
/// solver) can push full-screen pages over the whole app.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter buildAppRouter(String initialLocation) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      redirect: (BuildContext context, GoRouterState state) => AppRoutes.board,
    ),
    GoRoute(
      path: AppRoutes.watchPlay,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _playerPage(context, state),
    ),
    GoRoute(
      path: AppRoutes.watchParty,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _appPage(context, state, const WatchPartyScreen()),
    ),
    GoRoute(
      path: AppRoutes.watchPartyCreate,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _appPage(context, state, const CreateRoomScreen()),
    ),
    GoRoute(
      path: AppRoutes.watchPartyJoin,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          _appPage(context, state, const JoinRoomScreen()),
    ),
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) {
        final String currentLocation = state.uri.path;
        return ResponsiveScaffold(
          currentLocation: currentLocation,
          topOverlay: const StartupUpdatePopup(),
          onDestinationSelected: (String location) {
            if (currentLocation != location) {
              context.go(location);
            }
          },
          child: child,
        );
      },
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.board,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            const BoardPage(),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.discovery,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            DiscoveryPage(
              initialType: _mediaTypeFromQuery(
                state.uri.queryParameters['type'],
              ),
              initialFilter: state.uri.queryParameters['filter'],
              initialAniListKind: state.uri.queryParameters['kind'],
            ),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.library,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            const LibraryPage(),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.calendar,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            const CalendarPage(),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.addons,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            const AddonsPage(),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.addonsSources,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const SourcesPage()),
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            const SettingsPage(),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: (BuildContext context, GoRouterState state) => _appPage(
            context,
            state,
            const ProfilePage(),
            motion: AppPageMotion.fadeThrough,
          ),
        ),
        GoRoute(
          path: AppRoutes.profileActivities,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileActivitiesPage()),
        ),
        GoRoute(
          path: AppRoutes.profileFavourites,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileFavouritesPage()),
        ),
        GoRoute(
          path: AppRoutes.profileFeed,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileFeedPage()),
        ),
        GoRoute(
          path: AppRoutes.profileSocial,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileSocialPage()),
        ),
        GoRoute(
          path: AppRoutes.profileStatistics,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileStatisticsPage()),
        ),
        GoRoute(
          path: AppRoutes.profileReviews,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileReviewsPage()),
        ),
        GoRoute(
          path: AppRoutes.profileSettings,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _appPage(context, state, const ProfileAniListSettingsPage()),
        ),
        GoRoute(
          path: AppRoutes.profileUser,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final int userId =
                int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return _appPage(context, state, ProfileUserPage(userId: userId));
          },
        ),
        GoRoute(
          path: AppRoutes.mediaDetails,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final String id = Uri.decodeComponent(
              state.pathParameters['id'] ?? '',
            );
            return _appPage(
              context,
              state,
              MediaDetailsPage(
                id: id,
                initialItem: state.extra is MediaItem
                    ? state.extra! as MediaItem
                    : null,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.watch,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final String id = Uri.decodeComponent(
              state.pathParameters['id'] ?? '',
            );
            return _appPage(
              context,
              state,
              WatchPage(
                id: id,
                initialItem: state.extra is MediaItem
                    ? state.extra! as MediaItem
                    : null,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.offlineTitle,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final String id = Uri.decodeComponent(
              state.pathParameters['id'] ?? '',
            );
            return _appPage(
              context,
              state,
              OfflineTitlePage(
                mediaId: id,
                initialAddonId: state.uri.queryParameters['addon'],
              ),
            );
          },
        ),
      ],
    ),
  ],
);

CustomTransitionPage<void> _playerPage(
  BuildContext context,
  GoRouterState state,
) {
  if (state.extra is DirectPlayerRouteArgs) {
    final DirectPlayerRouteArgs args = state.extra! as DirectPlayerRouteArgs;
    return _appPage(
      context,
      state,
      PlayerPage.fromDirectRouteArgs(args),
      motion: AppPageMotion.immersiveFade,
    );
  }
  if (state.extra is MediaPlaybackItem) {
    return _appPage(
      context,
      state,
      PlayerPage(item: state.extra! as MediaPlaybackItem),
      motion: AppPageMotion.immersiveFade,
    );
  }
  final PlayerRouteArgs? args = state.extra is PlayerRouteArgs
      ? state.extra! as PlayerRouteArgs
      : null;
  if (args == null) {
    return _appPage(
      context,
      state,
      const SizedBox.shrink(),
      motion: AppPageMotion.immersiveFade,
    );
  }
  final MediaPlaybackItem item = MediaPlaybackItem.fromBundle(
    args.bundle,
    args.item,
    args.seasonNumber,
    startPosition: args.startPosition,
    ignoreProgress: args.ignoreProgress,
    seasons: args.episodeSeasons,
    initialQualityId: args.initialQualityId,
  );
  return _appPage(
    context,
    state,
    PlayerPage(item: item, startInFullscreen: args.startInFullscreen),
    motion: AppPageMotion.immersiveFade,
  );
}

MediaType? _mediaTypeFromQuery(String? value) {
  if (value == null || value.isEmpty) return null;
  for (final MediaType type in MediaType.values) {
    if (type.name == value) {
      return type;
    }
  }
  return null;
}

CustomTransitionPage<void> _appPage(
  BuildContext context,
  GoRouterState state,
  Widget child, {
  AppPageMotion motion = AppPageMotion.sharedAxis,
}) {
  final bool reduceMotion = AppAnimations.reduceMotion(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: reduceMotion ? Duration.zero : AppAnimations.page,
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : AppAnimations.pageReverse,
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          return AppPageTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            motion: motion,
            child: child,
          );
        },
  );
}

class PlayerRouteArgs {
  const PlayerRouteArgs({
    required this.bundle,
    required this.item,
    required this.seasonNumber,
    this.startInFullscreen = false,
    this.startPosition = Duration.zero,
    this.ignoreProgress = false,
    this.episodeSeasons = const <Season>[],
    this.initialQualityId,
  });

  final NormalizedStreamBundle bundle;
  final MediaItem item;
  final int seasonNumber;
  final bool startInFullscreen;
  final Duration startPosition;
  final bool ignoreProgress;

  /// Quality the user explicitly chose in the stream sheet, honored over the
  /// saved global preference. Null for auto-play / auto-next.
  final String? initialQualityId;

  /// Full episode list (grouped into seasons) for the in-player Episodes sheet,
  /// so the user can jump to any episode without leaving the player.
  final List<Season> episodeSeasons;
}
