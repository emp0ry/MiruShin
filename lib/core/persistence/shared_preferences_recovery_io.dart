import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _preferencesFileName = 'shared_preferences.json';

Future<bool> quarantineCorruptPreferences() async {
  if (!Platform.isLinux && !Platform.isWindows) return false;

  try {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    final File? quarantinedFile = await quarantineSharedPreferencesFile(
      supportDirectory,
    );
    if (quarantinedFile == null) return false;
    debugPrint(
      'Quarantined corrupt SharedPreferences file: ${quarantinedFile.path}',
    );
    return true;
  } on Object catch (error, stackTrace) {
    debugPrint('Unable to quarantine corrupt SharedPreferences: $error');
    if (kDebugMode) {
      debugPrint(stackTrace.toString());
    }
    return false;
  }
}

@visibleForTesting
Future<File?> quarantineSharedPreferencesFile(
  Directory supportDirectory, {
  DateTime? currentTime,
}) async {
  final File preferencesFile = File(
    p.join(supportDirectory.path, _preferencesFileName),
  );
  if (!await preferencesFile.exists()) return null;

  final String timestamp = (currentTime ?? DateTime.now())
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '');
  return preferencesFile.rename(
    p.join(supportDirectory.path, 'shared_preferences.corrupt-$timestamp.json'),
  );
}
