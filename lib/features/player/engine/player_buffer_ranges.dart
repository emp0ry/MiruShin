import 'player_engine.dart';

/// media_kit reports mpv's demuxer-cache-time: an absolute endpoint, not an
/// amount of buffered time. A missing/behind endpoint proves no forward cache.
List<PlayerBufferedRange> rangesFromAbsoluteBufferEnd({
  required Duration position,
  required Duration bufferEnd,
  required Duration duration,
}) {
  final start = position < Duration.zero ? Duration.zero : position;
  final end = duration > Duration.zero && bufferEnd > duration
      ? duration
      : bufferEnd;
  if (end <= start) return const [];
  return [PlayerBufferedRange(start: start, end: end)];
}
