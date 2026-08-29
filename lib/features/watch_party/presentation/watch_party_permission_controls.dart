import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../application/watch_party_controller.dart';
import '../domain/watch_party_models.dart';
import '../domain/watch_party_qr.dart';

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
        _PermissionChip(
          icon: Icons.dns_rounded,
          label: context.t('Change stream'),
          enabled: party.permissions.canChangeStream,
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
    final String? roomCode = party.roomCode?.trim();
    final String? inviteUrl =
        party.inviteUrl ??
        (roomCode == null || roomCode.isEmpty
            ? null
            : encodeWatchPartyQr(roomCode));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (inviteUrl != null) ...<Widget>[
          OutlinedButton.icon(
            key: const ValueKey<String>('copy-watch-party-invite'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inviteUrl));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.t('Invite link copied'))),
              );
            },
            icon: const Icon(Icons.link_rounded),
            label: Text(context.t('Copy invite link')),
          ),
          const SizedBox(height: 20),
        ],
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
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.dns_rounded),
          title: Text(context.t('Change stream')),
          value: party.permissions.canChangeStream,
          onChanged: controller.setGuestStreamChangeAllowed,
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
