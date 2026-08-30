import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/localization/app_localizations.dart';

const ValueKey<String> posterFullscreenViewerKey = ValueKey<String>(
  'poster-fullscreen-viewer',
);
const ValueKey<String> posterInteractiveViewerKey = ValueKey<String>(
  'poster-interactive-viewer',
);
const ValueKey<String> posterViewerCloseKey = ValueKey<String>(
  'poster-viewer-close',
);

Future<void> showNetworkPosterFullscreenViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  return _showNetworkImageFullscreenViewer(
    context,
    imageUrl: imageUrl,
    title: title,
    unavailableLabelKey: 'Poster unavailable',
  );
}

Future<void> showNetworkBackdropFullscreenViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
}) {
  return _showNetworkImageFullscreenViewer(
    context,
    imageUrl: imageUrl,
    title: title,
    unavailableLabelKey: 'Background image unavailable',
  );
}

Future<void> _showNetworkImageFullscreenViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String unavailableLabelKey,
}) {
  return showPosterFullscreenViewer(
    context,
    title: title,
    poster: CachedNetworkImage(
      imageUrl: imageUrl,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      placeholder: (BuildContext context, String url) =>
          const Center(child: CircularProgressIndicator.adaptive()),
      errorWidget: (BuildContext context, String url, Object error) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.broken_image_outlined, color: Colors.white70),
            const SizedBox(height: 8),
            Text(
              context.t(unavailableLabelKey),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showPosterFullscreenViewer(
  BuildContext context, {
  required String title,
  required Widget poster,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder:
        (
          BuildContext dialogContext,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => PosterFullscreenViewer(title: title, poster: poster),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) => FadeTransition(opacity: animation, child: child),
  );
}

class PosterFullscreenViewer extends StatefulWidget {
  const PosterFullscreenViewer({
    required this.title,
    required this.poster,
    super.key,
  });

  final String title;
  final Widget poster;

  @override
  State<PosterFullscreenViewer> createState() => _PosterFullscreenViewerState();
}

class _PosterFullscreenViewerState extends State<PosterFullscreenViewer> {
  final TransformationController _transformationController =
      TransformationController();

  void _resetView() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: SizedBox.expand(
          key: posterFullscreenViewerKey,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  onDoubleTap: _resetView,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: InteractiveViewer(
                      key: posterInteractiveViewerKey,
                      transformationController: _transformationController,
                      minScale: 1,
                      maxScale: 6,
                      scaleFactor: 180,
                      trackpadScrollCausesScale: true,
                      child: Semantics(
                        image: true,
                        label: widget.title,
                        child: SizedBox.expand(child: widget.poster),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _PosterViewerButton(
                        key: posterViewerCloseKey,
                        tooltip: context.t('Close'),
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterViewerButton extends StatelessWidget {
  const _PosterViewerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.66),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        color: Colors.white,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}
