import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';

class AutoNextOverlay extends StatefulWidget {
  const AutoNextOverlay({
    required this.onProceed,
    required this.onCancel,
    required this.autoProceed,
    required this.showButton,
    required this.showCountdown,
    super.key,
  });

  final VoidCallback onProceed;
  final VoidCallback onCancel;
  final bool autoProceed;
  final bool showButton;
  final bool showCountdown;

  @override
  State<AutoNextOverlay> createState() => _AutoNextOverlayState();
}

class _AutoNextOverlayState extends State<AutoNextOverlay> {
  late int _seconds;
  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _seconds = 5;
    if (widget.autoProceed || widget.showCountdown) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _seconds -= 1;
          if (_seconds <= 0) {
            _timer?.cancel();
            if (widget.autoProceed) {
              widget.onProceed();
            } else if (!_dismissed && widget.showCountdown) {
              _dismissed = true;
              widget.onCancel();
            }
          }
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant AutoNextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoProceed != widget.autoProceed ||
        oldWidget.showCountdown != widget.showCountdown) {
      _timer?.cancel();
      _seconds = 5;
      _dismissed = false;
      if (widget.autoProceed || widget.showCountdown) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {
            _seconds -= 1;
            if (_seconds <= 0) {
              _timer?.cancel();
              if (widget.autoProceed) {
                widget.onProceed();
              } else if (!_dismissed && widget.showCountdown) {
                _dismissed = true;
                widget.onCancel();
              }
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            if (!widget.showCountdown || _seconds > 0) ...<Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    context.t('Next Episode'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (!widget.showCountdown)
                    Text(
                      context.t('Ready to play next'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    Text(
                      context.tf('Playing in {seconds}s', <String, Object?>{
                        'seconds': _seconds,
                      }),
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
            if (widget.showButton && (!widget.showCountdown || _seconds > 0))
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
}
