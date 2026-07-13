import 'dart:io';

import 'package:flutter/material.dart';

bool isDownloadedArtworkLocalUrl(String imageUrl) {
  return Uri.tryParse(imageUrl.trim())?.scheme == 'file';
}

Widget downloadedArtworkLocalImage({
  required String imageUrl,
  required BoxFit fit,
  required Widget fallback,
}) {
  final Uri? uri = Uri.tryParse(imageUrl.trim());
  if (uri == null || uri.scheme != 'file') return fallback;
  return Image.file(
    File.fromUri(uri),
    fit: fit,
    errorBuilder:
        (BuildContext context, Object error, StackTrace? stackTrace) =>
            fallback,
  );
}
