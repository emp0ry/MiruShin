import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/player_models.dart';
import 'direct_frame_decoder.dart';
import 'direct_frame_decoder_io.dart';
import 'seek_thumbnail.dart';
import 'seek_thumbnail_media_loader_io.dart';

bool get seekThumbnailExtractionSupported =>
    Platform.isWindows ||
    Platform.isAndroid ||
    Platform.isLinux ||
    Platform.isIOS ||
    Platform.isMacOS;

PlayerBackend seekThumbnailExtractionBackend(PlayerBackend _) {
  // Thumbnail decoding is independent from the main MPV/FVP selection.
  return PlayerBackend.auto;
}

SeekThumbnailExtractor createSeekThumbnailExtractor(PlayerBackend _) {
  if (!seekThumbnailExtractionSupported) {
    return const _UnsupportedSeekThumbnailExtractor();
  }
  return NativeSeekThumbnailExtractor();
}

class NativeSeekThumbnailExtractor implements SeekThumbnailExtractor {
  NativeSeekThumbnailExtractor({
    DirectFrameDecoder? decoder,
    SeekThumbnailMediaLoader? loader,
  }) : _decoder = decoder ?? NativeDirectFrameDecoder(),
       _loader = loader ?? SeekThumbnailMediaLoader();

  final DirectFrameDecoder _decoder;
  final SeekThumbnailMediaLoader _loader;
  Future<void> _serial = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<void> warm(SeekThumbnailSource source) async {
    if (_disposed || !_decoder.isSupported) return;
    await _loader.warm(source);
  }

  @override
  void cancelPending() {
    _generation += 1;
    _loader.cancelPending();
  }

  @override
  Future<SeekThumbnail?> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
  }) {
    if (_disposed || !_decoder.isSupported) {
      return Future<SeekThumbnail?>.value();
    }
    final int generation = _generation;
    final Completer<SeekThumbnail?> result = Completer<SeekThumbnail?>();
    _serial = _serial.then((_) async {
      if (_disposed || generation != _generation) {
        result.complete();
        return;
      }
      try {
        final SeekThumbnail? thumbnail = await _extractSerial(source, position);
        result.complete(generation == _generation ? thumbnail : null);
      } on Object {
        result.complete();
      }
    });
    return result.future;
  }

  Future<SeekThumbnail?> _extractSerial(
    SeekThumbnailSource source,
    Duration position,
  ) async {
    final Stopwatch total = Stopwatch()..start();
    int prepareMilliseconds = 0;
    final bool segmented =
        source.kind == SeekThumbnailSourceKind.localHls ||
        source.kind == SeekThumbnailSourceKind.networkHls ||
        source.kind == SeekThumbnailSourceKind.networkDash;
    final int attempts = segmented ? 2 : 1;
    for (int index = 0; index < attempts; index += 1) {
      final Stopwatch prepare = Stopwatch()..start();
      final List<PreparedThumbnailInput> inputs = await _loader.prepare(
        source,
        position,
        previousSegment: index > 0,
      );
      prepare.stop();
      prepareMilliseconds += prepare.elapsedMilliseconds;
      if (inputs.isEmpty) continue;
      final PreparedThumbnailInput input = inputs.single;
      final Stopwatch decode = Stopwatch()..start();
      try {
        final DirectFrame? frame = await _decoder.decode(
          DirectFrameDecodeRequest(
            input: input.input,
            position: input.position,
            headers: input.headers,
            width: 240,
          ),
        );
        decode.stop();
        if (frame != null && frame.jpegBytes.isNotEmpty) {
          total.stop();
          if (kDebugMode) {
            debugPrint(
              'SeekPreview: frame timing '
              'prepare=${prepareMilliseconds}ms, '
              'decode=${decode.elapsedMilliseconds}ms, '
              'total=${total.elapsedMilliseconds}ms, '
              'fallback=$index.',
            );
          }
          return SeekThumbnail(
            bytes: frame.jpegBytes,
            position: position,
            width: frame.width,
            height: frame.height,
          );
        }
      } finally {
        // Native decode has returned and released its input before an offline
        // download can become eligible for auto-delete.
        await input.dispose();
      }
    }
    total.stop();
    if (kDebugMode) {
      debugPrint(
        'SeekPreview: frame unavailable after ${total.elapsedMilliseconds}ms.',
      );
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _serial;
    await _decoder.dispose();
    await _loader.dispose();
    if (kDebugMode) debugPrint('SeekPreview: direct decoder disposed.');
  }
}

class _UnsupportedSeekThumbnailExtractor implements SeekThumbnailExtractor {
  const _UnsupportedSeekThumbnailExtractor();

  @override
  void cancelPending() {}

  @override
  Future<void> warm(SeekThumbnailSource source) async {}

  @override
  Future<SeekThumbnail?> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
  }) async {
    return null;
  }

  @override
  Future<void> dispose() async {}
}
