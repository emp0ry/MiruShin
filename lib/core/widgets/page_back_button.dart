import 'package:flutter/material.dart';

class PageBackButton extends StatelessWidget {
  const PageBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        hoverColor: Colors.white.withValues(alpha: .08),
        focusColor: Colors.white.withValues(alpha: .08),
        highlightColor: Colors.white.withValues(alpha: .10),
      ),
      icon: const Icon(
        Icons.arrow_back_rounded,
        shadows: <Shadow>[
          Shadow(color: Colors.black54, offset: Offset(0, 1), blurRadius: 6),
        ],
      ),
    );
  }
}
