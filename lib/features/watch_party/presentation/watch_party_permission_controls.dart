import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../application/watch_party_controller.dart';
import '../domain/watch_party_models.dart';

class WatchPartyPermissionControls extends ConsumerWidget {
  const WatchPartyPermissionControls({super.key, required this.party});

  final WatchPartyRoomState party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!party.isActive) return const SizedBox.shrink();
    final ColorScheme colors = Theme.of(context).colorScheme;
    if (!party.isHost) {
      final List<Widget> chips = <Widget>[
        _PermissionChip(
          icon: Icons.play_arrow_rounded,
          label: context.t('Play / pause'),
          enabled: party.permissions.canControlPlayback,
        ),
        _PermissionChip(
          icon: Icons.fast_forward_rounded,
          label: context.t('Seek'),
          enabled: party.permissions.canSeek,
        ),
        _PermissionChip(
          icon: Icons.speed_rounded,
          label: context.t('Speed'),
          enabled: party.permissions.canChangeSpeed,
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.t('Your controls'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      );
    }

    final WatchPartyController controller = ref.read(
      watchPartyProvider.notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.t('Guest permissions'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.play_arrow_rounded),
          title: Text(context.t('Play / pause')),
          value: party.permissions.canControlPlayback,
          onChanged: controller.setGuestPlaybackControlAllowed,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fast_forward_rounded),
          title: Text(context.t('Seek')),
          value: party.permissions.canSeek,
          onChanged: controller.setGuestSeekAllowed,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.speed_rounded),
          title: Text(context.t('Speed')),
          value: party.permissions.canChangeSpeed,
          onChanged: controller.setGuestSpeedAllowed,
        ),
      ],
    );
  }
}

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        enabled ? icon : Icons.lock_outline_rounded,
        size: 16,
        color: enabled ? colors.primary : colors.onSurfaceVariant,
      ),
      label: Text(label),
      side: BorderSide(color: enabled ? colors.primary : colors.outlineVariant),
    );
  }
}
