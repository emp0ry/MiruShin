import 'dart:typed_data';

class DirectFrameDecodeRequest {
  const DirectFrameDecodeRequest({
    required this.input,
    required this.position,
    required this.sessionKey,
    this.headers = const <String, String>{},
    this.width = 240,
    this.reuseSession = false,
  });

  final String input;
  final Duration position;
  final String sessionKey;
  final Map<String, String> headers;
  final int width;
  final bool reuseSession;
}

class DirectFrame {
  const DirectFrame({
    required this.jpegBytes,
    required this.position,
    required this.width,
    required this.height,
    this.codedWidth = 0,
    this.codedHeight = 0,
    this.sampleAspectRatioNumerator = 1,
    this.sampleAspectRatioDenominator = 1,
    this.rotationDegrees = 0,
    this.displayAspectRatio = 0,
    this.sessionReused = false,
    this.nativeDecodeMicroseconds = 0,
    this.encodeMicroseconds = 0,
  });

  final Uint8List jpegBytes;
  final Duration position;
  final int width;
  final int height;
  final int codedWidth;
  final int codedHeight;
  final int sampleAspectRatioNumerator;
  final int sampleAspectRatioDenominator;
  final int rotationDegrees;
  final double displayAspectRatio;
  final bool sessionReused;
  final int nativeDecodeMicroseconds;
  final int encodeMicroseconds;
}

enum DirectFrameFailureKind {
  cancelled,
  openInput,
  streamInfo,
  noVideoTrack,
  unsupportedCodec,
  seek,
  noFrame,
  scale,
  unavailable,
  unknown,
}

class DirectFrameDecodeResult {
  const DirectFrameDecodeResult.success(this.frame) : failure = null;

  const DirectFrameDecodeResult.failure(this.failure) : frame = null;

  final DirectFrame? frame;
  final DirectFrameFailureKind? failure;

  bool get isSuccess => frame != null;
}

class ThumbnailDisplaySize {
  const ThumbnailDisplaySize({
    required this.width,
    required this.height,
    required this.displayAspectRatio,
  });

  final int width;
  final int height;
  final double displayAspectRatio;
}

/// Mirrors the native bridge's display-aspect calculation for deterministic
/// geometry tests and non-native platform adapters.
ThumbnailDisplaySize thumbnailDisplaySize({
  required int codedWidth,
  required int codedHeight,
  int sampleAspectRatioNumerator = 1,
  int sampleAspectRatioDenominator = 1,
  int rotationDegrees = 0,
  int targetWidth = 240,
}) {
  if (codedWidth <= 0 || codedHeight <= 0 || targetWidth <= 0) {
    throw ArgumentError('Thumbnail dimensions must be positive.');
  }
  final int sarNum = sampleAspectRatioNumerator > 0
      ? sampleAspectRatioNumerator
      : 1;
  final int sarDen = sampleAspectRatioDenominator > 0
      ? sampleAspectRatioDenominator
      : 1;
  double aspect = codedWidth * sarNum / (codedHeight * sarDen);
  final int rotation = ((rotationDegrees % 360) + 360) % 360;
  if (rotation == 90 || rotation == 270) aspect = 1 / aspect;
  if (!aspect.isFinite || aspect <= 0.01 || aspect > 100) {
    throw ArgumentError('Thumbnail display aspect is invalid.');
  }
  return ThumbnailDisplaySize(
    width: targetWidth,
    height: (targetWidth / aspect).round().clamp(1, 1440),
    displayAspectRatio: aspect,
  );
}

abstract interface class DirectFrameDecoder {
  bool get isSupported;

  Future<void> warm();

  Future<DirectFrameDecodeResult> decode(DirectFrameDecodeRequest request);

  void cancelPending();

  Future<void> dispose();
}
