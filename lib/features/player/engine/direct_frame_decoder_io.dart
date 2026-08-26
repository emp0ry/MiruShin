import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

import 'direct_frame_decoder.dart';

class NativeDirectFrameDecoder implements DirectFrameDecoder {
  NativeDirectFrameDecoder() : _supported = _nativeLibraryAvailable();

  final bool _supported;
  bool _disposed = false;

  @override
  bool get isSupported => _supported && !_disposed;

  @override
  Future<DirectFrame?> decode(DirectFrameDecodeRequest request) async {
    if (!isSupported) return null;
    final Map<String, Object>? result = await Isolate.run(
      () => _decodeOnWorker(<String, Object>{
        'input': request.input,
        'headers': _serializeHeaders(request.headers),
        'positionMs': request.position.inMilliseconds,
        'width': request.width,
      }),
    );
    if (_disposed || result == null) return null;
    return DirectFrame(
      jpegBytes: result['bytes']! as Uint8List,
      position: Duration(milliseconds: result['positionMs']! as int),
      width: result['width']! as int,
      height: result['height']! as int,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

typedef _DecodeNative =
    Int32 Function(
      Pointer<Utf8> input,
      Pointer<Utf8> headers,
      Int64 targetMs,
      Int32 targetWidth,
      Pointer<Pointer<Uint8>> rgba,
      Pointer<Int32> rgbaLength,
      Pointer<Int32> width,
      Pointer<Int32> height,
      Pointer<Int64> decodedMs,
      Pointer<Int8> error,
      Int32 errorCapacity,
    );
typedef _DecodeDart =
    int Function(
      Pointer<Utf8> input,
      Pointer<Utf8> headers,
      int targetMs,
      int targetWidth,
      Pointer<Pointer<Uint8>> rgba,
      Pointer<Int32> rgbaLength,
      Pointer<Int32> width,
      Pointer<Int32> height,
      Pointer<Int64> decodedMs,
      Pointer<Int8> error,
      int errorCapacity,
    );
typedef _FreeNative = Void Function(Pointer<Uint8> data);
typedef _FreeDart = void Function(Pointer<Uint8> data);

bool _nativeLibraryAvailable() {
  if (!(Platform.isWindows ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS)) {
    return false;
  }
  try {
    final DynamicLibrary library = _openLibrary();
    library.lookup<NativeFunction<_FreeNative>>('mirushin_seek_thumbnail_free');
    return true;
  } on Object {
    return false;
  }
}

DynamicLibrary _openLibrary() {
  if (Platform.isWindows) {
    return DynamicLibrary.open('mirushin_seek_thumbnail.dll');
  }
  if (Platform.isLinux || Platform.isAndroid) {
    return DynamicLibrary.open('libmirushin_seek_thumbnail.so');
  }
  return DynamicLibrary.process();
}

Map<String, Object>? _decodeOnWorker(Map<String, Object> message) {
  final DynamicLibrary library = _openLibrary();
  final _DecodeDart decode = library
      .lookup<NativeFunction<_DecodeNative>>('mirushin_seek_thumbnail_decode')
      .asFunction<_DecodeDart>();
  final _FreeDart release = library
      .lookup<NativeFunction<_FreeNative>>('mirushin_seek_thumbnail_free')
      .asFunction<_FreeDart>();

  final Pointer<Utf8> input = (message['input']! as String).toNativeUtf8();
  final Pointer<Utf8> headers = (message['headers']! as String).toNativeUtf8();
  final Pointer<Pointer<Uint8>> rgba = calloc<Pointer<Uint8>>();
  final Pointer<Int32> rgbaLength = calloc<Int32>();
  final Pointer<Int32> width = calloc<Int32>();
  final Pointer<Int32> height = calloc<Int32>();
  final Pointer<Int64> decodedMs = calloc<Int64>();
  final Pointer<Int8> error = calloc<Int8>(512);
  Pointer<Uint8> nativeBytes = nullptr;
  try {
    final int status = decode(
      input,
      headers,
      message['positionMs']! as int,
      message['width']! as int,
      rgba,
      rgbaLength,
      width,
      height,
      decodedMs,
      error,
      512,
    );
    nativeBytes = rgba.value;
    if (status != 0 || nativeBytes == nullptr || rgbaLength.value <= 0) {
      return null;
    }
    final Uint8List pixels = Uint8List.fromList(
      nativeBytes.asTypedList(rgbaLength.value),
    );
    final img.Image image = img.Image.fromBytes(
      width: width.value,
      height: height.value,
      bytes: pixels.buffer,
      numChannels: 4,
      rowStride: width.value * 4,
      order: img.ChannelOrder.rgba,
    );
    return <String, Object>{
      'bytes': Uint8List.fromList(img.encodeJpg(image, quality: 76)),
      'width': width.value,
      'height': height.value,
      'positionMs': decodedMs.value >= 0
          ? decodedMs.value
          : message['positionMs']! as int,
    };
  } finally {
    if (nativeBytes != nullptr) release(nativeBytes);
    calloc.free(input);
    calloc.free(headers);
    calloc.free(rgba);
    calloc.free(rgbaLength);
    calloc.free(width);
    calloc.free(height);
    calloc.free(decodedMs);
    calloc.free(error);
  }
}

String _serializeHeaders(Map<String, String> headers) {
  final StringBuffer buffer = StringBuffer();
  for (final MapEntry<String, String> entry in headers.entries) {
    if (entry.key.contains(RegExp(r'[\r\n:]')) ||
        entry.value.contains(RegExp(r'[\r\n]'))) {
      continue;
    }
    buffer.write('${entry.key}: ${entry.value}\r\n');
  }
  return buffer.toString();
}
