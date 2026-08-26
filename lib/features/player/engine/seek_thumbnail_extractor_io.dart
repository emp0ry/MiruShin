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
    await Future.wait<void>(<Future<void>>[
      _decoder.warm(),
      _loader.warm(source),
    ]);
  }

  @override
  void cancelPending() {
    _generation += 1;
    _loader.cancelPending();
    _decoder.cancelPending();
  }

  @override
  Future<SeekThumbnailExtractionResult> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
  }) {
    if (_disposed || !_decoder.isSupported) {
      return Future<SeekThumbnailExtractionResult>.value(
        const SeekThumbnailExtractionResult.failure(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.permanentSource,
            reason: SeekThumbnailFailureReason.unavailable,
          ),
        ),
      );
    }
    final int generation = _generation;
    final Completer<SeekThumbnailExtractionResult> result =
        Completer<SeekThumbnailExtractionResult>();
    _serial = _serial.then((_) async {
      if (_disposed || generation != _generation) {
        result.complete(_cancelledResult);
        return;
      }
      try {
        final SeekThumbnailExtractionResult extraction = await _extractSerial(
          source,
          position,
        );
        result.complete(
          generation == _generation ? extraction : _cancelledResult,
        );
      } on Object {
        result.complete(
          const SeekThumbnailExtractionResult.failure(
            SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.transient,
              reason: SeekThumbnailFailureReason.unknown,
            ),
          ),
        );
      }
    });
    return result.future;
  }

  Future<SeekThumbnailExtractionResult> _extractSerial(
    SeekThumbnailSource source,
    Duration position,
  ) async {
    final Stopwatch total = Stopwatch()..start();
    int prepareMilliseconds = 0;
    int indexLookupMicroseconds = 0;
    final bool segmented =
        source.kind == SeekThumbnailSourceKind.localHls ||
        source.kind == SeekThumbnailSourceKind.networkHls ||
        source.kind == SeekThumbnailSourceKind.networkDash;
    final int attempts = segmented ? 4 : 1;
    int lastWindowSize = 0;
    for (int index = 0; index < attempts; index += 1) {
      final Stopwatch prepare = Stopwatch()..start();
      PreparedThumbnailInput? input;
      try {
        input = await _loader.prepare(
          source,
          position,
          windowSegments: index + 1,
        );
      } on SeekThumbnailLoadException catch (error) {
        return SeekThumbnailExtractionResult.failure(error.failure);
      }
      prepare.stop();
      prepareMilliseconds += prepare.elapsedMilliseconds;
      if (input == null) continue;
      indexLookupMicroseconds += input.indexLookupMicroseconds;
      if (segmented && input.windowSegmentCount == lastWindowSize) {
        await input.dispose();
        break;
      }
      lastWindowSize = input.windowSegmentCount;
      final Stopwatch decode = Stopwatch()..start();
      try {
        final DirectFrameDecodeResult decoded = await _decoder.decode(
          DirectFrameDecodeRequest(
            input: input.input,
            position: input.position,
            sessionKey: source.decoderKey,
            headers: input.headers,
            width: 240,
            reuseSession: !segmented,
          ),
        );
        decode.stop();
        final DirectFrame? frame = decoded.frame;
        if (frame != null && frame.jpegBytes.isNotEmpty) {
          total.stop();
          if (kDebugMode) {
            debugPrint(
              'SeekPreview: frame timing '
              'indexLookup=${(indexLookupMicroseconds / 1000).toStringAsFixed(3)}ms, '
              'prepare=${prepareMilliseconds}ms, '
              'decode=${(frame.nativeDecodeMicroseconds / 1000).toStringAsFixed(3)}ms, '
              'encode=${(frame.encodeMicroseconds / 1000).toStringAsFixed(3)}ms, '
              'worker=${decode.elapsedMilliseconds}ms, '
              'total=${total.elapsedMilliseconds}ms, '
              'window=${input.windowSegmentCount}, '
              'decoderSession=${frame.sessionReused ? 'reused' : 'open'}, '
              'coded=${frame.codedWidth}x${frame.codedHeight}, '
              'SAR=${frame.sampleAspectRatioNumerator}:'
              '${frame.sampleAspectRatioDenominator}, '
              'DAR=${frame.displayAspectRatio.toStringAsFixed(4)}, '
              'rotation=${frame.rotationDegrees}, '
              'output=${frame.width}x${frame.height}.',
            );
          }
          return SeekThumbnailExtractionResult.success(
            SeekThumbnail(
              bytes: frame.jpegBytes,
              position: position,
              width: frame.width,
              height: frame.height,
            ),
          );
        }
        final DirectFrameFailureKind failure =
            decoded.failure ?? DirectFrameFailureKind.unknown;
        if (failure == DirectFrameFailureKind.cancelled) {
          return _cancelledResult;
        }
        if (failure == DirectFrameFailureKind.noVideoTrack ||
            failure == DirectFrameFailureKind.unsupportedCodec) {
          return SeekThumbnailExtractionResult.failure(
            SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.permanentSource,
              reason: failure == DirectFrameFailureKind.noVideoTrack
                  ? SeekThumbnailFailureReason.noVideoTrack
                  : SeekThumbnailFailureReason.unsupportedCodec,
            ),
          );
        }
        if (!segmented) {
          return SeekThumbnailExtractionResult.failure(
            SeekThumbnailFailure(
              scope:
                  failure == DirectFrameFailureKind.openInput ||
                      failure == DirectFrameFailureKind.streamInfo
                  ? SeekThumbnailFailureScope.transient
                  : SeekThumbnailFailureScope.bucketSpecific,
              reason: _thumbnailReason(failure),
            ),
          );
        }
        if (kDebugMode) {
          debugPrint(
            'SeekPreview: bucket=${position.inSeconds} '
            'window=${input.windowSegmentCount} '
            'result=${_thumbnailReason(failure).name}.',
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
    return const SeekThumbnailExtractionResult.failure(
      SeekThumbnailFailure(
        scope: SeekThumbnailFailureScope.bucketSpecific,
        reason: SeekThumbnailFailureReason.missingRandomAccessContext,
      ),
    );
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
  Future<SeekThumbnailExtractionResult> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
  }) async {
    return const SeekThumbnailExtractionResult.failure(
      SeekThumbnailFailure(
        scope: SeekThumbnailFailureScope.permanentSource,
        reason: SeekThumbnailFailureReason.unavailable,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

const SeekThumbnailExtractionResult _cancelledResult =
    SeekThumbnailExtractionResult.failure(
      SeekThumbnailFailure(
        scope: SeekThumbnailFailureScope.cancelled,
        reason: SeekThumbnailFailureReason.cancelled,
      ),
    );

SeekThumbnailFailureReason _thumbnailReason(
  DirectFrameFailureKind failure,
) => switch (failure) {
  DirectFrameFailureKind.cancelled => SeekThumbnailFailureReason.cancelled,
  DirectFrameFailureKind.noVideoTrack =>
    SeekThumbnailFailureReason.noVideoTrack,
  DirectFrameFailureKind.unsupportedCodec =>
    SeekThumbnailFailureReason.unsupportedCodec,
  DirectFrameFailureKind.noFrame =>
    SeekThumbnailFailureReason.missingRandomAccessContext,
  DirectFrameFailureKind.openInput ||
  DirectFrameFailureKind.streamInfo => SeekThumbnailFailureReason.network,
  DirectFrameFailureKind.seek ||
  DirectFrameFailureKind.scale ||
  DirectFrameFailureKind.unknown => SeekThumbnailFailureReason.decodeFailure,
  DirectFrameFailureKind.unavailable => SeekThumbnailFailureReason.unavailable,
};
