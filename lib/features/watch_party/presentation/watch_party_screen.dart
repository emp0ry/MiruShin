import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../application/watch_party_controller.dart';
import '../domain/watch_party_models.dart';
import 'watch_party_permission_controls.dart';
import 'watch_party_status_text.dart';

/// Hub for the watch-party feature: start a room as host, join one as guest, or
/// view/leave the currently active party.
class WatchPartyScreen extends ConsumerWidget {
  const WatchPartyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WatchPartyRoomState party = ref.watch(watchPartyProvider);
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Watch with Friend')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: party.isActive
                ? _ActivePartyCard(party: party)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Icon(
                        Icons.groups_rounded,
                        size: 64,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Watch the same episode together, in sync.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Each device plays its own local stream. Only playback '
                        'control is shared. The host controls play, pause, seek, '
                        'speed and the episode/source.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: () =>
                            context.push(AppRoutes.watchPartyCreate),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create a room'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutes.watchPartyJoin),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Join a room'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ActivePartyCard extends ConsumerWidget {
  const _ActivePartyCard({required this.party});

  final WatchPartyRoomState party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Icon(
          party.isHost ? Icons.cast_connected_rounded : Icons.group_rounded,
          size: 56,
          color: colors.primary,
        ),
        const SizedBox(height: 16),
        Text(
          party.isHost ? 'You are the host' : 'You joined as a guest',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (party.roomCode != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Room ${party.roomCode}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              letterSpacing: 2,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        WatchPartyStatusText(party: party),
        const SizedBox(height: 20),
        WatchPartyPermissionControls(party: party),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => ref.read(watchPartyProvider.notifier).leave(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Leave party'),
        ),
      ],
    );
  }
}
