import 'package:flutter/widgets.dart';

import '../../engine/player_engine.dart';

/// Playback clock/buffer updates do not change video layout. The native
/// texture keeps presenting frames without rebuilding its geometry every tick.
class PlayerVideoSurface extends StatefulWidget {
  const PlayerVideoSurface({
    super.key,
    required this.controller,
    required this.stretchVertical,
    this.fillSurface = false,
  });

  final PlayerEngine? controller;
  final bool stretchVertical;
  final bool fillSurface;

  @override
  State<PlayerVideoSurface> createState() => _PlayerVideoSurfaceState();
}

typedef _VideoLayout = ({bool initialized, Size size, double aspectRatio});

class _PlayerVideoSurfaceState extends State<PlayerVideoSurface> {
  final ValueNotifier<_VideoLayout> _layout = ValueNotifier((
    initialized: false,
    size: Size.zero,
    aspectRatio: 16 / 9,
  ));

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_updateLayout);
    _updateLayout();
  }

  @override
  void didUpdateWidget(PlayerVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_updateLayout);
      widget.controller?.addListener(_updateLayout);
      _updateLayout();
    }
  }

  void _updateLayout() {
    final state = widget.controller?.value;
    _layout.value = (
      initialized: state?.isInitialized ?? false,
      size: state?.videoSize ?? Size.zero,
      aspectRatio: state == null || state.aspectRatio <= 0
          ? 16 / 9
          : state.aspectRatio,
    );
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_updateLayout);
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller;
    if (active == null) return const ColoredBox(color: Color(0xff000000));
    return ValueListenableBuilder<_VideoLayout>(
      valueListenable: _layout,
      child: active.buildVideoSurface(context),
      builder: (context, layout, videoSurface) {
        if (!layout.initialized) {
          return const ColoredBox(color: Color(0xff000000));
        }
        if (widget.fillSurface) return videoSurface!;
        if (!widget.stretchVertical) {
          return Center(
            child: AspectRatio(
              aspectRatio: layout.aspectRatio,
              child: videoSurface,
            ),
          );
        }
        final width = layout.size.width > 0 ? layout.size.width : 1920.0;
        final height = layout.size.height > 0
            ? layout.size.height
            : width / layout.aspectRatio;
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: width,
                height: height,
                child: videoSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}
