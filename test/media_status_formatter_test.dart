import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/shared/utils/media_status_formatter.dart';

void main() {
  test('formats AniList media statuses for display', () {
    expect(humanReadableMediaStatus('NOT_YET_RELEASED'), 'Not Yet Released');
    expect(humanReadableMediaStatus('RELEASING'), 'Releasing');
    expect(humanReadableMediaStatus('HIATUS'), 'On Hiatus');
  });

  test('hides catalog placeholders', () {
    expect(humanReadableMediaStatus('AniList'), isEmpty);
    expect(humanReadableMediaStatus('TMDB'), isEmpty);
  });
}
