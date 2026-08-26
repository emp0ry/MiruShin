import 'dart:typed_data';

class DirectFrameDecodeRequest {
  const DirectFrameDecodeRequest({
    required this.input,
    required this.position,
    this.headers = const <String, String>{},
    this.width = 240,
  });

  final String input;
  final Duration position;
  final Map<String, String> headers;
  final int width;
}

class DirectFrame {
  const DirectFrame({
    required this.jpegBytes,
    required this.position,
    required this.width,
    required this.height,
  });

  final Uint8List jpegBytes;
  final Duration position;
  final int width;
  final int height;
}

abstract interface class DirectFrameDecoder {
  bool get isSupported;

  Future<DirectFrame?> decode(DirectFrameDecodeRequest request);

  Future<void> dispose();
}
