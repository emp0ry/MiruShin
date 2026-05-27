import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../features/catalog/application/catalog_mode.dart';
import '../../shared/models/media_item.dart';
import 'metadata_chip.dart';
import 'skeleton_box.dart';

class MediaPosterCard extends ConsumerStatefulWidget {
  const MediaPosterCard({
    required this.item,
    this.compact = false,
    this.watchProgress,
    this.statusBadgeLabel,
    this.onTap,
    super.key,
  });

  final MediaItem item;
  final bool compact;
  final double? watchProgress;
  final String? statusBadgeLabel;
  final VoidCallback? onTap;

  @override
  ConsumerState<MediaPosterCard> createState() => _MediaPosterCardState();
}

class _MediaPosterCardState extends ConsumerState<MediaPosterCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final MediaItem item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          scale: _hovered ? 1.025 : 1,
          child: InkWell(
            borderRadius: AppRadius.all(AppRadius.lg),
            onTap: widget.onTap,
            child: ClipRRect(
              borderRadius: AppRadius.all(AppRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (item.posterUrl.isEmpty)
                    _PosterFallback(title: item.title)
                  else
                    CachedNetworkImage(
                      imageUrl: item.posterUrl,
                      fit: BoxFit.cover,
                      placeholder: (BuildContext context, String url) =>
                          const SkeletonBox(),
                      errorWidget:
                          (BuildContext context, String url, Object error) =>
                              _PosterFallback(title: item.title),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.24),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                  if (widget.watchProgress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ProgressBar(progress: widget.watchProgress!),
                    ),
                  if (widget.statusBadgeLabel?.trim().isNotEmpty == true)
                    Positioned(
                      left: AppSpacing.sm,
                      top: AppSpacing.sm,
                      child: _PosterStatusBadge(
                        label: widget.statusBadgeLabel!.trim(),
                      ),
                    ),
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: widget.watchProgress != null
                        ? AppSpacing.md + 4
                        : AppSpacing.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        if (!widget.compact) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: <Widget>[
                              MetadataChip(
                                label: item.year.toString(),
                                onImage: true,
                              ),
                              if (item.rating > 0 && item.rating <= 10)
                                MetadataChip(
                                  icon: Icons.star_rounded,
                                  label: item.rating.toStringAsFixed(1),
                                  color: AppColors.accentAmber,
                                  onImage: true,
                                ),
                              if (mode != CatalogMode.anilist)
                                MetadataChip(
                                  label: context.t(item.type.labelKey),
                                  onImage: true,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterStatusBadge extends StatelessWidget {
  const _PosterStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: AppRadius.all(AppRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 4,
      child: Row(
        children: <Widget>[
          Flexible(
            flex: (progress * 1000).round(),
            child: Container(color: accent),
          ),
          Flexible(
            flex: ((1 - progress) * 1000).round(),
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    return Container(
      decoration: BoxDecoration(gradient: palette.posterFallbackGradient),
      padding: const EdgeInsets.all(AppSpacing.lg),
      alignment: Alignment.bottomLeft,
      child: Text(
        title,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white),
      ),
    );
  }
}
