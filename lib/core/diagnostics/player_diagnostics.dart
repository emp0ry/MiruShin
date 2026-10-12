import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class PlayerDiagnosticEvent {
  const PlayerDiagnosticEvent(this.elapsedUs, this.type, this.data);
  final int elapsedUs;
  final String type;
  final Map<String, Object?> data;
  Map<String, Object?> toJson() => {
    'elapsedUs': elapsedUs,
    'type': type,
    'data': data,
  };
}

/// Opt-in, memory-only observations. This recorder has no player control,
/// networking or persistence dependencies and never uploads to Drive.
class PlayerDiagnosticSpan {
  const PlayerDiagnosticSpan(this.elapsedUs, this.generation);
  final int elapsedUs;
  final int generation;
}

class PlayerDiagnostics {
  PlayerDiagnostics({
    this.capacity = 6000,
    this.retention = const Duration(minutes: 10),
    int Function()? elapsedMicroseconds,
  }) : _testClock = elapsedMicroseconds;
  static final instance = PlayerDiagnostics();
  static final _sensitiveKey = RegExp(
    r'url|uri|token|cookie|secret|credential|authorization|email',
    caseSensitive: false,
  );
  static final _url = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://[^\s]+');
  static final _secretAssignment = RegExp(
    r'(bearer\s+|(?:token|secret|cookie|key)=)[^\s&]+',
    caseSensitive: false,
  );
  static final _eventType = RegExp(r'[^a-zA-Z0-9._-]');
  final int capacity;
  final Duration retention;
  final _clock = Stopwatch();
  final int Function()? _testClock;
  int get _now => _testClock?.call() ?? _clock.elapsedMicroseconds;
  int _generation = 0;
  final _events = Queue<PlayerDiagnosticEvent>();
  final Map<String, int> _lastSamples = {};
  final Map<String, String> _lastTransitions = {};
  Timer? _timer;
  SchedulerBinding? _binding;
  int _lastTick = 0;
  int _lastFrameReport = 0;
  int _frames = 0;
  int _maxBuildUs = 0;
  int _maxRasterUs = 0;
  bool _enabled = false;
  bool get enabled => _enabled;
  PlayerDiagnosticSpan? begin() =>
      enabled ? PlayerDiagnosticSpan(_now, _generation) : null;
  bool get observing => _timer != null;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _binding?.removeTimingsCallback(_onFrames);
    _binding = null;
    _lastSamples.clear();
    _lastTransitions.clear();
    if (!value) {
      _clock.stop();
      return;
    }
    _events.clear();
    _clock.reset();
    _clock.start();
    _lastTick = 0;
    _lastFrameReport = 0;
    _frames = _maxBuildUs = _maxRasterUs = 0;
    // Pure recorder tests may not create a Flutter binding.
    try {
      _binding = SchedulerBinding.instance;
    } on Object {
      _binding = null;
    }
    _binding?.addTimingsCallback(_onFrames);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = _now;
      final delay = now - _lastTick - 250000;
      if (delay > 50000) record('dart.timerDelay', {'delayUs': delay});
      _lastTick = now;
      if (now - _lastFrameReport >= 1000000) {
        record('flutter.frames', {
          'count': _frames,
          'maxBuildUs': _maxBuildUs,
          'maxRasterUs': _maxRasterUs,
        });
        _frames = _maxBuildUs = _maxRasterUs = 0;
        _lastFrameReport = now;
      }
    });
    record('diagnostics.started', {
      'version': 1,
      'platform': defaultTargetPlatform.name,
      'web': kIsWeb,
    });
  }

  void _onFrames(List<FrameTiming> timings) {
    if (!enabled) return;
    for (final timing in timings) {
      _frames++;
      if (timing.buildDuration.inMicroseconds > _maxBuildUs) {
        _maxBuildUs = timing.buildDuration.inMicroseconds;
      }
      if (timing.rasterDuration.inMicroseconds > _maxRasterUs) {
        _maxRasterUs = timing.rasterDuration.inMicroseconds;
      }
    }
  }

  void record(String type, [Map<String, Object?> data = const {}]) {
    if (!enabled) return;
    final safe = <String, Object?>{};
    for (final entry in data.entries.take(24)) {
      if (entry.key.length > 64 || _sensitiveKey.hasMatch(entry.key)) {
        continue;
      }
      final value = entry.value;
      if (value is String) {
        final redacted = value
            .replaceAll(_url, '[redacted]')
            .replaceAll(_secretAssignment, '[redacted]');
        safe[entry.key] = redacted.length > 256
            ? redacted.substring(0, 256)
            : redacted;
      } else if (value == null ||
          value is bool ||
          (value is num && value.isFinite)) {
        safe[entry.key] = value;
      }
    }
    final now = _now;
    final eventType = type
        .replaceAll(_url, '[redacted]')
        .replaceAll(_secretAssignment, '[redacted]')
        .replaceAll(_eventType, '_');
    _events.add(
      PlayerDiagnosticEvent(
        now,
        eventType.substring(0, eventType.length.clamp(0, 64)),
        Map.unmodifiable(safe),
      ),
    );
    while (_events.isNotEmpty &&
        (now - _events.first.elapsedUs > retention.inMicroseconds ||
            _events.length > capacity)) {
      _events.removeFirst();
    }
  }

  void finish(
    String type,
    PlayerDiagnosticSpan? started, [
    Map<String, Object?> data = const {},
  ]) {
    if (started != null && enabled && started.generation == _generation) {
      record(type, {...data, 'durationUs': _now - started.elapsedUs});
    }
  }

  void sampleEngine(String backend, Map<String, Object?> values) {
    if (!enabled) return;
    final now = _now;
    final transition =
        '${values['playing']}|${values['buffering']}|${values['ended']}|${values['error']}';
    if (_lastTransitions[backend] != transition) {
      _lastTransitions[backend] = transition;
      record('engine.transition', {'backend': backend, ...values});
    }
    if (now - (_lastSamples[backend] ?? -250000) >= 250000) {
      _lastSamples[backend] = now;
      record('engine.sample', {'backend': backend, ...values});
    }
  }

  void markMicroPause() => record('user.microPause');

  void nativeTransition(
    String backend,
    String signature,
    Map<String, Object?> data,
  ) {
    if (!enabled || _lastTransitions['native:$backend'] == signature) return;
    _lastTransitions['native:$backend'] = signature;
    record('engine.nativeTransition', {'backend': backend, ...data});
  }

  String report() {
    final now = _now;
    while (_events.isNotEmpty &&
        now - _events.first.elapsedUs > retention.inMicroseconds) {
      _events.removeFirst();
    }
    return jsonEncode({
      'schemaVersion': 1,
      'events': _events.map((e) => e.toJson()).toList(),
    });
  }
}
