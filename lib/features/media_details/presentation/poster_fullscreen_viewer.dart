import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/localization/app_localizations.dart';
import 'artwork_export.dart';

const ValueKey<String> posterFullscreenViewerKey = ValueKey<String>(
  'poster-fullscreen-viewer',
);
const ValueKey<String> posterInteractiveViewerKey = ValueKey<String>(
  'poster-interactive-viewer',
);
const ValueKey<String> posterViewerCloseKey = ValueKey<String>(
  'poster-viewer-close',
);
const ValueKey<String> posterViewerDownloadKey = ValueKey<String>(
  'poster-viewer-download',
);

typedef PosterDownloadCallback = Future<void> Function(BuildContext context);

String maximumQualityArtworkUrl(String imageUrl) {
  final Uri? uri = Uri.tryParse(imageUrl.trim());
  if (uri == null) return imageUrl;

  final String host = uri.host.toLowerCase();
  final List<String> pathSegments = uri.pathSegments;

  if (RegExp(r'^s\d+\.anilist\.co$').hasMatch(host) &&
      pathSegments.length >= 7 &&
      pathSegments[0] == 'file' &&
      pathSegments[1] == 'anilistcdn' &&
      pathSegments[2] == 'media' &&
      pathSegments[4] == 'cover') {
    final String size = pathSegments[5].toLowerCase();
    if (size == 'large') return imageUrl;
    if (size != 'medium' && size != 'small') return imageUrl;

    return uri
        .replace(
          pathSegments: <String>[
            ...pathSegments.take(5),
            'large',
            ...pathSegments.skip(6),
          ],
        )
        .toString();
  }

  if (host != 'image.tmdb.org') return imageUrl;

  if (pathSegments.length < 4 ||
      pathSegments[0] != 't' ||
      pathSegments[1] != 'p') {
    return imageUrl;
  }

  final String size = pathSegments[2].toLowerCase();
  if (size == 'original') return imageUrl;
  if (!RegExp(r'^[wh]\d').hasMatch(size)) return imageUrl;

  return uri
      .replace(
        pathSegments: <String>[
          pathSegments[0],
          pathSegments[1],
          'original',
          ...pathSegments.skip(3),
        ],
      )
      .toString();
}

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
    filenameSuffix: 'poster',
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
    filenameSuffix: 'background',
  );
}

Future<void> _showNetworkImageFullscreenViewer(
  BuildContext context, {
  required String imageUrl,
  required String title,
  required String unavailableLabelKey,
  required String filenameSuffix,
}) {
  final String originalImageUrl = maximumQualityArtworkUrl(imageUrl);
  return showPosterFullscreenViewer(
    context,
    title: title,
    onDownload: (BuildContext dialogContext) => downloadArtworkImage(
      dialogContext,
      imageUrl: originalImageUrl,
      title: title,
      filenameSuffix: filenameSuffix,
    ),
    poster: CachedNetworkImage(
      imageUrl: originalImageUrl,
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
  PosterDownloadCallback? onDownload,
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
        ) => PosterFullscreenViewer(
          title: title,
          poster: poster,
          onDownload: onDownload,
        ),
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
    this.onDownload,
    super.key,
  });

  final String title;
  final Widget poster;
  final PosterDownloadCallback? onDownload;

  @override
  State<PosterFullscreenViewer> createState() => _PosterFullscreenViewerState();
}

class _PosterFullscreenViewerState extends State<PosterFullscreenViewer> {
  final TransformationController _transformationController =
      TransformationController();
  bool _downloading = false;

  void _resetView() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _download() async {
    final PosterDownloadCallback? callback = widget.onDownload;
    if (callback == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      await callback(context);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
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
                if (widget.onDownload != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      minimum: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _PosterViewerButton(
                          key: posterViewerDownloadKey,
                          tooltip: context.t('Download'),
                          icon: Icons.download_rounded,
                          busy: _downloading,
                          onPressed: _downloading ? null : _download,
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
    this.busy = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.66),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        color: Colors.white,
        disabledColor: Colors.white70,
        icon: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}
