import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Decode posters close to their painted size instead of retaining the full
/// CDN original for every offscreen title. Width-only resizing preserves ratio.
class PosterImage extends StatelessWidget {
  const PosterImage({
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    super.key,
  });
  final String imageUrl;
  final BoxFit fit;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final decodeWidth = width.isFinite && width > 0
          ? (width * MediaQuery.devicePixelRatioOf(context)).ceil()
          : null;
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        memCacheWidth: decodeWidth,
        placeholder: placeholder,
        errorWidget: errorWidget,
      );
    },
  );
}
