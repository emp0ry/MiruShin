import 'package:dio/dio.dart';

/// Cancels active requests without retaining already completed responses.
///
/// A long-lived Dio CancelToken keeps every listener attached to whenCancel
/// until it is cancelled. Dio's listeners can retain the entire response and
/// its decoded JSON. Never share a lifetime token across successive requests:
/// keep only the active, independently cancellable tokens in this scope.
class RequestCancellationScope {
  RequestCancellationScope();

  /// A single weak listener bridges a lifecycle token to active requests.
  /// The lifecycle token itself is never passed to Dio, so it cannot retain
  /// the decoded responses from earlier requests in a long sync pass.
  factory RequestCancellationScope.linkedTo(CancelToken parent) {
    final existing = _parents[parent];
    if (existing != null) {
      if (parent.isCancelled) existing.cancel(parent.cancelError?.error);
      return existing;
    }
    final scope = RequestCancellationScope();
    _parents[parent] = scope;
    if (parent.isCancelled) {
      scope.cancel(parent.cancelError?.error);
    } else {
      parent.whenCancel.then(_forwardScopeCancellation(WeakReference(scope)));
    }
    return scope;
  }

  static final _parents = Expando<RequestCancellationScope>();
  final Set<CancelToken> _active = <CancelToken>{};
  bool _cancelled = false;
  Object? _reason;

  bool get isCancelled => _cancelled;
  int get activeRequestCount => _active.length;

  Future<T> run<T>(Future<T> Function(CancelToken token) request) async {
    final token = CancelToken();
    if (_cancelled) {
      token.cancel(_reason);
      throw token.cancelError!;
    }
    _active.add(token);
    try {
      return await request(token);
    } finally {
      // Do not cancel a successful request: the response is already complete,
      // and aborting it could unnecessarily discard a keep-alive connection.
      // Removing its only scope reference makes the listener cycle collectible.
      _active.remove(token);
    }
  }

  void cancel([Object? reason]) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    for (final token in _active.toList(growable: false)) {
      token.cancel(reason);
    }
    _active.clear();
  }
}

// Keep this closure context separate from any request/response async state.
void Function(DioException) _forwardScopeCancellation(
  WeakReference<RequestCancellationScope> target,
) =>
    (error) => target.target?.cancel(error.error);
