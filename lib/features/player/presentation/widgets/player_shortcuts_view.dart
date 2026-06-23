import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';

/// A modern, responsive reference of the player's keyboard shortcuts and touch
/// gestures, rendered as a visual keyboard (key-caps annotated with their
/// action). Built to read well on phones (touch), TV (10-foot, focusable close
/// button supplied by the host sheet) and desktop. Shown from player settings.
class PlayerShortcutsView extends StatelessWidget {
  const PlayerShortcutsView({required this.seekSeconds, super.key});

  /// The configured seek step, surfaced on the ←/→ keys (defaults to 10s).
  final int seekSeconds;

  @override
  Widget build(BuildContext context) {
    final int step = seekSeconds <= 0 ? 10 : seekSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _sectionHeader(context, Icons.keyboard_rounded, 'Keyboard'),
        const SizedBox(height: 14),
        // Space bar — the headline action.
        Center(
          child: _LabeledKey(
            glyph: 'Space',
            minWidth: 188,
            label: context.t('Play / Pause'),
            hint: '${context.t('Speed up')} · ${context.t('Hold')}',
          ),
        ),
        const SizedBox(height: 18),
        // Arrow cluster laid out like a real keyboard d-pad.
        Center(child: _LabeledKey(glyph: '↑', label: context.t('Volume up'))),
        const SizedBox(height: 10),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _LabeledKey(glyph: '←', label: '−${step}s'),
              const SizedBox(width: 10),
              _LabeledKey(glyph: '↓', label: context.t('Volume down')),
              const SizedBox(width: 10),
              _LabeledKey(glyph: '→', label: '+${step}s'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Letter / Esc keys reflow on narrow screens.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 16,
          children: <Widget>[
            _LabeledKey(glyph: 'F', label: context.t('Fullscreen')),
            _LabeledKey(glyph: 'M', label: context.t('Mute')),
            _LabeledKey(glyph: 'S', label: context.t('Subtitles')),
            _LabeledKey(glyph: 'E', label: context.t('Episodes')),
            _LabeledKey(glyph: 'Q', label: context.t('Quality')),
            _LabeledKey(glyph: 'Esc', label: context.t('Back')),
          ],
        ),
        const SizedBox(height: 26),
        _sectionHeader(context, Icons.touch_app_rounded, 'Touch gestures'),
        const SizedBox(height: 8),
        _GestureRow(
          icon: Icons.touch_app_rounded,
          gesture: context.t('Tap'),
          action: context.t('Show controls'),
        ),
        _GestureRow(
          icon: Icons.keyboard_double_arrow_right_rounded,
          gesture: context.t('Double-tap edges'),
          action: '${context.t('Seek')} ±${step}s',
        ),
        _GestureRow(
          icon: Icons.fast_forward_rounded,
          gesture: context.t('Long-press'),
          action: context.t('Speed up'),
        ),
        _GestureRow(
          icon: Icons.swap_vert_rounded,
          gesture: context.t('Vertical swipe'),
          action: context.t('Volume'),
        ),
        _GestureRow(
          icon: Icons.swap_horiz_rounded,
          gesture: context.t('Horizontal swipe'),
          action: context.t('Seek'),
        ),
        _GestureRow(
          icon: Icons.pinch_rounded,
          gesture: context.t('Pinch'),
          action: context.t('Zoom'),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, IconData icon, String key) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          context.t(key).toUpperCase(),
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

/// A single key-cap with its action label (and optional hold/hint) beneath it.
class _LabeledKey extends StatelessWidget {
  const _LabeledKey({
    required this.glyph,
    required this.label,
    this.hint,
    this.minWidth = 46,
  });

  final String glyph;
  final String label;
  final String? hint;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // Cap the cell width so long labels wrap to a second line and the arrow
    // cluster stays aligned; the wide Space key needs a correspondingly wider
    // ceiling (must stay >= minWidth to avoid an invalid constraint).
    final double maxCellWidth = minWidth < 100 ? 120 : minWidth + 40;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth + 24, maxWidth: maxCellWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _KeyCap(glyph: glyph, minWidth: minWidth),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The raised key-cap visual. Sizes to its glyph with a minimum width so single
/// letters, "Esc" and the "Space" bar all share one consistent look.
class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.glyph, this.minWidth = 46});

  final String glyph;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      constraints: BoxConstraints(minWidth: minWidth),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            scheme.surfaceContainerHighest,
            scheme.surfaceContainerHigh,
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: <BoxShadow>[
          // Hard bottom edge gives the cap its depth.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            offset: const Offset(0, 2),
          ),
          // Soft drop shadow lifts it off the sheet.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            offset: const Offset(0, 3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        glyph,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// A touch-gesture row: icon chip · gesture name · resulting action.
class _GestureRow extends StatelessWidget {
  const _GestureRow({
    required this.icon,
    required this.gesture,
    required this.action,
  });

  final IconData icon;
  final String gesture;
  final String action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(icon, size: 19, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              gesture,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              action,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
