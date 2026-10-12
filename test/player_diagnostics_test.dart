import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/diagnostics/player_diagnostics.dart';
import 'package:mirushin/features/player/domain/player_models.dart';

void main() {
  test('event payloads have bounded sizes and cannot break JSON with NaN', () {
    final recorder = PlayerDiagnostics();
    recorder.setEnabled(true);
    addTearDown(() => recorder.setEnabled(false));
    recorder.record('payload', {
      for (int i = 0; i < 100; i++) 'field$i': 'x' * 10000,
      'nan': double.nan,
      'inf': double.infinity,
    });
    final data =
        (jsonDecode(recorder.report())['events'] as List).last['data'] as Map;
    expect(data.length, lessThanOrEqualTo(24));
    expect(
      data.values.every((value) => value is String && value.length <= 256),
      isTrue,
    );
    recorder.record('numbers', {'nan': double.nan, 'inf': double.infinity});
    expect(
      (jsonDecode(recorder.report())['events'] as List).last['data'],
      isEmpty,
    );
    recorder.record('https://cdn.invalid/private?token=abc');
    expect(recorder.report(), isNot(contains('cdn.invalid')));
  });
  test(
    'diagnostic toggle does not alter playback options or Auto Progress',
    () {
      const settings = PlayerSettings();
      final enabled = settings.copyWith(diagnosticsEnabled: true).toJson()
        ..remove('diagnosticsEnabled');
      final original = settings.toJson()..remove('diagnosticsEnabled');
      expect(enabled, original);
    },
  );

  test(
    'raw native EOF/buffering transitions are retained even if presentation suppresses them',
    () {
      final recorder = PlayerDiagnostics();
      recorder.setEnabled(true);
      addTearDown(() => recorder.setEnabled(false));
      recorder.nativeTransition('fvp', 'end', {'ended': true});
      recorder.nativeTransition('fvp', 'end', {'ended': true});
      recorder.sampleEngine('fvp', {'ended': false, 'playing': true});
      final events = jsonDecode(recorder.report())['events'] as List;
      expect(
        events.where((e) => e['type'] == 'engine.nativeTransition').length,
        1,
      );
      expect(
        events.any(
          (e) =>
              e['type'] == 'engine.nativeTransition' &&
              e['data']['ended'] == true,
        ),
        isTrue,
      );
      expect(
        events.any(
          (e) =>
              e['type'] == 'engine.transition' && e['data']['ended'] == false,
        ),
        isTrue,
      );
    },
  );
  test('disabled by default and backwards compatible settings', () {
    expect(const PlayerSettings().diagnosticsEnabled, isFalse);
    expect(PlayerSettings.fromJson({}).diagnosticsEnabled, isFalse);
    expect(
      PlayerSettings.fromJson(
        const PlayerSettings(diagnosticsEnabled: true).toJson(),
      ).diagnosticsEnabled,
      isTrue,
    );
    final recorder = PlayerDiagnostics();
    recorder.record('ignored');
    recorder.markMicroPause();
    expect(recorder.observing, isFalse);
    expect(jsonDecode(recorder.report())['events'], isEmpty);
  });

  test('bounded ring by time and event count, monotonic durations', () {
    int time = 0;
    final recorder = PlayerDiagnostics(
      capacity: 4,
      retention: const Duration(minutes: 10),
      elapsedMicroseconds: () => time,
    );
    recorder.setEnabled(true);
    addTearDown(() => recorder.setEnabled(false));
    final span = recorder.begin();
    time = 100;
    recorder.finish('checkpoint', span);
    final event = (jsonDecode(recorder.report())['events'] as List).last;
    expect(event['data']['durationUs'], 100);
    for (var i = 0; i < 10; i++) {
      recorder.record('event', {'n': i});
    }
    expect((jsonDecode(recorder.report())['events'] as List).length, 4);
    time = const Duration(minutes: 11).inMicroseconds;
    recorder.markMicroPause();
    expect(
      (jsonDecode(recorder.report())['events'] as List).single['type'],
      'user.microPause',
    );
  });

  test(
    'no URLs, credentials, cookies or nested arbitrary objects in reports',
    () {
      final recorder = PlayerDiagnostics();
      recorder.setEnabled(true);
      addTearDown(() => recorder.setEnabled(false));
      recorder.record('error', {
        'url': 'https://cdn.invalid/private?token=abc',
        'refreshToken': 'private-refresh',
        'cookies': 'session=abc',
        'clientSecret': 'private-client',
        'authorization': 'Bearer abc',
        'failure':
            'Failed https://cdn.invalid/secret?key=abc bearer abc token=xyz',
        'nested': {'private': 'credentials'},
        'backend': 'mpv',
        'positionMs': 10,
      });
      final report = recorder.report();
      for (final secret in [
        'https://',
        'private-refresh',
        'private-client',
        'Bearer abc',
        'token=xyz',
        'cdn.invalid',
        'credentials',
      ]) {
        expect(report, isNot(contains(secret)));
      }
      expect(report, contains('mpv'));
      expect(report, contains('positionMs'));
    },
  );

  test(
    'off detaches observers and stale spans cannot cross diagnostic sessions',
    () {
      final recorder = PlayerDiagnostics();
      recorder.setEnabled(true);
      final oldSpan = recorder.begin();
      expect(recorder.observing, isTrue);
      recorder.setEnabled(false);
      expect(recorder.observing, isFalse);
      final before = recorder.report();
      recorder.sampleEngine('fvp', {'playing': true});
      expect(recorder.report(), before);
      recorder.setEnabled(true);
      recorder.finish('oldSpan', oldSpan);
      expect(recorder.report(), isNot(contains('oldSpan')));
      recorder.setEnabled(false);
    },
  );

  test(
    'MPV/FVP samples identify backend/route and throttle position-only events',
    () {
      int time = 0;
      final recorder = PlayerDiagnostics(elapsedMicroseconds: () => time);
      recorder.setEnabled(true);
      addTearDown(() => recorder.setEnabled(false));
      for (var n = 0; n < 100; n++) {
        recorder.sampleEngine('mpv', {
          'playing': true,
          'route': 'proxy',
          'positionMs': n,
        });
      }
      recorder.sampleEngine('fvp', {'playing': true, 'route': 'direct'});
      time = 250000;
      recorder.sampleEngine('mpv', {
        'playing': true,
        'buffering': true,
        'route': 'proxy',
      });
      final events = jsonDecode(recorder.report())['events'] as List;
      expect(events.where((e) => e['type'] == 'engine.sample').length, 3);
      expect(events.where((e) => e['type'] == 'engine.transition').length, 3);
    },
  );
}
