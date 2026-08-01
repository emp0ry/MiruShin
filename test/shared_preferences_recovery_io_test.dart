import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/persistence/shared_preferences_recovery_io.dart';
import 'package:path/path.dart' as p;

void main() {
  test('quarantines the desktop JSON instead of deleting it', () async {
    final Directory supportDirectory = await Directory.systemTemp.createTemp(
      'mirushin_preferences_recovery.',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));
    final File preferencesFile = File(
      p.join(supportDirectory.path, 'shared_preferences.json'),
    );
    const String corruptContents = '<not-json>';
    await preferencesFile.writeAsString(corruptContents, flush: true);

    final File? quarantinedFile = await quarantineSharedPreferencesFile(
      supportDirectory,
      currentTime: DateTime.utc(2026, 8, 1, 12, 34, 56),
    );

    expect(await preferencesFile.exists(), isFalse);
    expect(quarantinedFile, isNotNull);
    expect(
      p.basename(quarantinedFile!.path),
      'shared_preferences.corrupt-20260801123456000.json',
    );
    expect(await quarantinedFile.readAsString(), corruptContents);
  });

  test('does nothing when no desktop preferences file exists', () async {
    final Directory supportDirectory = await Directory.systemTemp.createTemp(
      'mirushin_preferences_recovery.',
    );
    addTearDown(() => supportDirectory.delete(recursive: true));

    expect(await quarantineSharedPreferencesFile(supportDirectory), isNull);
  });
}
