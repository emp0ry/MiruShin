import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation_helpers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/cache/metadata_cache_store.dart';
import '../../../core/responsive/responsive_grid.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/page_back_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../player/application/player_settings.dart';
import '../../player/domain/player_models.dart';
import '../../settings/presentation/settings_state.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/application/anilist_login_flow.dart';
import '../../tracking/data/anilist_api_client.dart';
import '../application/anilist_profile_export.dart';
import '../application/anilist_profile_provider.dart';
import '../application/anilist_user_settings_provider.dart';
import '../domain/anilist_profile_models.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final SettingsState settings = ref.watch(settingsProvider);
    final AsyncValue<AniListUserProfile?> profileAsync = ref.watch(
      aniListViewerProfileProvider,
    );

    if (mode != CatalogMode.anilist) {
      return AdaptivePage(
        child: NeutralPlaceholder(
          title: context.t('Profile'),
          message: context.t(
            'Profile is only available while the AniList catalog is active.',
          ),
          icon: Icons.person_off_rounded,
          height: 340,
          action: FilledButton(
            onPressed: () => context.go(AppRoutes.settings),
            child: Text(context.t('Settings')),
          ),
        ),
      );
    }

    if (!settings.hasAniListSession) {
      return AdaptivePage(
        child: NeutralPlaceholder(
          title: context.t('AniList not connected'),
          message: context.t(
            'Sign in to open your AnimeShin-style AniList profile, social pages, exports, and content settings.',
          ),
          icon: Icons.login_rounded,
          height: 360,
          action: FilledButton.icon(
            onPressed: () => loginAniList(context, ref),
            icon: const Icon(Icons.login_rounded),
            label: Text(context.t('Sign in')),
          ),
        ),
      );
    }

    final AniListUserProfile? profile = profileAsync.maybeWhen(
      data: (AniListUserProfile? value) => value,
      orElse: () => null,
    );
    final String displayName =
        profile?.name ?? settings.anilistViewerName ?? 'AniList User';

    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ProfileHero(
              profile: profile,
              fallbackName: displayName,
              avatarUrl: settings.anilistAvatarUrl,
              onOpenSite: profile?.siteUrl == null
                  ? null
                  : () => _openExternal(profile!.siteUrl!),
              onSignOut: () async {
                await ref.read(settingsProvider.notifier).disconnectAniList();
                await _invalidateAniListScope(ref, clearMetadataCache: false);
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: context.t('Profile'),
              subtitle:
                  'Activities, favourites, feed, social, statistics, reviews, exports, and AniList content settings.',
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              itemCount: _profileActions.length,
              minItemWidth: 180,
              maxColumns: 4,
              childAspectRatio: 1.15,
              itemBuilder: (BuildContext context, int index) {
                final _ProfileAction action = _profileActions[index];
                return _ProfileActionCard(
                  title: action.title,
                  subtitle: action.subtitle,
                  icon: action.icon,
                  onTap: () => context.push(action.route),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            SettingsSection(
              title: context.t('Export'),
              icon: Icons.ios_share_rounded,
              children: <Widget>[
                SettingsRow(
                  title: context.t('Export (MyAnimeList)'),
                  subtitle: context.t(
                    'Saves a local AniList library export in MyAnimeList XML format.',
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () => _showExportSheet(
                      context,
                      ref,
                      target: AniListExportTarget.myAnimeList,
                    ),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('MyAnimeList'),
                  ),
                ),
                SettingsRow(
                  title: context.t('Export Shikimori'),
                  subtitle: context.t(
                    'Saves a local AniList library export in Shikimori JSON format.',
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => _showExportSheet(
                      context,
                      ref,
                      target: AniListExportTarget.shikimori,
                    ),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Shikimori'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileUserPage extends ConsumerWidget {
  const ProfileUserPage({required this.userId, super.key});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId <= 0 || !ref.watch(aniListSignedInProvider)) {
      return const _SignedOutProfilePage(title: 'Profile');
    }

    final AsyncValue<AniListUserProfile?> profileAsync = ref.watch(
      aniListUserProfileProvider(userId),
    );
    final AniListActivitiesQuery activitiesQuery = AniListActivitiesQuery(
      userId: userId,
      typeIn: const <String>['TEXT', 'ANIME_LIST', 'MANGA_LIST', 'MESSAGE'],
    );
    final AsyncValue<AniListPagedChunk<AniListActivity>> activities = ref.watch(
      aniListActivitiesProvider(activitiesQuery),
    );

    return _ProfileSubpage(
      title: 'Profile',
      subtitle: 'AniList user profile.',
      child: profileAsync.when(
        data: (AniListUserProfile? profile) {
          if (profile == null) {
            return const _EmptyPlaceholder(
              title: 'User not found',
              message: 'AniList did not return a profile for this user.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ProfileHero(
                profile: profile,
                fallbackName: profile.name,
                avatarUrl: profile.avatarUrl,
                onOpenSite: profile.siteUrl == null
                    ? null
                    : () => _openExternal(profile.siteUrl!),
              ),
              const SizedBox(height: AppSpacing.xl),
              _StatisticsSummaryCards(profile: profile),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: 'Recent Activity',
                subtitle: 'Profile activity from AniList.',
              ),
              const SizedBox(height: AppSpacing.md),
              _AsyncActivitiesView(
                query: activitiesQuery,
                asyncActivities: activities,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            _ErrorPlaceholder(message: error.toString()),
      ),
    );
  }
}

class ProfileActivitiesPage extends ConsumerStatefulWidget {
  const ProfileActivitiesPage({super.key});

  @override
  ConsumerState<ProfileActivitiesPage> createState() =>
      _ProfileActivitiesPageState();
}

class _ProfileActivitiesPageState extends ConsumerState<ProfileActivitiesPage> {
  static const List<({String label, String? type})> _typeOptions =
      <({String label, String? type})>[
        (label: 'All', type: null),
        (label: 'Text', type: 'TEXT'),
        (label: 'Anime List', type: 'ANIME_LIST'),
        (label: 'Manga List', type: 'MANGA_LIST'),
        (label: 'Messages', type: 'MESSAGE'),
      ];

  String? _selectedType;
  final List<AniListActivity> _items = <AniListActivity>[];
  int _currentPage = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  int? _viewerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  void _initialLoad() {
    _viewerId = ref.read(aniListViewerIdProvider);
    if (_viewerId != null) {
      _loadPage(1, reset: true);
    }
  }

  Future<void> _loadPage(int page, {bool reset = false}) async {
    final int? userId = _viewerId ?? ref.read(aniListViewerIdProvider);
    if (userId == null) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });
    try {
      final List<String> typeIn = _selectedType == null
          ? const <String>['TEXT', 'ANIME_LIST', 'MANGA_LIST', 'MESSAGE']
          : <String>[_selectedType!];
      final AniListPagedChunk<AniListActivity> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchActivities(userId: userId, typeIn: typeIn, page: page);
      if (!mounted) return;
      setState(() {
        _items.addAll(chunk.items);
        _currentPage = page;
        _hasMore = chunk.hasNextPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _setTypeFilter(String? type) {
    if (_selectedType == type) return;
    setState(() => _selectedType = type);
    _loadPage(1, reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final int? viewerId = ref.watch(aniListViewerIdProvider);
    if (viewerId == null) {
      return const _SignedOutProfilePage(title: 'Activities');
    }
    return _ProfileSubpage(
      title: 'Activities',
      subtitle: 'Recent AniList activity from your profile.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    children: _typeOptions
                        .map(
                          (({String label, String? type}) opt) => ChoiceChip(
                            label: Text(context.t(opt.label)),
                            selected: _selectedType == opt.type,
                            onSelected: (_) => _setTypeFilter(opt.type),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: () async {
                  await _showStatusComposerDirect(context);
                },
                icon: const Icon(Icons.edit_outlined),
                label: Text(context.t('New Post')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _PaginatedActivitiesView(
            items: _items,
            loading: _loading,
            hasMore: _hasMore,
            error: _error,
            onLoadMore: () => _loadPage(_currentPage + 1),
            onRetry: () => _loadPage(1, reset: true),
          ),
        ],
      ),
    );
  }

  Future<void> _showStatusComposerDirect(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? text = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.t('New Post')),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.t('Share an AniList status update...'),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(context.t('Post')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final String trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty || !context.mounted) return;
    try {
      await ref
          .read(aniListProfileClientProvider)
          .saveTextActivity(text: trimmed);
      _loadPage(1, reset: true);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.t('Failed to post')}: $error')),
      );
    }
  }
}

class ProfileFeedPage extends ConsumerStatefulWidget {
  const ProfileFeedPage({super.key});

  @override
  ConsumerState<ProfileFeedPage> createState() => _ProfileFeedPageState();
}

class _ProfileFeedPageState extends ConsumerState<ProfileFeedPage> {
  final List<AniListActivity> _items = <AniListActivity>[];
  int _currentPage = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadPage(1, reset: true),
    );
  }

  Future<void> _loadPage(int page, {bool reset = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });
    try {
      final AniListPagedChunk<AniListActivity> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchActivities(
            isFollowing: true,
            typeIn: const <String>['TEXT', 'ANIME_LIST', 'MANGA_LIST'],
            page: page,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(chunk.items);
        _currentPage = page;
        _hasMore = chunk.hasNextPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(aniListSignedInProvider)) {
      return const _SignedOutProfilePage(title: 'Feed');
    }
    return _ProfileSubpage(
      title: 'Feed',
      subtitle: 'Activity from people you follow on AniList.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _showStatusComposer(
                context,
                ref,
                const AniListActivitiesQuery(isFollowing: true),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.t('New Post')),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _PaginatedActivitiesView(
            items: _items,
            loading: _loading,
            hasMore: _hasMore,
            error: _error,
            onLoadMore: () => _loadPage(_currentPage + 1),
            onRetry: () => _loadPage(1, reset: true),
          ),
        ],
      ),
    );
  }
}

class ProfileFavouritesPage extends ConsumerWidget {
  const ProfileFavouritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? viewerId = ref.watch(aniListViewerIdProvider);
    if (viewerId == null) {
      return const _SignedOutProfilePage(title: 'Favourites');
    }
    return _ProfileSubpage(
      title: 'Favourites',
      subtitle: 'Favourite anime, manga, characters, staff, and studios.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: AniListFavouriteKind.values
            .map((AniListFavouriteKind kind) {
              final AsyncValue<AniListPagedChunk<MediaItem>> asyncItems = ref
                  .watch(
                    aniListFavouritesProvider(
                      AniListFavouriteQuery(userId: viewerId, kind: kind),
                    ),
                  );
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: _FavouriteSection(kind: kind, asyncItems: asyncItems),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class ProfileSocialPage extends ConsumerStatefulWidget {
  const ProfileSocialPage({super.key});

  @override
  ConsumerState<ProfileSocialPage> createState() => _ProfileSocialPageState();
}

class _ProfileSocialPageState extends ConsumerState<ProfileSocialPage> {
  int _tab = 0;

  // Following
  final List<AniListUserSnippet> _followingItems = <AniListUserSnippet>[];
  int _followingPage = 0;
  bool _followingLoading = false;
  bool _followingHasMore = true;

  // Followers
  final List<AniListUserSnippet> _followerItems = <AniListUserSnippet>[];
  int _followerPage = 0;
  bool _followerLoading = false;
  bool _followerHasMore = true;

  // Threads
  final List<AniListForumThread> _threadItems = <AniListForumThread>[];
  int _threadPage = 0;
  bool _threadLoading = false;
  bool _threadHasMore = true;

  // Comments
  final List<AniListForumComment> _commentItems = <AniListForumComment>[];
  int _commentPage = 0;
  bool _commentLoading = false;
  bool _commentHasMore = true;

  int? _viewerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewerId = ref.read(aniListViewerIdProvider);
      if (_viewerId != null) {
        _loadFollowing(1, reset: true);
        _loadFollowers(1, reset: true);
        _loadThreads(1, reset: true);
        _loadComments(1, reset: true);
      }
    });
  }

  Future<void> _loadFollowing(int page, {bool reset = false}) async {
    final int? userId = _viewerId;
    if (userId == null || !mounted) return;
    setState(() {
      _followingLoading = true;
      if (reset) {
        _followingItems.clear();
        _followingPage = 0;
        _followingHasMore = true;
      }
    });
    try {
      final AniListPagedChunk<AniListUserSnippet> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchSocialUsers(userId: userId, following: true, page: page);
      if (!mounted) return;
      setState(() {
        _followingItems.addAll(chunk.items);
        _followingPage = page;
        _followingHasMore = chunk.hasNextPage;
        _followingLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _followingLoading = false);
    }
  }

  Future<void> _loadFollowers(int page, {bool reset = false}) async {
    final int? userId = _viewerId;
    if (userId == null || !mounted) return;
    setState(() {
      _followerLoading = true;
      if (reset) {
        _followerItems.clear();
        _followerPage = 0;
        _followerHasMore = true;
      }
    });
    try {
      final AniListPagedChunk<AniListUserSnippet> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchSocialUsers(userId: userId, following: false, page: page);
      if (!mounted) return;
      setState(() {
        _followerItems.addAll(chunk.items);
        _followerPage = page;
        _followerHasMore = chunk.hasNextPage;
        _followerLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _followerLoading = false);
    }
  }

  Future<void> _loadThreads(int page, {bool reset = false}) async {
    final int? userId = _viewerId;
    if (userId == null || !mounted) return;
    setState(() {
      _threadLoading = true;
      if (reset) {
        _threadItems.clear();
        _threadPage = 0;
        _threadHasMore = true;
      }
    });
    try {
      final AniListPagedChunk<AniListForumThread> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchSocialThreads(userId: userId, page: page);
      if (!mounted) return;
      setState(() {
        _threadItems.addAll(chunk.items);
        _threadPage = page;
        _threadHasMore = chunk.hasNextPage;
        _threadLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _threadLoading = false);
    }
  }

  Future<void> _loadComments(int page, {bool reset = false}) async {
    final int? userId = _viewerId;
    if (userId == null || !mounted) return;
    setState(() {
      _commentLoading = true;
      if (reset) {
        _commentItems.clear();
        _commentPage = 0;
        _commentHasMore = true;
      }
    });
    try {
      final AniListPagedChunk<AniListForumComment> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchSocialComments(userId: userId, page: page);
      if (!mounted) return;
      setState(() {
        _commentItems.addAll(chunk.items);
        _commentPage = page;
        _commentHasMore = chunk.hasNextPage;
        _commentLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _commentLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? viewerId = ref.watch(aniListViewerIdProvider);
    if (viewerId == null) {
      return const _SignedOutProfilePage(title: 'Social');
    }
    return _ProfileSubpage(
      title: 'Social',
      subtitle: 'Following, followers, forum threads, and comments.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  label: Text(context.t('Following')),
                  icon: const Icon(Icons.people_alt_outlined),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text(context.t('Followers')),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text(context.t('Threads')),
                  icon: const Icon(Icons.forum_outlined),
                ),
                ButtonSegment<int>(
                  value: 3,
                  label: Text(context.t('Comments')),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                ),
              ],
              selected: <int>{_tab},
              onSelectionChanged: (Set<int> value) {
                setState(() => _tab = value.first);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (_tab) {
              0 => _SocialSection(
                key: const ValueKey<String>('following'),
                title: 'Following',
                items: _followingItems,
                loading: _followingLoading,
                hasMore: _followingHasMore,
                onLoadMore: () => _loadFollowing(_followingPage + 1),
              ),
              1 => _SocialSection(
                key: const ValueKey<String>('followers'),
                title: 'Followers',
                items: _followerItems,
                loading: _followerLoading,
                hasMore: _followerHasMore,
                onLoadMore: () => _loadFollowers(_followerPage + 1),
              ),
              2 => _ForumThreadSection(
                key: const ValueKey<String>('threads'),
                items: _threadItems,
                loading: _threadLoading,
                hasMore: _threadHasMore,
                onLoadMore: () => _loadThreads(_threadPage + 1),
              ),
              _ => _ForumCommentSection(
                key: const ValueKey<String>('comments'),
                items: _commentItems,
                loading: _commentLoading,
                hasMore: _commentHasMore,
                onLoadMore: () => _loadComments(_commentPage + 1),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class ProfileStatisticsPage extends ConsumerStatefulWidget {
  const ProfileStatisticsPage({super.key});

  @override
  ConsumerState<ProfileStatisticsPage> createState() =>
      _ProfileStatisticsPageState();
}

class _ProfileStatisticsPageState extends ConsumerState<ProfileStatisticsPage> {
  bool _anime = true;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AniListUserProfile?> profileAsync = ref.watch(
      aniListViewerProfileProvider,
    );
    return _ProfileSubpage(
      title: 'Statistics',
      subtitle: 'Anime and manga totals from your AniList account.',
      child: profileAsync.when(
        data: (AniListUserProfile? profile) {
          if (profile == null) {
            return const _SignedOutBody();
          }
          final AniListUserStatistics stats = _anime
              ? profile.animeStats
              : profile.mangaStats;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StatisticsSummaryCards(profile: profile),
              const SizedBox(height: AppSpacing.xl),
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: true,
                    icon: const Icon(Icons.live_tv_rounded),
                    label: Text(context.t('Anime')),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    icon: const Icon(Icons.menu_book_rounded),
                    label: Text(context.t('Manga')),
                  ),
                ],
                selected: <bool>{_anime},
                onSelectionChanged: (Set<bool> value) {
                  setState(() => _anime = value.first);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              _StatisticsDetailGrid(stats: stats, anime: _anime),
              const SizedBox(height: AppSpacing.xl),
              _StatisticBarSection(
                title: _anime ? 'Score Distribution' : 'Score Distribution',
                values: stats.scores,
                valueLabel: _anime ? 'Titles' : 'Titles',
              ),
              const SizedBox(height: AppSpacing.xl),
              _StatisticBarSection(
                title: _anime ? 'Episodes / Chapters' : 'Chapters',
                values: stats.lengths,
                valueLabel: _anime ? 'Minutes' : 'Chapters',
              ),
              const SizedBox(height: AppSpacing.xl),
              ResponsiveGrid(
                itemCount: 3,
                minItemWidth: 260,
                maxColumns: 3,
                childAspectRatio: 1.5,
                itemBuilder: (BuildContext context, int index) {
                  return _StatisticListSection(
                    title: switch (index) {
                      0 => 'Formats',
                      1 => 'Statuses',
                      _ => 'Countries',
                    },
                    values: switch (index) {
                      0 => stats.formats,
                      1 => stats.statuses,
                      _ => stats.countries,
                    },
                  );
                },
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            _ErrorPlaceholder(message: error.toString()),
      ),
    );
  }
}

class ProfileReviewsPage extends ConsumerStatefulWidget {
  const ProfileReviewsPage({super.key});

  @override
  ConsumerState<ProfileReviewsPage> createState() => _ProfileReviewsPageState();
}

class _ProfileReviewsPageState extends ConsumerState<ProfileReviewsPage> {
  String _sort = 'CREATED_AT_DESC';
  String? _mediaType;

  final List<AniListReviewItem> _items = <AniListReviewItem>[];
  int _currentPage = 0;
  bool _loading = false;
  bool _hasMore = true;
  int? _viewerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewerId = ref.read(aniListViewerIdProvider);
      if (_viewerId != null) _loadPage(1, reset: true);
    });
  }

  Future<void> _loadPage(int page, {bool reset = false}) async {
    final int? userId = _viewerId;
    if (userId == null || !mounted) return;
    setState(() {
      _loading = true;
      if (reset) {
        _items.clear();
        _currentPage = 0;
        _hasMore = true;
      }
    });
    try {
      final AniListPagedChunk<AniListReviewItem> chunk = await ref
          .read(aniListProfileClientProvider)
          .fetchUserReviews(
            userId: userId,
            sort: _sort,
            mediaType: _mediaType,
            page: page,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(chunk.items);
        _currentPage = page;
        _hasMore = chunk.hasNextPage;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setSort(String sort) {
    setState(() => _sort = sort);
    _loadPage(1, reset: true);
  }

  void _setMediaType(String? type) {
    setState(() => _mediaType = type);
    _loadPage(1, reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final int? viewerId = ref.watch(aniListViewerIdProvider);
    if (viewerId == null) {
      return const _SignedOutProfilePage(title: 'Reviews');
    }
    return _ProfileSubpage(
      title: 'Reviews',
      subtitle: 'Recent reviews published on AniList.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              DropdownButton<String>(
                value: _sort,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'CREATED_AT_DESC',
                    child: Text(context.t('Newest')),
                  ),
                  DropdownMenuItem<String>(
                    value: 'CREATED_AT',
                    child: Text(context.t('Oldest')),
                  ),
                  DropdownMenuItem<String>(
                    value: 'RATING_DESC',
                    child: Text(context.t('Highest Rated')),
                  ),
                  DropdownMenuItem<String>(
                    value: 'RATING',
                    child: Text(context.t('Lowest Rated')),
                  ),
                ],
                onChanged: (String? value) {
                  if (value != null) _setSort(value);
                },
              ),
              SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'ALL',
                    label: Text(context.t('All')),
                    icon: const Icon(Icons.all_inclusive_rounded),
                  ),
                  ButtonSegment<String>(
                    value: 'ANIME',
                    label: Text(context.t('Anime')),
                    icon: const Icon(Icons.live_tv_rounded),
                  ),
                  ButtonSegment<String>(
                    value: 'MANGA',
                    label: Text(context.t('Manga')),
                    icon: const Icon(Icons.menu_book_rounded),
                  ),
                ],
                selected: <String>{_mediaType ?? 'ALL'},
                onSelectionChanged: (Set<String> value) {
                  final String next = value.first;
                  _setMediaType(next == 'ALL' ? null : next);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_loading && _items.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            const _EmptyPlaceholder(
              title: 'No reviews yet',
              message: 'Your AniList reviews will appear here.',
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ResponsiveGrid(
                  itemCount: _items.length,
                  minItemWidth: 270,
                  maxColumns: 3,
                  childAspectRatio: 1.35,
                  itemBuilder: (BuildContext context, int index) =>
                      _ReviewTile(item: _items[index]),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : _hasMore
                      ? OutlinedButton.icon(
                          onPressed: () => _loadPage(_currentPage + 1),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(context.t('Load more')),
                        )
                      : Text(
                          context.t('All caught up'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
        ],
      ),
    );
  }
}

class ProfileAniListSettingsPage extends ConsumerStatefulWidget {
  const ProfileAniListSettingsPage({super.key});

  @override
  ConsumerState<ProfileAniListSettingsPage> createState() =>
      _ProfileAniListSettingsPageState();
}

class _ProfileAniListSettingsPageState
    extends ConsumerState<ProfileAniListSettingsPage> {
  static const List<({String label, int value})> _mergeTimeOptions =
      <({String label, int value})>[
        (label: 'Never', value: 0),
        (label: '30 Minutes', value: 30),
        (label: '1 Hour', value: 60),
        (label: '2 Hours', value: 120),
        (label: '3 Hours', value: 180),
        (label: '6 Hours', value: 360),
        (label: '12 Hours', value: 720),
        (label: '1 Day', value: 1440),
        (label: '2 Days', value: 2880),
        (label: '3 Days', value: 4320),
        (label: '1 Week', value: 10080),
        (label: '2 Weeks', value: 20160),
        (label: 'Always', value: 29160),
      ];

  static const List<({String label, String value})> _titleLanguages =
      <({String label, String value})>[
        (label: 'Romaji', value: 'ROMAJI'),
        (label: 'English', value: 'ENGLISH'),
        (label: 'Native', value: 'NATIVE'),
        (label: 'Russian (Shikimori)', value: 'RUSSIAN'),
      ];

  static const List<({String label, String value})> _staffNames =
      <({String label, String value})>[
        (label: 'Romaji, Western Order', value: 'ROMAJI_WESTERN'),
        (label: 'Romaji', value: 'ROMAJI'),
        (label: 'Native', value: 'NATIVE'),
      ];

  static const List<({String label, String value})> _scoreFormats =
      <({String label, String value})>[
        (label: '100-point', value: 'POINT_100'),
        (label: '10-point decimal', value: 'POINT_10_DECIMAL'),
        (label: '10-point', value: 'POINT_10'),
        (label: '5-star', value: 'POINT_5'),
        (label: '3-point', value: 'POINT_3'),
      ];

  static const List<({String label, String value})> _rowOrders =
      <({String label, String value})>[
        (label: 'Title', value: 'title'),
        (label: 'Score', value: 'score'),
        (label: 'Last Updated', value: 'updatedAt'),
        (label: 'Last Added', value: 'id'),
      ];

  final List<TextEditingController> _advancedScoreControllers =
      List<TextEditingController>.generate(5, (_) => TextEditingController());

  AniListUserSettings? _draft;
  Timer? _saveDebounce;
  bool _hydrated = false;
  bool _saving = false;
  Object? _lastSaveError;
  bool _autoTrackProgress = false;
  AniListLibraryDefaultPage _defaultPage = AniListLibraryDefaultPage.all;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final TextEditingController controller in _advancedScoreControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = ref.watch(settingsProvider);
    if (!settings.hasAniListSession) {
      return const _SignedOutProfilePage(title: 'AniList Settings');
    }

    final AsyncValue<AniListUserSettings> asyncSettings = ref.watch(
      aniListUserSettingsProvider,
    );
    final PlayerSettings playerSettings =
        ref.watch(playerSettingsProvider).value ?? const PlayerSettings();

    if (!_hydrated && asyncSettings.hasValue) {
      _hydrate(
        asyncSettings.requireValue,
        playerSettings,
        settings.anilistLibraryDefaultPage,
      );
    }

    return _ProfileSubpage(
      title: 'AniList Settings',
      subtitle:
          'AnimeShin content preferences, plus MiruShin auto-sync and library defaults.',
      child: asyncSettings.when(
        data: (AniListUserSettings value) {
          final AniListUserSettings draft = _draft ?? value;
          final String titleLanguageValue = _optionValue(
            draft.titleLanguage,
            _titleLanguages,
            fallback: 'ROMAJI',
          );
          final String staffNameValue = _optionValue(
            draft.staffNameLanguage,
            _staffNames,
            fallback: 'ROMAJI_WESTERN',
          );
          final int activityMergeValue = _intOptionValue(
            draft.activityMergeTime,
            _mergeTimeOptions,
            fallback: 720,
          );
          final String scoreFormatValue = _optionValue(
            draft.scoreFormat,
            _scoreFormats,
            fallback: 'POINT_10_DECIMAL',
          );
          final String rowOrderValue = _optionValue(
            draft.rowOrder,
            _rowOrders,
            fallback: 'title',
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SettingsSection(
                title: 'Media',
                icon: Icons.movie_filter_rounded,
                children: <Widget>[
                  SettingsRow(
                    title: 'Title language',
                    subtitle:
                        'Controls AniList media title display throughout the app.',
                    trailing: DropdownButton<String>(
                      value: titleLanguageValue,
                      items: _titleLanguages
                          .map(
                            (({String label, String value}) item) =>
                                DropdownMenuItem<String>(
                                  value: item.value,
                                  child: Text(context.t(item.label)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) {
                        if (value == null) return;
                        _updateDraft(draft.copyWith(titleLanguage: value));
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Character & Staff Names',
                    trailing: DropdownButton<String>(
                      value: staffNameValue,
                      items: _staffNames
                          .map(
                            (({String label, String value}) item) =>
                                DropdownMenuItem<String>(
                                  value: item.value,
                                  child: Text(context.t(item.label)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) {
                        if (value == null) return;
                        _updateDraft(draft.copyWith(staffNameLanguage: value));
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Activity Merge Time',
                    trailing: DropdownButton<int>(
                      value: activityMergeValue,
                      items: _mergeTimeOptions
                          .map(
                            (({String label, int value}) item) =>
                                DropdownMenuItem<int>(
                                  value: item.value,
                                  child: Text(context.t(item.label)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (int? value) {
                        if (value == null) return;
                        _updateDraft(draft.copyWith(activityMergeTime: value));
                      },
                    ),
                  ),
                  SettingsRow(
                    title: '18+ Content',
                    trailing: Switch(
                      value: draft.displayAdultContent,
                      onChanged: (bool value) {
                        _updateDraft(
                          draft.copyWith(displayAdultContent: value),
                        );
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Airing Anime Notifications',
                    trailing: Switch(
                      value: draft.airingNotifications,
                      onChanged: (bool value) {
                        _updateDraft(
                          draft.copyWith(airingNotifications: value),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsSection(
                title: 'Lists',
                icon: Icons.list_alt_rounded,
                children: <Widget>[
                  SettingsRow(
                    title: 'Scoring System',
                    trailing: DropdownButton<String>(
                      value: scoreFormatValue,
                      items: _scoreFormats
                          .map(
                            (({String label, String value}) item) =>
                                DropdownMenuItem<String>(
                                  value: item.value,
                                  child: Text(context.t(item.label)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) {
                        if (value == null) return;
                        _updateDraft(draft.copyWith(scoreFormat: value));
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Default Site List Sort',
                    trailing: DropdownButton<String>(
                      value: rowOrderValue,
                      items: _rowOrders
                          .map(
                            (({String label, String value}) item) =>
                                DropdownMenuItem<String>(
                                  value: item.value,
                                  child: Text(context.t(item.label)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (String? value) {
                        if (value == null) return;
                        _updateDraft(draft.copyWith(rowOrder: value));
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Split Completed Anime',
                    trailing: Checkbox(
                      value: draft.splitCompletedAnime,
                      onChanged: (bool? value) {
                        if (value == null) return;
                        _updateDraft(
                          draft.copyWith(splitCompletedAnime: value),
                        );
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Split Completed Manga',
                    trailing: Checkbox(
                      value: draft.splitCompletedManga,
                      onChanged: (bool? value) {
                        if (value == null) return;
                        _updateDraft(
                          draft.copyWith(splitCompletedManga: value),
                        );
                      },
                    ),
                  ),
                  SettingsRow(
                    title: 'Advanced Scoring',
                    trailing: Switch(
                      value: draft.advancedScoringEnabled,
                      onChanged: (bool value) {
                        _updateDraft(
                          draft.copyWith(advancedScoringEnabled: value),
                        );
                      },
                    ),
                  ),
                  if (draft.advancedScoringEnabled)
                    SettingsRow(
                      title: 'Advanced Score Labels',
                      subtitle:
                          'These labels are saved back to AniList for advanced score slots.',
                      fullWidthTrailing: true,
                      trailing: Column(
                        children: List<Widget>.generate(
                          _advancedScoreControllers.length,
                          (int index) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: TextField(
                              controller: _advancedScoreControllers[index],
                              decoration: InputDecoration(
                                labelText: 'Label ${index + 1}',
                              ),
                              onChanged: (_) =>
                                  _syncAdvancedScoresFromFields(save: true),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsSection(
                title: 'Social',
                icon: Icons.groups_rounded,
                children: <Widget>[
                  for (final AniListListStatus status
                      in AniListListStatus.values)
                    SettingsRow(
                      title: _createActivitiesTitle(context, status),
                      trailing: Switch(
                        value:
                            !(draft.disabledListActivity[status.graphQlValue] ??
                                false),
                        onChanged: (bool value) {
                          final Map<String, bool> updated =
                              Map<String, bool>.from(
                                draft.disabledListActivity,
                              );
                          updated[status.graphQlValue] = !value;
                          _updateDraft(
                            draft.copyWith(disabledListActivity: updated),
                          );
                        },
                      ),
                    ),
                  SettingsRow(
                    title: 'Limit Messages',
                    subtitle: 'Only users you follow can message you.',
                    trailing: Switch(
                      value: draft.restrictMessagesToFollowing,
                      onChanged: (bool value) {
                        _updateDraft(
                          draft.copyWith(restrictMessagesToFollowing: value),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              SettingsSection(
                title: 'MiruShin',
                icon: Icons.tune_rounded,
                children: <Widget>[
                  SettingsRow(
                    title: 'Auto track progress',
                    subtitle:
                        'Update AniList when 85% of an episode is watched.',
                    trailing: Switch(
                      value: _autoTrackProgress,
                      onChanged: (bool value) {
                        setState(() => _autoTrackProgress = value);
                        unawaited(
                          ref
                              .read(playerSettingsProvider.notifier)
                              .setAutoAnilistSync(value),
                        );
                      },
                    ),
                  ),
                  SettingsRow(
                    title: context.t('Default Library page'),
                    subtitle: context.t(
                      'Opened first when that AniList folder has entries.',
                    ),
                    trailing: DropdownButton<AniListLibraryDefaultPage>(
                      value: _defaultPage,
                      items: AniListLibraryDefaultPage.values
                          .map(
                            (AniListLibraryDefaultPage page) =>
                                DropdownMenuItem<AniListLibraryDefaultPage>(
                                  value: page,
                                  child: Text(context.t(page.labelKey)),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (AniListLibraryDefaultPage? value) {
                        if (value == null) return;
                        setState(() => _defaultPage = value);
                        ref
                            .read(settingsProvider.notifier)
                            .setAniListLibraryDefaultPage(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _saving
                      ? Row(
                          key: ValueKey<String>('saving'),
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(context.t('Saving automatically...')),
                          ],
                        )
                      : _lastSaveError == null
                      ? Text(
                          context.t('Changes save automatically'),
                          key: const ValueKey<String>('autosave'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textMuted),
                        )
                      : Text(
                          context.t('Autosave failed'),
                          key: const ValueKey<String>('error'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            _ErrorPlaceholder(message: error.toString()),
      ),
    );
  }

  void _hydrate(
    AniListUserSettings settings,
    PlayerSettings playerSettings,
    AniListLibraryDefaultPage defaultPage,
  ) {
    _hydrated = true;
    _draft = settings;
    _autoTrackProgress = playerSettings.autoAnilistSync;
    _defaultPage = defaultPage;
    final List<String> scores = settings.advancedScores;
    for (int index = 0; index < _advancedScoreControllers.length; index += 1) {
      _advancedScoreControllers[index].text = index < scores.length
          ? scores[index]
          : '';
    }
  }

  String _optionValue(
    String value,
    List<({String label, String value})> options, {
    required String fallback,
  }) {
    return options.any((({String label, String value}) option) {
          return option.value == value;
        })
        ? value
        : fallback;
  }

  int _intOptionValue(
    int value,
    List<({String label, int value})> options, {
    required int fallback,
  }) {
    return options.any((({String label, int value}) option) {
          return option.value == value;
        })
        ? value
        : fallback;
  }

  void _updateDraft(AniListUserSettings next) {
    setState(() {
      _draft = next;
      _lastSaveError = null;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(_save());
    });
  }

  void _syncAdvancedScoresFromFields({bool save = false}) {
    if (_draft == null) return;
    final List<String> labels = _advancedScoreControllers
        .map((TextEditingController controller) => controller.text.trim())
        .where((String label) => label.isNotEmpty)
        .toList(growable: false);
    _draft = _draft!.copyWith(advancedScores: labels);
    if (save) {
      setState(() => _lastSaveError = null);
      _scheduleSave();
    }
  }

  Future<void> _save() async {
    if (_draft == null) return;
    setState(() => _saving = true);
    _syncAdvancedScoresFromFields();
    try {
      final AniListUserSettings saved = await ref
          .read(aniListUserSettingsProvider.notifier)
          .save(_draft!);
      _draft = saved;
      await _invalidateAniListScope(ref);
    } catch (error) {
      if (!mounted) return;
      setState(() => _lastSaveError = error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _ProfileSubpage extends StatelessWidget {
  const _ProfileSubpage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdaptivePage(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ProfileBackHeader(title: title, subtitle: subtitle),
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileBackHeader extends StatelessWidget {
  const _ProfileBackHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PageBackButton(onPressed: () => goBackOrGo(context, AppRoutes.profile)),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: SectionHeader(title: context.t(title), subtitle: subtitle),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.fallbackName,
    required this.avatarUrl,
    this.onOpenSite,
    this.onSignOut,
  });

  final AniListUserProfile? profile;
  final String fallbackName;
  final String? avatarUrl;
  final VoidCallback? onOpenSite;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final String? bannerUrl = profile?.bannerUrl;
    final String? resolvedAvatarUrl = profile?.avatarUrl ?? avatarUrl;
    final int animeCount = profile?.animeStats.count ?? 0;
    final int mangaCount = profile?.mangaStats.count ?? 0;

    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.xxl),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              AppColors.accentAqua.withValues(alpha: 0.32),
              AppColors.surface,
              AppColors.accentPurple.withValues(alpha: 0.18),
            ],
          ),
          image: bannerUrl == null || bannerUrl.isEmpty
              ? null
              : DecorationImage(
                  image: CachedNetworkImageProvider(bannerUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.42),
                    BlendMode.darken,
                  ),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 38,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  backgroundImage: resolvedAvatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(resolvedAvatarUrl),
                  child: resolvedAvatarUrl == null
                      ? const Icon(Icons.person_rounded, size: 34)
                      : null,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        fallbackName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        profile?.about.isNotEmpty == true
                            ? profile!.about
                            : context.t(
                                'Your AniList profile hub inside MiruShin.',
                              ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _HeroChip(
                  icon: Icons.live_tv_rounded,
                  label: _countLabel(context, 'Anime', animeCount),
                ),
                _HeroChip(
                  icon: Icons.menu_book_rounded,
                  label: _countLabel(context, 'Manga', mangaCount),
                ),
                if (profile?.isFollowing == true)
                  _HeroChip(
                    icon: Icons.favorite_rounded,
                    label: context.t('Following'),
                  ),
                if (onOpenSite != null)
                  OutlinedButton.icon(
                    onPressed: onOpenSite,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(context.t('Open AniList')),
                  ),
                if (onSignOut != null)
                  TextButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(context.t('Sign out')),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: AppRadius.all(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text(label),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppRadius.all(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.all(AppRadius.xl),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: AppRadius.all(AppRadius.lg),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const Spacer(),
            Text(
              context.t(title),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.t(subtitle),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AsyncActivitiesView extends StatelessWidget {
  const _AsyncActivitiesView({
    required this.query,
    required this.asyncActivities,
  });

  final AniListActivitiesQuery query;
  final AsyncValue<AniListPagedChunk<AniListActivity>> asyncActivities;

  @override
  Widget build(BuildContext context) {
    return asyncActivities.when(
      data: (AniListPagedChunk<AniListActivity> chunk) {
        if (chunk.items.isEmpty) {
          return const _EmptyPlaceholder(
            title: 'Nothing here yet',
            message:
                'AniList activity will appear here once something is posted or tracked.',
          );
        }
        return Column(
          children: chunk.items
              .map(
                (AniListActivity item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _ActivityTile(query: query, item: item),
                ),
              )
              .toList(growable: false),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) =>
          _ErrorPlaceholder(message: error.toString()),
    );
  }
}

class _PaginatedActivitiesView extends StatelessWidget {
  const _PaginatedActivitiesView({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    required this.onRetry,
    this.error,
  });

  final List<AniListActivity> items;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _ErrorPlaceholder(message: error.toString());
    }
    if (items.isEmpty) {
      return const _EmptyPlaceholder(
        title: 'Nothing here yet',
        message:
            'AniList activity will appear here once something is posted or tracked.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...items.map(
          (AniListActivity item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _ActivityTile(item: item),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: loading
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : hasMore
              ? OutlinedButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(context.t('Load more')),
                )
              : Text(
                  context.t('All caught up'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _ActivityTile extends ConsumerStatefulWidget {
  const _ActivityTile({required this.item, this.query});

  final AniListActivitiesQuery? query;
  final AniListActivity item;

  @override
  ConsumerState<_ActivityTile> createState() => _ActivityTileState();
}

class _ActivityTileState extends ConsumerState<_ActivityTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AniListActivity item = widget.item;
    final String timestamp = item.createdAt == null
        ? context.t('Unknown time')
        : _formatShortDate(item.createdAt!);
    final String title = _activityTitle(context, item);
    final String body = item.text.isNotEmpty
        ? item.text
        : [
            if (item.statusLabel != null && item.statusLabel!.isNotEmpty)
              context.t(item.statusLabel!),
            if (item.progressLabel != null && item.progressLabel!.isNotEmpty)
              item.progressLabel,
            item.media?.title,
          ].whereType<String>().join(' · ');

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.push(
                  AppRoutes.profileUserPath(item.primaryUser.id),
                ),
                child: CircleAvatar(
                  backgroundImage: item.primaryUser.avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(item.primaryUser.avatarUrl!),
                  child: item.primaryUser.avatarUrl == null
                      ? const Icon(Icons.person_rounded)
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      timestamp,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.secondaryUser != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.arrow_forward_rounded, size: 18),
                const SizedBox(width: AppSpacing.sm),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.push(
                    AppRoutes.profileUserPath(item.secondaryUser!.id),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: item.secondaryUser!.avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(
                            item.secondaryUser!.avatarUrl!,
                          ),
                    child: item.secondaryUser!.avatarUrl == null
                        ? const Icon(Icons.person_rounded, size: 18)
                        : null,
                  ),
                ),
              ],
              if (item.isPinned) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.push_pin_outlined, size: 18),
              ],
            ],
          ),
          if (body.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (item.media != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _MiniMediaRow(item: item.media!),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (item.siteUrl != null && item.siteUrl!.isNotEmpty)
                IconButton(
                  tooltip: context.t('Open on AniList'),
                  onPressed: _busy ? null : () => _openExternal(item.siteUrl!),
                  icon: const Icon(Icons.open_in_new_rounded),
                ),
              TextButton.icon(
                onPressed: null,
                icon: const Icon(Icons.reply_all_rounded),
                label: Text(item.replyCount.toString()),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _toggleLike,
                icon: Icon(
                  item.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                ),
                label: Text(item.likeCount.toString()),
              ),
              IconButton(
                tooltip: item.isSubscribed
                    ? context.t('Unsubscribe')
                    : context.t('Subscribe'),
                onPressed: _busy ? null : _toggleSubscription,
                icon: Icon(
                  item.isSubscribed
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike() async {
    await _runActivityMutation(
      () => ref
          .read(aniListProfileClientProvider)
          .toggleActivityLike(widget.item.id),
    );
  }

  Future<void> _toggleSubscription() async {
    await _runActivityMutation(
      () => ref
          .read(aniListProfileClientProvider)
          .toggleActivitySubscription(
            id: widget.item.id,
            subscribe: !widget.item.isSubscribed,
          ),
    );
  }

  Future<void> _runActivityMutation(Future<void> Function() mutation) async {
    setState(() => _busy = true);
    try {
      await mutation();
      if (widget.query != null) {
        ref.invalidate(aniListActivitiesProvider(widget.query!));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.t('AniList action failed')}: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _MiniMediaRow extends StatelessWidget {
  const _MiniMediaRow({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.md),
      onTap: () =>
          context.push(AppRoutes.mediaDetailsPath(item.id), extra: item),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: AppRadius.all(AppRadius.md),
            child: Container(
              width: 54,
              height: 74,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: item.posterUrl.isEmpty
                  ? const Icon(Icons.movie_creation_outlined)
                  : Image(
                      image: CachedNetworkImageProvider(item.posterUrl),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.statusLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavouriteSection extends StatelessWidget {
  const _FavouriteSection({required this.kind, required this.asyncItems});

  final AniListFavouriteKind kind;
  final AsyncValue<AniListPagedChunk<MediaItem>> asyncItems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: kind.label),
        asyncItems.when(
          data: (AniListPagedChunk<MediaItem> chunk) {
            if (chunk.items.isEmpty) {
              return Text(
                _emptyKindMessage(context, kind.label),
                style: Theme.of(context).textTheme.bodyMedium,
              );
            }
            return ResponsiveGrid(
              itemCount: chunk.items.length,
              minItemWidth: 150,
              maxColumns: 5,
              childAspectRatio: 0.72,
              itemBuilder: (BuildContext context, int index) {
                return _FavouriteCard(item: chunk.items[index]);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) =>
              _ErrorPlaceholder(message: error.toString()),
        ),
      ],
    );
  }
}

class _FavouriteCard extends StatelessWidget {
  const _FavouriteCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: () =>
          context.push(AppRoutes.mediaDetailsPath(item.id), extra: item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: item.posterUrl.isEmpty
                    ? const Icon(Icons.image_not_supported_outlined)
                    : Image(
                        image: CachedNetworkImageProvider(item.posterUrl),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialSection extends StatelessWidget {
  const _SocialSection({
    required this.title,
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    super.key,
  });

  final String title;
  final List<AniListUserSnippet> items;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: title),
        if (loading && items.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (items.isEmpty)
          Text(
            _emptyKindMessage(context, title),
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Column(
            children: <Widget>[
              ...items.map(
                (AniListUserSnippet user) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _SocialUserTile(user: user),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : hasMore
                    ? OutlinedButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(context.t('Load more')),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }
}

class _SocialUserTile extends StatelessWidget {
  const _SocialUserTile({required this.user});

  final AniListUserSnippet user;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => context.push(AppRoutes.profileUserPath(user.id)),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundImage: user.avatarUrl == null
                ? null
                : CachedNetworkImageProvider(user.avatarUrl!),
            child: user.avatarUrl == null
                ? const Icon(Icons.person_rounded)
                : null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              user.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumThreadSection extends StatelessWidget {
  const _ForumThreadSection({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    super.key,
  });

  final List<AniListForumThread> items;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const _EmptyPlaceholder(
        title: 'No threads yet',
        message: 'AniList forum threads from this user will appear here.',
      );
    }
    return Column(
      children: <Widget>[
        ...items.map(
          (AniListForumThread thread) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ForumThreadTile(thread: thread),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : hasMore
              ? OutlinedButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(context.t('Load more')),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ForumThreadTile extends StatelessWidget {
  const _ForumThreadTile({required this.thread});

  final AniListForumThread thread;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: thread.siteUrl == null || thread.siteUrl!.isEmpty
          ? null
          : () => _openExternal(thread.siteUrl!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  thread.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (thread.isSticky) const Icon(Icons.push_pin_outlined),
              if (thread.isLocked) const Icon(Icons.lock_outline_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _MetricPill(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${thread.replyCount}',
              ),
              _MetricPill(
                icon: Icons.favorite_outline_rounded,
                label: '${thread.likeCount}',
              ),
              _MetricPill(
                icon: Icons.visibility_outlined,
                label: '${thread.viewCount}',
              ),
              if (thread.repliedAt != null)
                _MetricPill(
                  icon: Icons.schedule_rounded,
                  label: _formatShortDate(thread.repliedAt!),
                ),
            ],
          ),
          if (thread.categories.isNotEmpty ||
              thread.mediaCategories.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              <String>[
                ...thread.categories,
                ...thread.mediaCategories,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ForumCommentSection extends StatelessWidget {
  const _ForumCommentSection({
    required this.items,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    super.key,
  });

  final List<AniListForumComment> items;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return const _EmptyPlaceholder(
        title: 'No comments yet',
        message: 'AniList forum comments from this user will appear here.',
      );
    }
    return Column(
      children: <Widget>[
        ...items.map(
          (AniListForumComment comment) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ForumCommentTile(comment: comment),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : hasMore
              ? OutlinedButton.icon(
                  onPressed: onLoadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(context.t('Load more')),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ForumCommentTile extends StatelessWidget {
  const _ForumCommentTile({required this.comment});

  final AniListForumComment comment;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: comment.siteUrl == null || comment.siteUrl!.isEmpty
          ? null
          : () => _openExternal(comment.siteUrl!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            comment.threadTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (comment.comment.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(comment.comment, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              _MetricPill(
                icon: Icons.favorite_outline_rounded,
                label: '${comment.likeCount}',
              ),
              if (comment.createdAt != null)
                _MetricPill(
                  icon: Icons.schedule_rounded,
                  label: _formatShortDate(comment.createdAt!),
                ),
              if (comment.isLocked)
                _MetricPill(
                  icon: Icons.lock_outline_rounded,
                  label: context.t('Locked'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatisticsSummaryCards extends StatelessWidget {
  const _StatisticsSummaryCards({required this.profile});

  final AniListUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final List<({IconData icon, String label, String value})> items =
        <({IconData icon, String label, String value})>[
          (
            icon: Icons.live_tv_rounded,
            label: 'Anime count',
            value: profile.animeStats.count.toString(),
          ),
          (
            icon: Icons.timer_rounded,
            label: 'Minutes watched',
            value: profile.animeStats.minutesWatched.toString(),
          ),
          (
            icon: Icons.menu_book_rounded,
            label: 'Manga count',
            value: profile.mangaStats.count.toString(),
          ),
          (
            icon: Icons.auto_stories_rounded,
            label: 'Chapters read',
            value: profile.mangaStats.chaptersRead.toString(),
          ),
        ];
    return ResponsiveGrid(
      itemCount: items.length,
      minItemWidth: 160,
      maxColumns: 4,
      childAspectRatio: 2.35,
      itemBuilder: (BuildContext context, int index) {
        final item = items[index];
        return GlassCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(item.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.t(item.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatisticsDetailGrid extends StatelessWidget {
  const _StatisticsDetailGrid({required this.stats, required this.anime});

  final AniListUserStatistics stats;
  final bool anime;

  @override
  Widget build(BuildContext context) {
    final List<({IconData icon, String label, String value})> details =
        <({IconData icon, String label, String value})>[
          (
            icon: anime ? Icons.live_tv_rounded : Icons.menu_book_rounded,
            label: anime ? 'Total Anime' : 'Total Manga',
            value: stats.count.toString(),
          ),
          (
            icon: anime ? Icons.play_circle_outline : Icons.auto_stories,
            label: anime ? 'Episodes Watched' : 'Chapters Read',
            value: anime
                ? stats.episodesWatched.toString()
                : stats.chaptersRead.toString(),
          ),
          (
            icon: anime ? Icons.calendar_month_outlined : Icons.bookmark_border,
            label: anime ? 'Days Watched' : 'Volumes Read',
            value: anime
                ? (stats.minutesWatched / 1440).toStringAsFixed(1)
                : stats.volumesRead.toString(),
          ),
          (
            icon: Icons.star_half_rounded,
            label: 'Mean Score',
            value: stats.meanScore.toStringAsFixed(1),
          ),
          (
            icon: Icons.calculate_outlined,
            label: 'Standard Deviation',
            value: stats.standardDeviation.toStringAsFixed(1),
          ),
        ];
    return ResponsiveGrid(
      itemCount: details.length,
      minItemWidth: 180,
      maxColumns: 5,
      childAspectRatio: 3.2,
      itemBuilder: (BuildContext context, int index) {
        final item = details[index];
        return GlassCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Icon(item.icon, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.t(item.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatisticBarSection extends StatelessWidget {
  const _StatisticBarSection({
    required this.title,
    required this.values,
    required this.valueLabel,
  });

  final String title;
  final List<AniListStatisticValue> values;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final List<AniListStatisticValue> visible = values
        .where((AniListStatisticValue item) => item.count > 0)
        .take(12)
        .toList(growable: false);
    if (visible.isEmpty) {
      return _StatisticListSection(title: title, values: values);
    }
    final int maxCount = visible
        .map((AniListStatisticValue value) => value.count)
        .fold<int>(1, (int a, int b) => a > b ? a : b);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title, subtitle: valueLabel),
          const SizedBox(height: AppSpacing.md),
          ...visible.map((AniListStatisticValue value) {
            final double fraction = value.count / maxCount;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 88,
                    child: Text(
                      value.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: AppRadius.all(AppRadius.sm),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: fraction.clamp(0.04, 1.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 40,
                    child: Text(
                      value.count.toString(),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatisticListSection extends StatelessWidget {
  const _StatisticListSection({required this.title, required this.values});

  final String title;
  final List<AniListStatisticValue> values;

  @override
  Widget build(BuildContext context) {
    final List<AniListStatisticValue> visible = values
        .take(8)
        .toList(growable: false);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(title: title),
          const SizedBox(height: AppSpacing.md),
          if (visible.isEmpty)
            Text(context.t('No data available yet.'))
          else
            ...visible.map(
              (AniListStatisticValue value) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        value.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      value.meanScore > 0
                          ? value.meanScore.toStringAsFixed(1)
                          : value.value > 0
                          ? value.value.toString()
                          : value.count.toString(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.item});

  final AniListReviewItem item;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: item.siteUrl == null || item.siteUrl!.isEmpty
          ? null
          : () => _openExternal(item.siteUrl!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (item.bannerUrl != null && item.bannerUrl!.isNotEmpty)
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadius.lg),
                ),
                child: Image(
                  image: CachedNetworkImageProvider(item.bannerUrl!),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _reviewTitle(context, item.mediaTitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      item.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.thumb_up_outlined, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text('${item.rating}/${item.ratingAmount}'),
                      const Spacer(),
                      Text(
                        item.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _MediaSummaryTile extends StatelessWidget {
  const _MediaSummaryTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: AppRadius.all(AppRadius.md),
            child: Container(
              width: 62,
              height: 90,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: item.posterUrl.isEmpty
                  ? const Icon(Icons.article_outlined)
                  : Image(
                      image: CachedNetworkImageProvider(item.posterUrl),
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.overview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedOutProfilePage extends StatelessWidget {
  const _SignedOutProfilePage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return _ProfileSubpage(
      title: title,
      subtitle: context.t('Sign in to AniList to use this profile section.'),
      child: const _SignedOutBody(),
    );
  }
}

class _SignedOutBody extends StatelessWidget {
  const _SignedOutBody();

  @override
  Widget build(BuildContext context) {
    return _EmptyPlaceholder(
      title: 'AniList not connected',
      message: 'This page becomes available after you sign in to AniList.',
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return NeutralPlaceholder(
      title: title,
      message: message,
      icon: Icons.inbox_outlined,
      height: 260,
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return NeutralPlaceholder(
      title: 'Something went wrong',
      message: message,
      icon: Icons.error_outline_rounded,
      height: 260,
    );
  }
}

class _ProfileAction {
  const _ProfileAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}

const List<_ProfileAction> _profileActions = <_ProfileAction>[
  _ProfileAction(
    title: 'Activities',
    subtitle: 'Your profile activity and tracking timeline.',
    icon: Icons.dynamic_feed_rounded,
    route: AppRoutes.profileActivities,
  ),
  _ProfileAction(
    title: 'Favourites',
    subtitle: 'Anime, manga, characters, staff, and studios.',
    icon: Icons.favorite_outline_rounded,
    route: AppRoutes.profileFavourites,
  ),
  _ProfileAction(
    title: 'Feed',
    subtitle: 'People you follow on AniList.',
    icon: Icons.rss_feed_rounded,
    route: AppRoutes.profileFeed,
  ),
  _ProfileAction(
    title: 'Social',
    subtitle: 'Followers and following lists.',
    icon: Icons.groups_rounded,
    route: AppRoutes.profileSocial,
  ),
  _ProfileAction(
    title: 'Statistics',
    subtitle: 'Anime and manga account totals.',
    icon: Icons.bar_chart_rounded,
    route: AppRoutes.profileStatistics,
  ),
  _ProfileAction(
    title: 'Reviews',
    subtitle: 'Recent AniList reviews.',
    icon: Icons.rate_review_outlined,
    route: AppRoutes.profileReviews,
  ),
  _ProfileAction(
    title: 'AniList Settings',
    subtitle: 'AnimeShin content and list preferences.',
    icon: Icons.tune_rounded,
    route: AppRoutes.profileSettings,
  ),
];

String _countLabel(BuildContext context, String label, int count) {
  final String translated = context.t(label);
  return switch (Localizations.localeOf(context).languageCode) {
    'ja' => '$translated: $count',
    _ => '$translated: $count',
  };
}

String _activityTitle(BuildContext context, AniListActivity item) {
  final String name = item.primaryUser.name;
  return switch ((Localizations.localeOf(context).languageCode, item.type)) {
    ('ru', 'TEXT') => '$name опубликовал(а) обновление',
    ('ru', 'MESSAGE') => '$name отправил(а) сообщение',
    ('ru', _) => '$name обновил(а) ${item.media?.title ?? context.t('media')}',
    ('ja', 'TEXT') => '$name が更新を投稿しました',
    ('ja', 'MESSAGE') => '$name がメッセージを送信しました',
    ('ja', _) => '$name が ${item.media?.title ?? context.t('media')} を記録しました',
    (_, 'TEXT') => '$name posted an update',
    (_, 'MESSAGE') => '$name sent a message',
    _ => '$name tracked ${item.media?.title ?? 'media'}',
  };
}

String _emptyKindMessage(BuildContext context, String label) {
  final String translated = context.t(label).toLowerCase();
  return switch (Localizations.localeOf(context).languageCode) {
    'ru' => '$translated пока нет.',
    'ja' => '$translatedはまだありません。',
    _ => 'No $translated yet.',
  };
}

String _reviewTitle(BuildContext context, String mediaTitle) {
  return switch (Localizations.localeOf(context).languageCode) {
    'ru' => 'Обзор: $mediaTitle',
    'ja' => '$mediaTitle のレビュー',
    _ => 'Review of $mediaTitle',
  };
}

String _createActivitiesTitle(BuildContext context, AniListListStatus status) {
  final String label = context.t(status.label);
  return switch (Localizations.localeOf(context).languageCode) {
    'ru' => 'Создавать активности: $label',
    'ja' => '$labelのアクティビティを作成',
    _ => 'Create $label Activities',
  };
}

Future<void> _openExternal(String rawUrl) async {
  final Uri uri = Uri.parse(rawUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _formatShortDate(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

Future<void> _showStatusComposer(
  BuildContext context,
  WidgetRef ref,
  AniListActivitiesQuery query,
) async {
  final TextEditingController controller = TextEditingController();
  final String? text = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(context.t('New Post')),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.t('Share an AniList status update...'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.t('Post')),
          ),
        ],
      );
    },
  );
  controller.dispose();
  final String trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty || !context.mounted) return;
  try {
    await ref
        .read(aniListProfileClientProvider)
        .saveTextActivity(text: trimmed);
    ref.invalidate(aniListActivitiesProvider(query));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.t('Failed to post')}: $error')),
    );
  }
}

Future<void> _showExportSheet(
  BuildContext context,
  WidgetRef ref, {
  required AniListExportTarget target,
}) async {
  final SettingsState settings = ref.read(settingsProvider);
  final int? userId = settings.anilistViewerId;
  final String username = settings.anilistViewerName ?? 'AniList User';
  if (!settings.hasAniListSession || userId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('Please sign in to export'))),
    );
    return;
  }

  final bool? anime = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.live_tv_rounded),
                title: Text(context.t('Anime')),
                onTap: () => Navigator.of(context).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: Text(context.t('Manga')),
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (anime == null || !context.mounted) return;

  final AniListApiClient client = ref.read(aniListProfileClientProvider);
  final VoidCallback closeProgressDialog = await _showBlockingProgressDialog(
    context,
    context.t('Exporting...'),
  );

  try {
    final AniListExportPayload? payload = await buildAniListExportPayload(
      client: client,
      userId: userId,
      username: username,
      anime: anime,
      target: target,
    ).timeout(const Duration(seconds: 35));
    closeProgressDialog();
    if (!context.mounted) return;
    if (payload == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Nothing to export'))));
      return;
    }
    final String? savedPath = await saveAniListExportPayload(context, payload);
    if (!context.mounted) return;
    if (savedPath == null) {
      return;
    }
    if (savedPath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Export file shared'))));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.t('Exported to')}: $savedPath')),
    );
  } on TimeoutException {
    closeProgressDialog();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.t('Export timeout. Check connection and try again.'),
        ),
      ),
    );
  } catch (error) {
    closeProgressDialog();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.t('Export failed')}: $error')),
    );
  }
}

Future<VoidCallback> _showBlockingProgressDialog(
  BuildContext context,
  String message,
) async {
  final Completer<BuildContext> dialogContext = Completer<BuildContext>();
  var closed = false;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        if (!dialogContext.isCompleted) {
          scheduleMicrotask(() => dialogContext.complete(context));
        }
        return AlertDialog(
          content: Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(message),
            ],
          ),
        );
      },
    ).catchError((Object error) {
      if (!dialogContext.isCompleted) {
        dialogContext.completeError(error);
      }
    }),
  );

  final BuildContext mountedDialogContext = await dialogContext.future;
  return () {
    if (closed) return;
    closed = true;
    if (!mountedDialogContext.mounted) return;
    final NavigatorState navigator = Navigator.of(
      mountedDialogContext,
      rootNavigator: true,
    );
    if (navigator.canPop()) navigator.pop();
  };
}

Future<void> _invalidateAniListScope(
  WidgetRef ref, {
  bool clearMetadataCache = true,
}) async {
  if (clearMetadataCache) {
    await ref.read(metadataCacheStoreProvider).removeByPrefix('anilist');
  }
  ref.invalidate(aniListViewerProfileProvider);
  invalidateAniListLibraryProviders(ref.invalidate);
  ref.invalidate(activeCatalogRepositoryProvider);
  ref.invalidate(boardRailsProvider);
  ref.invalidate(discoveryMetadataProvider);
  ref.invalidate(mediaDetailsProvider);
}
