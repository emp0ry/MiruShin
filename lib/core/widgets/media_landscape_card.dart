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
import '../../shared/utils/media_status_formatter.dart';
import 'metadata_chip.dart';
import 'skeleton_box.dart';
import 'tv_focusable.dart';

class MediaLandscapeCard extends ConsumerWidget {
  const MediaLandscapeCard({
    required this.item,
    this.onTap,
    this.autofocus = false,
    super.key,
  });

  final MediaItem item;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogMode mode = ref.watch(catalogModeProvider);
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final String statusLabel = humanReadableMediaStatus(item.statusLabel);
    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: AppRadius.all(AppRadius.lg),
      interactPointer: false,
      child: InkWell(
        canRequestFocus: false,
        borderRadius: AppRadius.all(AppRadius.lg),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: AppRadius.all(AppRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (item.backdropUrl.isEmpty)
                  Container(
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
                    errorWidget:
                        (BuildContext context, String url, Object error) =>
                            Container(
                              decoration: BoxDecoration(
                                gradient: palette.posterFallbackGradient,
                              ),
                            ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.30),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: AppSpacing.lg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: <Widget>[
                          if (mode != CatalogMode.anilist)
                            MetadataChip(
                              label: context.t(item.type.labelKey),
                              onImage: true,
                            ),
                          if (statusLabel.isNotEmpty)
                            MetadataChip(label: statusLabel, onImage: true),
                          if (item.rating > 0 && item.rating <= 10)
                            MetadataChip(
                              icon: Icons.star_rounded,
                              label: item.rating.toStringAsFixed(1),
                              color: AppColors.accentAmber,
                              onImage: true,
                            ),
                        ],
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
}
