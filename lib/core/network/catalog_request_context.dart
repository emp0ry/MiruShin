import 'dart:async';

import 'package:dio/dio.dart';

import '../../shared/models/media_item.dart';
import 'request_cancellation_scope.dart';

enum CatalogRequestPriority { background, interactive }

/// One UI operation, with fresh child tokens for each actual HTTP request.
/// The zone keeps existing provider methods and third-party implementations
/// compatible while propagating cancellation through optional enrichment.
class CatalogRequestContext {
  CatalogRequestContext({
    this.priority = CatalogRequestPriority.interactive,
    Duration timeout = const Duration(seconds: 15),
    this.onItemsUpdated,
  }) {
    _timer = Timer(timeout, () => cancel(CatalogRequestTimeout(retryAt)));
  }

  static final Object _zoneKey = Object();
  static const optionsKey = 'mirushin.catalogRequest';
  static CatalogRequestContext? get current =>
      Zone.current[_zoneKey] as CatalogRequestContext?;
  static CatalogRequestContext? fromOptions(RequestOptions options) =>
      options.extra[optionsKey] as CatalogRequestContext?;

  final CatalogRequestPriority priority;
  final void Function(List<MediaItem>)? onItemsUpdated;
  final cancellation = RequestCancellationScope();
  final _cancelled = Completer<void>();
  Timer? _timer;
  int _backgroundCount = 0;
  bool _baseCompleted = false;
  Object? _reason;
  DateTime? retryAt;
  List<MediaItem>? enrichedItems;
  bool get isCancelled => cancellation.isCancelled;

  Future<T> run<T>(Future<T> Function() action) async {
    check();
    try {
      return await runZoned(
        () => Future.any<T>([
          Future<T>.sync(action),
          _cancelled.future.then<T>((_) => throw _reason!),
        ]),
        zoneValues: {_zoneKey: this},
      );
    } finally {
      _baseCompleted = true;
      _finishIfIdle();
    }
  }

  void background(Future<void> Function() task) {
    _backgroundCount++;
    unawaited(
      Future<void>.sync(task).whenComplete(() {
        _backgroundCount--;
        _finishIfIdle();
      }),
    );
  }

  void _finishIfIdle() {
    if (_baseCompleted && _backgroundCount == 0) _timer?.cancel();
  }

  Future<T> request<T>(Future<T> Function(CancelToken) send) =>
      cancellation.run(send);

  void check() {
    if (isCancelled) throw _reason!;
  }

  void waitingUntil(DateTime at) {
    if (at.isAfter(DateTime.now().add(const Duration(seconds: 1)))) {
      retryAt = at;
    }
  }

  void publish(List<MediaItem> items) {
    if (isCancelled) return;
    enrichedItems = items;
    onItemsUpdated?.call(items);
  }

  void cancel([Object? reason]) {
    if (isCancelled) return;
    _reason = reason ?? const CatalogRequestCancelled();
    _timer?.cancel();
    cancellation.cancel(_reason);
    _cancelled.complete();
  }
}

class CatalogRequestCancelled implements Exception {
  const CatalogRequestCancelled();
}

class CatalogRequestTimeout implements Exception {
  const CatalogRequestTimeout(this.retryAt);
  final DateTime? retryAt;
}

Future<Response<T>> catalogGet<T>(
  Dio dio,
  String path, {
  Map<String, dynamic>? queryParameters,
  Options? options,
}) {
  final context = CatalogRequestContext.current;
  Future<Response<T>> send(CancelToken? token) => dio.get<T>(
    path,
    queryParameters: queryParameters,
    options: options,
    cancelToken: token,
  );
  return context == null ? send(null) : context.request(send);
}

Future<Response<T>> catalogPost<T>(
  Dio dio,
  String path, {
  Object? data,
  Map<String, dynamic>? queryParameters,
  Options? options,
}) {
  final context = CatalogRequestContext.current;
  Future<Response<T>> send(CancelToken? token) => dio.post<T>(
    path,
    data: data,
    queryParameters: queryParameters,
    options: options,
    cancelToken: token,
  );
  return context == null ? send(null) : context.request(send);
}
