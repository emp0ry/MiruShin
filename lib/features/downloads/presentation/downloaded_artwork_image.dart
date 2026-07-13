import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'downloaded_artwork_local_image.dart';

class DownloadedArtworkImage extends StatelessWidget {
  const DownloadedArtworkImage({
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final String url = imageUrl.trim();
    if (url.isEmpty) return fallback;
    if (isDownloadedArtworkLocalUrl(url)) {
      return downloadedArtworkLocalImage(
        imageUrl: url,
        fit: fit,
        fallback: fallback,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      errorWidget: (BuildContext context, String url, Object error) => fallback,
    );
  }
}
