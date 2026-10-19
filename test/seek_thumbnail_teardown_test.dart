import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/direct_frame_decoder.dart';
import 'package:mirushin/features/player/engine/player_engine.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_extractor_io.dart';
import 'package:mirushin/features/player/engine/seek_thumbnail_media_loader_io.dart';

SeekThumbnailSource _source() => SeekThumbnailSource(
  source: const PlayerSource(url: 'https://example.invalid/video'),
  sourceKey: 'source',
  decoderKey: 'decoder',
  label: 'test',
  isOffline: false,
  kind: SeekThumbnailSourceKind.networkDirect,
);

class _BlockedDecoder implements DirectFrameDecoder {
  final started = Completer<void>();
  final result = Completer<DirectFrameDecodeResult>();
  int requests = 0;
  bool disposed = false;
  @override
  bool get isSupported => true;
  @override
  Future<void> warm() async {}
  @override
  Future<DirectFrameDecodeResult> decode(DirectFrameDecodeRequest request) {
    requests++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  void cancelPending() {
    if (!result.isCompleted) {
      result.complete(
        const DirectFrameDecodeResult.failure(DirectFrameFailureKind.cancelled),
      );
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _BlockedPreparation extends SeekThumbnailMediaLoader {
  final started = Completer<void>();
  final result = Completer<PreparedThumbnailInput?>();
  @override
  Future<PreparedThumbnailInput?> prepare(
    SeekThumbnailSource source,
    Duration position, {
    int windowSegments = 1,
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  test(
    'extractor disposal cancels native work before draining its queue',
    () async {
      final decoder = _BlockedDecoder();
      final extractor = NativeSeekThumbnailExtractor(decoder: decoder);
      final pending = extractor.extract(
        source: _source(),
        position: Duration.zero,
        duration: const Duration(minutes: 24),
      );
      await decoder.started.future;
      await extractor.dispose().timeout(const Duration(seconds: 1));
      expect(decoder.disposed, isTrue);
      expect(
        (await pending).failure?.reason,
        SeekThumbnailFailureReason.cancelled,
      );
    },
  );

  test('cancelled preparation cannot start a fresh native decoder', () async {
    final loader = _BlockedPreparation();
    final decoder = _BlockedDecoder();
    final extractor = NativeSeekThumbnailExtractor(
      decoder: decoder,
      loader: loader,
    );
    addTearDown(extractor.dispose);
    final pending = extractor.extract(
      source: _source(),
      position: Duration.zero,
      duration: const Duration(minutes: 24),
    );
    await loader.started.future;
    extractor.cancelPending();
    loader.result.complete(
      PreparedThumbnailInput(
        input: 'synthetic',
        position: Duration.zero,
        headers: {},
        windowSegmentCount: 0,
      ),
    );
    expect(
      (await pending).failure?.reason,
      SeekThumbnailFailureReason.cancelled,
    );
    expect(decoder.requests, 0);
  });
}
