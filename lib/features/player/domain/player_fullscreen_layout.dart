import 'package:flutter/widgets.dart';

/// Native macOS geometry is in points, matching Flutter logical pixels.
/// The video keeps the entire viewport; SafeArea-based controls use the cutout
/// insets. Taking the maximum avoids counting a system-provided inset twice.
class PlayerFullscreenLayout {
  const PlayerFullscreenLayout({
    required this.fullscreen,
    required this.edgeToEdge,
    this.safeInsets = EdgeInsets.zero,
  });

  final bool fullscreen;
  final bool edgeToEdge;
  final EdgeInsets safeInsets;

  static PlayerFullscreenLayout? fromNative(Object? value) {
    if (value is! Map || value['fullscreen'] is! bool) return null;
    final fullscreen = value['fullscreen'] as bool;
    final edge = fullscreen && value['edgeToEdge'] == true;
    double inset(String name) {
      final number = value[name];
      return number is num && number.isFinite && number > 0
          ? number.toDouble()
          : 0;
    }

    return PlayerFullscreenLayout(
      fullscreen: fullscreen,
      edgeToEdge: edge,
      safeInsets: edge
          ? EdgeInsets.fromLTRB(
              inset('left'),
              inset('top'),
              inset('right'),
              inset('bottom'),
            )
          : EdgeInsets.zero,
    );
  }

  MediaQueryData applyTo(MediaQueryData data) {
    if (!edgeToEdge) return data;
    EdgeInsets merge(EdgeInsets padding) => EdgeInsets.fromLTRB(
      padding.left > safeInsets.left ? padding.left : safeInsets.left,
      padding.top > safeInsets.top ? padding.top : safeInsets.top,
      padding.right > safeInsets.right ? padding.right : safeInsets.right,
      padding.bottom > safeInsets.bottom ? padding.bottom : safeInsets.bottom,
    );
    return data.copyWith(
      padding: merge(data.padding),
      viewPadding: merge(data.viewPadding),
    );
  }
}
