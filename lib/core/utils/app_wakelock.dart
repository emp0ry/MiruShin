import 'package:wakelock_plus/wakelock_plus.dart';

class AppWakelock {
  AppWakelock._();

  static final Set<Object> _owners = Set<Object>.identity();
  static Future<void> _pendingOperation = Future<void>.value();

  static Future<void> acquire(Object owner) {
    _owners.add(owner);
    return _sync();
  }

  static Future<void> release(Object owner) {
    _owners.remove(owner);
    return _sync();
  }

  static Future<void> reassert() {
    if (_owners.isEmpty) return Future<void>.value();
    return _sync();
  }

  static Future<void> _sync() {
    _pendingOperation = _pendingOperation.then((_) async {
      try {
        if (_owners.isEmpty) {
          await WakelockPlus.disable();
        } else {
          await WakelockPlus.enable();
        }
      } on Object {
        // The platform channel may be unavailable during app shutdown.
      }
    });
    return _pendingOperation;
  }
}
