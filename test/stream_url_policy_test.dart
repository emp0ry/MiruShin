import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/stream_url_policy.dart';

void main() {
  test('signed playback URLs are redacted in diagnostics', () {
    const String signed =
        'https://cdn.example/video?token=private&urls=127.0.0.2';
    final String diagnostic = mediaUrlForLog(signed);

    expect(diagnostic, 'https://cdn.example/<redacted>');
    expect(diagnostic, isNot(contains('private')));
    expect(diagnostic, isNot(contains('127.0.0.2')));
  });

  test('native open errors do not expose signed URL parameters', () {
    const String error =
        'Failed to open https://cdn.example/video?token=private&urls=127.0.0.2';
    final String diagnostic = redactMediaUrlsInText(error);

    expect(diagnostic, 'Failed to open https://cdn.example/<redacted>');
    expect(diagnostic, isNot(contains('private')));
  });
}
