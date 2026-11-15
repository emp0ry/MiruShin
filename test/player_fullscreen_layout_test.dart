import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/domain/player_fullscreen_layout.dart';

void main() {
  test(
    'camera insets protect controls without reducing the video viewport',
    () {
      final layout = PlayerFullscreenLayout.fromNative({
        'fullscreen': true,
        'edgeToEdge': true,
        'top': 38.0,
      })!;
      const data = MediaQueryData(
        size: Size(1512, 982),
        devicePixelRatio: 2,
        padding: EdgeInsets.only(top: 38),
        viewPadding: EdgeInsets.only(top: 38),
      );
      final adjusted = layout.applyTo(data);
      expect(adjusted.size, data.size);
      expect(adjusted.devicePixelRatio, 2);
      expect(
        adjusted.padding.top,
        38,
        reason: 'Do not double the cutout inset',
      );
      expect(adjusted.viewPadding.top, 38);
    },
  );

  test('standard fullscreen, exit, and external displays keep zero cutout', () {
    for (final fullscreen in [false, true]) {
      final layout = PlayerFullscreenLayout.fromNative({
        'fullscreen': fullscreen,
        'edgeToEdge': false,
        'top': 38.0,
      })!;
      expect(layout.safeInsets, EdgeInsets.zero);
      const data = MediaQueryData(size: Size(1920, 1080));
      expect(identical(layout.applyTo(data), data), isTrue);
    }
    final external = PlayerFullscreenLayout.fromNative({
      'fullscreen': true,
      'edgeToEdge': true,
    })!;
    expect(external.safeInsets, EdgeInsets.zero);
  });

  test('malformed geometry cannot create invalid safe-area padding', () {
    expect(PlayerFullscreenLayout.fromNative(null), isNull);
    expect(PlayerFullscreenLayout.fromNative({'fullscreen': 'true'}), isNull);
    final layout = PlayerFullscreenLayout.fromNative({
      'fullscreen': true,
      'edgeToEdge': true,
      'top': double.nan,
      'left': -2.0,
      'bottom': double.infinity,
      'right': 8,
    })!;
    expect(layout.safeInsets, const EdgeInsets.only(right: 8));
  });
}
