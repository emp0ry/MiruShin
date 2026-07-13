import 'package:flutter/material.dart';

bool isDownloadedArtworkLocalUrl(String imageUrl) => false;

Widget downloadedArtworkLocalImage({
  required String imageUrl,
  required BoxFit fit,
  required Widget fallback,
}) {
  return fallback;
}
