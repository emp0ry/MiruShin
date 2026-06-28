import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/profile/presentation/profile_page.dart';
import 'app_routes.dart';
import '../core/responsive/responsive_scaffold.dart';
import '../features/addons/presentation/addons_page.dart';
import '../features/addons/presentation/sources_page.dart';
import '../features/board/presentation/board_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/discovery/presentation/discovery_page.dart';
import '../features/downloads/presentation/offline_title_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/media_details/presentation/media_details_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/player/domain/player_models.dart';
import '../features/player/presentation/player_page.dart';
import '../features/watch/domain/normalized_models.dart';
import '../features/watch/presentation/watch_page.dart';
import '../shared/models/media_item.dart';

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
          _playerPage(state),
    ),
    ShellRoute(
      builder: (BuildContext context, GoRouterState state, Widget child) {
        final String currentLocation = state.uri.path;
        return ResponsiveScaffold(
          currentLocation: currentLocation,
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
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const BoardPage()),
        ),
        GoRoute(
          path: AppRoutes.discovery,
          pageBuilder: (BuildContext context, GoRouterState state) => _fadePage(
            state,
            DiscoveryPage(
              initialType: _mediaTypeFromQuery(
                state.uri.queryParameters['type'],
              ),
              initialFilter: state.uri.queryParameters['filter'],
              initialAniListKind: state.uri.queryParameters['kind'],
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.library,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const LibraryPage()),
        ),
        GoRoute(
          path: AppRoutes.calendar,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const CalendarPage()),
        ),
        GoRoute(
          path: AppRoutes.addons,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const AddonsPage()),
        ),
        GoRoute(
          path: AppRoutes.addonsSources,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const SourcesPage()),
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const SettingsPage()),
        ),
        GoRoute(
          path: AppRoutes.profile,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfilePage()),
        ),
        GoRoute(
          path: AppRoutes.profileActivities,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileActivitiesPage()),
        ),
        GoRoute(
          path: AppRoutes.profileFavourites,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileFavouritesPage()),
        ),
        GoRoute(
          path: AppRoutes.profileFeed,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileFeedPage()),
        ),
        GoRoute(
          path: AppRoutes.profileSocial,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileSocialPage()),
        ),
        GoRoute(
          path: AppRoutes.profileStatistics,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileStatisticsPage()),
        ),
        GoRoute(
          path: AppRoutes.profileReviews,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileReviewsPage()),
        ),
        GoRoute(
          path: AppRoutes.profileSettings,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              _fadePage(state, const ProfileAniListSettingsPage()),
        ),
        GoRoute(
          path: AppRoutes.profileUser,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final int userId =
                int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return _fadePage(state, ProfileUserPage(userId: userId));
          },
        ),
        GoRoute(
          path: AppRoutes.mediaDetails,
          pageBuilder: (BuildContext context, GoRouterState state) {
            final String id = Uri.decodeComponent(
              state.pathParameters['id'] ?? '',
            );
            return _fadePage(
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
            return _fadePage(
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
            return _fadePage(
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

CustomTransitionPage<void> _playerPage(GoRouterState state) {
  if (state.extra is MediaPlaybackItem) {
    return _fadePage(
      state,
      PlayerPage(item: state.extra! as MediaPlaybackItem),
    );
  }
  final PlayerRouteArgs? args = state.extra is PlayerRouteArgs
      ? state.extra! as PlayerRouteArgs
      : null;
  if (args == null) return _fadePage(state, const SizedBox.shrink());
  final MediaPlaybackItem item = MediaPlaybackItem.fromBundle(
    args.bundle,
    args.item,
    args.seasonNumber,
    startPosition: args.startPosition,
    ignoreProgress: args.ignoreProgress,
    seasons: args.episodeSeasons,
  );
  return _fadePage(
    state,
    PlayerPage(item: item, startInFullscreen: args.startInFullscreen),
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

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
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
  });

  final NormalizedStreamBundle bundle;
  final MediaItem item;
  final int seasonNumber;
  final bool startInFullscreen;
  final Duration startPosition;
  final bool ignoreProgress;

  /// Full episode list (grouped into seasons) for the in-player Episodes sheet,
  /// so the user can jump to any episode without leaving the player.
  final List<Season> episodeSeasons;
}
