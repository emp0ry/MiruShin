import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart'
    show
        MethodChannel,
        MissingPluginException,
        PlatformException,
        SystemChrome,
        SystemUiMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation_helpers.dart';
import '../../../app/router.dart' show PlayerRouteArgs;
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/metadata_chip.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/page_back_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton_box.dart';
import '../../../shared/models/media_item.dart';
import '../../addons/application/sora_addons_provider.dart';
import '../../addons/application/sora_source_providers.dart';
import '../../addons/domain/sora_models.dart';
import '../../catalog/application/catalog_repository.dart';
import '../../catalog/application/catalog_mode.dart';
import '../../metadata/application/metadata_providers.dart';
import '../../metadata/domain/anime_episode_metadata.dart';
import '../../library/application/local_library_provider.dart';
import '../../settings/presentation/settings_state.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../../../shared/models/anilist_models.dart';
import '../application/watch_session.dart';
import '../domain/normalized_models.dart';

// ---------------------------------------------------------------------------
// Title-based fallback provider
// When a stored item has a stale/wrong TVDB ID (returns 404), this searches
// by title and loads full details for the best matching result.
// ---------------------------------------------------------------------------

@immutable
class _TitleFallbackQuery {
  const _TitleFallbackQuery({required this.title, this.type});
  final String title;
  final MediaType? type;

  @override
  bool operator ==(Object other) =>
      other is _TitleFallbackQuery &&
      other.title == title &&
      other.type == type;

  @override
  int get hashCode => Object.hash(title, type);
}

final _titleFallbackDetailsProvider =
    FutureProvider.family<MediaItem?, _TitleFallbackQuery>((
      Ref ref,
      _TitleFallbackQuery query,
    ) async {
      if (query.title.isEmpty) return null;
      final CatalogRepository? repository = ref.watch(
        activeCatalogRepositoryProvider,
      );
      if (repository == null) return null;
      try {
        final List<MediaItem> results = await repository.discover(
          search: query.title,
          type: query.type,
          filter: 'Trending',
          page: 1,
        );
        if (results.isEmpty) return null;
        final String normalized = query.title.toLowerCase().trim();
        MediaItem? best;
        for (final MediaItem result in results) {
          if (query.type != null && result.type != query.type) continue;
          if (result.title.toLowerCase().trim() == normalized ||
              result.originalTitle.toLowerCase().trim() == normalized) {
            best = result;
            break;
          }
        }
        if (best == null) {
          for (final MediaItem result in results) {
            if (query.type == null || result.type == query.type) {
              best = result;
              break;
            }
          }
        }
        if (best == null) return null;
        debugPrint(
          '[WatchFallback] resolved "${query.title}" via search → ${best.id} "${best.title}"',
        );
        return repository.details(best.id);
      } catch (_) {
        return null;
      }
    });

const String _nextEpisodeSignal = 'next_episode';
const String _nextEpisodeFullscreenSignal = 'next_episode_fullscreen';

class WatchPage extends ConsumerStatefulWidget {
  const WatchPage({required this.id, this.initialItem, super.key});

  final String id;
  final MediaItem? initialItem;

  @override
  ConsumerState<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends ConsumerState<WatchPage> {
  static const MethodChannel _windowChannel = MethodChannel('mirushin/window');

  WatchSession? _session;
  MediaItem? _lastItem;
  String? _lastWatchDebugSignature;
  String? _lastAutoNextFromEpisodeHref;
  String? _activePlayerEpisodeKey;
  bool _playerRouteInFlight = false;
  bool _nextEpisodeInFullscreen = false;
  final AutoNextStreamResolutionState _streamResolutionState =
      AutoNextStreamResolutionState();
  String? _preferredServerTitle;
  String? _preferredVoiceOverLabel;
  DateTime? _lastAutoNextAt;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _sourceKey = GlobalKey();
  final GlobalKey _episodeKey = GlobalKey();
  final GlobalKey _streamKey = GlobalKey();
  int _visibleTab = 0; // 0 = Find Sources, 1 = Choose Episode
  SoraEpisode? _continueEpisode;
  AnimeEpisodeMetadata? _continueEpisodeMeta;
  int _continueDisplayNum = 0;

  @override
  void didUpdateWidget(covariant WatchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) {
      return;
    }
    _session = null;
    _lastItem = null;
    _lastWatchDebugSignature = null;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initSession(MediaItem item) {
    _lastItem = item;
    _session ??= WatchSession.initial(item);
  }

  void _syncSessionForItem(MediaItem item) {
    _lastItem = item;
    final WatchSession? current = _session;
    if (current == null) {
      _session = WatchSession.initial(item);
      return;
    }
    final WatchSession realSession = current.resyncForItem(item);
    if (!identical(current, realSession)) {
      debugPrint(
        '[WatchSeason] resync session id=${item.id} '
        'from=${current.step.name}/s${current.seasonNumber} '
        'to=${realSession.step.name}/s${realSession.seasonNumber} '
        'seasons=${_seasonDebugSummary(item.seasons)}',
      );
      _session = realSession;
    }
  }

  void _pickSeason(int seasonNumber) {
    MediaSeason? picked;
    final MediaItem? item = _lastItem;
    if (item != null) {
      for (final MediaSeason season in item.seasons) {
        if (season.seasonNumber == seasonNumber) {
          picked = season;
          break;
        }
      }
    }
    debugPrint(
      '[WatchSeason] picked id=${item?.id ?? widget.id} '
      'season=$seasonNumber name="${picked?.name ?? ''}" '
      'all=${item == null ? '<none>' : _seasonDebugSummary(item.seasons)}',
    );
    setState(() {
      _visibleTab = 0;
      _session = _session!.copyWith(
        step: WatchStep.pickSource,
        seasonNumber: seasonNumber,
        clearSource: true,
        clearEpisode: true,
        clearCandidate: true,
        clearError: true,
        seasonPicked: true,
      );
    });
    _scrollToKey(_sourceKey);
  }

  void _pickSource(SoraSearchResult result) {
    // Synchronously bump the epoch so every in-flight search loop sees a stale
    // epoch on its next await and breaks out — without restarting providers.
    cancelAllSoraSearches();
    setState(() {
      _visibleTab = 1;
      _continueEpisode = null;
      _continueEpisodeMeta = null;
      _continueDisplayNum = 0;
      _streamResolutionState.clear();
      _session = _session!.copyWith(
        step: WatchStep.pickEpisode,
        source: result,
        clearEpisode: true,
        clearCandidate: true,
        clearError: true,
      );
    });
    _scrollToKey(_sourceKey);
  }

  void _onContinueResolved(
    SoraEpisode? ep,
    AnimeEpisodeMetadata? meta,
    int effectiveContinued,
  ) {
    final int displayNum = effectiveContinued > 0 ? effectiveContinued + 1 : 0;
    if (_continueEpisode?.href == ep?.href &&
        _continueDisplayNum == displayNum) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _continueEpisode = ep;
      _continueEpisodeMeta = meta;
      _continueDisplayNum = displayNum;
    });
  }

  void _pickEpisode(SoraEpisode episode, {bool isAutoNext = false}) {
    final String? requestKey = _streamRequestKey(_session?.source, episode);
    if (requestKey != null) {
      _streamResolutionState.begin(requestKey, autoNext: isAutoNext);
    }
    setState(() {
      _session = _session!.copyWith(
        step: WatchStep.resolveStream,
        episode: episode,
        clearCandidate: true,
        clearError: true,
        isResolving: true,
      );
    });
    _scrollToKey(_streamKey);
  }

  void _onStreamResolved(String requestKey, NormalizedStreamBundle bundle) {
    if (!mounted ||
        _session?.isResolving != true ||
        !_streamResolutionState.isCurrent(requestKey)) {
      _streamResolutionState.forget(requestKey);
      return;
    }

    final bool isAutoNext = _streamResolutionState.takeAutoNext(requestKey);

    NormalizedStreamBundle resolvedBundle = bundle;
    if (isAutoNext) {
      resolvedBundle = _applyStreamPreferences(bundle);
    }

    final bool canAutoPlay =
        resolvedBundle.activeUrl.trim().isNotEmpty &&
        (isAutoNext || !_bundleRequiresManualChoice(resolvedBundle));

    setState(() {
      _session = _session!.copyWith(
        step: WatchStep.streamReady,
        clearCandidate: true,
        isResolving: false,
      );
    });

    if (canAutoPlay) {
      _playResolvedBundle(resolvedBundle, isAutoNext: isAutoNext);
    } else {
      _showStreamSheet(resolvedBundle);
    }
  }

  void _onStreamError(String requestKey, Object error) {
    if (!mounted) {
      return;
    }
    if (!_streamResolutionState.isCurrent(requestKey)) {
      _streamResolutionState.forget(requestKey);
      return;
    }
    final bool wasAutoNext = _streamResolutionState.takeAutoNext(requestKey);
    if (wasAutoNext) {
      _nextEpisodeInFullscreen = false;
    }
    setState(() {
      _session = _session!.copyWith(
        // On auto-next failures keep streamReady so the user stays on the
        // watch page instead of being dropped to the episode picker.
        step: wasAutoNext ? WatchStep.streamReady : WatchStep.pickEpisode,
        isResolving: false,
        error: error.toString(),
      );
    });
  }

  NormalizedStreamBundle _applyStreamPreferences(
    NormalizedStreamBundle bundle,
  ) {
    NormalizedStreamBundle result = bundle;

    final String? serverTitle = _preferredServerTitle;
    if (serverTitle != null) {
      for (final NormalizedServer s in bundle.availableServers) {
        if (s.title == serverTitle) {
          result = result.withServer(s);
          break;
        }
      }
    }

    final String? voLabel = _preferredVoiceOverLabel;
    if (voLabel != null) {
      for (final NormalizedVoiceOver vo in bundle.availableVoiceOvers) {
        if (vo.label == voLabel) {
          result = result.withVoiceOver(vo);
          break;
        }
      }
    }

    return result;
  }

  Future<void> _exitFullscreen() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await _windowChannel.invokeMethod<bool>('setFullscreen', false);
    } on MissingPluginException {
      // Not on desktop.
    } on PlatformException {
      // Ignore.
    }
  }

  void _scrollToKey(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.04,
        );
      }
    });
  }

  bool _bundleRequiresManualChoice(NormalizedStreamBundle bundle) {
    return bundle.availableServers.length > 1 ||
        bundle.availableVoiceOvers.length > 1;
  }

  void _playResolvedBundle(
    NormalizedStreamBundle bundle, {
    bool isAutoNext = false,
  }) {
    _preferredServerTitle = bundle.selectedServer.title;
    _preferredVoiceOverLabel = bundle.selectedVoiceOver?.label;

    // For auto-next always start from the beginning regardless of saved progress.
    // For manual opens, look up the saved position so the controller's async
    // lookup doesn't race with the stop() call from the previous episode.
    Duration startPosition = Duration.zero;
    if (!isAutoNext) {
      final String? mediaId = _lastItem?.id;
      final int? seasonNum = _session?.seasonNumber;
      if (mediaId != null && seasonNum != null) {
        final EpisodeProgress? prog = ref
            .read(localLibraryProvider.notifier)
            .episodeProgress(mediaId, seasonNum, bundle.episode.number);
        if (prog != null && prog.positionSeconds > 0) {
          startPosition = Duration(seconds: prog.positionSeconds);
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastItem == null || _session == null) {
        return;
      }
      final String episodeKey = '${bundle.addonId}:${bundle.episode.href}';
      if (_playerRouteInFlight && _activePlayerEpisodeKey == episodeKey) {
        return;
      }
      _playerRouteInFlight = true;
      _activePlayerEpisodeKey = episodeKey;
      final bool startFs = _nextEpisodeInFullscreen;
      _nextEpisodeInFullscreen = false;
      context
          .push(
            AppRoutes.watchPlay,
            extra: PlayerRouteArgs(
              bundle: bundle,
              item: _playerRouteItem(_lastItem!, _session!),
              seasonNumber: _session!.seasonNumber,
              startInFullscreen: startFs,
              startPosition: startPosition,
              ignoreProgress: isAutoNext,
            ),
          )
          .then((Object? result) {
            if (!mounted) return;
            _playerRouteInFlight = false;
            _activePlayerEpisodeKey = null;
            if (result == _nextEpisodeSignal ||
                result == _nextEpisodeFullscreenSignal) {
              _nextEpisodeInFullscreen = result == _nextEpisodeFullscreenSignal;
              unawaited(_playNextEpisodeFromPlayer());
            }
          });
    });
  }

  Future<void> _playNextEpisodeFromPlayer() async {
    final WatchSession? session = _session;
    final MediaItem? item = _lastItem;
    if (session == null || item == null) return;
    final SoraSearchResult? source = session.source;
    final SoraEpisode? current = session.episode;
    if (source == null || current == null) return;
    final DateTime now = DateTime.now();
    final DateTime? lastAt = _lastAutoNextAt;
    if (lastAt != null && now.difference(lastAt) < const Duration(seconds: 8)) {
      return;
    }
    if (_lastAutoNextFromEpisodeHref == current.href) return;
    _lastAutoNextFromEpisodeHref = current.href;
    _lastAutoNextAt = now;

    final SoraSourceRequest request = SoraSourceRequest(
      addonId: source.addonId,
      result: source,
    );
    final SoraSourceContent content;
    try {
      content = await ref.read(soraSourceContentProvider(request).future);
    } on Object catch (error) {
      if (!mounted) return;
      _nextEpisodeInFullscreen = false;
      setState(() {
        _session = _session?.copyWith(
          step: WatchStep.streamReady,
          isResolving: false,
          error: error.toString(),
        );
      });
      return;
    }
    if (!mounted) return;

    final List<SoraEpisode> episodes = content.episodes;
    if (episodes.isEmpty) return;
    int index = episodes.indexWhere((SoraEpisode e) => e.href == current.href);
    if (index < 0) {
      index = episodes.indexWhere(
        (SoraEpisode e) => e.number == current.number,
      );
    }
    if (index < 0 || index + 1 >= episodes.length) {
      // Last episode — if the player kept the window fullscreen for the smooth
      // transition, exit fullscreen now since there's nothing to play next.
      if (_nextEpisodeInFullscreen) {
        _nextEpisodeInFullscreen = false;
        unawaited(_exitFullscreen());
      }
      return;
    }

    final SoraEpisode rawNext = episodes[index + 1];
    final AnimeEpisodeMetadata? nextMetadata = await _metadataForAutoNext(
      item,
      rawNext,
    );
    if (!mounted) return;

    final SoraEpisode next = _episodeForPlayback(rawNext, nextMetadata);
    // Discard any stale cached stream for the next episode so resolution
    // always uses a fresh URL (avoids instant failure from expired cache).
    ref.invalidate(
      soraStreamBundleProvider(
        SoraStreamRequest(addonId: source.addonId, episode: next),
      ),
    );
    _pickEpisode(next, isAutoNext: true);
  }

  Future<AnimeEpisodeMetadata?> _metadataForAutoNext(
    MediaItem item,
    SoraEpisode episode,
  ) async {
    final int? anilistId = _animeAnilistId(item);
    if (anilistId == null) return null;

    final SettingsState settings = ref.read(settingsProvider);
    try {
      final AnimeEpisodeMetadataBundle bundle = await ref.read(
        animeEpisodeMetadataProvider(
          AnimeEpisodeMetadataRequest(
            anilistId: anilistId,
            languageCode: _episodeMetadataLanguage(settings),
          ),
        ).future,
      );
      return bundle.forNumber(episode.number);
    } on Object {
      return null;
    }
  }

  void _showStreamSheet(NormalizedStreamBundle bundle) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,

        backgroundColor: Colors.transparent,
        barrierColor: Colors.black54,
        elevation: 0,
        showDragHandle: false,
        useSafeArea: false,
        clipBehavior: Clip.none,

        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide.none,
        ),

        builder: (BuildContext sheetContext) {
          return Material(
            type: MaterialType.transparency,
            color: Colors.transparent,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: _StreamReadySheet(
              bundle: bundle,
              onPlay: (NormalizedStreamBundle selected) {
                Navigator.of(sheetContext).pop();
                _playResolvedBundle(selected);
              },
            ),
          );
        },
      );
    });
  }

  void _debugWatchSeasonState({
    required MediaItem item,
    required bool hasDetails,
    required bool loadingSeasonDetails,
    required WatchSession? session,
  }) {
    final String signature =
        '${item.id}|${item.title}|$hasDetails|$loadingSeasonDetails|'
        '${session?.step.name}|${session?.seasonNumber}|'
        '${_seasonDebugSummary(item.seasons)}';
    if (_lastWatchDebugSignature == signature) {
      return;
    }
    _lastWatchDebugSignature = signature;
    debugPrint(
      '[WatchSeason] state id=${item.id} type=${item.type.name} '
      'title="${item.title}" details=$hasDetails '
      'loadingSeasons=$loadingSeasonDetails '
      'session=${session?.step.name ?? '<none>'}/s${session?.seasonNumber ?? '-'} '
      'seasons=${_seasonDebugSummary(item.seasons)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MediaItem?> asyncDetails = ref.watch(
      mediaDetailsProvider(widget.id),
    );
    final MediaItem? primaryDetails = asyncDetails.maybeWhen(
      data: (MediaItem? item) => item,
      orElse: () => null,
    );

    // When the stored ID is stale/wrong and returns 404, fall back to a title
    // search so we can resolve the correct TVDB ID and load season data.
    final bool primaryFailed = asyncDetails.hasValue && primaryDetails == null;
    final String fallbackTitle = primaryFailed
        ? (widget.initialItem?.title ?? '')
        : '';
    final AsyncValue<MediaItem?> asyncFallback = ref.watch(
      _titleFallbackDetailsProvider(
        _TitleFallbackQuery(
          title: fallbackTitle,
          type: widget.initialItem?.type,
        ),
      ),
    );
    final MediaItem? fallbackDetails = asyncFallback.maybeWhen(
      data: (MediaItem? item) => item,
      orElse: () => null,
    );

    final MediaItem? details = primaryDetails ?? fallbackDetails;
    final MediaItem? item = details ?? widget.initialItem;
    final bool loading = item == null && asyncDetails.isLoading;
    final bool loadingSeasonDetails =
        item != null &&
        details == null &&
        (asyncDetails.isLoading ||
            (primaryFailed && asyncFallback.isLoading)) &&
        _needsSeasonDetails(item);

    if (item != null) {
      if (_session == null) {
        _initSession(item);
      } else if (details != null) {
        _syncSessionForItem(item);
      } else {
        _lastItem = item;
      }
    }

    final WatchSession? session = _session;
    if (item != null) {
      _debugWatchSeasonState(
        item: item,
        hasDetails: details != null,
        loadingSeasonDetails: loadingSeasonDetails,
        session: session,
      );
    }

    final bool showContinueButton =
        _visibleTab == 1 && _continueEpisode != null && _continueDisplayNum > 0;

    return Stack(
      children: <Widget>[
        AdaptivePage(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (loading)
                  const SkeletonBox(height: 360, radius: AppRadius.xxl)
                else if (item == null)
                  NeutralPlaceholder(
                    title: context.t('Watch unavailable'),
                    message: context.t(
                      'Could not load details. Check your metadata settings.',
                    ),
                    height: 420,
                    icon: Icons.play_disabled_rounded,
                    action: OutlinedButton.icon(
                      onPressed: () => context.go(AppRoutes.discovery),
                      icon: const Icon(Icons.explore_rounded),
                      label: Text(context.t('Discovery')),
                    ),
                  )
                else ...<Widget>[
                  _WatchHero(item: _heroDisplayItem(item, session)),
                  const SizedBox(height: AppSpacing.xxl),
                  if (session != null) ...<Widget>[
                    // Step 1 — Season picker (series with multiple seasons)
                    if (session.step == WatchStep.pickSeason)
                      _SeasonPickerSection(
                        item: item,
                        selectedSeason: session.seasonNumber,
                        loading: loadingSeasonDetails,
                        onSeasonPicked: _pickSeason,
                      ),

                    // Tab bar (Find Sources / Choose Episode)
                    if (session.step != WatchStep.pickSeason) ...<Widget>[
                      _WatchTabBar(
                        selectedTab: _visibleTab,
                        hasEpisodes: session.source != null,
                        onTabSelected: (int tab) =>
                            setState(() => _visibleTab = tab),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],

                    // Tab 0 — Source search (hidden when on episode tab so searches
                    // stop after picking a source and restart if the user returns)
                    if (session.step != WatchStep.pickSeason &&
                        _visibleTab == 0)
                      KeyedSubtree(
                        key: _sourceKey,
                        child: _SourceSearchSection(
                          item: _seasonSearchItem(item, session),
                          selectedHref: session.source?.href,
                          onSourcePicked: _pickSource,
                        ),
                      ),

                    // Tab 1 — Episode picker
                    if (session.step != WatchStep.pickSeason &&
                        _visibleTab == 1 &&
                        session.source != null)
                      KeyedSubtree(
                        key: _episodeKey,
                        child: _EpisodePickerSection(
                          item: _seasonSearchItem(item, session),
                          source: session.source!,
                          selectedEpisodeHref: session.episode?.href,
                          onEpisodePicked: _pickEpisode,
                          seasonNumber: session.seasonNumber,
                          onContinueResolved: _onContinueResolved,
                        ),
                      ),

                    // Stream resolving indicator
                    if (session.isResolving ||
                        session.step == WatchStep.resolveStream) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxl),
                      KeyedSubtree(
                        key: _streamKey,
                        child: _StreamResolvingSection(
                          source: session.source,
                          episode: session.episode,
                          onResolved: _onStreamResolved,
                          onError: _onStreamError,
                        ),
                      ),
                    ],

                    if (session.error != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      _ErrorBanner(message: session.error!),
                    ],
                  ],
                ],
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
        if (showContinueButton)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.xl,
            child: SafeArea(
              child: FilledButton.icon(
                onPressed: () => _pickEpisode(
                  _episodeForPlayback(_continueEpisode!, _continueEpisodeMeta),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text('Continue EP $_continueDisplayNum'),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _WatchHero extends ConsumerWidget {
  const _WatchHero({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.xxl),
      child: SizedBox(
        height: 360,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (item.backdropUrl.isEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: palette.posterFallbackGradient,
                ),
              )
            else
              CachedNetworkImage(
                imageUrl: item.backdropUrl,
                fit: BoxFit.cover,
                placeholder: (BuildContext context, String url) =>
                    const SkeletonBox(),
                errorWidget: (BuildContext context, String url, Object error) =>
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: palette.posterFallbackGradient,
                      ),
                    ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54),
            ),
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              child: PageBackButton(
                onPressed: () => _goBackFromWatch(context, item),
              ),
            ),
            Positioned(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.xl,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  _WatchPoster(item: item),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: <Widget>[
                            if (mode != CatalogMode.anilist)
                              MetadataChip(
                                label: context.t(item.type.labelKey),
                                onImage: true,
                              ),
                            MetadataChip(
                              label: item.year.toString(),
                              onImage: true,
                            ),
                            MetadataChip(
                              label: item.durationLabel,
                              onImage: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _goBackFromWatch(BuildContext context, MediaItem item) {
  goBackOrGo(context, AppRoutes.mediaDetailsPath(item.id));
}

class _WatchPoster extends StatelessWidget {
  const _WatchPoster({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.lg),
      child: SizedBox(
        width: 116,
        height: 174,
        child: item.posterUrl.isEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: palette.posterFallbackGradient,
                ),
              )
            : CachedNetworkImage(imageUrl: item.posterUrl, fit: BoxFit.cover),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Watch tab bar
// ---------------------------------------------------------------------------

class _WatchTabBar extends StatelessWidget {
  const _WatchTabBar({
    required this.selectedTab,
    required this.hasEpisodes,
    required this.onTabSelected,
  });

  final int selectedTab;
  final bool hasEpisodes;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _WatchTab(
          label: context.t('Find Sources'),
          icon: Icons.search_rounded,
          selected: selectedTab == 0,
          onTap: () => onTabSelected(0),
        ),
        const SizedBox(width: AppSpacing.sm),
        _WatchTab(
          label: context.t('Choose Episode'),
          icon: Icons.list_rounded,
          selected: selectedTab == 1,
          enabled: hasEpisodes,
          onTap: hasEpisodes ? () => onTabSelected(1) : null,
        ),
      ],
    );
  }
}

class _WatchTab extends StatelessWidget {
  const _WatchTab({
    required this.label,
    required this.icon,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fgColor = selected
        ? scheme.primary
        : enabled
        ? scheme.onSurface.withValues(alpha: 0.65)
        : scheme.onSurface.withValues(alpha: 0.3);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(
            color: selected ? scheme.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: fgColor),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: fgColor,
                fontWeight: selected ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Season picker
// ---------------------------------------------------------------------------

class _SeasonPickerSection extends StatelessWidget {
  const _SeasonPickerSection({
    required this.item,
    required this.selectedSeason,
    required this.loading,
    required this.onSeasonPicked,
  });

  final MediaItem item;
  final int selectedSeason;
  final bool loading;
  final ValueChanged<int> onSeasonPicked;

  @override
  Widget build(BuildContext context) {
    final List<MediaSeason> all = _selectableSeasons(item);
    if (all.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: context.t('Choose Season'),
              subtitle: context.t('Select a season to find sources for.'),
            ),
            if (loading)
              const SkeletonBox(height: 132, radius: AppRadius.lg)
            else
              NeutralPlaceholder(
                title: context.t('No seasons found'),
                message: context.t(
                  'TVDB details did not return season metadata.',
                ),
                icon: Icons.event_busy_rounded,
                action: OutlinedButton.icon(
                  onPressed: () => onSeasonPicked(1),
                  icon: const Icon(Icons.search_rounded),
                  label: Text(context.t('Search sources')),
                ),
              ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('Choose Season'),
            subtitle: context.t('Select a season to find sources for.'),
          ),
          SizedBox(
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: all.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (BuildContext context, int index) {
                final MediaSeason season = all[index];
                final bool selected = selectedSeason == season.seasonNumber;
                final String label = _seasonPickerLabel(context, season);
                return GestureDetector(
                  onTap: () => onSeasonPicked(season.seasonNumber),
                  child: SizedBox(
                    width: 108,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.all(AppRadius.lg),
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.border,
                                width: selected ? 2.5 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: AppRadius.all(
                                selected ? AppRadius.md : AppRadius.lg,
                              ),
                              child: season.posterUrl.isEmpty
                                  ? _SeasonPosterFallback(label: label)
                                  : CachedNetworkImage(
                                      imageUrl: season.posterUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const SkeletonBox(),
                                      errorWidget: (context, url, err) =>
                                          _SeasonPosterFallback(label: label),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                fontWeight: selected ? FontWeight.w700 : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonPosterFallback extends StatelessWidget {
  const _SeasonPosterFallback({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.22),
            scheme.secondary.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: Center(
        child: Text(
          label.isNotEmpty ? label[0].toUpperCase() : '?',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source search
// ---------------------------------------------------------------------------

class _SourceSearchSection extends ConsumerStatefulWidget {
  const _SourceSearchSection({
    required this.item,
    required this.onSourcePicked,
    this.selectedHref,
  });

  final MediaItem item;
  final String? selectedHref;
  final ValueChanged<SoraSearchResult> onSourcePicked;

  @override
  ConsumerState<_SourceSearchSection> createState() =>
      _SourceSearchSectionState();
}

class _SourceSearchSectionState extends ConsumerState<_SourceSearchSection> {
  final Map<String, bool> _showMore = <String, bool>{};
  final Map<String, String?> _customQueries = <String, String?>{};
  String? _lastSearchDebugSignature;

  @override
  Widget build(BuildContext context) {
    final SoraAddonsState addonsState = ref.watch(soraAddonsProvider);
    final List<String> languageCodes = ref.watch(soraSourceLanguagesProvider);
    final SoraSourceLanguageController langController = ref.read(
      soraSourceLanguagesProvider.notifier,
    );

    if (addonsState.loading) {
      return const SkeletonBox(height: 160, radius: AppRadius.xl);
    }

    if (languageCodes.isEmpty) {
      return const SkeletonBox(height: 160, radius: AppRadius.xl);
    }

    _debugSourceSearchItem(languageCodes);

    if (addonsState.installed.isEmpty) {
      return NeutralPlaceholder(
        title: context.t('No addons installed'),
        message: context.t('Install a Sora addon to search for sources.'),
        height: 200,
        icon: Icons.extension_off_rounded,
        action: OutlinedButton.icon(
          onPressed: () => context.go(AppRoutes.addons),
          icon: const Icon(Icons.extension_rounded),
          label: Text(context.t('Addons')),
        ),
      );
    }

    // Ordered list of enabled addons — each loads independently.
    final List<SoraInstalledAddon> enabledAddons = addonsState.enabledOrdered;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: context.t('Find Sources'),
            subtitle: context.t(
              'Results grouped by addon, sorted by title match.',
            ),
          ),

          // Language priority row
          _LanguagePriorityRow(
            languages: languageCodes,
            onMove: (String code, int direction) =>
                langController.move(code, direction),
            onToggle: (String code) => langController.toggle(code),
          ),
          const SizedBox(height: AppSpacing.lg),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final SoraInstalledAddon addon in enabledAddons) ...<Widget>[
                _AddonSearchRow(
                  addon: addon,
                  request: SoraSourceSearchRequest(
                    media: widget.item,
                    languageCodes: languageCodes,
                    addonId: addon.id,
                    customQuery: _customQueries[addon.id],
                  ),
                  showMore: _showMore[addon.id] ?? false,
                  selectedHref: widget.selectedHref,
                  onToggleMore: () => setState(() {
                    _showMore[addon.id] = !(_showMore[addon.id] ?? false);
                  }),
                  onResultTapped: widget.onSourcePicked,
                  onCustomSearch: (String query) => setState(() {
                    _customQueries[addon.id] = query;
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _debugSourceSearchItem(List<String> languageCodes) {
    final MediaItem item = widget.item;
    final String signature =
        '${item.id}|${item.title}|${item.externalIds['sora_season_number']}|'
        '${item.externalIds['sora_season_name']}|'
        '${item.externalIds['sora_season_original_name']}|'
        '${item.externalIds['sora_season_aliases']}|${languageCodes.join(',')}';
    if (_lastSearchDebugSignature == signature) return;
    _lastSearchDebugSignature = signature;
    debugPrint(
      '[SoraSearchItem] id=${item.id} type=${item.type.name} '
      'title="${item.title}" original="${item.originalTitle}" '
      'season=${item.externalIds['sora_season_number'] ?? '-'} '
      'seasonName="${item.externalIds['sora_season_name'] ?? ''}" '
      'seasonOriginal="${item.externalIds['sora_season_original_name'] ?? ''}" '
      'langs=${languageCodes.join(' -> ')}',
    );
  }
}

class _LanguagePriorityRow extends StatelessWidget {
  const _LanguagePriorityRow({
    required this.languages,
    required this.onMove,
    required this.onToggle,
  });

  final List<String> languages;
  final void Function(String code, int direction) onMove;
  final void Function(String code) onToggle;

  @override
  Widget build(BuildContext context) {
    final List<SoraSearchLanguage> all = SoraSearchLanguage.supported;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.t('Search language priority'),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            // Active languages with up/down controls.
            for (int i = 0; i < languages.length; i++) ...<Widget>[
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: AppRadius.all(AppRadius.md),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${i + 1}. ${SoraSearchLanguage.byCode(languages[i]).name}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    if (i > 0)
                      GestureDetector(
                        onTap: () => onMove(languages[i], -1),
                        child: Icon(
                          Icons.arrow_left_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                    if (i < languages.length - 1)
                      GestureDetector(
                        onTap: () => onMove(languages[i], 1),
                        child: Icon(
                          Icons.arrow_right_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                    if (languages.length > 1)
                      GestureDetector(
                        onTap: () => onToggle(languages[i]),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: scheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            // Inactive languages as add buttons.
            for (final SoraSearchLanguage lang in all)
              if (!languages.contains(lang.code))
                InkWell(
                  onTap: () => onToggle(lang.code),
                  borderRadius: AppRadius.all(AppRadius.md),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.all(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.add_rounded,
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          lang.name,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

// Per-addon widget that watches its own provider so results stream in independently.
class _AddonSearchRow extends ConsumerWidget {
  const _AddonSearchRow({
    required this.addon,
    required this.request,
    required this.showMore,
    required this.onToggleMore,
    required this.onResultTapped,
    required this.onCustomSearch,
    this.selectedHref,
  });

  final SoraInstalledAddon addon;
  final SoraSourceSearchRequest request;
  final bool showMore;
  final String? selectedHref;
  final VoidCallback onToggleMore;
  final ValueChanged<SoraSearchResult> onResultTapped;
  final ValueChanged<String> onCustomSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SoraSourceSearchBundle> async = ref.watch(
      soraSourceSearchProvider(request),
    );
    return async.when(
      loading: () => Row(
        children: <Widget>[
          _AddonLogo(url: addon.manifest.iconUrl),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              addon.manifest.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
      error: (Object error, _) => _AddonEmptyRow(
        addonName: addon.manifest.sourceName,
        iconUrl: addon.manifest.iconUrl,
        error: error.toString(),
        onCustomSearch: onCustomSearch,
      ),
      data: (SoraSourceSearchBundle bundle) {
        if (bundle.errors.isNotEmpty) {
          return _AddonEmptyRow(
            addonName: addon.manifest.sourceName,
            iconUrl: addon.manifest.iconUrl,
            error: bundle.errors.first.message,
            onCustomSearch: onCustomSearch,
          );
        }
        if (bundle.results.isEmpty) {
          return _AddonEmptyRow(
            addonName: addon.manifest.sourceName,
            iconUrl: addon.manifest.iconUrl,
            onCustomSearch: onCustomSearch,
          );
        }
        return _AddonGroup(
          addonId: addon.id,
          addonName: addon.manifest.sourceName,
          iconUrl: addon.manifest.iconUrl,
          results: bundle.results,
          showMore: showMore,
          selectedHref: selectedHref,
          onToggleMore: onToggleMore,
          onResultTapped: onResultTapped,
          onCustomSearch: onCustomSearch,
        );
      },
    );
  }
}

class _AddonEmptyRow extends StatefulWidget {
  const _AddonEmptyRow({
    required this.addonName,
    required this.iconUrl,
    required this.onCustomSearch,
    this.error,
  });

  final String addonName;
  final String iconUrl;
  final String? error;
  final ValueChanged<String> onCustomSearch;

  @override
  State<_AddonEmptyRow> createState() => _AddonEmptyRowState();
}

class _AddonEmptyRowState extends State<_AddonEmptyRow> {
  bool _searching = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String q = _controller.text.trim();
    if (q.isNotEmpty) widget.onCustomSearch(q);
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.error != null;

    if (_searching) {
      return Row(
        children: <Widget>[
          _AddonLogo(url: widget.iconUrl),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: context.t('Custom search…'),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          IconButton(
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.search_rounded),
            onPressed: _submit,
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              _controller.clear();
              setState(() => _searching = false);
            },
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        _AddonLogo(url: widget.iconUrl),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall,
              children: <TextSpan>[
                TextSpan(
                  text: widget.addonName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: hasError
                      ? ' — ${widget.error}'
                      : ' — ${context.t('No results')}',
                  style: TextStyle(
                    color: hasError
                        ? AppColors.danger
                        : Theme.of(context).disabledColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.fromLTRB(5, 0, 5, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            foregroundColor: Theme.of(context).disabledColor,
          ),
          icon: const Icon(Icons.manage_search_rounded, size: 16),
          label: Text(
            context.t('Custom Search'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          onPressed: () => setState(() => _searching = true),
        ),
      ],
    );
  }
}

class _AddonGroup extends StatefulWidget {
  const _AddonGroup({
    required this.addonId,
    required this.addonName,
    required this.iconUrl,
    required this.results,
    required this.showMore,
    required this.onToggleMore,
    required this.onResultTapped,
    required this.onCustomSearch,
    this.selectedHref,
  });

  final String addonId;
  final String addonName;
  final String iconUrl;
  final List<SoraSearchResult> results;
  final bool showMore;
  final String? selectedHref;
  final VoidCallback onToggleMore;
  final ValueChanged<SoraSearchResult> onResultTapped;
  final ValueChanged<String> onCustomSearch;

  @override
  State<_AddonGroup> createState() => _AddonGroupState();
}

class _AddonGroupState extends State<_AddonGroup> {
  static const int _defaultMax = 5;
  bool _searching = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String q = _controller.text.trim();
    if (q.isNotEmpty) widget.onCustomSearch(q);
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final List<SoraSearchResult> visible = widget.showMore
        ? widget.results
        : widget.results.take(_defaultMax).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _AddonLogo(url: widget.iconUrl),
            const SizedBox(width: AppSpacing.sm),
            if (_searching) ...<Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: InputDecoration(
                    hintText: context.t('Custom search…'),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              IconButton(
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.search_rounded),
                onPressed: _submit,
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _controller.clear();
                  setState(() => _searching = false);
                },
              ),
            ] else ...<Widget>[
              Expanded(
                child: Text(
                  widget.addonName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.fromLTRB(5, 0, 5, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Theme.of(context).disabledColor,
                ),
                icon: const Icon(Icons.manage_search_rounded, size: 16),
                label: Text(
                  context.t('Custom Search'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                onPressed: () => setState(() => _searching = true),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...visible.map(
          (SoraSearchResult result) => _SourceResultTile(
            result: result,
            selected: widget.selectedHref == result.href,
            onTap: () => widget.onResultTapped(result),
          ),
        ),
        if (widget.results.length > _defaultMax) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: widget.onToggleMore,
            icon: Icon(
              widget.showMore
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            label: Text(
              widget.showMore
                  ? context.t('Show less')
                  : context.tf('Show {count} more', <String, Object?>{
                      'count': widget.results.length - _defaultMax,
                    }),
            ),
          ),
        ],
      ],
    );
  }
}

class _AddonLogo extends StatelessWidget {
  const _AddonLogo({required this.url});

  static const double _size = 28;

  final String url;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(Icons.extension_rounded, size: _size * 0.48),
    );
    if (url.trim().isEmpty) {
      return fallback;
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        placeholder: (BuildContext context, String url) => fallback,
        errorWidget: (BuildContext context, String url, Object error) =>
            fallback,
      ),
    );
  }
}

class _SourceResultTile extends StatelessWidget {
  const _SourceResultTile({
    required this.result,
    required this.selected,
    required this.onTap,
  });

  final SoraSearchResult result;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
              : null,
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : AppColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.md),
              child: SizedBox(
                width: 80,
                height: 52,
                child: result.image.isEmpty
                    ? _ThumbnailFallback(title: result.title)
                    : CachedNetworkImage(
                        imageUrl: result.image,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, err) =>
                            _ThumbnailFallback(title: result.title),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                result.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ScoreBadge(score: result.score, languageCode: result.languageCode),
            if (selected) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score, required this.languageCode});

  final double score;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final Color color = score >= 0.8
        ? AppColors.success
        : score >= 0.5
        ? AppColors.warning
        : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.all(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '${_languageFlag(languageCode)} ${(score * 100).round()}%'.trim(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _languageFlag(String languageCode) {
  final String countryCode = switch (languageCode.toLowerCase()) {
    'ja' => 'JP',
    'ru' => 'RU',
    'en' => 'US',
    _ => '',
  };
  if (countryCode.isEmpty) return '';
  const int base = 0x1F1E6;
  return String.fromCharCodes(
    countryCode.codeUnits.map((int unit) => base + unit - 65),
  );
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.18),
            scheme.secondary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode picker
// ---------------------------------------------------------------------------

class _EpisodePickerSection extends ConsumerStatefulWidget {
  const _EpisodePickerSection({
    required this.item,
    required this.source,
    required this.onEpisodePicked,
    this.selectedEpisodeHref,
    this.seasonNumber = 1,
    this.onContinueResolved,
  });

  final MediaItem item;
  final SoraSearchResult source;
  final String? selectedEpisodeHref;
  final ValueChanged<SoraEpisode> onEpisodePicked;
  final int seasonNumber;
  final void Function(SoraEpisode?, AnimeEpisodeMetadata?, int)?
  onContinueResolved;

  @override
  ConsumerState<_EpisodePickerSection> createState() =>
      _EpisodePickerSectionState();
}

class _EpisodePickerSectionState extends ConsumerState<_EpisodePickerSection> {
  String? _lastNotifiedHref;
  int _lastNotifiedNum = -1;

  @override
  Widget build(BuildContext context) {
    final SoraSourceRequest request = SoraSourceRequest(
      addonId: widget.source.addonId,
      result: widget.source,
    );

    final AsyncValue<SoraSourceContent> contentAsync = ref.watch(
      soraSourceContentProvider(request),
    );
    final Set<String> watchedSet = ref.watch(soraEpisodeProgressProvider);
    final SettingsState settings = ref.watch(settingsProvider);
    final bool useAniListProgress =
        ref.watch(catalogModeProvider) == CatalogMode.anilist;
    final int? anilistId = _animeAnilistId(widget.item);

    // AniList episode progress (integer count of watched episodes)
    int anilistProgress = 0;
    if (useAniListProgress && anilistId != null) {
      void scanFolders(List<AniListAnimeListFolder> folders) {
        for (final AniListAnimeListFolder folder in folders) {
          for (final AniListAnimeListEntry entry in folder.entries) {
            final int? entryAnilistId = int.tryParse(
              entry.mediaItem.externalIds['anilist'] ?? '',
            );
            if (entryAnilistId == anilistId &&
                entry.progress > anilistProgress) {
              anilistProgress = entry.progress;
            }
          }
        }
      }

      ref.watch(anilistAnimeListProvider).whenData(scanFolders);
      // Fall back to preview list (loads first) when full list is still loading.
      if (anilistProgress == 0) {
        ref.watch(anilistAnimePreviewListProvider).whenData(scanFolders);
      }
    }

    final LocalLibraryController libraryNotifier = ref.read(
      localLibraryProvider.notifier,
    );

    final AnimeEpisodeMetadataBundle episodeMetadata =
        !useAniListProgress || anilistId == null
        ? AnimeEpisodeMetadataBundle.empty
        : ref
              .watch(
                animeEpisodeMetadataProvider(
                  AnimeEpisodeMetadataRequest(
                    anilistId: anilistId,
                    languageCode: _episodeMetadataLanguage(settings),
                  ),
                ),
              )
              .maybeWhen(
                data: (AnimeEpisodeMetadataBundle value) => value,
                orElse: () => AnimeEpisodeMetadataBundle.empty,
              );

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: widget.item.type == MediaType.movie
                ? context.t('Start Watching')
                : context.t('Choose Episode'),
            subtitle: context.t('Tap to resolve stream.'),
          ),
          contentAsync.when(
            loading: () => const SkeletonBox(height: 200, radius: AppRadius.lg),
            error: (Object error, _) => Text(
              error.toString(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.danger),
            ),
            data: (SoraSourceContent content) {
              if (content.episodes.isEmpty) {
                final SoraEpisode episode = SoraEpisode(
                  number: 1,
                  href: widget.source.href,
                  title: '',
                  image: '',
                  description: '',
                  duration: '',
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: FilledButton.icon(
                    onPressed: () => widget.onEpisodePicked(
                      _episodeForPlayback(
                        episode,
                        episodeMetadata.forNumber(episode.number),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(context.t('Play')),
                  ),
                );
              }

              // Compute the max watched episode number from soraEpisodeProgress
              // as fallback when AniList is not connected.
              // Episode 0 (number < 1) is excluded — it's a special/prologue
              // that must not shift the watched range for numbered episodes.
              int maxLocalWatched = 0;
              for (final SoraEpisode ep in content.episodes) {
                if (ep.number < 1) continue;
                final String key = ref
                    .read(soraEpisodeProgressProvider.notifier)
                    .keyFor(
                      mediaId: widget.item.id,
                      result: widget.source,
                      episode: ep,
                    );
                if (watchedSet.contains(key)) {
                  final int n = ep.number.round();
                  if (n > maxLocalWatched) maxLocalWatched = n;
                }
              }
              // Also check local position-based progress
              int maxPositionWatched = 0;
              for (final SoraEpisode ep in content.episodes) {
                if (ep.number < 1) continue;
                final EpisodeProgress? prog = libraryNotifier.episodeProgress(
                  widget.item.id,
                  widget.seasonNumber,
                  ep.number,
                );
                if (prog?.isWatched == true) {
                  final int n = ep.number.round();
                  if (n > maxPositionWatched) maxPositionWatched = n;
                }
              }

              // In AniList mode, AniList is the sole source of truth — never
              // fall back to local data, so that AniList decrements/resets
              // are immediately reflected in the episode list.
              final int effectiveContinued = useAniListProgress
                  ? anilistProgress
                  : (maxLocalWatched > 0
                        ? maxLocalWatched
                        : maxPositionWatched);

              // Find the episode to continue from (next after last watched).
              SoraEpisode? continueEp;
              AnimeEpisodeMetadata? continueEpMeta;
              if (effectiveContinued > 0) {
                for (final SoraEpisode ep in content.episodes) {
                  if (ep.number.round() == effectiveContinued + 1) {
                    continueEp = ep;
                    continueEpMeta = episodeMetadata.forNumber(ep.number);
                    break;
                  }
                }
              }

              // Notify parent about continue episode (deduplicated).
              final String? newHref = continueEp?.href;
              if (newHref != _lastNotifiedHref ||
                  effectiveContinued != _lastNotifiedNum) {
                _lastNotifiedHref = newHref;
                _lastNotifiedNum = effectiveContinued;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    widget.onContinueResolved?.call(
                      continueEp,
                      continueEpMeta,
                      effectiveContinued,
                    );
                  }
                });
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: content.episodes.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final SoraEpisode episode = content.episodes[index];
                  final AnimeEpisodeMetadata? metadata = episodeMetadata
                      .forNumber(episode.number);
                  final int epNum = episode.number.round();

                  final String soraKey = ref
                      .read(soraEpisodeProgressProvider.notifier)
                      .keyFor(
                        mediaId: widget.item.id,
                        result: widget.source,
                        episode: episode,
                      );
                  final EpisodeProgress? localProg = libraryNotifier
                      .episodeProgress(
                        widget.item.id,
                        widget.seasonNumber,
                        episode.number,
                      );
                  // Episode 0 (number < 1): only its own local data,
                  //   never derived from the range counter.
                  // AniList mode: AniList is sole truth — local playback
                  //   must not override decremented/reset AniList progress.
                  // Local mode: full local data.
                  final bool isWatched;
                  if (epNum <= 0) {
                    isWatched =
                        watchedSet.contains(soraKey) ||
                        (localProg?.isWatched ?? false);
                  } else {
                    isWatched =
                        (effectiveContinued > 0 &&
                            epNum <= effectiveContinued) ||
                        watchedSet.contains(soraKey) ||
                        (!useAniListProgress &&
                            (localProg?.isWatched ?? false));
                  }

                  final bool isContinue =
                      !isWatched &&
                      effectiveContinued > 0 &&
                      epNum == effectiveContinued + 1;

                  return _EpisodeTile(
                    episode: episode,
                    displayTitle: _episodeCardTitle(episode, metadata),
                    imageUrl: _episodeImageUrl(
                      episode: episode,
                      metadata: metadata,
                      item: widget.item,
                    ),
                    isSelected: widget.selectedEpisodeHref == episode.href,
                    isWatched: isWatched,
                    isContinue: isContinue,
                    localProgress: localProg,
                    onTap: () => widget.onEpisodePicked(
                      _episodeForPlayback(episode, metadata),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.displayTitle,
    required this.imageUrl,
    required this.isSelected,
    required this.isWatched,
    required this.isContinue,
    required this.onTap,
    this.localProgress,
  });

  final SoraEpisode episode;
  final String displayTitle;
  final String imageUrl;
  final bool isSelected;
  final bool isWatched;
  final bool isContinue;
  final EpisodeProgress? localProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String header = episode.displayNumber.isNotEmpty
        ? '${context.t('Episode')} ${episode.displayNumber}'
        : displayTitle.isNotEmpty
        ? displayTitle
        : context.t('Episode 0');
    final bool showDisplayTitle =
        displayTitle.isNotEmpty &&
        displayTitle.toLowerCase() != header.toLowerCase();
    final String subtitle = showDisplayTitle
        ? displayTitle
        : episode.description;

    final double progressFraction = localProgress?.fraction ?? 0.0;
    final bool showProgressBar =
        progressFraction > 0.02 && progressFraction < 0.99;

    return InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
              : null,
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : AppColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.md),
              child: SizedBox(
                width: 120,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    imageUrl.isEmpty
                        ? _EpisodeThumbFallback(number: episode.number)
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, err) =>
                                _EpisodeThumbFallback(number: episode.number),
                          ),
                    if (episode.number != 0 && (isWatched || isContinue))
                      _WatchedBadge(isContinue: isContinue),
                    if (showProgressBar)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progressFraction,
                          minHeight: 3,
                          backgroundColor: Colors.black38,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    header,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (isSelected)
              Icon(
                Icons.radio_button_checked,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              )
            else
              const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge({required this.isContinue});
  final bool isContinue;

  @override
  Widget build(BuildContext context) {
    final String text = isContinue ? 'Continue' : 'Watched';
    return Align(
      alignment: Alignment.bottomLeft,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topRight: Radius.circular(6)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.black.withValues(alpha: 0.55),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeThumbFallback extends StatelessWidget {
  const _EpisodeThumbFallback({required this.number});

  final double number;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int n = number.round();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.18),
            scheme.secondary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Text(
          n > 0 ? n.toString().padLeft(2, '0') : '▶',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

int? _animeAnilistId(MediaItem item) {
  if (item.type != MediaType.anime) return null;
  final int? direct = int.tryParse(item.externalIds['anilist'] ?? '');
  if (direct != null && direct > 0) return direct;
  final List<String> parts = item.id.split(':');
  if (parts.length == 2 && parts.first == 'anilist') {
    final int? id = int.tryParse(parts[1]);
    if (id != null && id > 0) return id;
  }
  return null;
}

String _episodeMetadataLanguage(SettingsState settings) {
  return (settings.metadataLocale ?? settings.appLocale)?.languageCode ??
      settings.effectiveTmdbLanguage.split('-').first.toLowerCase();
}

String _episodeCardTitle(SoraEpisode episode, AnimeEpisodeMetadata? metadata) {
  final String moduleTitle = episode.title.trim();
  if (moduleTitle.isNotEmpty &&
      !isGenericEpisodeTitle(moduleTitle, episode.number)) {
    return moduleTitle;
  }

  final String fallbackTitle = metadata == null
      ? ''
      : (metadata.aniListTitle.trim().isNotEmpty
            ? metadata.aniListTitle
            : metadata.aniZipTitle);
  return _cleanEpisodePrefix(fallbackTitle);
}

String _cleanEpisodePrefix(String title) {
  return title
      .trim()
      .replaceFirst(
        RegExp(r'^\s*(episode|ep)\s*\d+\s*[-:–—]?\s*', caseSensitive: false),
        '',
      )
      .trim();
}

String _episodeImageUrl({
  required SoraEpisode episode,
  required AnimeEpisodeMetadata? metadata,
  required MediaItem item,
}) {
  for (final String image in <String>[
    metadata?.aniZipImage ?? '',
    metadata?.aniListThumbnail ?? '',
    episode.image,
    item.posterUrl,
  ]) {
    final String trimmed = image.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String? _streamRequestKey(SoraSearchResult? source, SoraEpisode? episode) {
  if (source == null || episode == null) return null;
  return '${source.addonId}:${episode.href}';
}

SoraEpisode _episodeForPlayback(
  SoraEpisode episode,
  AnimeEpisodeMetadata? metadata,
) {
  return episode.copyWith(
    metadataTitle: metadata?.fallbackTitle(episode.number) ?? '',
    metadataImage: metadata?.preferredImage ?? '',
    tvdbTitle: metadata?.tvdbTitle ?? '',
  );
}

// ---------------------------------------------------------------------------
// Stream resolving section
// ---------------------------------------------------------------------------

class _StreamResolvingSection extends ConsumerWidget {
  const _StreamResolvingSection({
    required this.source,
    required this.episode,
    required this.onResolved,
    required this.onError,
  });

  final SoraSearchResult? source;
  final SoraEpisode? episode;
  final void Function(String requestKey, NormalizedStreamBundle bundle)
  onResolved;
  final void Function(String requestKey, Object error) onError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SoraSearchResult? src = source;
    if (src == null) {
      return const SizedBox.shrink();
    }

    final SoraEpisode ep =
        episode ??
        SoraEpisode(
          number: 1,
          href: src.href,
          title: '',
          image: '',
          description: '',
          duration: '',
        );

    final SoraStreamRequest request = SoraStreamRequest(
      addonId: src.addonId,
      episode: ep,
    );
    final String requestKey = _streamRequestKey(src, ep)!;

    final AsyncValue<NormalizedStreamBundle> bundleAsync = ref.watch(
      soraStreamBundleProvider(request),
    );

    bundleAsync.whenOrNull(
      data: (NormalizedStreamBundle bundle) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onResolved(requestKey, bundle),
        );
      },
      error: (Object error, _) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onError(requestKey, error),
        );
      },
    );

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: <Widget>[
          bundleAsync.isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  bundleAsync.hasError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: bundleAsync.hasError
                      ? AppColors.danger
                      : AppColors.success,
                ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              bundleAsync.isLoading
                  ? context.t('Resolving stream…')
                  : bundleAsync.hasError
                  ? context.t('Stream resolution failed')
                  : context.t('Choose stream'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Choose stream sheet
// ---------------------------------------------------------------------------

class _StreamReadySheet extends StatefulWidget {
  const _StreamReadySheet({required this.bundle, required this.onPlay});

  final NormalizedStreamBundle bundle;
  final ValueChanged<NormalizedStreamBundle> onPlay;

  @override
  State<_StreamReadySheet> createState() => _StreamReadySheetState();
}

class _StreamReadySheetState extends State<_StreamReadySheet> {
  late int _selectedIndex;
  late int _selectedVoiceOverIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = 0;
    _selectedVoiceOverIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final List<NormalizedServer> servers = widget.bundle.availableServers;
    final List<NormalizedVoiceOver> voiceovers =
        widget.bundle.availableVoiceOvers;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.surfaceColor,
        borderRadius: AppRadius.all(AppRadius.xxl),
        border: Border.all(color: palette.borderColor),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.play_circle_outline_rounded),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      context.t('Choose Stream'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (servers.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                if (servers.length > 1) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      for (int i = 0; i < servers.length; i++)
                        ChoiceChip(
                          label: Text(servers[i].title),
                          selected: _selectedIndex == i,
                          onSelected: (_) => setState(() => _selectedIndex = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (voiceovers.length > 1) ...<Widget>[
                  Text(
                    context.t('Soundtrack'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: <Widget>[
                      for (int i = 0; i < voiceovers.length; i++)
                        ChoiceChip(
                          label: Text(voiceovers[i].label),
                          selected: _selectedVoiceOverIndex == i,
                          onSelected: (_) =>
                              setState(() => _selectedVoiceOverIndex = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                // Container(
                //   padding: const EdgeInsets.all(AppSpacing.md),
                //   decoration: BoxDecoration(
                //     color: palette.surfaceSoftColor,
                //     borderRadius: AppRadius.all(AppRadius.lg),
                //     border: Border.all(color: palette.borderColor),
                //   ),
                //   child: Column(
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: <Widget>[
                //       if (widget.bundle.selectedVoiceOver != null &&
                //           voiceovers.length <= 1)
                //         Text(
                //           '${context.t('Soundtrack')}: ${widget.bundle.selectedVoiceOver!.label}',
                //           style: Theme.of(context).textTheme.bodySmall,
                //         ),
                //       Text(
                //         servers[_selectedIndex].streamUrl,
                //         maxLines: 2,
                //         overflow: TextOverflow.ellipsis,
                //         style: Theme.of(context).textTheme.bodySmall,
                //       ),
                //     ],
                //   ),
                // ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () {
                      NormalizedStreamBundle selected = widget.bundle
                          .withServer(servers[_selectedIndex]);
                      if (voiceovers.length > 1) {
                        selected = selected.withVoiceOver(
                          voiceovers[_selectedVoiceOverIndex],
                        );
                      }
                      widget.onPlay(selected);
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(context.t('Play')),
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  context.t('No streams available for this source.'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<MediaSeason> _selectableSeasons(MediaItem item) {
  final List<MediaSeason> seasons = item.seasons.toList(growable: false);
  seasons.sort((MediaSeason a, MediaSeason b) {
    final int left = a.seasonNumber <= 0 ? 1 << 30 : a.seasonNumber;
    final int right = b.seasonNumber <= 0 ? 1 << 30 : b.seasonNumber;
    final int order = left.compareTo(right);
    if (order != 0) {
      return order;
    }
    return a.name.compareTo(b.name);
  });
  return seasons;
}

String _seasonPickerLabel(BuildContext context, MediaSeason season) {
  final String cleaned = _cleanSeasonName(season.name);
  if (cleaned.isNotEmpty) {
    return cleaned;
  }
  if (season.isSpecials) {
    return context.t('Specials');
  }
  return '${context.t('Season')} ${season.seasonNumber}';
}

String _cleanSeasonName(String value) {
  return value
      .trim()
      .replaceFirst(
        RegExp(
          r'^(?:Season\s+\d+|S\d+|Movie|Specials?|OVA|ONA)\s*[·:–—-]\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

bool _needsSeasonDetails(MediaItem item) {
  return item.type != MediaType.movie && item.seasons.isEmpty;
}

String _seasonDebugSummary(List<MediaSeason> seasons) {
  if (seasons.isEmpty) return '<empty>';
  return seasons
      .map(
        (MediaSeason s) =>
            '${s.seasonNumber}:${s.name.isEmpty ? '<blank>' : s.name}'
            ':episodes=${s.episodeCount}:poster=${s.posterUrl.isNotEmpty}',
      )
      .join(', ');
}

MediaItem _seasonSearchItem(MediaItem item, WatchSession session) {
  if (item.type == MediaType.movie) {
    return item;
  }
  final int seasonNumber = session.seasonNumber;
  if (seasonNumber <= 1) {
    return item;
  }
  MediaSeason? season;
  for (final MediaSeason s in item.seasons) {
    if (s.seasonNumber == seasonNumber) {
      season = s;
      break;
    }
  }
  final String seasonName = season?.name.trim() ?? '';
  final String originalSeasonName = season?.originalName.trim() ?? '';
  final List<String> seasonAliases = season == null
      ? const <String>[]
      : _uniqueSeasonSearchAliases(season);
  return MediaItem(
    id: item.id,
    title: item.title,
    originalTitle: item.originalTitle,
    overview: season != null && season.overview.isNotEmpty
        ? season.overview
        : item.overview,
    type: item.type,
    year: item.year,
    posterUrl: season != null && season.posterUrl.isNotEmpty
        ? season.posterUrl
        : item.posterUrl,
    backdropUrl: item.backdropUrl,
    rating: item.rating,
    genres: item.genres,
    sourceProvider: item.sourceProvider,
    externalIds: <String, String>{
      ...item.externalIds,
      if (season != null) ...season.externalIds,
      'sora_season_number': seasonNumber.toString(),
      if (seasonName.isNotEmpty) ...{
        'sora_season_name': seasonName,
        // Full season title used as the primary source-search query.
        // Sources index seasons by their real name ("JJK: Shibuya Incident",
        // "AoT: The Final Season"), not by synthetic "Series Season 2" strings.
        'sora_season_full_title': _fullSeasonTitle(item.title, seasonName),
      },
      if (originalSeasonName.isNotEmpty)
        'sora_season_original_name': originalSeasonName,
      if (seasonAliases.isNotEmpty)
        'sora_season_aliases': seasonAliases.join('\n'),
    },
    runtimeMinutes: item.runtimeMinutes,
    episodeCount: season?.episodeCount ?? item.episodeCount,
    seasons: item.seasons,
    statusLabel: item.statusLabel,
    aliases: item.aliases,
    originalLanguage: item.originalLanguage,
  );
}

MediaItem _playerRouteItem(MediaItem item, WatchSession session) {
  final MediaItem base = _seasonSearchItem(item, session);
  final Map<String, String> externalIds = <String, String>{
    ...base.externalIds,
    'mirushin_metadata_title': base.title,
    'mirushin_metadata_original_title': base.originalTitle,
    if (item.episodeCount != null && item.episodeCount! > 0)
      'mirushin_total_episode_count': item.episodeCount!.toString(),
  };
  final String sourceTitle = session.source?.title.trim() ?? '';
  return MediaItem(
    id: base.id,
    title: sourceTitle.isEmpty ? base.title : sourceTitle,
    originalTitle: base.originalTitle,
    overview: base.overview,
    type: base.type,
    year: base.year,
    posterUrl: base.posterUrl,
    backdropUrl: base.backdropUrl,
    rating: base.rating,
    genres: base.genres,
    sourceProvider: base.sourceProvider,
    externalIds: externalIds,
    runtimeMinutes: base.runtimeMinutes,
    episodeCount: item.episodeCount,
    seasons: base.seasons,
    statusLabel: base.statusLabel,
    aliases: base.aliases,
    originalLanguage: base.originalLanguage,
  );
}

/// Returns a display-only MediaItem reflecting the selected season's poster,
/// overview, and full title. Used only for the hero — source search continues
/// to use [_seasonSearchItem].
MediaItem _heroDisplayItem(MediaItem item, WatchSession? session) {
  if (session == null || session.step == WatchStep.pickSeason) return item;
  if (item.type == MediaType.movie) return item;
  if (item.sourceProvider == 'AniList') return item;
  final int seasonNumber = session.seasonNumber;
  MediaSeason? season;
  for (final MediaSeason s in item.seasons) {
    if (s.seasonNumber == seasonNumber) {
      season = s;
      break;
    }
  }
  if (season == null) return item;
  final String seasonName = season.name.trim();
  // Only replace the title when the season has a real distinctive name.
  // Synthetic fallbacks like "Season 1", "Season 2", "Specials" are not
  // meaningful titles — showing them appended to the series name would be
  // misleading (e.g. "Rascal Does Not Dream: Season 1").
  final bool hasRealName =
      seasonName.isNotEmpty &&
      !RegExp(r'^(Season\s+\d+|Specials?)$').hasMatch(seasonName);
  final String displayTitle = hasRealName
      ? _fullSeasonTitle(item.title, seasonName)
      : item.title;
  return MediaItem(
    id: item.id,
    title: displayTitle,
    originalTitle: item.originalTitle,
    overview: season.overview.isNotEmpty ? season.overview : item.overview,
    type: item.type,
    year: item.year,
    posterUrl: season.posterUrl.isNotEmpty ? season.posterUrl : item.posterUrl,
    backdropUrl: item.backdropUrl,
    rating: item.rating,
    genres: item.genres,
    sourceProvider: item.sourceProvider,
    externalIds: item.externalIds,
    runtimeMinutes: item.runtimeMinutes,
    episodeCount: season.episodeCount > 0
        ? season.episodeCount
        : item.episodeCount,
    seasons: item.seasons,
    statusLabel: item.statusLabel,
    aliases: item.aliases,
    originalLanguage: item.originalLanguage,
  );
}

bool _containsJapaneseScript(String text) => text.runes.any(
  (int r) => (r >= 0x3040 && r <= 0x30FF) || (r >= 0x3400 && r <= 0x9FFF),
);

/// Returns the canonical full title for a season.
///
/// If [seasonName] already contains [seriesTitle] (e.g. "Sword Art Online:
/// Alicization"), returns [seasonName] unchanged. If the titles are in
/// different scripts (e.g. English series + Japanese season name), returns
/// [seasonName] alone rather than producing a garbled mixed-script title.
/// Otherwise returns "[seriesTitle]: [seasonName]".
String _fullSeasonTitle(String seriesTitle, String seasonName) {
  if (seasonName.isEmpty) return seriesTitle;
  final String seriesLower = seriesTitle.toLowerCase().trim();
  if (seriesLower.isNotEmpty &&
      seasonName.toLowerCase().trim().contains(seriesLower)) {
    return seasonName;
  }
  // Different scripts → don't combine (e.g. "Rascal: 青春ブタ野郎は..." is wrong).
  if (_containsJapaneseScript(seasonName) !=
      _containsJapaneseScript(seriesTitle)) {
    return seasonName;
  }
  return '$seriesTitle: $seasonName';
}

List<String> _uniqueSeasonSearchAliases(MediaSeason season) {
  final List<String> aliases = <String>[
    if (season.originalName.trim().isNotEmpty) season.originalName.trim(),
    ...season.aliases,
  ];
  final List<String> result = <String>[];
  final Set<String> seen = <String>{season.name.trim().toLowerCase()};
  for (final String alias in aliases) {
    final String trimmed = alias.trim();
    if (trimmed.isEmpty) continue;
    if (seen.add(trimmed.toLowerCase())) result.add(trimmed);
  }
  return result;
}
