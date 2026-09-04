import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/cache/artwork_cache_manager.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/models/anilist_models.dart';
import '../../../shared/models/media_item.dart';
import '../../tracking/application/anilist_library_provider.dart';
import '../application/watch_order_provider.dart';
import '../domain/watch_order.dart';

class WatchOrderSection extends ConsumerStatefulWidget {
  const WatchOrderSection({required this.item, super.key});
  final MediaItem item;

  @override
  ConsumerState<WatchOrderSection> createState() => _WatchOrderSectionState();
}

class _WatchOrderSectionState extends ConsumerState<WatchOrderSection> {
  bool _mainOnly = false;
  int _visibleCount = 12;

  @override
  void didUpdateWidget(covariant WatchOrderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _mainOnly = false;
      _visibleCount = 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final malId = int.tryParse(item.externalIds['mal'] ?? '');
    if (!item.id.startsWith('anilist:') ||
        item.id.startsWith('anilist:manga:') ||
        item.externalIds['anilist_type'] == 'MANGA' ||
        item.type != MediaType.anime ||
        malId == null ||
        malId <= 0) {
      return const SizedBox.shrink();
    }
    final order = ref.watch(watchOrderProvider(malId));
    return order.when(
      loading: () =>
          _panel(context, [const LinearProgressIndicator(minHeight: 2)]),
      error: (error, stack) => _panel(context, [
        Text(context.t('Watch order could not be loaded.')),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(watchOrderProvider(malId)),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.t('Retry')),
        ),
      ]),
      data: (order) {
        if (order.entries.length < 2 && order.missingEntries == 0) {
          return const SizedBox.shrink();
        }
        final entries = order.entries
            .where((entry) => !_mainOnly || entry.isMainline)
            .toList();
        final progress = <int, AniListAnimeListEntry>{};
        for (final provider in [
          anilistAnimePreviewListProvider,
          anilistAnimeListProvider,
        ]) {
          final folders = ref
              .watch(provider)
              .maybeWhen(
                skipLoadingOnReload: true,
                data: (folders) => folders,
                orElse: () => const <AniListAnimeListFolder>[],
              );
          for (final folder in folders) {
            for (final entry in folder.entries) {
              final id = int.tryParse(
                entry.mediaItem.externalIds['anilist'] ?? '',
              );
              if (id != null) progress[id] = entry;
            }
          }
        }
        final palette = AppThemeExtension.of(context);
        return _panel(context, [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              FilterChip(
                label: Text(context.t('Main story only')),
                selected: _mainOnly,
                onSelected: (value) => setState(() {
                  _mainOnly = value;
                  _visibleCount = 12;
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.t(
              'Automatic order. Side stories may be watched separately.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMutedColor),
          ),
          if (order.missingEntries > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tf('Some franchise entries are unavailable ({count}).', {
                'count': order.missingEntries,
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (order.hasCycles) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.t(
                'Conflicting sequence data was resolved by release date.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (entries.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(context.t('No main story could be identified.')),
          ],
          for (var i = 0; i < entries.length && i < _visibleCount; i++) ...[
            const SizedBox(height: AppSpacing.sm),
            _WatchOrderTile(
              entry: entries[i],
              number: i + 1,
              current: entries[i].media.item.id == item.id,
              progress: progress[entries[i].media.id],
            ),
          ],
          if (entries.length > _visibleCount) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => setState(() => _visibleCount += 12),
              child: Text(context.t('Load more')),
            ),
          ],
        ]);
      },
    );
  }

  Widget _panel(BuildContext context, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xxl),
    child: GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Watch Order'),
          ...children,
        ],
      ),
    ),
  );
}

class _WatchOrderTile extends StatelessWidget {
  const _WatchOrderTile({
    required this.entry,
    required this.number,
    required this.current,
    this.progress,
  });
  final WatchOrderEntry entry;
  final int number;
  final bool current;
  final AniListAnimeListEntry? progress;

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final item = media.item;
    final palette = AppThemeExtension.of(context);
    final total = item.episodeCount;
    final metadata = <String>[
      context.t(entry.isMainline ? 'Main story' : 'Extra'),
      if (media.format.isNotEmpty) media.format.replaceAll('_', ' '),
      if (media.startDate.year != null) '${media.startDate.year}',
      if (current) context.t('Current title'),
    ];
    Widget placeholder() => ColoredBox(
      color: palette.surfaceSoftColor,
      child: const Center(child: Icon(Icons.movie_outlined, size: 24)),
    );
    return InkWell(
      key: ValueKey('watch-order-${media.id}'),
      borderRadius: AppRadius.all(AppRadius.sm),
      onTap: current
          ? null
          : () =>
                context.push(AppRoutes.mediaDetailsPath(item.id), extra: item),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text('$number', textAlign: TextAlign.center),
            ),
            const SizedBox(width: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.sm),
              child: SizedBox(
                width: 48,
                height: 68,
                child: item.posterUrl.isEmpty
                    ? placeholder()
                    : CachedNetworkImage(
                        imageUrl: item.posterUrl,
                        fit: BoxFit.cover,
                        cacheManager: miruShinArtworkCacheManager,
                        memCacheWidth: 144,
                        placeholder: (context, url) => placeholder(),
                        errorWidget: (context, url, error) => placeholder(),
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    metadata.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondaryColor,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${context.t(progress!.status.label)} · ${progress!.progress}${total == null ? '' : ' / $total'}',
                      key: ValueKey('watch-order-progress-${media.id}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
