import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/localization/app_localizations.dart';
import '../application/watch_party_connection_settings.dart';
import '../application/watch_party_controller.dart';
import '../data/relay_trust_store.dart';
import '../domain/watch_party_models.dart';
import '../domain/watch_party_qr.dart';
import 'watch_party_status_text.dart';

/// Guest screen: enter a room code manually or scan the host's QR.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key, this.invite});

  final WatchPartyInvite? invite;

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _scanning = false;
  bool _submitted = false;
  bool _closedAfterPairingStarts = false;
  bool _handlingInvite = false;

  // Only phones/tablets have a usable camera for the QR scanner.
  bool get _scannerSupported {
    final TargetPlatform platform = defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (widget.invite != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _joinInvite(widget.invite!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _join(String code) {
    final WatchPartyRoomState current = ref.read(watchPartyProvider);
    if (current.isGuest &&
        (current.status == WatchPartyConnectionStatus.signaling ||
            current.status == WatchPartyConnectionStatus.connecting ||
            current.status == WatchPartyConnectionStatus.connected ||
            current.status == WatchPartyConnectionStatus.reconnecting)) {
      return;
    }
    final WatchPartyInvite? invite = WatchPartyInvite.tryParse(code);
    if (invite != null && invite.isRelay) {
      _joinInvite(invite);
      return;
    }
    final String? parsed =
        invite?.roomId ?? decodeWatchPartyQr(code) ?? _normalize(code);
    if (parsed == null) return;
    setState(() {
      _scanning = false;
      _submitted = true;
    });
    ref.read(watchPartyProvider.notifier).joinRoom(parsed);
  }

  Future<void> _joinInvite(WatchPartyInvite invite) async {
    if (_handlingInvite) return;
    if (!invite.isRelay) {
      _join(invite.roomId);
      return;
    }
    _handlingInvite = true;
    try {
      final Uri relay;
      try {
        relay = WatchPartyRelayUrl.parse(invite.relayUrl.toString());
      } on FormatException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.t(error.message))));
        }
        return;
      }
      final RelayTrustStore trustStore = RelayTrustStore();
      final bool trusted = await trustStore.isTrusted(relay);
      bool remember = false;
      if (!trusted && mounted) {
        final bool? accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return AlertDialog(
                  title: Text(context.t('Custom relay')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.t(
                          'This Watch with Friends room uses a custom relay:',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        WatchPartyRelayUrl.origin(relay),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        context.t(
                          'Custom relays are operated by third parties and are not controlled by MiruShin. They can observe watch-party synchronization data. Video and audio are not sent through the relay.',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: remember,
                        onChanged: (bool? value) {
                          setDialogState(() => remember = value == true);
                        },
                        title: Text(context.t('Trust this exact relay origin')),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(context.t('Cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(context.t('Join')),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (accepted != true) return;
        if (remember) await trustStore.trust(relay);
      }
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _submitted = true;
      });
      await ref.read(watchPartyProvider.notifier).joinInvite(invite);
    } finally {
      _handlingInvite = false;
    }
  }

  String? _normalize(String value) {
    final String cleaned = value.trim().toUpperCase();
    return cleaned.length == 6 ? cleaned : null;
  }

  void _onDetect(BarcodeCapture capture) {
    for (final Barcode barcode in capture.barcodes) {
      final WatchPartyInvite? invite = WatchPartyInvite.tryParse(
        barcode.rawValue,
      );
      if (invite != null) {
        if (invite.isRelay) {
          _joinInvite(invite);
        } else {
          _join(invite.roomId);
        }
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final WatchPartyRoomState party = ref.watch(watchPartyProvider);
    if (!_closedAfterPairingStarts &&
        party.isGuest &&
        (party.status == WatchPartyConnectionStatus.connecting ||
            party.status == WatchPartyConnectionStatus.connected)) {
      _closedAfterPairingStarts = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
    }
    final bool joining =
        party.isGuest &&
        (party.status == WatchPartyConnectionStatus.signaling ||
            party.status == WatchPartyConnectionStatus.connecting ||
            party.status == WatchPartyConnectionStatus.connected ||
            party.status == WatchPartyConnectionStatus.reconnecting);

    return Scaffold(
      appBar: AppBar(title: Text(context.t('Join a room'))),
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
                  if (_scanning && _scannerSupported)
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: MobileScanner(onDetect: _onDetect),
                      ),
                    )
                  else ...<Widget>[
                    Text(
                      context.t(
                        'Enter the 6-character room code, or paste a relay invite link from the host.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 2048,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                      inputFormatters: <TextInputFormatter>[
                        _RoomOrInviteFormatter(),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'ABC123 or mirushin:///watch-party/…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: _join,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_submitted) WatchPartyStatusText(party: party),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: joining ? null : () => _join(_controller.text),
                    icon: const Icon(Icons.login_rounded),
                    label: Text(context.t('Join')),
                  ),
                  if (_scannerSupported) ...<Widget>[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _scanning = !_scanning),
                      icon: Icon(
                        _scanning
                            ? Icons.keyboard_rounded
                            : Icons.qr_code_scanner_rounded,
                      ),
                      label: Text(
                        _scanning
                            ? context.t('Enter code manually')
                            : context.t('Scan QR'),
                      ),
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

/// Forces typed room codes to uppercase as they are entered.
class _RoomOrInviteFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text = newValue.text;
    if (text.length <= 6 && RegExp(r'^[A-Za-z0-9]*$').hasMatch(text)) {
      return newValue.copyWith(text: text.toUpperCase());
    }
    return newValue;
  }
}
