import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../core/cache/artwork_cache_manager.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/models/media_item.dart';
import '../application/fanart_gallery_provider.dart';
import '../domain/fanart_gallery.dart';

const ValueKey<String> fanartGallerySectionKey = ValueKey<String>(
  'fanart-gallery-section',
);
const ValueKey<String> fanartGalleryViewerKey = ValueKey<String>(
  'fanart-gallery-viewer',
);
const ValueKey<String> fanartGalleryCounterKey = ValueKey<String>(
  'fanart-gallery-counter',
);

class FanartGallerySection extends ConsumerWidget {
  const FanartGallerySection({required this.item, super.key});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FanartGallery? gallery = ref
        .watch(fanartGalleryProvider(FanartGalleryRequest(item)))
        .maybeWhen(data: (FanartGallery value) => value, orElse: () => null);
    if (gallery == null || gallery.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: FanartGalleryContent(gallery: gallery, mediaTitle: item.title),
    );
  }
}

class FanartGalleryContent extends StatelessWidget {
  const FanartGalleryContent({
    required this.gallery,
    required this.mediaTitle,
    super.key,
  });

  final FanartGallery gallery;
  final String mediaTitle;

  @override
  Widget build(BuildContext context) {
    if (gallery.isEmpty) return const SizedBox.shrink();
    final List<FanartBackground> all = gallery.allBackgrounds;
    return GlassCard(
      key: fanartGallerySectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Gallery'),
          _FanartGalleryGroup(
            title: 'Backgrounds',
            showTitle: false,
            images: all,
            allImages: all,
            mediaTitle: mediaTitle,
          ),
        ],
      ),
    );
  }
}

class _FanartGalleryGroup extends StatelessWidget {
  const _FanartGalleryGroup({
    required this.title,
    required this.images,
    required this.allImages,
    required this.mediaTitle,
    this.showTitle = true,
  });

  final String title;
  final List<FanartBackground> images;
  final List<FanartBackground> allImages;
  final String mediaTitle;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cardWidth = switch (constraints.maxWidth) {
          < 420 => (constraints.maxWidth * 0.82).clamp(210.0, 280.0),
          < 760 => (constraints.maxWidth * 0.60).clamp(240.0, 300.0),
          < 1100 => 290,
          _ => 320,
        };
        final double cardHeight = cardWidth * 9 / 16;
        return Column(
          key: ValueKey<String>('fanart-gallery-group-$title'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (showTitle) ...<Widget>[
              Text(
                context.t(title),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              height: cardHeight,
              child: ScrollConfiguration(
                behavior: const _GalleryScrollBehavior(),
                child: ListView.separated(
                  key: ValueKey<String>('fanart-gallery-row-$title'),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: images.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (BuildContext context, int index) {
                    final FanartBackground image = images[index];
                    return SizedBox(
                      width: cardWidth,
                      child: _FanartGalleryCard(
                        image: image,
                        mediaTitle: mediaTitle,
                        onTap: () {
                          showFanartGalleryViewer(
                            context,
                            images: allImages,
                            initialIndex: allImages.indexOf(image),
                            mediaTitle: mediaTitle,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FanartGalleryCard extends StatelessWidget {
  const _FanartGalleryCard({
    required this.image,
    required this.mediaTitle,
    required this.onTap,
  });

  final FanartBackground image;
  final String mediaTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeExtension palette = AppThemeExtension.of(context);
    final String semanticLabel = '$mediaTitle ${context.t('Backgrounds')}';
    return Semantics(
      button: true,
      image: true,
      label: semanticLabel,
      child: Material(
        color: palette.surfaceColor,
        borderRadius: AppRadius.all(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('fanart-gallery-image-${image.id}'),
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(color: palette.borderColor),
              borderRadius: AppRadius.all(AppRadius.md),
            ),
            child: CachedNetworkImage(
              imageUrl: image.url,
              fit: BoxFit.cover,
              memCacheWidth: 480,
              maxWidthDiskCache: 480,
              imageBuilder: (BuildContext context, ImageProvider provider) {
                _preloadOriginalArtwork(context, image.url);
                return Image(image: provider, fit: BoxFit.cover);
              },
              placeholder: (_, _) => const ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, _, _) => const ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryScrollBehavior extends MaterialScrollBehavior {
  const _GalleryScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

Future<void> showFanartGalleryViewer(
  BuildContext context, {
  required List<FanartBackground> images,
  required int initialIndex,
  required String mediaTitle,
}) {
  if (images.isEmpty) return Future<void>.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => FanartGalleryViewer(
          images: images,
          initialIndex: initialIndex,
          mediaTitle: mediaTitle,
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

class FanartGalleryViewer extends StatefulWidget {
  const FanartGalleryViewer({
    required this.images,
    required this.initialIndex,
    required this.mediaTitle,
    super.key,
  });

  final List<FanartBackground> images;
  final int initialIndex;
  final String mediaTitle;

  @override
  State<FanartGalleryViewer> createState() => _FanartGalleryViewerState();
}

class _FanartGalleryViewerState extends State<FanartGalleryViewer> {
  final TransformationController _transformationController =
      TransformationController();
  late int _index;
  int _activePointers = 0;
  double _swipeDistance = 0;
  bool _cancelSwipe = false;
  DateTime? _lastPointerNavigation;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
  }

  @override
  void dispose() {
    _discardOriginalArtwork(widget.images);
    _transformationController.dispose();
    super.dispose();
  }

  bool get _canGoBack => _index > 0;
  bool get _canGoForward => _index + 1 < widget.images.length;
  double get _scale => _transformationController.value.getMaxScaleOnAxis();

  void _go(int delta) {
    final int next = (_index + delta).clamp(0, widget.images.length - 1);
    if (next == _index) return;
    setState(() {
      _index = next;
      _transformationController.value = Matrix4.identity();
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers += 1;
    if (_activePointers == 1) {
      _swipeDistance = 0;
      _cancelSwipe = false;
    } else {
      _cancelSwipe = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointers == 1 && !_cancelSwipe && _scale <= 1.01) {
      _swipeDistance += event.delta.dx;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final bool shouldNavigate =
        _activePointers == 1 && !_cancelSwipe && _swipeDistance.abs() >= 64;
    final double distance = _swipeDistance;
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (shouldNavigate) _go(distance < 0 ? 1 : -1);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    _cancelSwipe = true;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _scale > 1.01) return;
    if (event.scrollDelta.dx.abs() <= event.scrollDelta.dy.abs() ||
        event.scrollDelta.dx.abs() < 12) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastPointerNavigation
            ?.add(const Duration(milliseconds: 300))
            .isAfter(now) ??
        false) {
      return;
    }
    _lastPointerNavigation = now;
    _go(event.scrollDelta.dx > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final FanartBackground image = widget.images[_index];
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: SizedBox.expand(
          key: fanartGalleryViewerKey,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  onPointerSignal: _onPointerSignal,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    onDoubleTap: () =>
                        _transformationController.value = Matrix4.identity(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: InteractiveViewer(
                        key: ValueKey<String>(
                          'fanart-gallery-interactive-${image.id}',
                        ),
                        transformationController: _transformationController,
                        minScale: 1,
                        maxScale: 6,
                        scaleFactor: 180,
                        trackpadScrollCausesScale: true,
                        child: Semantics(
                          image: true,
                          label: widget.mediaTitle,
                          child: SizedBox.expand(
                            child: Image.network(
                              image.url,
                              key: ValueKey<String>(
                                'fanart-gallery-original-${image.id}',
                              ),
                              fit: BoxFit.contain,
                              loadingBuilder:
                                  (
                                    BuildContext context,
                                    Widget child,
                                    ImageChunkEvent? progress,
                                  ) => progress == null
                                  ? child
                                  : const Center(
                                      child:
                                          CircularProgressIndicator.adaptive(),
                                    ),
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ),
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
                      child: _GalleryViewerButton(
                        tooltip: context.t('Close'),
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
                if (_canGoBack)
                  Positioned(
                    left: 12,
                    top: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Center(
                        child: _GalleryViewerButton(
                          key: const ValueKey<String>(
                            'fanart-gallery-previous',
                          ),
                          tooltip: context.t('Previous'),
                          icon: Icons.chevron_left_rounded,
                          onPressed: () => _go(-1),
                        ),
                      ),
                    ),
                  ),
                if (_canGoForward)
                  Positioned(
                    right: 12,
                    top: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Center(
                        child: _GalleryViewerButton(
                          key: const ValueKey<String>('fanart-gallery-next'),
                          tooltip: context.t('Next'),
                          icon: Icons.chevron_right_rounded,
                          onPressed: () => _go(1),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        '${_index + 1}/${widget.images.length}',
                        key: fanartGalleryCounterKey,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                          shadows: <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
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

final Map<String, Future<void>> _originalArtworkPrefetches =
    <String, Future<void>>{};

void _preloadOriginalArtwork(BuildContext context, String url) {
  if (url.isEmpty || _originalArtworkPrefetches.containsKey(url)) return;
  final Future<void> request = () async {
    try {
      await precacheImage(
        NetworkImage(url),
        context,
        onError: (Object error, StackTrace? stackTrace) {},
      );
    } catch (_) {
      // Fullscreen loading remains the fallback when prefetching is unavailable.
    }
  }();
  _originalArtworkPrefetches[url] = request;
  unawaited(
    request.whenComplete(() {
      _originalArtworkPrefetches.remove(url);
    }),
  );
}

void _discardOriginalArtwork(Iterable<FanartBackground> images) {
  for (final FanartBackground image in images) {
    final String url = image.url;
    if (url.isEmpty) continue;
    final Future<void>? pending = _originalArtworkPrefetches.remove(url);
    final NetworkImage provider = NetworkImage(url);
    unawaited(() async {
      try {
        await miruShinArtworkCacheManager.removeFile(url);
      } catch (_) {}
      try {
        await provider.evict();
      } catch (_) {}
      if (pending != null) {
        await pending;
        try {
          await provider.evict();
        } catch (_) {}
        try {
          await miruShinArtworkCacheManager.removeFile(url);
        } catch (_) {}
      }
    }());
  }
}

class _GalleryViewerButton extends StatelessWidget {
  const _GalleryViewerButton({
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
