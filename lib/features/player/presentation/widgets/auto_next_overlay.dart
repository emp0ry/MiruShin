import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';

class AutoNextOverlay extends StatefulWidget {
  const AutoNextOverlay({
    required this.onProceed,
    required this.onCancel,
    required this.onExpire,
    required this.autoProceed,
    required this.showButton,
    required this.showCountdown,
    super.key,
  });

  /// The user chose to continue to the next episode.
  final VoidCallback onProceed;

  /// The user aborted an in-progress auto-advance (autoProceed mode only).
  final VoidCallback onCancel;

  /// The countdown ran out without the user acting. In button (non-autoProceed)
  /// mode this closes the player instead of looping the countdown.
  final VoidCallback onExpire;

  final bool autoProceed;
  final bool showButton;
  final bool showCountdown;

  @override
  State<AutoNextOverlay> createState() => _AutoNextOverlayState();
}

class _AutoNextOverlayState extends State<AutoNextOverlay> {
  static const int _countdownStart = 5;

  late int _seconds;
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant AutoNextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoProceed != widget.autoProceed ||
        oldWidget.showCountdown != widget.showCountdown) {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _seconds = _countdownStart;
    _expired = false;
    if (!widget.autoProceed && !widget.showCountdown) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _seconds -= 1;
        if (_seconds > 0) return;
        _timer?.cancel();
        if (_expired) return;
        _expired = true;
        // Auto-advance fires the proceed action; the manual button+countdown
        // mode closes the player so the overlay can't loop the countdown.
        if (widget.autoProceed) {
          widget.onProceed();
        } else {
          widget.onExpire();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool countdownDone = widget.showCountdown && _seconds <= 0;
    return Positioned(
      right: 24,
      bottom: 100,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!countdownDone) ...<Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.t('Next Episode'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    _statusLabel(context),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
            ],
            if (widget.showButton && !countdownDone)
              FilledButton(
                onPressed: () {
                  _timer?.cancel();
                  widget.onProceed();
                },
                child: Text(context.t('Next')),
              ),
            if (widget.autoProceed)
              TextButton(
                onPressed: () {
                  _timer?.cancel();
                  widget.onCancel();
                },
                child: Text(context.t('Cancel')),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context) {
    if (!widget.showCountdown) {
      return context.t('Ready to play next');
    }
    // Auto-advance plays the next episode when the countdown ends; the manual
    // button mode closes the player, so the label must say so.
    final String key = widget.autoProceed
        ? 'Playing in {seconds}s'
        : 'Closing in {seconds}s';
    return context.tf(key, <String, Object?>{'seconds': _seconds});
  }
}
