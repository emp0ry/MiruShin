import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../shared/models/media_item.dart';
import '../../settings/presentation/settings_state.dart';
import '../application/anilist_favorite_provider.dart';

class AniListFavoriteButton extends ConsumerStatefulWidget {
  const AniListFavoriteButton({
    required this.item,
    this.onImage = false,
    super.key,
  });

  final MediaItem item;
  final bool onImage;

  @override
  ConsumerState<AniListFavoriteButton> createState() =>
      _AniListFavoriteButtonState();
}

class _AniListFavoriteButtonState extends ConsumerState<AniListFavoriteButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final int? mediaId = aniListMediaIdOf(widget.item);
    final String token = ref.watch(
      settingsProvider.select(
        (SettingsState settings) => settings.anilistAccessToken.trim(),
      ),
    );
    if (mediaId == null || token.isEmpty) return const SizedBox.shrink();

    final bool itemFavourite = aniListItemIsFavourite(widget.item);
    final bool? serverFavourite = ref
        .watch(anilistMediaFavoriteStatusProvider(mediaId))
        .maybeWhen(data: (bool? value) => value, orElse: () => null);
    final bool baseFavourite = serverFavourite ?? itemFavourite;
    final bool favourite =
        ref.watch(
          anilistFavoriteProvider.select(
            (Map<int, bool> overrides) => overrides[mediaId],
          ),
        ) ??
        baseFavourite;
    final Color iconColor = favourite
        ? Colors.redAccent.shade100
        : widget.onImage
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return IconButton(
      tooltip: context.t(favourite ? 'Remove favorite' : 'Add favorite'),
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await ref
                    .read(anilistFavoriteProvider.notifier)
                    .toggle(
                      mediaId: mediaId,
                      isManga: isAniListMangaItem(widget.item),
                      current: favourite,
                    );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.t('AniList favorite update failed'),
                      ),
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: iconColor,
              ),
            )
          : Icon(
              favourite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: iconColor,
            ),
    );
  }
}
