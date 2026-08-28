import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/player_models.dart';
import 'player_engine.dart';

const Duration defaultSeekThumbnailInterval = Duration(seconds: 5);
const Duration progressiveSeekThumbnailTargetInterval = Duration(seconds: 6);

/// Produces whole-timeline preview targets breadth-first.
///
/// The first pass covers 0%, 20%, ... 100%. Every later pass bisects all gaps
/// that are still wider than [targetInterval]. Targets that land in the same
/// decoder bucket are emitted once, and completion is based on the distance
/// between the actual decoder buckets rather than only the ideal percentages.
Iterable<Duration> progressiveSeekThumbnailPositions(
  Duration duration, {
  Duration targetInterval = progressiveSeekThumbnailTargetInterval,
}) sync* {
  final int durationMs = duration.inMilliseconds;
  final int targetMs = targetInterval.inMilliseconds;
  if (durationMs <= 0) return;
  if (targetMs <= 0) {
    throw ArgumentError.value(
      targetInterval,
      'targetInterval',
      'Must be positive.',
    );
  }

  final List<int> positions = <int>[
    for (int index = 0; index <= 5; index++) (durationMs * index / 5).round(),
  ];
  final Set<int> emittedBuckets = <int>{};

  Iterable<Duration> uniqueTargets(Iterable<int> values) sync* {
    for (final int value in values) {
      final Duration target = Duration(milliseconds: value);
      final int bucket = quantizeSeekThumbnailPosition(
        target,
        duration: duration,
      ).inMilliseconds;
      if (emittedBuckets.add(bucket)) yield target;
    }
  }

  yield* uniqueTargets(positions);
  while (true) {
    final List<int> midpoints = <int>[];
    for (int index = 0; index < positions.length - 1; index++) {
      final int start = positions[index];
      final int end = positions[index + 1];
      final int startBucket = quantizeSeekThumbnailPosition(
        Duration(milliseconds: start),
        duration: duration,
      ).inMilliseconds;
      final int endBucket = quantizeSeekThumbnailPosition(
        Duration(milliseconds: end),
        duration: duration,
      ).inMilliseconds;
      if (endBucket - startBucket <= targetMs) continue;
      final int midpoint = start + ((end - start) ~/ 2);
      if (midpoint > start && midpoint < end) midpoints.add(midpoint);
    }
    if (midpoints.isEmpty) return;
    yield* uniqueTargets(midpoints);
    positions
      ..addAll(midpoints)
      ..sort();
  }
}

bool shouldProgressivelyGenerateSeekThumbnails({
  required SeekPreviewMode mode,
  required SeekThumbnailPlan plan,
}) {
  return mode == SeekPreviewMode.progressive &&
      !plan.isOffline &&
      plan.candidates.isNotEmpty;
}

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

enum SeekThumbnailSourceKind {
  localFile,
  localHls,
  networkFile,
  networkHls,
  networkDash,
  networkUnknown,
  networkDirect,
  unknown,
}

class SeekThumbnailSource {
  const SeekThumbnailSource({
    required this.source,
    required this.sourceKey,
    required this.decoderKey,
    required this.label,
    required this.isOffline,
    this.kind = SeekThumbnailSourceKind.unknown,
    this.declaredStreamType,
    this.inspectMasterPlaylist = false,
  });

  final PlayerSource source;
  final String sourceKey;
  final String decoderKey;
  final String label;
  final bool isOffline;
  final SeekThumbnailSourceKind kind;
  final StreamType? declaredStreamType;

  /// True only when the URL may still be a master playlist. Explicit quality
  /// URLs are already renditions and must not incur a redundant master fetch.
  final bool inspectMasterPlaylist;
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

enum SeekThumbnailFailureScope {
  cancelled,
  bucketSpecific,
  transient,
  permanentSource,
}

enum SeekThumbnailFailureReason {
  cancelled,
  timeout,
  network,
  networkTimeout,
  httpStatus,
  httpNotFound,
  httpForbidden,
  noVideoTrack,
  notHlsPlaylist,
  hlsParseFailure,
  invalidPlaylist,
  unsupportedCodec,
  unsupportedEncryption,
  missingRandomAccessContext,
  rangeUnsupported,
  rangeProbeRejected,
  plainProbeRejected,
  libavOpenFailure,
  libavSeekFailure,
  libavNoFrame,
  decodeFailure,
  unavailable,
  unknown,
}

class SeekThumbnailFailure {
  const SeekThumbnailFailure({required this.scope, required this.reason});

  final SeekThumbnailFailureScope scope;
  final SeekThumbnailFailureReason reason;
}

class SeekThumbnailExtractionResult {
  const SeekThumbnailExtractionResult.success(this.thumbnail) : failure = null;

  const SeekThumbnailExtractionResult.failure(this.failure) : thumbnail = null;

  final SeekThumbnail? thumbnail;
  final SeekThumbnailFailure? failure;

  bool get isSuccess => thumbnail != null;
}

abstract interface class SeekThumbnailExtractor {
  Future<void> warm(SeekThumbnailSource source);

  void cancelPending();

  Future<SeekThumbnailExtractionResult> extract({
    required SeekThumbnailSource source,
    required Duration position,
    required Duration duration,
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
    this.extractionTimeout = const Duration(milliseconds: 1300),
    this.onlineRequestTimeout = const Duration(milliseconds: 3200),
    this.offlineRequestTimeout = const Duration(milliseconds: 900),
  }) : _extractorFactory = extractorFactory;

  final SeekThumbnailExtractorFactory _extractorFactory;
  final int maxCacheBytes;
  final int maxCacheEntries;
  final Duration extractionTimeout;
  final Duration onlineRequestTimeout;
  final Duration offlineRequestTimeout;

  final LinkedHashMap<SeekThumbnailCacheKey, SeekThumbnail> _cache =
      LinkedHashMap<SeekThumbnailCacheKey, SeekThumbnail>();
  final Map<String, Future<SeekThumbnail?>> _inFlight =
      <String, Future<SeekThumbnail?>>{};
  final Map<String, Map<String, _SeekThumbnailSourceHealth>> _sourceHealth =
      <String, Map<String, _SeekThumbnailSourceHealth>>{};

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

  SeekThumbnail? nearestCachedFor(
    SeekThumbnailPlan plan,
    Duration position, {
    Duration duration = Duration.zero,
    Duration maxDistance = const Duration(seconds: 15),
  }) {
    final Duration bucket = quantizeSeekThumbnailPosition(
      position,
      duration: duration,
    );
    SeekThumbnailCacheKey? nearestKey;
    SeekThumbnail? nearest;
    int nearestDistance = maxDistance.inMilliseconds + 1;
    final Set<String> sourceKeys = <String>{
      for (final SeekThumbnailSource source in plan.candidates)
        source.sourceKey,
    };
    for (final MapEntry<SeekThumbnailCacheKey, SeekThumbnail> entry
        in _cache.entries) {
      if (!sourceKeys.contains(entry.key.sourceKey)) continue;
      final int distance =
          (entry.key.bucket.inMilliseconds - bucket.inMilliseconds).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestKey = entry.key;
        nearest = entry.value;
      }
    }
    if (nearestKey != null && nearest != null) {
      _cache.remove(nearestKey);
      _cache[nearestKey] = nearest;
    }
    return nearest;
  }

  Future<void> warm(SeekThumbnailPlan plan, PlayerBackend backend) async {
    if (_disposed || plan.candidates.isEmpty) return;
    await activate(plan, backend);
    if (_disposed ||
        _activeContextKey != '${backend.name}|${plan.sessionKey}') {
      return;
    }
    try {
      await _extractor?.warm(plan.candidates.first);
    } on Object {
      // Warmup is opportunistic; the first real request can retry preparation.
    }
  }

  void cancelPending() {
    _extractor?.cancelPending();
    // A replacement interactive request must not coalesce with work that was
    // just cancelled by the progressive background scheduler.
    _inFlight.clear();
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
    final Stopwatch stopwatch = Stopwatch()..start();

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
      final Duration totalBudget = plan.isOffline
          ? offlineRequestTimeout
          : onlineRequestTimeout;
      final Duration elapsed = stopwatch.elapsed;
      final Duration remaining = totalBudget - elapsed;
      if (remaining <= Duration.zero) {
        if (kDebugMode) {
          debugPrint(
            'SeekPreview: bucket=${bucket.inSeconds} result=total-timeout.',
          );
        }
        break;
      }
      final Duration candidateBudget = remaining < extractionTimeout
          ? remaining
          : extractionTimeout;
      SeekThumbnailExtractionResult extraction;
      try {
        extraction = await extractor
            .extract(source: candidate, position: bucket, duration: duration)
            .timeout(
              candidateBudget,
              onTimeout: () {
                extractor.cancelPending();
                return const SeekThumbnailExtractionResult.failure(
                  SeekThumbnailFailure(
                    scope: SeekThumbnailFailureScope.transient,
                    reason: SeekThumbnailFailureReason.timeout,
                  ),
                );
              },
            );
      } on TimeoutException {
        extraction = const SeekThumbnailExtractionResult.failure(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.transient,
            reason: SeekThumbnailFailureReason.timeout,
          ),
        );
      } on Object {
        extraction = const SeekThumbnailExtractionResult.failure(
          SeekThumbnailFailure(
            scope: SeekThumbnailFailureScope.transient,
            reason: SeekThumbnailFailureReason.unknown,
          ),
        );
      }
      final SeekThumbnail? thumbnail = extraction.thumbnail;
      if (thumbnail == null || thumbnail.bytes.isEmpty) {
        final SeekThumbnailFailure failure =
            extraction.failure ??
            const SeekThumbnailFailure(
              scope: SeekThumbnailFailureScope.bucketSpecific,
              reason: SeekThumbnailFailureReason.decodeFailure,
            );
        _recordFailure(plan, candidate, bucket, failure);
        if (kDebugMode) {
          debugPrint(
            'SeekPreview: bucket=${bucket.inSeconds} '
            'quality=${_safeCandidateLabel(candidate.label)} '
            'result=${failure.reason.name} scope=${failure.scope.name}.',
          );
        }
        continue;
      }

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
    final Map<String, _SeekThumbnailSourceHealth>? health =
        _sourceHealth[plan.sessionKey];
    return <int>[
      for (int index = 0; index < plan.candidates.length; index++)
        if (!(health?[plan.candidates[index].sourceKey]?.hardFailed ?? false))
          index,
    ];
  }

  void _recordFailure(
    SeekThumbnailPlan plan,
    SeekThumbnailSource source,
    Duration bucket,
    SeekThumbnailFailure failure,
  ) {
    if (failure.scope == SeekThumbnailFailureScope.cancelled ||
        failure.scope == SeekThumbnailFailureScope.bucketSpecific ||
        (failure.scope == SeekThumbnailFailureScope.transient &&
            failure.reason != SeekThumbnailFailureReason.httpNotFound)) {
      return;
    }
    final _SeekThumbnailSourceHealth health = _sourceHealth
        .putIfAbsent(
          plan.sessionKey,
          () => <String, _SeekThumbnailSourceHealth>{},
        )
        .putIfAbsent(source.sourceKey, _SeekThumbnailSourceHealth.new);
    if (failure.scope == SeekThumbnailFailureScope.permanentSource) {
      health.hardFailed = true;
      return;
    }
    if (failure.reason == SeekThumbnailFailureReason.httpNotFound) {
      health.notFoundBuckets.add(bucket.inMilliseconds);
      // A single missing object may be one bad segment. Require separate
      // buckets to independently confirm that the rendition itself is gone.
      if (health.notFoundBuckets.length >= 2) health.hardFailed = true;
    }
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
    _sourceHealth.clear();
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
    _sourceHealth.clear();
    if (kDebugMode) debugPrint('SeekPreview: service disposed.');
  }
}

class _SeekThumbnailSourceHealth {
  bool hardFailed = false;
  final Set<int> notFoundBuckets = <int>{};
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
