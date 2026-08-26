import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

import 'direct_frame_decoder.dart';

class NativeDirectFrameDecoder implements DirectFrameDecoder {
  NativeDirectFrameDecoder() {
    try {
      final DynamicLibrary library = _openLibrary();
      _cancel = library
          .lookup<NativeFunction<_SessionCancelNative>>(
            'mirushin_seek_thumbnail_session_cancel',
          )
          .asFunction<_SessionCancelDart>();
      library.lookup<NativeFunction<_SessionCreateNative>>(
        'mirushin_seek_thumbnail_session_create',
      );
      _supported = true;
    } on Object {
      _supported = false;
    }
  }

  bool _supported = false;
  bool _disposed = false;
  _SessionCancelDart? _cancel;
  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _responses;
  Future<void>? _starting;
  int _nextRequestId = 1;
  final Map<int, Completer<DirectFrameDecodeResult>> _pending =
      <int, Completer<DirectFrameDecodeResult>>{};
  final Map<int, int> _activeHandles = <int, int>{};
  final Map<int, Map<Object?, Object?>> _awaitingRelease =
      <int, Map<Object?, Object?>>{};

  @override
  bool get isSupported => _supported && !_disposed;

  @override
  Future<void> warm() async {
    if (isSupported) await _ensureWorker();
  }

  Future<void> _ensureWorker() {
    final Future<void>? existing = _starting;
    if (existing != null) return existing;
    final Future<void> starting = _startWorker();
    _starting = starting;
    return starting;
  }

  Future<void> _startWorker() async {
    final ReceivePort ready = ReceivePort();
    final ReceivePort responses = ReceivePort();
    _responses = responses;
    responses.listen(_handleWorkerMessage);
    try {
      _isolate = await Isolate.spawn<Map<String, Object>>(
        _decoderWorkerMain,
        <String, Object>{
          'ready': ready.sendPort,
          'responses': responses.sendPort,
        },
        debugName: 'MiruShinSeekThumbnailDecoder',
      );
      _worker = await ready.first as SendPort;
    } finally {
      ready.close();
    }
  }

  void _handleWorkerMessage(Object? raw) {
    if (raw is! Map<Object?, Object?>) return;
    final String? type = raw['type'] as String?;
    final int? id = raw['id'] as int?;
    if (type == 'active' && id != null) {
      _activeHandles[id] = raw['handle']! as int;
      return;
    }
    if (type == 'stopped') return;
    if (type == 'released' && id != null) {
      final Map<Object?, Object?>? result = _awaitingRelease.remove(id);
      if (result != null) _completeWorkerResult(id, result);
      return;
    }
    if (type != 'result' || id == null) return;
    _activeHandles.remove(id);
    if (raw['release'] == true) {
      _awaitingRelease[id] = raw;
      _worker?.send(<String, Object>{'type': 'release', 'id': id});
      return;
    }
    _completeWorkerResult(id, raw);
  }

  void _completeWorkerResult(int id, Map<Object?, Object?> raw) {
    final Completer<DirectFrameDecodeResult>? completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final int status = raw['status']! as int;
    if (status != 0) {
      completer.complete(
        DirectFrameDecodeResult.failure(_failureForStatus(status)),
      );
      return;
    }
    final TransferableTypedData transferred =
        raw['bytes']! as TransferableTypedData;
    completer.complete(
      DirectFrameDecodeResult.success(
        DirectFrame(
          jpegBytes: transferred.materialize().asUint8List(),
          position: Duration(milliseconds: raw['positionMs']! as int),
          width: raw['width']! as int,
          height: raw['height']! as int,
          codedWidth: raw['codedWidth']! as int,
          codedHeight: raw['codedHeight']! as int,
          sampleAspectRatioNumerator: raw['sarNum']! as int,
          sampleAspectRatioDenominator: raw['sarDen']! as int,
          rotationDegrees: raw['rotation']! as int,
          displayAspectRatio: raw['dar']! as double,
          sessionReused: raw['sessionReused']! as bool,
          nativeDecodeMicroseconds: raw['nativeDecodeUs']! as int,
          encodeMicroseconds: raw['encodeUs']! as int,
        ),
      ),
    );
  }

  @override
  Future<DirectFrameDecodeResult> decode(
    DirectFrameDecodeRequest request,
  ) async {
    if (!isSupported) {
      return const DirectFrameDecodeResult.failure(
        DirectFrameFailureKind.unavailable,
      );
    }
    await _ensureWorker();
    if (_disposed || _worker == null) {
      return const DirectFrameDecodeResult.failure(
        DirectFrameFailureKind.cancelled,
      );
    }
    final int id = _nextRequestId++;
    final Completer<DirectFrameDecodeResult> completer =
        Completer<DirectFrameDecodeResult>();
    _pending[id] = completer;
    _worker!.send(<String, Object>{
      'type': 'decode',
      'id': id,
      'input': request.input,
      'headers': _serializeHeaders(request.headers),
      'positionMs': request.position.inMilliseconds,
      'width': request.width,
      'sessionKey': request.sessionKey,
      'reuseSession': request.reuseSession,
    });
    return completer.future;
  }

  @override
  void cancelPending() {
    final _SessionCancelDart? cancel = _cancel;
    if (cancel != null) {
      for (final int address in _activeHandles.values.toSet()) {
        cancel(Pointer<Void>.fromAddress(address));
      }
    }
    _worker?.send(const <String, Object>{'type': 'cancel'});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
    final Future<void>? starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } on Object {
        // A worker that never started owns no native sessions.
      }
    }
    final SendPort? worker = _worker;
    if (worker != null) {
      final ReceivePort stopped = ReceivePort();
      worker.send(<String, Object>{
        'type': 'shutdown',
        'reply': stopped.sendPort,
      });
      try {
        await stopped.first.timeout(const Duration(seconds: 2));
      } on Object {
        _isolate?.kill(priority: Isolate.immediate);
      } finally {
        stopped.close();
      }
    }
    _responses?.close();
    _responses = null;
    _worker = null;
    _isolate = null;
    _activeHandles.clear();
    _awaitingRelease.clear();
    for (final Completer<DirectFrameDecodeResult> completer
        in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(
          const DirectFrameDecodeResult.failure(
            DirectFrameFailureKind.cancelled,
          ),
        );
      }
    }
    _pending.clear();
  }
}

class _WorkerSession {
  const _WorkerSession({
    required this.handle,
    required this.input,
    required this.headers,
  });

  final Pointer<Void> handle;
  final String input;
  final String headers;
}

void _decoderWorkerMain(Map<String, Object> bootstrap) {
  final SendPort ready = bootstrap['ready']! as SendPort;
  final SendPort responses = bootstrap['responses']! as SendPort;
  final ReceivePort commands = ReceivePort();
  final DynamicLibrary library = _openLibrary();
  final _SessionCreateDart create = library
      .lookup<NativeFunction<_SessionCreateNative>>(
        'mirushin_seek_thumbnail_session_create',
      )
      .asFunction<_SessionCreateDart>();
  final _SessionResetDart reset = library
      .lookup<NativeFunction<_SessionResetNative>>(
        'mirushin_seek_thumbnail_session_reset_cancel',
      )
      .asFunction<_SessionResetDart>();
  final _SessionOpenDart open = library
      .lookup<NativeFunction<_SessionOpenNative>>(
        'mirushin_seek_thumbnail_session_open',
      )
      .asFunction<_SessionOpenDart>();
  final _SessionDecodeDart decode = library
      .lookup<NativeFunction<_SessionDecodeNative>>(
        'mirushin_seek_thumbnail_session_decode',
      )
      .asFunction<_SessionDecodeDart>();
  final _SessionCancelDart cancel = library
      .lookup<NativeFunction<_SessionCancelNative>>(
        'mirushin_seek_thumbnail_session_cancel',
      )
      .asFunction<_SessionCancelDart>();
  final _SessionDestroyDart destroy = library
      .lookup<NativeFunction<_SessionDestroyNative>>(
        'mirushin_seek_thumbnail_session_destroy',
      )
      .asFunction<_SessionDestroyDart>();
  final _FreeDart release = library
      .lookup<NativeFunction<_FreeNative>>('mirushin_seek_thumbnail_free')
      .asFunction<_FreeDart>();
  final Map<String, _WorkerSession> sessions = <String, _WorkerSession>{};
  final Map<int, _WorkerSession> pendingRelease = <int, _WorkerSession>{};

  ready.send(commands.sendPort);
  commands.listen((Object? raw) {
    if (raw is! Map<Object?, Object?>) return;
    final String? type = raw['type'] as String?;
    if (type == 'cancel') {
      for (final _WorkerSession session in <_WorkerSession>{
        ...sessions.values,
        ...pendingRelease.values,
      }) {
        cancel(session.handle);
      }
      return;
    }
    if (type == 'release') {
      final int id = raw['id']! as int;
      final _WorkerSession? session = pendingRelease.remove(id);
      if (session != null) destroy(session.handle);
      responses.send(<String, Object>{'type': 'released', 'id': id});
      return;
    }
    if (type == 'shutdown') {
      for (final _WorkerSession session in <_WorkerSession>{
        ...sessions.values,
        ...pendingRelease.values,
      }) {
        cancel(session.handle);
        destroy(session.handle);
      }
      sessions.clear();
      pendingRelease.clear();
      (raw['reply']! as SendPort).send(true);
      commands.close();
      return;
    }
    if (type != 'decode') return;
    final int id = raw['id']! as int;
    final String input = raw['input']! as String;
    final String headers = raw['headers']! as String;
    final String sessionKey = raw['sessionKey']! as String;
    final bool reuseSession = raw['reuseSession']! as bool;
    _WorkerSession? session = reuseSession ? sessions[sessionKey] : null;
    bool sessionReused =
        session != null && session.input == input && session.headers == headers;
    if (session != null && !sessionReused) {
      destroy(session.handle);
      sessions.remove(sessionKey);
      session = null;
    }
    session ??= _WorkerSession(
      handle: create(),
      input: input,
      headers: headers,
    );
    if (session.handle == nullptr) {
      responses.send(<String, Object>{
        'type': 'result',
        'id': id,
        'status': -2,
      });
      return;
    }
    reset(session.handle);
    responses.send(<String, Object>{
      'type': 'active',
      'id': id,
      'handle': session.handle.address,
    });
    int status = 0;
    if (!sessionReused) {
      status = _openWorkerSession(session, open: open);
      if (status == 0 && reuseSession) sessions[sessionKey] = session;
    }
    Map<String, Object> result;
    if (status == 0) {
      result = _decodeWorkerFrame(
        session,
        decode: decode,
        release: release,
        positionMs: raw['positionMs']! as int,
        width: raw['width']! as int,
        sessionReused: sessionReused,
      );
      status = result['status']! as int;
    } else {
      result = <String, Object>{'status': status};
    }
    final bool keepSession =
        reuseSession &&
        identical(sessions[sessionKey], session) &&
        status != -20;
    if (!keepSession) {
      if (identical(sessions[sessionKey], session)) sessions.remove(sessionKey);
      pendingRelease[id] = session;
      result['release'] = true;
    }
    responses.send(<String, Object>{'type': 'result', 'id': id, ...result});
  });
}

int _openWorkerSession(
  _WorkerSession session, {
  required _SessionOpenDart open,
}) {
  final Pointer<Utf8> input = session.input.toNativeUtf8();
  final Pointer<Utf8> headers = session.headers.toNativeUtf8();
  final Pointer<Int8> error = calloc<Int8>(512);
  try {
    return open(session.handle, input, headers, error, 512);
  } finally {
    calloc.free(input);
    calloc.free(headers);
    calloc.free(error);
  }
}

Map<String, Object> _decodeWorkerFrame(
  _WorkerSession session, {
  required _SessionDecodeDart decode,
  required _FreeDart release,
  required int positionMs,
  required int width,
  required bool sessionReused,
}) {
  final Pointer<Pointer<Uint8>> rgba = calloc<Pointer<Uint8>>();
  final Pointer<Int32> rgbaLength = calloc<Int32>();
  final Pointer<Int32> outputWidth = calloc<Int32>();
  final Pointer<Int32> outputHeight = calloc<Int32>();
  final Pointer<Int64> decodedMs = calloc<Int64>();
  final Pointer<Int32> codedWidth = calloc<Int32>();
  final Pointer<Int32> codedHeight = calloc<Int32>();
  final Pointer<Int32> sarNum = calloc<Int32>();
  final Pointer<Int32> sarDen = calloc<Int32>();
  final Pointer<Int32> rotation = calloc<Int32>();
  final Pointer<Double> dar = calloc<Double>();
  final Pointer<Int8> error = calloc<Int8>(512);
  Pointer<Uint8> nativeBytes = nullptr;
  try {
    final Stopwatch nativeDecode = Stopwatch()..start();
    final int status = decode(
      session.handle,
      positionMs,
      width,
      rgba,
      rgbaLength,
      outputWidth,
      outputHeight,
      decodedMs,
      codedWidth,
      codedHeight,
      sarNum,
      sarDen,
      rotation,
      dar,
      error,
      512,
    );
    nativeDecode.stop();
    nativeBytes = rgba.value;
    if (status != 0 || nativeBytes == nullptr || rgbaLength.value <= 0) {
      return <String, Object>{'status': status == 0 ? -15 : status};
    }
    final Uint8List pixels = Uint8List.fromList(
      nativeBytes.asTypedList(rgbaLength.value),
    );
    final img.Image image = img.Image.fromBytes(
      width: outputWidth.value,
      height: outputHeight.value,
      bytes: pixels.buffer,
      numChannels: 4,
      rowStride: outputWidth.value * 4,
      order: img.ChannelOrder.rgba,
    );
    final Stopwatch encode = Stopwatch()..start();
    final Uint8List jpeg = Uint8List.fromList(
      img.encodeJpg(image, quality: 76),
    );
    encode.stop();
    return <String, Object>{
      'status': 0,
      'bytes': TransferableTypedData.fromList(<Uint8List>[jpeg]),
      'width': outputWidth.value,
      'height': outputHeight.value,
      'positionMs': decodedMs.value >= 0 ? decodedMs.value : positionMs,
      'codedWidth': codedWidth.value,
      'codedHeight': codedHeight.value,
      'sarNum': sarNum.value,
      'sarDen': sarDen.value,
      'rotation': rotation.value,
      'dar': dar.value,
      'sessionReused': sessionReused,
      'nativeDecodeUs': nativeDecode.elapsedMicroseconds,
      'encodeUs': encode.elapsedMicroseconds,
    };
  } finally {
    if (nativeBytes != nullptr) release(nativeBytes);
    calloc.free(rgba);
    calloc.free(rgbaLength);
    calloc.free(outputWidth);
    calloc.free(outputHeight);
    calloc.free(decodedMs);
    calloc.free(codedWidth);
    calloc.free(codedHeight);
    calloc.free(sarNum);
    calloc.free(sarDen);
    calloc.free(rotation);
    calloc.free(dar);
    calloc.free(error);
  }
}

DirectFrameFailureKind _failureForStatus(int status) => switch (status) {
  -20 => DirectFrameFailureKind.cancelled,
  -10 => DirectFrameFailureKind.openInput,
  -11 => DirectFrameFailureKind.streamInfo,
  -12 => DirectFrameFailureKind.noVideoTrack,
  -13 => DirectFrameFailureKind.unsupportedCodec,
  -14 => DirectFrameFailureKind.seek,
  -15 => DirectFrameFailureKind.noFrame,
  -16 => DirectFrameFailureKind.scale,
  -2 => DirectFrameFailureKind.unavailable,
  _ => DirectFrameFailureKind.unknown,
};

DynamicLibrary _openLibrary() {
  if (Platform.isWindows) {
    return DynamicLibrary.open('mirushin_seek_thumbnail.dll');
  }
  if (Platform.isLinux || Platform.isAndroid) {
    return DynamicLibrary.open('libmirushin_seek_thumbnail.so');
  }
  return DynamicLibrary.process();
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

typedef _SessionCreateNative = Pointer<Void> Function();
typedef _SessionCreateDart = Pointer<Void> Function();
typedef _SessionResetNative = Void Function(Pointer<Void> session);
typedef _SessionResetDart = void Function(Pointer<Void> session);
typedef _SessionCancelNative = Void Function(Pointer<Void> session);
typedef _SessionCancelDart = void Function(Pointer<Void> session);
typedef _SessionDestroyNative = Void Function(Pointer<Void> session);
typedef _SessionDestroyDart = void Function(Pointer<Void> session);
typedef _SessionOpenNative =
    Int32 Function(
      Pointer<Void> session,
      Pointer<Utf8> input,
      Pointer<Utf8> headers,
      Pointer<Int8> error,
      Int32 errorCapacity,
    );
typedef _SessionOpenDart =
    int Function(
      Pointer<Void> session,
      Pointer<Utf8> input,
      Pointer<Utf8> headers,
      Pointer<Int8> error,
      int errorCapacity,
    );
typedef _SessionDecodeNative =
    Int32 Function(
      Pointer<Void> session,
      Int64 targetMs,
      Int32 targetWidth,
      Pointer<Pointer<Uint8>> rgba,
      Pointer<Int32> rgbaLength,
      Pointer<Int32> width,
      Pointer<Int32> height,
      Pointer<Int64> decodedMs,
      Pointer<Int32> codedWidth,
      Pointer<Int32> codedHeight,
      Pointer<Int32> sarNum,
      Pointer<Int32> sarDen,
      Pointer<Int32> rotation,
      Pointer<Double> displayAspectRatio,
      Pointer<Int8> error,
      Int32 errorCapacity,
    );
typedef _SessionDecodeDart =
    int Function(
      Pointer<Void> session,
      int targetMs,
      int targetWidth,
      Pointer<Pointer<Uint8>> rgba,
      Pointer<Int32> rgbaLength,
      Pointer<Int32> width,
      Pointer<Int32> height,
      Pointer<Int64> decodedMs,
      Pointer<Int32> codedWidth,
      Pointer<Int32> codedHeight,
      Pointer<Int32> sarNum,
      Pointer<Int32> sarDen,
      Pointer<Int32> rotation,
      Pointer<Double> displayAspectRatio,
      Pointer<Int8> error,
      int errorCapacity,
    );
typedef _FreeNative = Void Function(Pointer<Uint8> data);
typedef _FreeDart = void Function(Pointer<Uint8> data);
