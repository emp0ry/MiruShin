import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/player_models.dart';
import 'player_engine.dart';

const Duration defaultSeekThumbnailInterval = Duration(seconds: 5);

class SeekThumbnail {
  const SeekThumbnail({
    required this.bytes,
    required this.position,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final Duration position;
  final int width;
  final int height;
}

class SeekThumbnailSource {
  const SeekThumbnailSource({
    required this.source,
    required this.sourceKey,
    required this.decoderKey,
    required this.label,
    required this.isOffline,
  });

  final PlayerSource source;
  final String sourceKey;
  final String decoderKey;
  final String label;
  final bool isOffline;
}

class SeekThumbnailPlan {
  const SeekThumbnailPlan({
    required this.sessionKey,
    required this.candidates,
    required this.isOffline,
  });

  final String sessionKey;
  final List<SeekThumbnailSource> candidates;
  final bool isOffline;
}

abstract interface class SeekThumbnailExtractor {
  Future<SeekThumbnail?> extract({
    required PlayerSource source,
    required Duration position,
    required Duration duration,
    required String sourceKey,
  });

  Future<void> dispose();
}

typedef SeekThumbnailExtractorFactory =
    SeekThumbnailExtractor Function(PlayerBackend backend);

Duration quantizeSeekThumbnailPosition(
  Duration position, {
  Duration duration = Duration.zero,
  Duration interval = defaultSeekThumbnailInterval,
}) {
  final int intervalMs = interval.inMilliseconds;
  if (intervalMs <= 0) {
    throw ArgumentError.value(interval, 'interval', 'Must be positive.');
  }

  final int durationMs = duration.inMilliseconds;
  final int clampedMs = durationMs > 0
      ? position.inMilliseconds.clamp(0, durationMs).toInt()
      : position.inMilliseconds.clamp(0, 1 << 62).toInt();
  int bucketMs = (clampedMs ~/ intervalMs) * intervalMs;
  if (durationMs > 0 && bucketMs >= durationMs) {
    bucketMs = (durationMs - const Duration(milliseconds: 250).inMilliseconds)
        .clamp(0, durationMs)
        .toInt();
  }
  return Duration(milliseconds: bucketMs);
}

class SeekThumbnailCacheKey {
  const SeekThumbnailCacheKey({required this.sourceKey, required this.bucket});

  final String sourceKey;
  final Duration bucket;

  @override
  bool operator ==(Object other) {
    return other is SeekThumbnailCacheKey &&
        other.sourceKey == sourceKey &&
        other.bucket == bucket;
  }

  @override
  int get hashCode => Object.hash(sourceKey, bucket);
}

class SeekThumbnailRequestTracker {
  int _generation = 0;
  String? _sessionKey;
  Duration? _bucket;

  int begin(String sessionKey, Duration bucket) {
    _sessionKey = sessionKey;
    _bucket = bucket;
    return ++_generation;
  }

  void invalidate() {
    _generation++;
    _sessionKey = null;
    _bucket = null;
  }

  bool accepts(int generation, String sessionKey, Duration bucket) {
    return generation == _generation &&
        sessionKey == _sessionKey &&
        bucket == _bucket;
  }
}

class SeekThumbnailService {
  SeekThumbnailService({
    required SeekThumbnailExtractorFactory extractorFactory,
    this.maxCacheBytes = 16 * 1024 * 1024,
    this.maxCacheEntries = 120,
    this.extractionTimeout = const Duration(seconds: 4),
  }) : _extractorFactory = extractorFactory;

  final SeekThumbnailExtractorFactory _extractorFactory;
  final int maxCacheBytes;
  final int maxCacheEntries;
  final Duration extractionTimeout;

  final LinkedHashMap<SeekThumbnailCacheKey, SeekThumbnail> _cache =
      LinkedHashMap<SeekThumbnailCacheKey, SeekThumbnail>();
  final Map<String, Future<SeekThumbnail?>> _inFlight =
      <String, Future<SeekThumbnail?>>{};
  final Map<String, int> _successfulCandidateBySession = <String, int>{};

  SeekThumbnailExtractor? _extractor;
  String? _desiredContextKey;
  String? _activeContextKey;
  PlayerBackend _desiredBackend = PlayerBackend.auto;
  Future<void> _activation = Future<void>.value();
  int _cacheBytes = 0;
  bool _disposed = false;

  int get cacheEntryCount => _cache.length;
  int get cacheByteCount => _cacheBytes;

  Future<void> activate(SeekThumbnailPlan plan, PlayerBackend backend) {
    if (_disposed) return Future<void>.value();
    final String contextKey = '${backend.name}|${plan.sessionKey}';
    _desiredContextKey = contextKey;
    _desiredBackend = backend;
    if (_activeContextKey == contextKey) return _activation;

    _activation = _activation.then((_) async {
      if (_disposed) return;
      final String? desired = _desiredContextKey;
      if (desired == null || desired == _activeContextKey) return;
      final SeekThumbnailExtractor? previous = _extractor;
      _extractor = null;
      _activeContextKey = null;
      if (previous != null) {
        try {
          await previous.dispose();
        } on Object {
          // Thumbnail teardown is best effort and must not affect playback.
        }
      }
      if (_disposed || desired != _desiredContextKey) return;
      _extractor = _extractorFactory(_desiredBackend);
      _activeContextKey = desired;
      if (kDebugMode) {
        debugPrint('SeekPreview: backend=${_desiredBackend.name}.');
      }
    });
    return _activation;
  }

  SeekThumbnail? cachedFor(
    SeekThumbnailPlan plan,
    Duration position, {
    Duration duration = Duration.zero,
  }) {
    final Duration bucket = quantizeSeekThumbnailPosition(
      position,
      duration: duration,
    );
    for (final int index in _candidateOrder(plan)) {
      final SeekThumbnailCacheKey key = SeekThumbnailCacheKey(
        sourceKey: plan.candidates[index].sourceKey,
        bucket: bucket,
      );
      final SeekThumbnail? thumbnail = _cache.remove(key);
      if (thumbnail != null) {
        _cache[key] = thumbnail;
        if (kDebugMode) {
          debugPrint(
            'SeekPreview: cache hit @ ${bucket.inSeconds}s '
            '(${_safeCandidateLabel(plan.candidates[index].label)}).',
          );
        }
        return thumbnail;
      }
    }
    return null;
  }

  Future<SeekThumbnail?> request({
    required SeekThumbnailPlan plan,
    required PlayerBackend backend,
    required Duration position,
    required Duration duration,
  }) async {
    if (_disposed || plan.candidates.isEmpty) return null;
    final Duration bucket = quantizeSeekThumbnailPosition(
      position,
      duration: duration,
    );
    final String requestKey = '${plan.sessionKey}|${bucket.inMilliseconds}';
    final Future<SeekThumbnail?>? existing = _inFlight[requestKey];
    if (existing != null) {
      if (kDebugMode) {
        debugPrint('SeekPreview: coalesced @ ${bucket.inSeconds}s.');
      }
      return existing;
    }

    late final Future<SeekThumbnail?> pending;
    pending = _extractFromCandidates(plan, backend, bucket, duration)
        .whenComplete(() {
          if (identical(_inFlight[requestKey], pending)) {
            _inFlight.remove(requestKey);
          }
        });
    _inFlight[requestKey] = pending;
    return pending;
  }

  Future<SeekThumbnail?> _extractFromCandidates(
    SeekThumbnailPlan plan,
    PlayerBackend backend,
    Duration bucket,
    Duration duration,
  ) async {
    await activate(plan, backend);
    if (_disposed ||
        _activeContextKey != '${backend.name}|${plan.sessionKey}') {
      return null;
    }
    final SeekThumbnailExtractor? extractor = _extractor;
    if (extractor == null) return null;

    for (final int index in _candidateOrder(plan)) {
      final SeekThumbnailSource candidate = plan.candidates[index];
      final SeekThumbnailCacheKey cacheKey = SeekThumbnailCacheKey(
        sourceKey: candidate.sourceKey,
        bucket: bucket,
      );
      final SeekThumbnail? cached = _cache.remove(cacheKey);
      if (cached != null) {
        _cache[cacheKey] = cached;
        if (kDebugMode) {
          debugPrint(
            'SeekPreview: cache hit @ ${bucket.inSeconds}s '
            '(${_safeCandidateLabel(candidate.label)}).',
          );
        }
        return cached;
      }

      if (kDebugMode) {
        debugPrint(
          'SeekPreview: cache miss @ ${bucket.inSeconds}s; '
          'trying ${index + 1}/${plan.candidates.length} '
          '(${_safeCandidateLabel(candidate.label)}).',
        );
      }
      SeekThumbnail? thumbnail;
      try {
        thumbnail = await extractor
            .extract(
              source: candidate.source,
              position: bucket,
              duration: duration,
              sourceKey: candidate.decoderKey,
            )
            .timeout(extractionTimeout);
      } on TimeoutException {
        if (kDebugMode) {
          debugPrint(
            'SeekPreview: candidate ${index + 1} timed out after '
            '${extractionTimeout.inMilliseconds}ms.',
          );
        }
        thumbnail = null;
      } on Object {
        thumbnail = null;
      }
      if (thumbnail == null || thumbnail.bytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('SeekPreview: candidate ${index + 1} failed; fallback.');
        }
        continue;
      }

      _successfulCandidateBySession[plan.sessionKey] = index;
      _put(cacheKey, thumbnail);
      if (kDebugMode) {
        debugPrint(
          'SeekPreview: frame ready @ ${bucket.inSeconds}s '
          '(${thumbnail.width}x${thumbnail.height}).',
        );
      }
      return thumbnail;
    }
    return null;
  }

  List<int> _candidateOrder(SeekThumbnailPlan plan) {
    if (plan.candidates.isEmpty) return const <int>[];
    final int start = (_successfulCandidateBySession[plan.sessionKey] ?? 0)
        .clamp(0, plan.candidates.length - 1)
        .toInt();
    return <int>[
      for (int index = start; index < plan.candidates.length; index++) index,
    ];
  }

  void _put(SeekThumbnailCacheKey key, SeekThumbnail thumbnail) {
    final SeekThumbnail? replaced = _cache.remove(key);
    if (replaced != null) _cacheBytes -= replaced.bytes.length;
    _cache[key] = thumbnail;
    _cacheBytes += thumbnail.bytes.length;

    while (_cache.isNotEmpty &&
        (_cache.length > maxCacheEntries || _cacheBytes > maxCacheBytes)) {
      final SeekThumbnailCacheKey oldest = _cache.keys.first;
      final SeekThumbnail removed = _cache.remove(oldest)!;
      _cacheBytes -= removed.bytes.length;
    }
  }

  Future<void> reset() async {
    if (_disposed) return;
    _desiredContextKey = null;
    await _activation;
    final SeekThumbnailExtractor? extractor = _extractor;
    _extractor = null;
    _activeContextKey = null;
    if (extractor != null) {
      try {
        await extractor.dispose();
      } on Object {
        // A superseded native extraction may already have released the player.
      }
    }
    _inFlight.clear();
    _cache.clear();
    _cacheBytes = 0;
    _successfulCandidateBySession.clear();
    if (kDebugMode) debugPrint('SeekPreview: cache and decoder reset.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _desiredContextKey = null;
    await _activation;
    final SeekThumbnailExtractor? extractor = _extractor;
    _extractor = null;
    _activeContextKey = null;
    if (extractor != null) {
      try {
        await extractor.dispose();
      } on Object {
        // Native resources may already be gone during application teardown.
      }
    }
    _inFlight.clear();
    _cache.clear();
    _cacheBytes = 0;
    _successfulCandidateBySession.clear();
    if (kDebugMode) debugPrint('SeekPreview: service disposed.');
  }
}

String _safeCandidateLabel(String value) {
  final String compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  final String lower = compact.toLowerCase();
  if (compact.contains('://') ||
      lower.contains('bearer ') ||
      lower.contains('cookie=')) {
    return '<redacted quality>';
  }
  return compact.length <= 48 ? compact : '${compact.substring(0, 48)}…';
}
