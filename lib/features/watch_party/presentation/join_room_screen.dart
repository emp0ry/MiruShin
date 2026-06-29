import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../application/watch_party_controller.dart';
import '../domain/watch_party_models.dart';
import 'watch_party_qr.dart';
import 'watch_party_status_text.dart';

/// Guest screen: enter a room code manually or scan the host's QR.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _scanning = false;
  bool _submitted = false;
  bool _closedAfterPairingStarts = false;

  // Only phones/tablets have a usable camera for the QR scanner.
  bool get _scannerSupported {
    final TargetPlatform platform = defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
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
    final String? parsed = decodeWatchPartyQr(code) ?? _normalize(code);
    if (parsed == null) return;
    setState(() {
      _scanning = false;
      _submitted = true;
    });
    ref.read(watchPartyProvider.notifier).joinRoom(parsed);
  }

  String? _normalize(String value) {
    final String cleaned = value.trim().toUpperCase();
    return cleaned.length == 6 ? cleaned : null;
  }

  void _onDetect(BarcodeCapture capture) {
    for (final Barcode barcode in capture.barcodes) {
      final String? code = decodeWatchPartyQr(barcode.rawValue);
      if (code != null) {
        _join(code);
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
      appBar: AppBar(title: const Text('Join a room')),
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
                      'Enter the 6-character room code from the host.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            letterSpacing: 8,
                            fontWeight: FontWeight.bold,
                          ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp('[A-Za-z0-9]'),
                        ),
                        UpperCaseFormatter(),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'ABC123',
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
                    label: const Text('Join'),
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
                        _scanning ? 'Enter code manually' : 'Scan QR',
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
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
