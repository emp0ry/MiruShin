import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

RandomAccessFile? _singleInstanceLockFile;

Future<bool> acquireMiruShinSingleInstanceLock() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return true;
  }
  if (_singleInstanceLockFile != null) return true;

  RandomAccessFile? lockFile;
  try {
    final Directory supportDirectory = await getApplicationSupportDirectory();
    await supportDirectory.create(recursive: true);
    final File file = File(
      p.join(supportDirectory.path, 'mirushin.instance.lock'),
    );
    lockFile = await file.open(mode: FileMode.append);
    try {
      await lockFile.lock(FileLock.exclusive);
    } on Object catch (error) {
      await lockFile.close();
      debugPrint('MiruShin duplicate instance lock rejected: $error');
      return false;
    }

    _singleInstanceLockFile = lockFile;
    await lockFile.setPosition(0);
    await lockFile.truncate(0);
    await lockFile.writeString('$pid\n');
    await lockFile.flush();
    return true;
  } on Object catch (error, stackTrace) {
    await lockFile?.close();
    debugPrint('MiruShin single-instance lock unavailable: $error');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stackTrace);
    }
    return true;
  }
}
