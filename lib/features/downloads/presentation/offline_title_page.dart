import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/navigation_helpers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/widgets/adaptive_page.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/neutral_placeholder.dart';
import '../../../core/widgets/page_back_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/models/media_item.dart';
import '../../library/application/local_library_provider.dart';
import '../../player/domain/player_models.dart';
import '../../watch/domain/normalized_models.dart';
import '../application/download_episode_display.dart';
import '../application/downloads_provider.dart';
import '../application/offline_playback.dart';
import '../domain/download_models.dart';

/// Offline detail page for a downloaded title: pick a module, then play its
/// downloaded episodes (non-downloaded episodes are shown disabled).
class OfflineTitlePage extends ConsumerStatefulWidget {
  const OfflineTitlePage({
    required this.mediaId,
    this.initialAddonId,
    super.key,
  });

  final String mediaId;
  final String? initialAddonId;

  @override
  ConsumerState<OfflineTitlePage> createState() => _OfflineTitlePageState();
}

class _OfflineTitlePageState extends ConsumerState<OfflineTitlePage> {
  String? _selectedAddonId;

  @override
  void didUpdateWidget(covariant OfflineTitlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId ||
        oldWidget.initialAddonId != widget.initialAddonId) {
      _selectedAddonId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(downloadsProvider);
    ref.watch(localLibraryProvider);
    final DownloadController controller = ref.read(downloadsProvider.notifier);
    final List<DownloadedEpisode> episodes = controller.episodesFor(
      widget.mediaId,
    );

    if (episodes.isEmpty) {
      return AdaptivePage(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: PageBackButton(
                onPressed: () => goBackOrGo(context, AppRoutes.library),
              ),
            ),
            NeutralPlaceholder(
              title: context.t('No downloads'),
              message: context.t('This title has no downloaded episodes.'),
              icon: Icons.download_done_rounded,
              height: 360,
            ),
          ],
        ),
      );
    }

    final MediaItem media = episodes.first.media;

    // Distinct modules with downloads for this title.
    final Map<String, String> modules = <String, String>{};
    for (final DownloadedEpisode e in episodes) {
      modules.putIfAbsent(e.addonId, () => e.addonName);
    }
    final String? requestedAddonId = _selectedAddonId ?? widget.initialAddonId;
    final String selected =
        (requestedAddonId != null && modules.containsKey(requestedAddonId))
        ? requestedAddonId
        : modules.keys.first;

    final List<DownloadedEpisode> moduleEpisodes = episodes
        .where((DownloadedEpisode e) => e.addonId == selected)
        .toList(growable: false);
    final int effectiveContinued = _effectiveContinued(moduleEpisodes);
    final DownloadedEpisode? continueEpisode = _continueEpisodeFor(
      moduleEpisodes,
      effectiveContinued,
    );

    return Stack(
      children: <Widget>[
        AdaptivePage(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _OfflineHero(media: media),
                const SizedBox(height: AppSpacing.xl),

                // Module chooser (only modules with downloads).
                GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: context.t('Choose Module'),
                        subtitle: context.t('Modules you downloaded from.'),
                        trailing: IconButton(
                          tooltip: context.t('Delete all'),
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _confirmDeleteTitle(controller),
                        ),
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: modules.entries.map((
                          MapEntry<String, String> m,
                        ) {
                          return ChoiceChip(
                            label: Text(m.value.isNotEmpty ? m.value : m.key),
                            selected: m.key == selected,
                            onSelected: (_) =>
                                setState(() => _selectedAddonId = m.key),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionHeader(
                        title: context.t('Episodes'),
                        subtitle: context.t(
                          'Downloaded episodes play offline.',
                        ),
                      ),
                      ..._buildEpisodeRows(
                        context,
                        controller,
                        media,
                        moduleEpisodes,
                        effectiveContinued,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl * 2),
              ],
            ),
          ),
        ),
        if (continueEpisode != null)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.xl,
            child: SafeArea(
              child: FilledButton.icon(
                onPressed: () => _play(continueEpisode, moduleEpisodes),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(
                  continueEpisode.displayNumber.isEmpty
                      ? context.t('Continue')
                      : context.tf('Continue EP {number}', <String, Object?>{
                          'number': continueEpisode.displayNumber,
                        }),
                ),
              ),
            ),
          ),
      ],
    );
  }

  int _effectiveContinued(List<DownloadedEpisode> moduleEpisodes) {
    int maxWatched = 0;
    for (final DownloadedEpisode e in moduleEpisodes) {
      if (!e.isComplete || e.episodeNumber < 1) continue;
      final EpisodeProgress? progress = _localProgress(e);
      if (progress?.isWatched != true) continue;
      final int n = e.episodeNumber.round();
      if (n > maxWatched) maxWatched = n;
    }
    return maxWatched;
  }

  DownloadedEpisode? _continueEpisodeFor(
    List<DownloadedEpisode> moduleEpisodes,
    int effectiveContinued,
  ) {
    if (effectiveContinued <= 0) return null;
    for (final DownloadedEpisode e in moduleEpisodes) {
      if (e.isComplete && e.episodeNumber.round() == effectiveContinued + 1) {
        return e;
      }
    }
    return null;
  }

  EpisodeProgress? _localProgress(DownloadedEpisode ep) {
    final LocalLibraryController library = ref.read(
      localLibraryProvider.notifier,
    );
    final String? soraMediaId = soraEpisodeProgressMediaId(
      addonId: ep.addonId,
      episodeHref: ep.episodeHref,
    );
    if (soraMediaId != null) {
      final EpisodeProgress? progress = library.episodeProgress(
        soraMediaId,
        ep.seasonNumber,
        ep.episodeNumber,
      );
      if (progress != null) return progress;
    }
    return library.episodeProgress(
      ep.mediaId,
      ep.seasonNumber,
      ep.episodeNumber,
    );
  }

  List<Widget> _buildEpisodeRows(
    BuildContext context,
    DownloadController controller,
    MediaItem media,
    List<DownloadedEpisode> moduleEpisodes,
    int effectiveContinued,
  ) {
    // Group by season.
    final Map<int, List<DownloadedEpisode>> bySeason =
        <int, List<DownloadedEpisode>>{};
    for (final DownloadedEpisode e in moduleEpisodes) {
      bySeason.putIfAbsent(e.seasonNumber, () => <DownloadedEpisode>[]).add(e);
    }
    final List<int> seasons = bySeason.keys.toList()..sort();
    final bool multiSeason = seasons.length > 1;

    final List<Widget> rows = <Widget>[];
    for (final int season in seasons) {
      final List<DownloadedEpisode> seasonEpisodes = bySeason[season]!;
      if (multiSeason) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              context.tf('Season {number}', <String, Object?>{
                'number': season,
              }),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }

      // Downloaded episodes keyed by rounded number for placeholder matching.
      final Map<int, DownloadedEpisode> downloadedByNum =
          <int, DownloadedEpisode>{};
      for (final DownloadedEpisode e in seasonEpisodes) {
        downloadedByNum[e.episodeNumber.round()] = e;
      }

      final int total = _seasonEpisodeTotal(media, season, seasonEpisodes);
      final Set<int> rendered = <int>{};

      for (int n = 1; n <= total; n++) {
        final DownloadedEpisode? ep = downloadedByNum[n];
        rendered.add(n);
        if (ep != null) {
          rows.add(
            _episodeTile(
              context,
              controller,
              media,
              ep,
              moduleEpisodes,
              effectiveContinued,
            ),
          );
        } else {
          rows.add(_disabledEpisodeRow(context, n));
        }
      }
      // Specials / non-integer / out-of-range downloads not covered above.
      for (final DownloadedEpisode e in seasonEpisodes) {
        if (rendered.contains(e.episodeNumber.round()) &&
            e.episodeNumber == e.episodeNumber.roundToDouble() &&
            e.episodeNumber.round() <= total &&
            e.episodeNumber.round() >= 1) {
          continue;
        }
        rows.add(
          _episodeTile(
            context,
            controller,
            media,
            e,
            moduleEpisodes,
            effectiveContinued,
          ),
        );
      }
    }
    return rows;
  }

  int _seasonEpisodeTotal(
    MediaItem media,
    int season,
    List<DownloadedEpisode> seasonEpisodes,
  ) {
    for (final MediaSeason s in media.seasons) {
      if (s.seasonNumber == season && s.episodeCount > 0) {
        return s.episodeCount;
      }
    }
    if (media.seasons.isEmpty && (media.episodeCount ?? 0) > 0 && season <= 1) {
      return media.episodeCount!;
    }
    // Fall back to the highest downloaded number so nothing is hidden.
    int maxNum = 0;
    for (final DownloadedEpisode e in seasonEpisodes) {
      final int n = e.episodeNumber.round();
      if (n > maxNum) maxNum = n;
    }
    return maxNum;
  }

  Widget _episodeTile(
    BuildContext context,
    DownloadController controller,
    MediaItem media,
    DownloadedEpisode ep,
    List<DownloadedEpisode> moduleEpisodes,
    int effectiveContinued,
  ) {
    final bool complete = ep.isComplete;
    final String numberLabel = ep.displayNumber.isNotEmpty
        ? '${context.t('Episode')} ${ep.displayNumber}'
        : context.t('Episode');
    final EpisodeProgress? localProgress = _localProgress(ep);
    final bool watched = localProgress?.isWatched ?? false;
    final bool isContinue =
        complete &&
        effectiveContinued > 0 &&
        ep.episodeNumber.round() == effectiveContinued + 1;
    final String displayTitle = downloadedEpisodeDisplayTitle(ep);
    final String status = _statusLabel(context, ep, localProgress, isContinue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: _OfflineEpisodeTile(
        number: ep.episodeNumber,
        header: numberLabel,
        displayTitle: displayTitle,
        imageUrl: downloadedEpisodeImageUrl(ep, media: media),
        statusLabel: status,
        downloadProgress: complete ? 0 : ep.progressFraction,
        localProgress: localProgress,
        isEnabled: complete,
        isWatched: watched,
        isContinue: isContinue,
        onTap: complete ? () => _play(ep, moduleEpisodes) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: _tileActions(context, controller, ep),
        ),
      ),
    );
  }

  List<Widget> _tileActions(
    BuildContext context,
    DownloadController controller,
    DownloadedEpisode ep,
  ) {
    final List<Widget> actions = <Widget>[];
    switch (ep.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        actions.add(
          IconButton(
            icon: const Icon(Icons.pause_rounded),
            tooltip: context.t('Pause'),
            onPressed: () => controller.pauseResume(ep.id),
          ),
        );
      case DownloadStatus.paused:
        actions.add(
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: context.t('Resume'),
            onPressed: () => controller.pauseResume(ep.id),
          ),
        );
      case DownloadStatus.failed:
        actions.add(
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.t('Retry'),
            onPressed: () => controller.retry(ep.id),
          ),
        );
      case DownloadStatus.completed:
        break;
    }
    actions.add(
      IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        tooltip: context.t('Delete'),
        onPressed: () => controller.delete(ep.id),
      ),
    );
    return actions;
  }

  Widget _disabledEpisodeRow(BuildContext context, int number) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Opacity(
        opacity: 0.42,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadius.all(AppRadius.lg),
            border: Border.all(color: AppColors.border),
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
                      _OfflineEpisodeThumbFallback(number: number.toDouble()),
                      Center(
                        child: Icon(
                          Icons.lock_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${context.t('Episode')} $number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.t('Not downloaded'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(
    BuildContext context,
    DownloadedEpisode ep,
    EpisodeProgress? localProgress,
    bool isContinue,
  ) {
    switch (ep.status) {
      case DownloadStatus.completed:
        final List<String> parts = <String>[];
        final String playbackStatus = _playbackStatusLabel(
          context,
          localProgress,
          isContinue,
        );
        if (playbackStatus.isNotEmpty) parts.add(playbackStatus);
        if (ep.qualityLabel.isNotEmpty) parts.add(ep.qualityLabel);
        if (ep.totalBytes > 0) parts.add(_formatBytes(ep.totalBytes));
        return parts.isEmpty ? context.t('Downloaded') : parts.join(' · ');
      case DownloadStatus.downloading:
        if (ep.kind == DownloadKind.hls && ep.totalSegments > 0) {
          return '${context.t('Downloading')} ${ep.doneSegments}/${ep.totalSegments}';
        }
        return '${context.t('Downloading')} ${(ep.progressFraction * 100).round()}%';
      case DownloadStatus.queued:
        return context.t('Queued');
      case DownloadStatus.paused:
        return context.t('Paused');
      case DownloadStatus.failed:
        return ep.error ?? context.t('Failed');
    }
  }

  String _playbackStatusLabel(
    BuildContext context,
    EpisodeProgress? progress,
    bool isContinue,
  ) {
    if (isContinue) return context.t('Continue');
    if (progress?.isWatched == true) return context.t('Watched');
    if (progress?.isStarted == true && progress!.positionSeconds > 0) {
      return context.tf('Progress {minutes} min', <String, Object?>{
        'minutes': progress.positionSeconds ~/ 60,
      });
    }
    return '';
  }

  void _play(DownloadedEpisode ep, List<DownloadedEpisode> moduleEpisodes) {
    final String? rootPath = ref.read(downloadsProvider.notifier).rootPath;
    if (rootPath == null) return;
    final MediaPlaybackItem item = buildOfflinePlaybackItem(
      episode: ep,
      rootPath: rootPath,
      moduleEpisodes: moduleEpisodes,
    );
    unawaited(
      context.push(AppRoutes.watchPlay, extra: item).then((Object? result) {
        if (!mounted) return;
        _handlePlayerResult(result, ep, moduleEpisodes);
      }),
    );
  }

  void _handlePlayerResult(
    Object? result,
    DownloadedEpisode current,
    List<DownloadedEpisode> moduleEpisodes,
  ) {
    if (result is PlayerEpisodeSelectionResult) {
      final DownloadedEpisode? next = downloadedEpisodeByHref(
        result.episodeHref,
        moduleEpisodes,
      );
      if (next != null) {
        _play(next, moduleEpisodes);
        return;
      }
    }
    if (result is PlayerNextEpisodeResult) {
      final DownloadedEpisode? next = nextDownloadedEpisode(
        current,
        moduleEpisodes,
      );
      if (next != null) {
        _play(next, moduleEpisodes);
        return;
      }
    }
    setState(() {});
  }

  Future<void> _confirmDeleteTitle(DownloadController controller) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(context.t('Delete all')),
        content: Text(
          context.t('Remove all downloaded episodes for this title?'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await controller.deleteTitle(widget.mediaId);
    if (!mounted) return;
    goBackOrGo(context, AppRoutes.library);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    final int decimals = (size >= 100 || unit == 0) ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[unit]}';
  }
}

class _OfflineEpisodeTile extends StatelessWidget {
  const _OfflineEpisodeTile({
    required this.number,
    required this.header,
    required this.displayTitle,
    required this.imageUrl,
    required this.statusLabel,
    required this.downloadProgress,
    required this.localProgress,
    required this.isEnabled,
    required this.isWatched,
    required this.isContinue,
    required this.trailing,
    this.onTap,
  });

  final double number;
  final String header;
  final String displayTitle;
  final String imageUrl;
  final String statusLabel;
  final double downloadProgress;
  final EpisodeProgress? localProgress;
  final bool isEnabled;
  final bool isWatched;
  final bool isContinue;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool showDisplayTitle =
        displayTitle.isNotEmpty &&
        displayTitle.toLowerCase() != header.toLowerCase();
    final double playbackFraction = localProgress?.fraction ?? 0;
    final bool showPlaybackProgress =
        isEnabled && playbackFraction > 0.02 && playbackFraction < 0.99;
    final bool showDownloadProgress =
        !isEnabled && downloadProgress > 0 && downloadProgress < 1;

    return InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(color: AppColors.border),
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
                        ? _OfflineEpisodeThumbFallback(number: number)
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                _OfflineEpisodeThumbFallback(number: number),
                          ),
                    if (number != 0 && (isWatched || isContinue))
                      _OfflineWatchedBadge(isContinue: isContinue),
                    if (showPlaybackProgress || showDownloadProgress)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: showPlaybackProgress
                              ? playbackFraction
                              : downloadProgress,
                          minHeight: 3,
                          backgroundColor: Colors.black38,
                          color: scheme.primary,
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
                  if (showDisplayTitle) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (statusLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _OfflineWatchedBadge extends StatelessWidget {
  const _OfflineWatchedBadge({required this.isContinue});

  final bool isContinue;

  @override
  Widget build(BuildContext context) {
    final String text = isContinue
        ? context.t('Continue')
        : context.t('Watched');
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

class _OfflineEpisodeThumbFallback extends StatelessWidget {
  const _OfflineEpisodeThumbFallback({required this.number});

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

class _OfflineHero extends StatelessWidget {
  const _OfflineHero({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final String image = media.backdropUrl.isNotEmpty
        ? media.backdropUrl
        : media.posterUrl;
    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.xxl),
      child: SizedBox(
        height: 240,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (image.isEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: palette.posterFallbackGradient,
                ),
              )
            else
              CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
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
                onPressed: () => goBackOrGo(context, AppRoutes.library),
              ),
            ),
            Positioned(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.xl,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: AppRadius.all(AppRadius.lg),
                    child: SizedBox(
                      width: 92,
                      height: 138,
                      child: media.posterUrl.isEmpty
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: palette.posterFallbackGradient,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: media.posterUrl,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.85),
                            borderRadius: AppRadius.all(AppRadius.sm),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.download_done_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                context.t('Offline'),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          media.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
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
