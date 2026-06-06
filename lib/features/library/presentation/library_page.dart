import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/library_item.dart';
import '../../../shared/models/media_item.dart';
import '../../../shared/utils/media_status_formatter.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../catalog/application/catalog_status.dart';
import '../../catalog/presentation/catalog_offline_banner.dart';
import '../../profile/application/anilist_user_settings_provider.dart';
import '../application/local_library_provider.dart';
import 'local_library_editor.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../tracking/application/anilist_login_flow.dart';
import '../../tracking/presentation/anilist_entry_editor.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const double _kTileHeight = 156.0;
const double _kCoverAspect = 1.45; // H:W ratio (same as AnimeShin)
const double _kCoverWidth = _kTileHeight / _kCoverAspect;
const Duration _kSlowFullListThreshold = Duration(seconds: 4);

const List<AniListListStatus> _kStatusOrder = <AniListListStatus>[
  AniListListStatus.current,
  AniListListStatus.planning,
  AniListListStatus.completed,
  AniListListStatus.paused,
  AniListListStatus.dropped,
  AniListListStatus.repeating,
];

List<AniListAnimeListFolder> _orderedFolders(List<AniListAnimeListFolder> src) {
  final Map<AniListListStatus, AniListAnimeListFolder> byStatus =
      <AniListListStatus, AniListAnimeListFolder>{};
  for (final AniListAnimeListFolder f in src) {
    if (f.status != null) byStatus[f.status!] = f;
  }
  final List<AniListAnimeListFolder> ordered = _kStatusOrder
      .where(byStatus.containsKey)
      .map((AniListListStatus s) => byStatus[s]!)
      .where((AniListAnimeListFolder f) => f.entries.isNotEmpty)
      .toList(growable: false);
  final List<AniListAnimeListFolder> extras = src
      .where(
        (AniListAnimeListFolder folder) =>
            folder.entries.isNotEmpty &&
            (folder.status == null || !_kStatusOrder.contains(folder.status)),
      )
      .toList(growable: false);
  if (extras.isEmpty) {
    return ordered;
  }
  return <AniListAnimeListFolder>[...ordered, ...extras];
}

bool _hasAnyEntries(List<AniListAnimeListFolder> folders) {
  return folders.any(
    (AniListAnimeListFolder folder) => folder.entries.isNotEmpty,
  );
}

// ─── Sort ─────────────────────────────────────────────────────────────────────

enum _Sort {
  titleAZ('Title A–Z'),
  titleZA('Title Z–A'),
  scoreHigh('Score ↓'),
  scoreLow('Score ↑'),
  progressHigh('Progress ↓'),
  progressLow('Progress ↑'),
  updatedNewest('Updated Newest'),
  updatedOldest('Updated Oldest'),
  addedNewest('Added Newest'),
  addedOldest('Added Oldest'),
  repeatHigh('Rewatches ↓'),
  repeatLow('Rewatches ↑'),
  airingNearest('Airing Next'),
  avgScoreHigh('Avg Score ↓'),
  avgScoreLow('Avg Score ↑');

  const _Sort(this.label);
  final String label;
}

enum _LibraryFlag {
  airingSoon('Airing soon'),
  behind('Behind'),
  hasNotes('Has notes'),
  repeating('Repeating'),
  unscored('Unscored'),
  unstarted('Not started'),
  finishedProgress('Finished progress');

  const _LibraryFlag(this.label);
  final String label;
}

enum _AniListTabPhase { loading, content, previewEmpty, empty, offline }

class _AniListStatusBannerState {
  const _AniListStatusBannerState({
    required this.message,
    this.isLoading = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isLoading;
  final String? actionLabel;
  final Future<void> Function()? onAction;
}

class _AniListTabViewState {
  const _AniListTabViewState({
    required this.phase,
    this.folders = const <AniListAnimeListFolder>[],
    this.loadingTitle,
    this.loadingMessage,
    this.offlineTitle,
    this.offlineMessage,
    this.banner,
    this.onRetry,
  });

  final _AniListTabPhase phase;
  final List<AniListAnimeListFolder> folders;
  final String? loadingTitle;
  final String? loadingMessage;
  final String? offlineTitle;
  final String? offlineMessage;
  final _AniListStatusBannerState? banner;
  final Future<void> Function()? onRetry;
}

// ─── Root page ────────────────────────────────────────────────────────────────

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _mainTab;

  @override
  void initState() {
    super.initState();
    _mainTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _mainTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final SettingsState settings = ref.watch(settingsProvider);

    if (mode == CatalogMode.tmdb) {
      final localLibrary = ref
          .watch(localLibraryProvider)
          .where((LibraryItem item) => item.mediaItem.id.startsWith('tmdb:'))
          .toList(growable: false);
      return _LocalLibraryView(items: localLibrary);
    }

    final bool connected = settings.anilistAccessToken.trim().isNotEmpty;
    return Column(
      children: <Widget>[
        const CatalogOfflineBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: TabBar(
            controller: _mainTab,
            tabs: const <Widget>[
              Tab(text: 'Anime'),
              Tab(text: 'Manga'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _mainTab,
            children: <Widget>[
              _AniListDataTab(
                connected: connected,
                mediaType: 'ANIME',
                defaultPage: settings.anilistLibraryDefaultPage,
                emptyMessage:
                    'Add anime to your AniList account to see them here.',
              ),
              _AniListDataTab(
                connected: connected,
                mediaType: 'MANGA',
                defaultPage: settings.anilistLibraryDefaultPage,
                emptyMessage:
                    'Add manga to your AniList account to see them here.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AniListDataTab extends ConsumerStatefulWidget {
  const _AniListDataTab({
    required this.connected,
    required this.mediaType,
    required this.defaultPage,
    required this.emptyMessage,
  });

  final bool connected;
  final String mediaType;
  final AniListLibraryDefaultPage defaultPage;
  final String emptyMessage;

  @override
  ConsumerState<_AniListDataTab> createState() => _AniListDataTabState();
}

class _AniListDataTabState extends ConsumerState<_AniListDataTab>
    with AutomaticKeepAliveClientMixin {
  Timer? _slowFullListTimer;
  DateTime? _fullListPendingSince;
  bool _showSlowFullList = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _slowFullListTimer?.cancel();
    super.dispose();
  }

  void _syncSlowFullListState(bool waitingForFirstFullResult) {
    if (!waitingForFirstFullResult) {
      _slowFullListTimer?.cancel();
      _slowFullListTimer = null;
      _fullListPendingSince = null;
      _showSlowFullList = false;
      return;
    }

    _fullListPendingSince ??= DateTime.now();
    if (_showSlowFullList) {
      return;
    }

    final Duration elapsed = DateTime.now().difference(_fullListPendingSince!);
    if (elapsed >= _kSlowFullListThreshold) {
      _showSlowFullList = true;
      _slowFullListTimer?.cancel();
      _slowFullListTimer = null;
      return;
    }

    _slowFullListTimer ??= Timer(_kSlowFullListThreshold - elapsed, () {
      if (!mounted) return;
      setState(() {
        _showSlowFullList = true;
        _slowFullListTimer = null;
      });
    });
  }

  String get _previewLoadingTitle => widget.mediaType == 'MANGA'
      ? 'Loading your AniList manga library...'
      : 'Loading your AniList anime library...';

  String get _previewLoadingMessage => widget.mediaType == 'MANGA'
      ? 'Fetching reading and rereading first.'
      : 'Fetching watching and rewatching first.';

  String get _fullListBannerMessage => widget.mediaType == 'MANGA'
      ? _showSlowFullList
            ? 'Still loading full list. Showing Reading and Rereading while AniList catches up.'
            : 'Loading full list in the background. Showing Reading and Rereading first.'
      : _showSlowFullList
      ? 'Still loading full list. Showing Watching and Rewatching while AniList catches up.'
      : 'Loading full list in the background. Showing Watching and Rewatching first.';

  String get _fullListUnavailableMessage => widget.mediaType == 'MANGA'
      ? 'Full list unavailable right now. Showing Reading and Rereading only.'
      : 'Full list unavailable right now. Showing Watching and Rewatching only.';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!widget.connected) {
      return _AniListTabContent(
        connected: false,
        state: const _AniListTabViewState(phase: _AniListTabPhase.empty),
        mediaType: widget.mediaType,
        defaultPage: widget.defaultPage,
        emptyMessage: widget.emptyMessage,
      );
    }

    final CatalogOfflineNotice? offlineNotice = ref.watch(
      catalogOfflineNoticeProvider,
    );
    final CatalogOfflineNotice? anilistOfflineNotice =
        offlineNotice?.mode == CatalogMode.anilist ? offlineNotice : null;
    final bool wantsRussianTitles =
        widget.mediaType == 'ANIME' &&
        ref.watch(aniListEffectiveTitleLanguageProvider) == 'RUSSIAN';

    final AsyncValue<List<AniListAnimeListFolder>> previewLists =
        widget.mediaType == 'MANGA'
        ? ref.watch(anilistMangaPreviewListProvider)
        : ref.watch(anilistAnimePreviewListProvider);
    final List<AniListAnimeListFolder> previewSourceFolders =
        previewLists.maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> value) => value,
          orElse: () => const <AniListAnimeListFolder>[],
        ) ??
        const <AniListAnimeListFolder>[];
    final List<AniListAnimeListFolder> previewFolders = previewLists.maybeWhen(
      skipLoadingOnReload: true,
      data: (List<AniListAnimeListFolder> value) => _orderedFolders(value),
      orElse: () => const <AniListAnimeListFolder>[],
    );
    final AniListLibraryLoadStatus fullLoadStatus =
        watchAniListLibraryLoadStatus(ref, mediaType: widget.mediaType);
    final AsyncValue<List<AniListAnimeListFolder>> fullLists =
        widget.mediaType == 'MANGA'
        ? ref.watch(anilistMangaListProvider)
        : ref.watch(anilistAnimeListProvider);
    final List<AniListAnimeListFolder> fullSourceFolders =
        fullLists.maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> value) => value,
          orElse: () => const <AniListAnimeListFolder>[],
        ) ??
        const <AniListAnimeListFolder>[];
    final List<AniListAnimeListFolder> fullFolders =
        fullLists.maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> value) => _orderedFolders(value),
          orElse: () => const <AniListAnimeListFolder>[],
        ) ??
        const <AniListAnimeListFolder>[];

    final AsyncValue<List<AniListAnimeListFolder>>? previewRussianLists =
        wantsRussianTitles
        ? ref.watch(anilistAnimePreviewRussianListProvider)
        : null;
    final AsyncValue<List<AniListAnimeListFolder>>? fullRussianLists =
        wantsRussianTitles && fullLists.hasValue
        ? ref.watch(anilistAnimeRussianListProvider)
        : null;

    final List<AniListAnimeListFolder> previewDisplayFolders =
        previewRussianLists?.maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> value) => _orderedFolders(value),
          orElse: () => previewFolders,
        ) ??
        previewFolders;
    final List<AniListAnimeListFolder> fullDisplayFolders =
        fullRussianLists?.maybeWhen(
          skipLoadingOnReload: true,
          data: (List<AniListAnimeListFolder> value) => _orderedFolders(value),
          orElse: () => fullFolders,
        ) ??
        fullFolders;

    final bool fullResolved = fullLists.hasValue || fullLists.hasError;
    final bool fullSucceeded =
        fullLoadStatus.phase == AniListLibraryLoadPhase.success;
    final bool previewRussianPending =
        wantsRussianTitles &&
        previewRussianLists != null &&
        previewRussianLists.isLoading &&
        !previewRussianLists.hasValue;
    final bool fullRussianPending =
        wantsRussianTitles &&
        fullRussianLists != null &&
        fullRussianLists.isLoading &&
        !fullRussianLists.hasValue;
    final bool hasPreviewContent = previewDisplayFolders.isNotEmpty;
    final bool hasFullContent = fullDisplayFolders.isNotEmpty;
    // Spinner while no content yet and at least one provider is doing its first load
    final bool waitingForInitialPreview =
        !hasPreviewContent &&
        !hasFullContent &&
        ((previewLists.isLoading && !previewLists.hasValue) ||
            (fullLists.isLoading && !fullLists.hasValue));
    // Banner while preview has content but full list hasn't produced results yet
    final bool waitingForFirstFullResult =
        hasPreviewContent &&
        !hasFullContent &&
        fullLists.isLoading &&
        !fullLists.hasValue;
    _syncSlowFullListState(waitingForFirstFullResult);

    final List<AniListAnimeListFolder> displayFolders = hasFullContent
        ? fullDisplayFolders
        : hasPreviewContent
        ? previewDisplayFolders
        : const <AniListAnimeListFolder>[];
    final bool fullUnavailable =
        hasPreviewContent && !hasFullContent && fullLoadStatus.isFailed;
    final bool showOfflinePlaceholder =
        displayFolders.isEmpty &&
        fullLoadStatus.isFailed &&
        !fullLists.isLoading;
    final bool showEmptyPlaceholder =
        displayFolders.isEmpty &&
        fullSucceeded &&
        fullResolved &&
        !fullLists.isLoading &&
        !fullLoadStatus.isFailed &&
        !_hasAnyEntries(previewSourceFolders) &&
        !_hasAnyEntries(fullSourceFolders);

    _AniListStatusBannerState? banner;
    if (waitingForFirstFullResult) {
      banner = _AniListStatusBannerState(
        message: _fullListBannerMessage,
        isLoading: true,
      );
    } else if (fullUnavailable) {
      final String? errorDetail = anilistOfflineNotice?.detail;
      banner = _AniListStatusBannerState(
        message: errorDetail != null
            ? '$_fullListUnavailableMessage\nError: $errorDetail'
            : _fullListUnavailableMessage,
        actionLabel: 'Retry',
        onAction: () =>
            retryAniListFullListForMediaType(ref, mediaType: widget.mediaType),
      );
    } else if ((hasFullContent && fullRussianPending) ||
        (!hasFullContent && hasPreviewContent && previewRussianPending)) {
      banner = const _AniListStatusBannerState(
        message: 'Updating Russian titles in the background.',
        isLoading: true,
      );
    }

    final _AniListTabViewState state;
    if (waitingForInitialPreview) {
      state = _AniListTabViewState(
        phase: _AniListTabPhase.loading,
        loadingTitle: _previewLoadingTitle,
        loadingMessage: _previewLoadingMessage,
      );
    } else if (showOfflinePlaceholder) {
      state = _AniListTabViewState(
        phase: _AniListTabPhase.offline,
        offlineTitle:
            anilistOfflineNotice?.title ?? 'AniList is temporarily unavailable',
        offlineMessage:
            anilistOfflineNotice?.message ??
            'MiruShin cannot load this page yet because the AniList full list request failed. Please try again later.',
        onRetry: () =>
            refreshAniListLibraryForMediaType(ref, mediaType: widget.mediaType),
      );
    } else if (showEmptyPlaceholder) {
      state = const _AniListTabViewState(phase: _AniListTabPhase.empty);
    } else {
      state = _AniListTabViewState(
        phase: _AniListTabPhase.content,
        folders: displayFolders,
        banner: banner,
      );
    }

    return _AniListTabContent(
      connected: true,
      state: state,
      mediaType: widget.mediaType,
      defaultPage: widget.defaultPage,
      emptyMessage: widget.emptyMessage,
    );
  }
}

// ─── AniList tab content ──────────────────────────────────────────────────────

class _AniListTabContent extends ConsumerWidget {
  const _AniListTabContent({
    required this.connected,
    required this.state,
    required this.mediaType,
    required this.defaultPage,
    required this.emptyMessage,
  });

  final bool connected;
  final _AniListTabViewState state;
  final String mediaType;
  final AniListLibraryDefaultPage defaultPage;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.phase == _AniListTabPhase.loading) {
      return _AniListLoadingState(
        title: state.loadingTitle!,
        message: state.loadingMessage,
      );
    }
    if (!connected) {
      return NeutralPlaceholder(
        title: 'AniList not connected',
        message: 'Sign in to sync your anime library with AniList.',
        icon: Icons.link_off_rounded,
        height: 300,
        action: FilledButton.icon(
          onPressed: () => loginAniList(context, ref),
          icon: const Icon(Icons.login_rounded),
          label: Text(context.t('Sign in with AniList')),
        ),
      );
    }
    if (state.phase == _AniListTabPhase.offline &&
        state.offlineTitle != null &&
        state.offlineMessage != null) {
      return NeutralPlaceholder(
        title: state.offlineTitle!,
        message: state.offlineMessage!,
        icon: Icons.cloud_off_rounded,
        height: 300,
        action: FilledButton.icon(
          onPressed: () {
            final Future<void> Function()? onRetry = state.onRetry;
            if (onRetry != null) {
              unawaited(onRetry());
            }
          },
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.t('Retry')),
        ),
      );
    }
    if (state.phase == _AniListTabPhase.previewEmpty) {
      return Column(
        children: <Widget>[
          if (state.banner != null) _AniListBannerBox(banner: state.banner!),
          Expanded(
            child: NeutralPlaceholder(
              title: state.loadingTitle ?? 'Preview list is empty',
              message: state.loadingMessage ?? '',
              icon: Icons.playlist_add_check_rounded,
              height: 300,
            ),
          ),
        ],
      );
    }
    if (state.phase == _AniListTabPhase.empty) {
      return NeutralPlaceholder(
        title: 'AniList library is empty',
        message: emptyMessage,
        icon: Icons.video_library_rounded,
        height: 300,
      );
    }
    final Widget libraryView = _AniListView(
      folders: state.folders,
      mediaType: mediaType,
      defaultPage: defaultPage,
    );
    if (state.banner == null) {
      return libraryView;
    }
    return Column(
      children: <Widget>[
        _AniListBannerBox(banner: state.banner!),
        Expanded(child: libraryView),
      ],
    );
  }
}

class _AniListBannerBox extends StatelessWidget {
  const _AniListBannerBox({required this.banner});

  final _AniListStatusBannerState banner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: _AniListStatusBanner(banner: banner),
      ),
    );
  }
}

class _AniListStatusBanner extends StatelessWidget {
  const _AniListStatusBanner({required this.banner});

  final _AniListStatusBannerState banner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (banner.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline_rounded, size: 18),
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  banner.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (banner.actionLabel != null && banner.onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: TextButton.icon(
                      onPressed: () => unawaited(banner.onAction!.call()),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(banner.actionLabel!),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 0,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AniListLoadingState extends StatelessWidget {
  const _AniListLoadingState({required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppThemeExtension.of(context).textMutedColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── AniList tabbed view ──────────────────────────────────────────────────────

class _AniListView extends ConsumerStatefulWidget {
  const _AniListView({
    required this.folders,
    required this.mediaType,
    required this.defaultPage,
  });

  final List<AniListAnimeListFolder> folders;
  final String mediaType;
  final AniListLibraryDefaultPage defaultPage;

  @override
  ConsumerState<_AniListView> createState() => _AniListViewState();
}

class _AniListViewState extends ConsumerState<_AniListView>
    with TickerProviderStateMixin {
  late TabController _tab;
  int _activeTabIndex = 0;

  List<AniListAnimeListFolder> get _viewFolders {
    final Map<int, AniListAnimeListEntry> byEntryId =
        <int, AniListAnimeListEntry>{};
    for (final AniListAnimeListFolder folder in widget.folders) {
      for (final AniListAnimeListEntry entry in folder.entries) {
        byEntryId[entry.id] = entry;
      }
    }
    return <AniListAnimeListFolder>[
      AniListAnimeListFolder(
        name: 'All',
        status: null,
        entries: byEntryId.values.toList(growable: false),
      ),
      ...widget.folders,
    ];
  }

  @override
  void initState() {
    super.initState();
    final List<AniListAnimeListFolder> folders = _viewFolders;
    _activeTabIndex = _defaultFolderIndex(folders, widget.defaultPage);
    _tab = TabController(
      length: folders.length,
      vsync: this,
      initialIndex: _activeTabIndex,
    );
    _tab.addListener(_handleTabChanged);
  }

  @override
  void didUpdateWidget(_AniListView old) {
    super.didUpdateWidget(old);
    final List<AniListAnimeListFolder> folders = _viewFolders;
    final int nextLength = folders.length;
    if (_tab.length != nextLength) {
      final int prev = old.defaultPage != widget.defaultPage
          ? _defaultFolderIndex(folders, widget.defaultPage)
          : _tab.index.clamp(0, nextLength - 1);
      _tab.removeListener(_handleTabChanged);
      _tab.dispose();
      _tab = TabController(length: nextLength, vsync: this, initialIndex: prev);
      _activeTabIndex = prev;
      _tab.addListener(_handleTabChanged);
    } else if (old.defaultPage != widget.defaultPage) {
      _tab.animateTo(_defaultFolderIndex(folders, widget.defaultPage));
    } else if (_activeTabIndex >= nextLength) {
      _activeTabIndex = nextLength - 1;
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_handleTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    final int next = _tab.index;
    if (next == _activeTabIndex || !mounted) return;
    setState(() => _activeTabIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final List<AniListAnimeListFolder> folders = _viewFolders;
    return Column(
      children: <Widget>[
        TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: palette.textMutedColor,
          dividerColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          tabs: folders.map((f) {
            final String name = context.t(_folderLabel(f));
            return Tab(text: '$name  ${f.entries.length}');
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: folders.asMap().entries.map((entry) {
              return _FolderView(
                folder: entry.value,
                mediaType: widget.mediaType,
                enableRussianAliasLoad: entry.key == _activeTabIndex,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _folderLabel(AniListAnimeListFolder folder) {
    return switch (folder.status) {
      AniListListStatus.current =>
        widget.mediaType == 'MANGA' ? 'Reading' : 'Watching',
      AniListListStatus.repeating =>
        widget.mediaType == 'MANGA' ? 'Rereading' : 'Rewatching',
      null => folder.name,
      _ => folder.status!.label,
    };
  }

  int _defaultFolderIndex(
    List<AniListAnimeListFolder> folders,
    AniListLibraryDefaultPage defaultPage,
  ) {
    final AniListListStatus? status = defaultPage.status;
    if (status == null) return 0;
    final int index = folders.indexWhere(
      (AniListAnimeListFolder folder) =>
          folder.status == status && folder.entries.isNotEmpty,
    );
    return index < 0 ? 0 : index;
  }
}

// ─── Per-status folder view ───────────────────────────────────────────────────

class _FolderView extends ConsumerStatefulWidget {
  const _FolderView({
    required this.folder,
    required this.mediaType,
    required this.enableRussianAliasLoad,
  });

  final AniListAnimeListFolder folder;
  final String mediaType;
  final bool enableRussianAliasLoad;

  @override
  ConsumerState<_FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends ConsumerState<_FolderView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _search = TextEditingController();
  _Sort _sort = _Sort.titleAZ;
  final Set<AniListListStatus> _statuses = {};
  final Set<String> _mediaStatuses = {};
  final Set<String> _genres = {};
  final Set<String> _formats = {};
  final Set<_LibraryFlag> _flags = {};
  double _minScore = 0;
  bool _isGrid = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedPreferences());
  }

  @override
  void didUpdateWidget(covariant _FolderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preferencesPrefixFor(oldWidget.folder, oldWidget.mediaType) !=
        _preferencesPrefix) {
      unawaited(_loadSavedPreferences());
    }
  }

  String get _preferencesPrefix {
    return _preferencesPrefixFor(widget.folder, widget.mediaType);
  }

  String get _folderDisplayName {
    return switch (widget.folder.status) {
      AniListListStatus.current =>
        widget.mediaType == 'MANGA' ? 'Reading' : 'Watching',
      AniListListStatus.repeating =>
        widget.mediaType == 'MANGA' ? 'Rereading' : 'Rewatching',
      null => widget.folder.name,
      _ => widget.folder.status!.label,
    };
  }

  String _emptyEntriesMessage(bool filterActive) {
    if (widget.folder.entries.isEmpty) {
      return 'No entries in $_folderDisplayName yet.';
    }
    if (filterActive || _search.text.trim().isNotEmpty) {
      return 'No matching entries.';
    }
    return 'No entries here yet.';
  }

  String _preferencesPrefixFor(
    AniListAnimeListFolder folder,
    String mediaType,
  ) {
    final String status = folder.status?.name ?? folder.name;
    return 'library.anilist.$mediaType.$status';
  }

  Future<void> _loadSavedPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String prefix = _preferencesPrefix;
    final String? sortName = prefs.getString('$prefix.sort');
    final _Sort savedSort = _Sort.values.firstWhere(
      (_Sort sort) => sort.name == sortName,
      orElse: () => _sort,
    );
    final List<String> savedGenres =
        prefs.getStringList('$prefix.genres') ?? const <String>[];
    final List<String> savedFormats =
        prefs.getStringList('$prefix.formats') ?? const <String>[];
    final List<String> savedStatuses =
        prefs.getStringList('$prefix.statuses') ?? const <String>[];
    final List<String> savedMediaStatuses =
        prefs.getStringList('$prefix.mediaStatuses') ?? const <String>[];
    final List<String> savedFlags =
        prefs.getStringList('$prefix.flags') ?? const <String>[];
    final double savedMinScore = prefs.getDouble('$prefix.minScore') ?? 0;
    final bool savedGrid = prefs.getBool('$prefix.grid') ?? _isGrid;
    if (!mounted) return;
    setState(() {
      _sort = savedSort;
      _isGrid = savedGrid;
      _statuses
        ..clear()
        ..addAll(
          savedStatuses.map(_statusFromName).whereType<AniListListStatus>(),
        );
      _mediaStatuses
        ..clear()
        ..addAll(savedMediaStatuses);
      _genres
        ..clear()
        ..addAll(savedGenres);
      _formats
        ..clear()
        ..addAll(savedFormats);
      _flags
        ..clear()
        ..addAll(savedFlags.map(_flagFromName).whereType<_LibraryFlag>());
      _minScore = savedMinScore.clamp(0, 10).toDouble();
    });
  }

  Future<void> _savePreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String prefix = _preferencesPrefix;
    await prefs.setString('$prefix.sort', _sort.name);
    await prefs.setBool('$prefix.grid', _isGrid);
    await prefs.setStringList(
      '$prefix.statuses',
      _statuses.map((AniListListStatus status) => status.name).toList()..sort(),
    );
    await prefs.setStringList(
      '$prefix.mediaStatuses',
      _mediaStatuses.toList()..sort(),
    );
    await prefs.setStringList('$prefix.genres', _genres.toList()..sort());
    await prefs.setStringList('$prefix.formats', _formats.toList()..sort());
    await prefs.setStringList(
      '$prefix.flags',
      _flags.map((_LibraryFlag flag) => flag.name).toList()..sort(),
    );
    await prefs.setDouble('$prefix.minScore', _minScore);
  }

  List<AniListAnimeListEntry> get _filtered {
    final String q = _search.text.toLowerCase().trim();
    final Map<int, String> russianAliasesByMalId = _russianAliasesByMalId;
    List<AniListAnimeListEntry> list = widget.folder.entries;

    if (q.isNotEmpty) {
      list = list
          .where((e) {
            final int? malId = _malIdForMediaItem(e.mediaItem);
            final String russianAlias = malId == null
                ? ''
                : russianAliasesByMalId[malId] ?? '';
            final List<String> searchable = <String>[
              e.mediaItem.title,
              e.mediaItem.originalTitle,
              ...e.mediaItem.aliases,
              russianAlias,
              ...e.mediaItem.genres,
              e.format ?? '',
              e.status.label,
              _humanizeMediaStatus(e.mediaItem.statusLabel),
            ];
            return searchable.any(
              (String value) => value.toLowerCase().contains(q),
            );
          })
          .toList(growable: false);
    }

    if (_statuses.isNotEmpty) {
      list = list
          .where((AniListAnimeListEntry e) => _statuses.contains(e.status))
          .toList(growable: false);
    }

    if (_mediaStatuses.isNotEmpty) {
      list = list
          .where(
            (AniListAnimeListEntry e) => _mediaStatuses.contains(
              _humanizeMediaStatus(e.mediaItem.statusLabel),
            ),
          )
          .toList(growable: false);
    }

    if (_genres.isNotEmpty) {
      list = list
          .where((e) => _genres.any(e.mediaItem.genres.contains))
          .toList(growable: false);
    }

    if (_formats.isNotEmpty) {
      list = list
          .where((e) => e.format != null && _formats.contains(e.format))
          .toList(growable: false);
    }

    if (_minScore > 0) {
      list = list
          .where((AniListAnimeListEntry e) => (e.score ?? 0) >= _minScore)
          .toList(growable: false);
    }

    if (_flags.isNotEmpty) {
      list = list
          .where(
            (AniListAnimeListEntry e) =>
                _flags.every((_LibraryFlag flag) => _matchesFlag(e, flag)),
          )
          .toList(growable: false);
    }

    list = List<AniListAnimeListEntry>.from(list);
    switch (_sort) {
      case _Sort.titleAZ:
        list.sort((a, b) => a.mediaItem.title.compareTo(b.mediaItem.title));
      case _Sort.titleZA:
        list.sort((a, b) => b.mediaItem.title.compareTo(a.mediaItem.title));
      case _Sort.scoreHigh:
        list.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
      case _Sort.scoreLow:
        list.sort((a, b) => (a.score ?? 0).compareTo(b.score ?? 0));
      case _Sort.progressHigh:
        list.sort((a, b) => b.progress.compareTo(a.progress));
      case _Sort.progressLow:
        list.sort((a, b) => a.progress.compareTo(b.progress));
      case _Sort.updatedNewest:
        list.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
      case _Sort.updatedOldest:
        list.sort((a, b) => (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0));
      case _Sort.addedNewest:
        list.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
      case _Sort.addedOldest:
        list.sort((a, b) => (a.createdAt ?? 0).compareTo(b.createdAt ?? 0));
      case _Sort.repeatHigh:
        list.sort((a, b) => b.repeat.compareTo(a.repeat));
      case _Sort.repeatLow:
        list.sort((a, b) => a.repeat.compareTo(b.repeat));
      case _Sort.airingNearest:
        list.sort((a, b) {
          if (a.airingAt == null && b.airingAt == null) return 0;
          if (a.airingAt == null) return 1;
          if (b.airingAt == null) return -1;
          return a.airingAt!.compareTo(b.airingAt!);
        });
      case _Sort.avgScoreHigh:
        list.sort((a, b) => (b.avgScore ?? 0).compareTo(a.avgScore ?? 0));
      case _Sort.avgScoreLow:
        list.sort((a, b) => (a.avgScore ?? 0).compareTo(b.avgScore ?? 0));
    }
    return list;
  }

  Map<int, String> get _russianAliasesByMalId {
    if (widget.mediaType != 'ANIME' || !widget.enableRussianAliasLoad) {
      return const <int, String>{};
    }

    final bool isAllTab = widget.folder.status == null;
    final bool hasRussianSearch = _hasCyrillic(_search.text);
    final bool loadNetwork = !isAllTab || hasRussianSearch;
    final int? viewerId = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.anilistViewerId,
      ),
    );
    return ref
        .watch(
          anilistRussianAliasProvider(
            AniListRussianAliasRequest(
              viewerId: viewerId,
              mediaType: widget.mediaType,
              statusKey: widget.folder.status?.name ?? 'all',
              malIds: widget.folder.entries
                  .map(
                    (AniListAnimeListEntry entry) =>
                        _malIdForMediaItem(entry.mediaItem),
                  )
                  .whereType<int>(),
              loadNetwork: loadNetwork,
            ),
          ),
        )
        .maybeWhen(
          skipLoadingOnReload: true,
          data: (Map<int, String> value) => value,
          orElse: () => const <int, String>{},
        );
  }

  int get _activeFilterCount {
    int count =
        _statuses.length +
        _mediaStatuses.length +
        _genres.length +
        _formats.length +
        _flags.length;
    if (_minScore > 0) count += 1;
    return count;
  }

  List<AniListAnimeListEntry> _upcomingEntries(
    List<AniListAnimeListEntry> entries,
  ) {
    final DateTime now = DateTime.now();
    final List<AniListAnimeListEntry> upcoming = entries
        .where(
          (AniListAnimeListEntry entry) =>
              entry.airingAt != null && entry.airingAt!.isAfter(now),
        )
        .toList();
    upcoming.sort((a, b) => a.airingAt!.compareTo(b.airingAt!));
    return upcoming.take(10).toList(growable: false);
  }

  void _openSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (ctx) => AniListSheetSurface(
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
            ),
            child: ListView(
              shrinkWrap: true,
              children: _Sort.values
                  .map(
                    (s) => ListTile(
                      title: Text(s.label),
                      trailing: _sort == s
                          ? Icon(
                              Icons.check_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () {
                        setState(() => _sort = s);
                        unawaited(_savePreferences());
                        Navigator.pop(ctx);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _openFilterSheet() {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final List<AniListListStatus> allStatuses = _kStatusOrder
        .where(
          (AniListListStatus status) =>
              widget.folder.entries.any((entry) => entry.status == status),
        )
        .toList(growable: false);
    final List<String> allMediaStatuses = ({
      for (final AniListAnimeListEntry e in widget.folder.entries)
        if (_humanizeMediaStatus(e.mediaItem.statusLabel).isNotEmpty)
          _humanizeMediaStatus(e.mediaItem.statusLabel),
    }.toList()..sort());
    final List<String> allGenres = ({
      for (final e in widget.folder.entries) ...e.mediaItem.genres,
    }.toList()..sort());
    final List<String> allFormats = ({
      for (final e in widget.folder.entries)
        if (e.format != null) e.format!,
    }.toList()..sort());
    final Set<AniListListStatus> tmpStatuses = Set<AniListListStatus>.from(
      _statuses,
    );
    final Set<String> tmpMediaStatuses = Set<String>.from(_mediaStatuses);
    final Set<String> tmpGenres = Set<String>.from(_genres);
    final Set<String> tmpFormats = Set<String>.from(_formats);
    final Set<_LibraryFlag> tmpFlags = Set<_LibraryFlag>.from(_flags);
    double tmpMinScore = _minScore;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AniListSheetSurface(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (ctx, ctrl) => Column(
              children: <Widget>[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMutedColor,
                    borderRadius: AppRadius.all(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setLocal(() {
                          tmpStatuses.clear();
                          tmpMediaStatuses.clear();
                          tmpGenres.clear();
                          tmpFormats.clear();
                          tmpFlags.clear();
                          tmpMinScore = 0;
                        }),
                        child: Text(context.t('Clear all')),
                      ),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _statuses
                              ..clear()
                              ..addAll(tmpStatuses);
                            _mediaStatuses
                              ..clear()
                              ..addAll(tmpMediaStatuses);
                            _genres
                              ..clear()
                              ..addAll(tmpGenres);
                            _formats
                              ..clear()
                              ..addAll(tmpFormats);
                            _flags
                              ..clear()
                              ..addAll(tmpFlags);
                            _minScore = tmpMinScore;
                          });
                          unawaited(_savePreferences());
                          Navigator.pop(ctx);
                        },
                        child: Text(context.t('Apply')),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: ctrl,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    children: <Widget>[
                      if (allStatuses.length > 1) ...<Widget>[
                        Text(
                          'List status',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: allStatuses.map((AniListListStatus status) {
                            final bool selected = tmpStatuses.contains(status);
                            return FilterChip(
                              label: Text(status.label),
                              selected: selected,
                              onSelected: (bool value) => setLocal(
                                () => value
                                    ? tmpStatuses.add(status)
                                    : tmpStatuses.remove(status),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (allMediaStatuses.isNotEmpty) ...<Widget>[
                        Text(
                          'Media status',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: allMediaStatuses.map((String status) {
                            final bool selected = tmpMediaStatuses.contains(
                              status,
                            );
                            return FilterChip(
                              label: Text(status),
                              selected: selected,
                              onSelected: (bool value) => setLocal(
                                () => value
                                    ? tmpMediaStatuses.add(status)
                                    : tmpMediaStatuses.remove(status),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (allFormats.isNotEmpty) ...<Widget>[
                        Text(
                          'Format',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: allFormats.map((f) {
                            final bool sel = tmpFormats.contains(f);
                            return FilterChip(
                              label: Text(f),
                              selected: sel,
                              onSelected: (v) => setLocal(
                                () => v
                                    ? tmpFormats.add(f)
                                    : tmpFormats.remove(f),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        'Progress and metadata',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: _LibraryFlag.values.map((_LibraryFlag flag) {
                          final bool selected = tmpFlags.contains(flag);
                          return FilterChip(
                            label: Text(flag.label),
                            selected: selected,
                            onSelected: (bool value) => setLocal(
                              () => value
                                  ? tmpFlags.add(flag)
                                  : tmpFlags.remove(flag),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Minimum score',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          Text(
                            tmpMinScore <= 0
                                ? 'Any'
                                : tmpMinScore.toStringAsFixed(1),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      Slider(
                        value: tmpMinScore,
                        min: 0,
                        max: 10,
                        divisions: 20,
                        label: tmpMinScore <= 0
                            ? 'Any'
                            : tmpMinScore.toStringAsFixed(1),
                        onChanged: (double value) {
                          setLocal(() => tmpMinScore = value);
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        context.t('Genre'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (allGenres.isEmpty)
                        Text(context.t('No genres available'))
                      else
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: allGenres.map((g) {
                            final bool sel = tmpGenres.contains(g);
                            return FilterChip(
                              label: Text(g),
                              selected: sel,
                              onSelected: (v) => setLocal(
                                () =>
                                    v ? tmpGenres.add(g) : tmpGenres.remove(g),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final List<AniListAnimeListEntry> entries = _filtered;
    final int activeFilterCount = _activeFilterCount;
    final bool filterActive = activeFilterCount > 0;
    final List<AniListAnimeListEntry> upcoming = _upcomingEntries(entries);

    return RefreshIndicator(
      onRefresh: () =>
          refreshAniListLibraryForMediaType(ref, mediaType: widget.mediaType),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _buildActionBar(
              context,
              palette: palette,
              activeFilterCount: activeFilterCount,
              filterActive: filterActive,
            ),
          ),
          // _LibrarySummaryBar(
          //   entries: entries,
          //   totalCount: widget.folder.entries.length,
          // ),
          if (upcoming.isNotEmpty)
            SliverToBoxAdapter(child: _AiringSoonStrip(entries: upcoming)),
          // ── Entry list / grid ─────────────────────────────────────────────
          if (entries.isEmpty)
            _buildEmptySliver(context, palette, filterActive)
          else if (_isGrid)
            _buildGrid(entries)
          else
            _buildList(entries),
        ],
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context, {
    required AppThemeExtension palette,
    required int activeFilterCount,
    required bool filterActive,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText:
                    'Search ${widget.folder.status?.label ?? widget.folder.name}…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.all(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: palette.surfaceSoftColor,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _BarIcon(
            icon: _isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            tooltip: _isGrid ? 'List view' : 'Grid view',
            onTap: () {
              setState(() => _isGrid = !_isGrid);
              unawaited(_savePreferences());
            },
          ),
          const SizedBox(width: AppSpacing.xs),
          _BarIcon(
            icon: Icons.sort_rounded,
            tooltip: 'Sort',
            onTap: _openSortSheet,
          ),
          const SizedBox(width: AppSpacing.xs),
          Badge(
            isLabelVisible: filterActive,
            label: Text(activeFilterCount.toString()),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: _BarIcon(
              icon: Icons.filter_list_rounded,
              tooltip: 'Filter',
              active: filterActive,
              onTap: _openFilterSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySliver(
    BuildContext context,
    AppThemeExtension palette,
    bool filterActive,
  ) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xxl,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: palette.textMutedColor,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _emptyEntriesMessage(filterActive),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMutedColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<AniListAnimeListEntry> entries) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _CollectionTile(entry: entries[i]),
          ),
          childCount: entries.length,
        ),
      ),
    );
  }

  Widget _buildGrid(List<AniListAnimeListEntry> entries) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 0.65,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _GridCell(entry: entries[i]),
          childCount: entries.length,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LibrarySummaryBar extends StatelessWidget {
  const _LibrarySummaryBar({required this.entries, required this.totalCount});

  final List<AniListAnimeListEntry> entries;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final int progressTotal = entries.fold<int>(
      0,
      (int total, AniListAnimeListEntry entry) => total + entry.progress,
    );
    final int scored = entries
        .where((AniListAnimeListEntry entry) => (entry.score ?? 0) > 0)
        .length;
    final int airing = entries
        .where((AniListAnimeListEntry entry) => entry.airingAt != null)
        .length;
    final int behind = entries
        .where(
          (AniListAnimeListEntry entry) =>
              _matchesFlag(entry, _LibraryFlag.behind),
        )
        .length;
    final int hidden = totalCount - entries.length;

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: <Widget>[
          _SummaryPill(
            icon: Icons.collections_bookmark_rounded,
            label: 'Shown',
            value: hidden > 0
                ? '${entries.length}/$totalCount'
                : '${entries.length}',
          ),
          _SummaryPill(
            icon: Icons.done_all_rounded,
            label: 'Progress',
            value: progressTotal.toString(),
          ),
          _SummaryPill(
            icon: Icons.star_half_rounded,
            label: 'Scored',
            value: scored.toString(),
          ),
          _SummaryPill(
            icon: Icons.schedule_rounded,
            label: 'Airing',
            value: airing.toString(),
          ),
          _SummaryPill(
            icon: Icons.notifications_active_rounded,
            label: 'Behind',
            value: behind.toString(),
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSoftColor,
        borderRadius: AppRadius.all(AppRadius.md),
        border: Border.all(color: palette.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 5),
          Text(
            '$label $value',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.textSecondaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiringSoonStrip extends StatelessWidget {
  const _AiringSoonStrip({required this.entries});

  final List<AniListAnimeListEntry> entries;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final AniListAnimeListEntry entry = entries[index];
          final media = entry.mediaItem;
          final String? label = _nextAiringLabel(
            nextEpisode: entry.nextEpisode,
            airingAt: entry.airingAt,
          );
          return InkWell(
            borderRadius: AppRadius.all(AppRadius.md),
            onTap: () => context.push(
              AppRoutes.mediaDetailsPath(media.id),
              extra: media,
            ),
            child: Container(
              width: 260,
              decoration: BoxDecoration(
                color: palette.surfaceSoftColor,
                borderRadius: AppRadius.all(AppRadius.md),
                border: Border.all(color: palette.borderColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 52,
                    height: double.infinity,
                    child: media.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: media.posterUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                _CoverFallback(media.title),
                          )
                        : _CoverFallback(media.title),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            media.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          if (label != null)
                            _AiringBadge(label: label)
                          else
                            Text(
                              'Airing soon',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: palette.textMutedColor),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Collection tile (156px, exact AnimeShin layout) ─────────────────────────

class _CollectionTile extends ConsumerStatefulWidget {
  const _CollectionTile({required this.entry});
  final AniListAnimeListEntry entry;

  @override
  ConsumerState<_CollectionTile> createState() => _CollectionTileState();
}

class _CollectionTileState extends ConsumerState<_CollectionTile> {
  late int _progress;
  late AniListListStatus _status;
  double? _score;
  late String _notes;
  late int _repeat;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.entry.progress;
    _status = widget.entry.status;
    _score = widget.entry.score;
    _notes = widget.entry.notes;
    _repeat = widget.entry.repeat;
  }

  @override
  void didUpdateWidget(_CollectionTile old) {
    super.didUpdateWidget(old);
    if (!_syncing &&
        (old.entry.progress != widget.entry.progress ||
            old.entry.status != widget.entry.status ||
            old.entry.score != widget.entry.score ||
            old.entry.notes != widget.entry.notes ||
            old.entry.repeat != widget.entry.repeat)) {
      _progress = widget.entry.progress;
      _status = widget.entry.status;
      _score = widget.entry.score;
      _notes = widget.entry.notes;
      _repeat = widget.entry.repeat;
    }
  }

  int? get _total => widget.entry.mediaItem.episodeCount;
  bool get _canInc => _total == null || _progress < _total!;
  bool get _canDec => _progress > 0;

  Future<void> _adjust(int delta) async {
    if (delta > 0 && !_canInc) return;
    if (delta < 0 && !_canDec) return;

    final int nextProgress = _progress + delta;

    setState(() {
      _syncing = true;
    });

    try {
      final AniListEntrySaveResult result = await saveAniListEntryEdit(
        context: context,
        ref: ref,
        entry: widget.entry,
        draft: AniListEntryEditDraft(
          status: _status,
          progress: nextProgress,
          score: _score,
          notes: _notes,
          repeat: _repeat,
        ),
        showSuccessSnack: false,
      );
      if (mounted && result != AniListEntrySaveResult.failed) {
        setState(() => _progress = nextProgress);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openEditSheet() async {
    final String scoreFormat = ref.read(aniListEffectiveScoreFormatProvider);
    final AniListEntryEditDraft? draft = await showAniListEntryEditor(
      context,
      ref: ref,
      entry: widget.entry,
      status: _status,
      progress: _progress,
      score: _score,
      notes: _notes,
      repeat: _repeat,
      scoreFormat: scoreFormat,
    );
    if (draft == null || !mounted) return;

    if (draft.remove) {
      setState(() => _syncing = true);
      try {
        await deleteAniListEntry(
          context: context,
          ref: ref,
          entry: widget.entry,
        );
      } finally {
        if (mounted) setState(() => _syncing = false);
      }
      return;
    }

    setState(() => _syncing = true);
    try {
      final AniListEntrySaveResult result = await saveAniListEntryEdit(
        context: context,
        ref: ref,
        entry: widget.entry,
        draft: draft,
      );
      if (mounted && result != AniListEntrySaveResult.failed) {
        setState(() {
          _status = draft.status ?? _status;
          _progress = draft.progress;
          _score = draft.score;
          _notes = draft.notes;
          _repeat = draft.repeat;
        });
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.entry.mediaItem;
    const bool canWatch = true;
    final int? total = _total;
    final double? score = _score;

    double frac = 0;
    if (total != null && total > 0) {
      frac = (_progress / total).clamp(0.0, 1.0);
    } else if (_progress > 0) {
      frac = 1.0;
    }

    // TextRail items
    final Map<String, bool> railItems = <String, bool>{};
    final String? format = widget.entry.format;
    if (format != null) railItems[format] = false;
    final String statusLabel = media.statusLabel;
    if (statusLabel.isNotEmpty &&
        statusLabel != 'AniList' &&
        statusLabel != 'FINISHED') {
      railItems[_humanizeMediaStatus(statusLabel)] = false;
    }
    if (media.genres.isNotEmpty) railItems[media.genres.first] = false;
    if (_repeat > 0) {
      railItems['↩ $_repeat×'] = true;
    }
    final int? nextEp = widget.entry.nextEpisode;
    final DateTime? airingAt = widget.entry.airingAt;
    final String? airingLabel = _nextAiringLabel(
      nextEpisode: nextEp,
      airingAt: airingAt,
    );
    // Episodes aired but not yet watched.
    final int? behindCount = () {
      if (nextEp == null || nextEp <= 1) return null;
      final int b = (nextEp - 1) - _progress;
      return b > 0 ? b : null;
    }();
    final int? avgScore = widget.entry.avgScore;
    final String notes = _notes;

    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final TextTheme tt = Theme.of(context).textTheme;

    return Dismissible(
      key: ValueKey<int>(widget.entry.id),
      direction: DismissDirection.horizontal,
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      confirmDismiss: (DismissDirection dir) async {
        HapticFeedback.mediumImpact();
        if (dir == DismissDirection.startToEnd) {
          unawaited(_adjust(-1));
        } else {
          unawaited(_adjust(1));
        }
        return false;
      },
      background: _SwipeBg(
        color: AppColors.danger.withValues(alpha: 0.9),
        icon: Icons.remove_rounded,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.xl),
      ),
      secondaryBackground: _SwipeBg(
        color: AppColors.success.withValues(alpha: 0.9),
        icon: Icons.add_rounded,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
      ),
      child: SizedBox(
        height: _kTileHeight,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: palette.surfaceSoftColor,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.all(AppRadius.md),
          ),
          child: InkWell(
            onTap: () => context.push(
              AppRoutes.mediaDetailsPath(media.id),
              extra: media,
            ),
            onLongPress: _openEditSheet,
            onSecondaryTap: _openEditSheet,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ── Cover ──────────────────────────────────────────────
                SizedBox(
                  width: _kCoverWidth,
                  height: _kTileHeight,
                  child: media.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: media.posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _CoverFallback(media.title),
                        )
                      : _CoverFallback(media.title),
                ),
                // ── Content ────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Title row + Watch button
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                media.title,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // const SizedBox(width: AppSpacing.xs),
                            // IconButton(
                            //   tooltip: 'Edit AniList entry',
                            //   style: IconButton.styleFrom(
                            //     minimumSize: const Size(32, 32),
                            //     padding: EdgeInsets.zero,
                            //     tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            //   ),
                            //   icon: const Icon(Icons.tune_rounded, size: 17),
                            //   onPressed: _openEditSheet,
                            // ),
                            if (canWatch) ...<Widget>[
                              const SizedBox(width: AppSpacing.sm),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(72, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => context.push(
                                  AppRoutes.watchPath(media.id),
                                  extra: media,
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(Icons.play_arrow_rounded, size: 16),
                                    SizedBox(width: 2),
                                    Text('Watch'),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (airingLabel != null) ...<Widget>[
                          const SizedBox(height: AppSpacing.xs),
                          _AiringBadge(label: airingLabel),
                        ],
                        // TextRail — status / genre / runtime
                        if (railItems.isNotEmpty)
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: _TextRail(railItems),
                            ),
                          ),
                        // Progress bar (AnimeShin gradient style)
                        Container(
                          height: 5,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.all(AppRadius.sm),
                            gradient: LinearGradient(
                              colors: <Color>[
                                cs.onSurfaceVariant,
                                cs.onSurfaceVariant,
                                cs.surface,
                                cs.surface,
                              ],
                              stops: <double>[0, frac, frac, 1.0],
                            ),
                          ),
                        ),
                        // Score / avgScore / notes + progress counter
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            // Left: user score + community score + notes icon
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (score != null && score > 0) ...<Widget>[
                                  Builder(
                                    builder: (BuildContext ctx) {
                                      final String fmt = ref.watch(
                                        aniListEffectiveScoreFormatProvider,
                                      );
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          if (fmt == 'SMILEY' ||
                                              fmt == 'POINT_3')
                                            Icon(
                                              aniListSmileyScoreIcon(score),
                                              size: 14,
                                            )
                                          else if (!isSmileyAniListFormat(fmt))
                                            const Icon(
                                              Icons.star_half_rounded,
                                              size: 14,
                                            ),
                                          if (!isSmileyAniListFormat(fmt) &&
                                              fmt != 'POINT_3')
                                            const SizedBox(width: 2),
                                          if (fmt != 'SMILEY' &&
                                              fmt != 'POINT_3')
                                            Text(
                                              formatAniListScore(score, fmt),
                                              style: tt.labelSmall,
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                                if (avgScore != null &&
                                    avgScore > 0) ...<Widget>[
                                  if (score != null && score > 0)
                                    const SizedBox(width: 6),
                                  Icon(
                                    Icons.people_alt_rounded,
                                    size: 13,
                                    color: palette.textMutedColor,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$avgScore%',
                                    style: tt.labelSmall?.copyWith(
                                      color: palette.textMutedColor,
                                    ),
                                  ),
                                ],
                                if (notes.isNotEmpty) ...<Widget>[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: notes,
                                    child: Icon(
                                      Icons.sticky_note_2_rounded,
                                      size: 13,
                                      color: palette.textMutedColor,
                                    ),
                                  ),
                                ],
                                if (behindCount != null) ...<Widget>[
                                  const SizedBox(width: 6),
                                  Text(
                                    '$behindCount ep behind',
                                    style: tt.labelSmall?.copyWith(
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            // Right: sync + progress counter
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (_syncing) ...<Widget>[
                                  SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: palette.textMutedColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  _progress == total
                                      ? '$_progress'
                                      : '$_progress / ${total ?? "?"}',
                                  style: tt.labelSmall?.copyWith(
                                    color: behindCount != null
                                        ? AppColors.danger
                                        : palette.textMutedColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

AniListListStatus? _statusFromName(String name) {
  for (final AniListListStatus status in AniListListStatus.values) {
    if (status.name == name) return status;
  }
  return null;
}

_LibraryFlag? _flagFromName(String name) {
  for (final _LibraryFlag flag in _LibraryFlag.values) {
    if (flag.name == name) return flag;
  }
  return null;
}

bool _matchesFlag(AniListAnimeListEntry entry, _LibraryFlag flag) {
  return switch (flag) {
    _LibraryFlag.airingSoon =>
      entry.airingAt != null && entry.airingAt!.isAfter(DateTime.now()),
    _LibraryFlag.behind => () {
      final int? nextEpisode = entry.nextEpisode;
      if (nextEpisode == null || nextEpisode <= 1) return false;
      return entry.progress < nextEpisode - 1;
    }(),
    _LibraryFlag.hasNotes => entry.notes.trim().isNotEmpty,
    _LibraryFlag.repeating =>
      entry.repeat > 0 || entry.status == AniListListStatus.repeating,
    _LibraryFlag.unscored => (entry.score ?? 0) <= 0,
    _LibraryFlag.unstarted => entry.progress <= 0,
    _LibraryFlag.finishedProgress => () {
      final int? total = entry.mediaItem.episodeCount;
      return total != null && total > 0 && entry.progress >= total;
    }(),
  };
}

String _humanizeMediaStatus(String raw) {
  return humanReadableMediaStatus(raw);
}

bool _hasCyrillic(String value) => RegExp(r'[а-яёА-ЯЁ]').hasMatch(value);

int? _malIdForMediaItem(MediaItem item) {
  final int? malId = int.tryParse(item.externalIds['mal'] ?? '');
  return malId != null && malId > 0 ? malId : null;
}

String? _nextAiringLabel({
  required int? nextEpisode,
  required DateTime? airingAt,
}) {
  if (nextEpisode == null || airingAt == null) return null;
  final Duration diff = airingAt.difference(DateTime.now());
  final String when = diff.inDays > 0
      ? '${diff.inDays}d'
      : diff.inHours > 0
      ? '${diff.inHours}h'
      : diff.inMinutes > 0
      ? '${diff.inMinutes}m'
      : 'soon';
  return 'Ep $nextEpisode in $when';
}

class _AiringBadge extends StatelessWidget {
  const _AiringBadge({required this.label, this.overlay = false});

  final String label;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: overlay
            ? Colors.black.withValues(alpha: 0.62)
            : cs.primaryContainer.withValues(alpha: 0.74),
        borderRadius: AppRadius.all(AppRadius.sm),
        border: Border.all(
          color: overlay
              ? Colors.white.withValues(alpha: 0.18)
              : cs.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.schedule_rounded,
              size: 12,
              color: overlay ? Colors.white : cs.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: overlay ? Colors.white : cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Grid cell ────────────────────────────────────────────────────────────────

class _GridCell extends ConsumerWidget {
  const _GridCell({required this.entry});
  final AniListAnimeListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = entry.mediaItem;
    final int? total = media.episodeCount;
    final int progress = entry.progress;
    final String fmt = ref.watch(aniListEffectiveScoreFormatProvider);
    final String? airingLabel = _nextAiringLabel(
      nextEpisode: entry.nextEpisode,
      airingAt: entry.airingAt,
    );
    final double frac = total != null && total > 0
        ? (progress / total).clamp(0.0, 1.0)
        : progress > 0
        ? 1.0
        : 0.0;

    Future<void> openEditor() async {
      final AniListEntryEditDraft? draft = await showAniListEntryEditor(
        context,
        ref: ref,
        entry: entry,
        status: entry.status,
        progress: entry.progress,
        score: entry.score,
        notes: entry.notes,
        repeat: entry.repeat,
        scoreFormat: ref.read(aniListEffectiveScoreFormatProvider),
      );
      if (draft == null || !context.mounted) return;
      if (draft.remove) {
        await deleteAniListEntry(context: context, ref: ref, entry: entry);
        return;
      }
      await saveAniListEntryEdit(
        context: context,
        ref: ref,
        entry: entry,
        draft: draft,
      );
    }

    return GestureDetector(
      onTap: () =>
          context.push(AppRoutes.mediaDetailsPath(media.id), extra: media),
      onLongPress: openEditor,
      onSecondaryTap: openEditor,
      child: ClipRRect(
        borderRadius: AppRadius.all(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Poster
            media.posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: media.posterUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _CoverFallback(media.title),
                  )
                : _CoverFallback(media.title),
            // Bottom gradient + title + progress
            if (airingLabel != null)
              Positioned(
                left: AppSpacing.xs,
                top: AppSpacing.xs,
                child: _AiringBadge(label: airingLabel, overlay: true),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Colors.black87, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Progress bar
                    if (frac > 0)
                      ClipRRect(
                        borderRadius: AppRadius.all(2),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '$progress / ${total ?? "?"}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Score badge top-right
            if (entry.score != null && entry.score! > 0)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: AppRadius.all(4),
                  ),
                  child: fmt == 'SMILEY' || fmt == 'POINT_3'
                      ? Icon(
                          aniListSmileyScoreIcon(entry.score!),
                          size: 14,
                          color: Colors.white,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              entry.score! % 1 == 0
                                  ? entry.score!.toInt().toString()
                                  : entry.score!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── TextRail (mirrors AnimeShin's TextRail widget) ────────────────────────────

class _TextRail extends StatelessWidget {
  const _TextRail(this.items);
  final Map<String, bool> items;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    final TextStyle? base = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: palette.textSecondaryColor);
    final TextStyle? highlight = base?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    );
    const TextSpan dot = TextSpan(text: ' • ');
    final List<String> keys = items.keys.toList();
    return Text.rich(
      overflow: TextOverflow.fade,
      maxLines: 1,
      TextSpan(
        style: base,
        children: <TextSpan>[
          for (int i = 0; i < keys.length - 1; i++) ...<TextSpan>[
            TextSpan(text: keys[i], style: items[keys[i]]! ? highlight : null),
            dot,
          ],
          TextSpan(
            text: keys.last,
            style: items[keys.last]! ? highlight : null,
          ),
        ],
      ),
    );
  }
}

// ─── Swipe action background ──────────────────────────────────────────────────

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.color,
    required this.icon,
    required this.alignment,
    required this.padding,
  });

  final Color color;
  final IconData icon;
  final Alignment alignment;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final Color foreground = color.computeLuminance() > 0.45
        ? Colors.black
        : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.all(AppRadius.md),
      ),
      alignment: alignment,
      padding: padding,
      child: Icon(icon, color: foreground, size: 26),
    );
  }
}

// ─── Cover fallback ───────────────────────────────────────────────────────────

class _CoverFallback extends StatelessWidget {
  const _CoverFallback(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(color: palette.textMutedColor),
      ),
    );
  }
}

// ─── Bar icon button ──────────────────────────────────────────────────────────

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return IconButton(
      style: IconButton.styleFrom(
        backgroundColor: active
            ? cs.primaryContainer
            : palette.surfaceSoftColor,
        foregroundColor: active
            ? cs.onPrimaryContainer
            : palette.textSecondaryColor,
        side: BorderSide(
          color: active ? Colors.transparent : palette.borderColor,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.md),
        ),
      ),
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      onPressed: onTap,
    );
  }
}

// ─── Local library view ───────────────────────────────────────────────────────

const List<LibraryStatus> _kLocalStatuses = <LibraryStatus>[
  LibraryStatus.planned,
  LibraryStatus.watching,
  LibraryStatus.completed,
  LibraryStatus.dropped,
  LibraryStatus.favorite,
];

class _LocalLibraryView extends StatefulWidget {
  const _LocalLibraryView({required this.items});
  final List<LibraryItem> items;

  @override
  State<_LocalLibraryView> createState() => _LocalLibraryViewState();
}

class _LocalLibraryViewState extends State<_LocalLibraryView> {
  static const String _preferencesPrefix = 'library.local';

  final TextEditingController _search = TextEditingController();
  _Sort _sort = _Sort.addedNewest;
  LibraryStatus? _selectedStatus;
  bool _isGrid = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedPreferences());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? sortName = prefs.getString('$_preferencesPrefix.sort');
    final _Sort savedSort = _Sort.values.firstWhere(
      (_Sort sort) => sort.name == sortName,
      orElse: () => _sort,
    );
    final bool savedGrid = prefs.getBool('$_preferencesPrefix.grid') ?? false;
    if (!mounted) return;
    setState(() {
      _sort = savedSort;
      _isGrid = savedGrid;
    });
  }

  Future<void> _savePreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_preferencesPrefix.sort', _sort.name);
    await prefs.setBool('$_preferencesPrefix.grid', _isGrid);
  }

  List<LibraryStatus> get _presentStatuses {
    final Set<LibraryStatus> found = <LibraryStatus>{};
    for (final LibraryItem item in widget.items) {
      if (_kLocalStatuses.contains(item.status)) found.add(item.status);
    }
    return _kLocalStatuses
        .where((LibraryStatus s) => found.contains(s))
        .toList(growable: false);
  }

  List<LibraryItem> get _filtered {
    final String q = _search.text.toLowerCase().trim();
    List<LibraryItem> list = widget.items;

    if (_selectedStatus != null) {
      list = list
          .where((LibraryItem i) => i.status == _selectedStatus)
          .toList(growable: false);
    }

    if (q.isNotEmpty) {
      list = list
          .where(
            (LibraryItem i) =>
                i.mediaItem.title.toLowerCase().contains(q) ||
                i.mediaItem.originalTitle.toLowerCase().contains(q) ||
                i.mediaItem.genres.any(
                  (String g) => g.toLowerCase().contains(q),
                ),
          )
          .toList(growable: false);
    }

    list = List<LibraryItem>.from(list);
    switch (_sort) {
      case _Sort.titleAZ:
        list.sort((a, b) => a.mediaItem.title.compareTo(b.mediaItem.title));
      case _Sort.titleZA:
        list.sort((a, b) => b.mediaItem.title.compareTo(a.mediaItem.title));
      case _Sort.progressHigh:
        list.sort((a, b) => b.progress.compareTo(a.progress));
      case _Sort.progressLow:
        list.sort((a, b) => a.progress.compareTo(b.progress));
      case _Sort.addedNewest:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case _Sort.addedOldest:
        list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
      case _Sort.updatedNewest:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case _Sort.updatedOldest:
        list.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case _Sort.avgScoreHigh:
        list.sort((a, b) => b.mediaItem.rating.compareTo(a.mediaItem.rating));
      case _Sort.avgScoreLow:
        list.sort((a, b) => a.mediaItem.rating.compareTo(b.mediaItem.rating));
      default:
        break;
    }
    return list;
  }

  void _openSort() {
    const List<_Sort> opts = <_Sort>[
      _Sort.addedNewest,
      _Sort.addedOldest,
      _Sort.updatedNewest,
      _Sort.updatedOldest,
      _Sort.titleAZ,
      _Sort.titleZA,
      _Sort.progressHigh,
      _Sort.progressLow,
      _Sort.avgScoreHigh,
      _Sort.avgScoreLow,
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (BuildContext ctx) => AniListSheetSurface(
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: opts
                .map(
                  (_Sort s) => ListTile(
                    title: Text(s.label),
                    trailing: _sort == s
                        ? Icon(
                            Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      setState(() => _sort = s);
                      unawaited(_savePreferences());
                      Navigator.pop(ctx);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);

    if (widget.items.isEmpty) {
      return NeutralPlaceholder(
        title: 'Library is empty',
        message:
            'Browse titles and add them here, or connect AniList in Settings.',
        icon: Icons.video_library_rounded,
        height: 300,
      );
    }

    final List<LibraryStatus> presentStatuses = _presentStatuses;
    final List<LibraryItem> items = _filtered;

    return Column(
      children: <Widget>[
        // ── Search / grid / sort bar ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search library…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.all(AppRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: palette.surfaceSoftColor,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _BarIcon(
                icon: _isGrid
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
                tooltip: _isGrid ? 'List view' : 'Grid view',
                onTap: () {
                  setState(() => _isGrid = !_isGrid);
                  unawaited(_savePreferences());
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              _BarIcon(
                icon: Icons.sort_rounded,
                tooltip: 'Sort',
                onTap: _openSort,
              ),
            ],
          ),
        ),

        // ── Status filter chips ───────────────────────────────────────────
        if (presentStatuses.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              children: <Widget>[
                ChoiceChip(
                  label: Text(context.t('All')),
                  selected: _selectedStatus == null,
                  onSelected: (_) => setState(() => _selectedStatus = null),
                ),
                ...presentStatuses.map(
                  (LibraryStatus s) => Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: _selectedStatus == s,
                      onSelected: (_) => setState(() => _selectedStatus = s),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Content ───────────────────────────────────────────────────────
        if (items.isEmpty)
          Expanded(child: Center(child: Text(context.t('No results'))))
        else if (_isGrid)
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.65,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: items.length,
              itemBuilder: (_, int i) => _LocalGridCell(item: items[i]),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: items.length,
              itemBuilder: (_, int i) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _LocalTile(item: items[i]),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Local tile ───────────────────────────────────────────────────────────────

class _LocalTile extends ConsumerStatefulWidget {
  const _LocalTile({required this.item});
  final LibraryItem item;

  @override
  ConsumerState<_LocalTile> createState() => _LocalTileState();
}

class _LocalTileState extends ConsumerState<_LocalTile> {
  Future<void> _openEditor() async {
    final LocalLibraryEditResult? result = await showLocalLibraryEditor(
      context,
      item: widget.item.mediaItem,
      current: widget.item.status,
    );
    if (result == null || !mounted) return;
    final LocalLibraryController controller = ref.read(
      localLibraryProvider.notifier,
    );
    if (result.remove) {
      await controller.remove(widget.item.mediaItem.id);
    } else {
      await controller.addToLibrary(
        widget.item.mediaItem,
        status: result.status,
        progress: widget.item.progress,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaItem media = widget.item.mediaItem;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final TextTheme tt = Theme.of(context).textTheme;
    final double frac = widget.item.progress.clamp(0.0, 1.0);

    final Map<String, bool> rail = <String, bool>{};
    final String typeLabel = switch (media.type) {
      MediaType.movie => 'Movie',
      MediaType.series => 'Series',
      MediaType.anime => 'Anime',
    };
    rail[typeLabel] = false;
    if (media.year > 0) rail[media.year.toString()] = false;
    if (media.rating > 0) rail['★ ${media.rating.toStringAsFixed(1)}'] = true;

    return Dismissible(
      key: ValueKey<String>(widget.item.id),
      direction: DismissDirection.horizontal,
      dismissThresholds: const <DismissDirection, double>{
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      confirmDismiss: (DismissDirection dir) async {
        final LocalLibraryController controller = ref.read(
          localLibraryProvider.notifier,
        );
        if (dir == DismissDirection.startToEnd) {
          await controller.markWatched(media);
        } else {
          await controller.remove(media.id);
        }
        return false;
      },
      background: _SwipeBg(
        color: AppColors.success.withValues(alpha: 0.9),
        icon: Icons.check_circle_outline_rounded,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.xl),
      ),
      secondaryBackground: _SwipeBg(
        color: AppColors.danger.withValues(alpha: 0.9),
        icon: Icons.delete_outline_rounded,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
      ),
      child: SizedBox(
        height: _kTileHeight,
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: palette.surfaceSoftColor,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.all(AppRadius.md),
          ),
          child: InkWell(
            onTap: () => context.push(
              AppRoutes.mediaDetailsPath(media.id),
              extra: media,
            ),
            onLongPress: _openEditor,
            onSecondaryTap: _openEditor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ── Cover ──────────────────────────────────────────────
                SizedBox(
                  width: _kCoverWidth,
                  height: _kTileHeight,
                  child: media.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: media.posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _CoverFallback(media.title),
                        )
                      : _CoverFallback(media.title),
                ),
                // ── Content ────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                media.title,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                minimumSize: const Size(72, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => context.push(
                                AppRoutes.watchPath(media.id),
                                extra: media,
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.play_arrow_rounded, size: 16),
                                  SizedBox(width: 2),
                                  Text('Watch'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: _TextRail(rail),
                          ),
                        ),
                        Container(
                          height: 5,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.all(AppRadius.sm),
                            gradient: LinearGradient(
                              colors: <Color>[
                                cs.onSurfaceVariant,
                                cs.onSurfaceVariant,
                                cs.surface,
                                cs.surface,
                              ],
                              stops: <double>[0, frac, frac, 1.0],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              widget.item.status.label,
                              style: tt.labelSmall?.copyWith(
                                color: palette.textMutedColor,
                              ),
                            ),
                            Text(
                              '${(frac * 100).round()}%',
                              style: tt.labelSmall?.copyWith(
                                color: palette.textMutedColor,
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
          ),
        ),
      ),
    );
  }
}

// ─── Local grid cell ──────────────────────────────────────────────────────────

class _LocalGridCell extends ConsumerWidget {
  const _LocalGridCell({required this.item});
  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MediaItem media = item.mediaItem;
    final double frac = item.progress.clamp(0.0, 1.0);

    Future<void> openEditor() async {
      final LocalLibraryEditResult? result = await showLocalLibraryEditor(
        context,
        item: media,
        current: item.status,
      );
      if (result == null || !context.mounted) return;
      final LocalLibraryController controller = ref.read(
        localLibraryProvider.notifier,
      );
      if (result.remove) {
        await controller.remove(media.id);
      } else {
        await controller.addToLibrary(
          media,
          status: result.status,
          progress: item.progress,
        );
      }
    }

    return GestureDetector(
      onTap: () =>
          context.push(AppRoutes.mediaDetailsPath(media.id), extra: media),
      onLongPress: openEditor,
      onSecondaryTap: openEditor,
      child: ClipRRect(
        borderRadius: AppRadius.all(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            media.posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: media.posterUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _CoverFallback(media.title),
                  )
                : _CoverFallback(media.title),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[Colors.black87, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (frac > 0)
                      ClipRRect(
                        borderRadius: AppRadius.all(2),
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      item.status.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
