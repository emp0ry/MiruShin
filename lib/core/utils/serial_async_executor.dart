import 'dart:async';

/// Runs asynchronous operations in submission order without poisoning later
/// work when one operation fails.
class SerialAsyncExecutor {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final Completer<T> result = Completer<T>();
    final Future<void> previous = _tail;

    _tail = () async {
      try {
        await previous;
      } on Object {
        // A failed caller must not prevent the next queued operation.
      }

      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    }();

    return result.future;
  }
}
