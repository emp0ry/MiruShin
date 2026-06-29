import 'package:flutter/material.dart';

import '../domain/watch_party_models.dart';

/// A compact, colour-coded line describing the current connection status.
class WatchPartyStatusText extends StatelessWidget {
  const WatchPartyStatusText({super.key, required this.party});

  final WatchPartyRoomState party;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (String label, Color color) = switch (party.status) {
      WatchPartyConnectionStatus.idle => (
        'Not connected',
        colors.onSurfaceVariant,
      ),
      WatchPartyConnectionStatus.signaling => (
        'Waiting for the other device…',
        colors.onSurfaceVariant,
      ),
      WatchPartyConnectionStatus.connecting => (
        'Connecting…',
        colors.onSurfaceVariant,
      ),
      WatchPartyConnectionStatus.connected => ('Connected', colors.primary),
      WatchPartyConnectionStatus.reconnecting => (
        'Reconnecting…',
        colors.tertiary,
      ),
      WatchPartyConnectionStatus.closed => ('Disconnected', colors.error),
      WatchPartyConnectionStatus.error => (
        party.lastError ?? 'Something went wrong',
        colors.error,
      ),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (party.status == WatchPartyConnectionStatus.signaling ||
            party.status == WatchPartyConnectionStatus.connecting ||
            party.status == WatchPartyConnectionStatus.reconnecting)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              party.status == WatchPartyConnectionStatus.connected
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              size: 16,
              color: color,
            ),
          ),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
