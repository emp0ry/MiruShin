import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/watch_party_controller.dart';
import '../domain/watch_party_models.dart';
import 'watch_party_permission_controls.dart';
import 'watch_party_qr.dart';
import 'watch_party_status_text.dart';

/// Host screen: creates a room, shows the code + QR, and waits for a guest.
class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  @override
  void initState() {
    super.initState();
    // Create the room once this screen mounts, unless one is already active.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final WatchPartyRoomState party = ref.read(watchPartyProvider);
      if (!party.isActive) {
        ref.read(watchPartyProvider.notifier).createRoom();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final WatchPartyRoomState party = ref.watch(watchPartyProvider);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? code = party.roomCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a room')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Share this code or QR with your friend.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  if (code == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...<Widget>[
                    Center(
                      child: SizedBox.square(
                        dimension: 232,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.75),
                              width: 1.2,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: colors.primary.withValues(alpha: 0.18),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: QrImageView(
                                data: encodeWatchPartyQr(code),
                                size: 200,
                                backgroundColor: Colors.white,
                                // Force black modules so the code is always visible,
                                // regardless of the app's light/dark theme.
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Colors.black,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Colors.black,
                                ),
                                errorStateBuilder:
                                    (BuildContext _, Object? _) =>
                                        const SizedBox(
                                          width: 200,
                                          height: 200,
                                          child: Center(
                                            child: Text(
                                              'QR unavailable',
                                              style: TextStyle(
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Room code copied')),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 24,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              code,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    letterSpacing: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.copy_rounded,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  WatchPartyStatusText(party: party),
                  if (party.isHost) ...<Widget>[
                    const SizedBox(height: 20),
                    WatchPartyPermissionControls(party: party),
                  ],
                  if (party.status == WatchPartyConnectionStatus.error) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(watchPartyProvider.notifier).createRoom(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Create new room'),
                    ),
                  ],
                  if (party.isConnected) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Connected! Open an episode and your friend will follow along.',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.primary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
