import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/deep_links/mirushin_deep_link.dart';
import '../../../app/localization/app_localizations.dart';
import '../../../shared/models/media_item.dart';

class MediaLinksButton extends StatelessWidget {
  const MediaLinksButton({required this.item, super.key});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final MiruShinMediaDeepLink? link = mirushinMediaLink(
      internalId: item.id,
      mediaType: item.type,
      externalIds: item.externalIds,
    );
    if (link == null) return const SizedBox.shrink();

    return IconButton(
      key: const ValueKey<String>('details-links-action'),
      tooltip: context.t('Media links'),
      color: Colors.white,
      onPressed: () => _showMediaLinksDialog(context, link),
      icon: const Icon(Icons.link_rounded),
    );
  }
}

Future<void> _showMediaLinksDialog(
  BuildContext context,
  MiruShinMediaDeepLink link,
) async {
  final String providerLabel = switch (link.provider) {
    MiruShinMediaProvider.anilist => 'AniList link',
    MiruShinMediaProvider.tmdb => 'TMDB link',
  };
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(dialogContext.t('Media links')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              dialogContext.t(
                'Share the MiruShin link to open this title directly in the app.',
              ),
            ),
            const SizedBox(height: 16),
            _MediaLinkEntry(
              label: dialogContext.t(providerLabel),
              value: link.providerUri.toString(),
              icon: Icons.public_rounded,
            ),
            const SizedBox(height: 12),
            _MediaLinkEntry(
              label: dialogContext.t('MiruShin link'),
              value: link.webOpenUri.toString(),
              icon: Icons.link_rounded,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.t('Close')),
        ),
      ],
    ),
  );
}

class _MediaLinkEntry extends StatelessWidget {
  const _MediaLinkEntry({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: SelectableText(value),
        trailing: IconButton(
          tooltip: context.t('Copy link'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(context.t('Link copied'))));
          },
          icon: const Icon(Icons.copy_rounded),
        ),
      ),
    );
  }
}
