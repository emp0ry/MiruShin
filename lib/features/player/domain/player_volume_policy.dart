import 'package:flutter/foundation.dart';

bool usesSystemVolumeOnly({
  required bool isWeb,
  required TargetPlatform platform,
  required bool isAndroidTv,
}) {
  if (isWeb || isAndroidTv) return false;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

double effectivePlayerOutputVolume({
  required double configuredVolume,
  required bool systemVolumeOnly,
}) {
  if (systemVolumeOnly) return 1;
  return configuredVolume.clamp(0.0, 1.0).toDouble();
}
