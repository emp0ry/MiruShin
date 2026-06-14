import 'package:flutter/material.dart';

import '../core/responsive/app_navigation_item.dart';
import '../features/catalog/application/catalog_mode.dart';
import '../shared/models/media_item.dart';

abstract final class AppRoutes {
  static const String board = '/board';
  static const String discovery = '/discovery';
  static const String library = '/library';
  static const String calendar = '/calendar';
  static const String addons = '/addons';
  static const String addonsSources = '/addons/sources';
  static const String profile = '/profile';
  static const String profileActivities = '/profile/activities';
  static const String profileFavourites = '/profile/favourites';
  static const String profileFeed = '/profile/feed';
  static const String profileSocial = '/profile/social';
  static const String profileStatistics = '/profile/statistics';
  static const String profileReviews = '/profile/reviews';
  static const String profileSettings = '/profile/settings';
  static const String profileUser = '/profile/user/:id';
  static const String settings = '/settings';
  static const String mediaDetails = '/media/:id';
  static const String watch = '/watch/:id';
  static const String watchPlay = '/watch/play';

  static String discoveryPath({
    MediaType? type,
    String? filter,
    String? anilistKind,
  }) {
    final Map<String, String> queryParameters = <String, String>{
      if (type != null) 'type': type.name,
      if (filter != null && filter.trim().isNotEmpty) 'filter': filter,
      if (anilistKind != null && anilistKind.trim().isNotEmpty)
        'kind': anilistKind,
    };
    return Uri(
      path: discovery,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }

  static String mediaDetailsPath(String id) {
    return '/media/${Uri.encodeComponent(id)}';
  }

  static String profileUserPath(int id) {
    return '/profile/user/$id';
  }

  static String watchPath(String id) {
    return '/watch/${Uri.encodeComponent(id)}';
  }
}

List<AppNavigationItem> appNavigationItemsForMode(CatalogMode mode) {
  final List<AppNavigationItem> items = <AppNavigationItem>[
    const AppNavigationItem(
      path: AppRoutes.board,
      labelKey: 'Board',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    const AppNavigationItem(
      path: AppRoutes.discovery,
      labelKey: 'Discovery',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
    ),
    const AppNavigationItem(
      path: AppRoutes.library,
      labelKey: 'Library',
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library_rounded,
    ),
    const AppNavigationItem(
      path: AppRoutes.calendar,
      labelKey: 'Calendar',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
    ),
    const AppNavigationItem(
      path: AppRoutes.addons,
      labelKey: 'Addons',
      icon: Icons.extension_outlined,
      selectedIcon: Icons.extension_rounded,
    ),
    if (mode == CatalogMode.anilist)
      const AppNavigationItem(
        path: AppRoutes.profile,
        labelKey: 'Profile',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
    const AppNavigationItem(
      path: AppRoutes.settings,
      labelKey: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];
  return List<AppNavigationItem>.unmodifiable(items);
}
