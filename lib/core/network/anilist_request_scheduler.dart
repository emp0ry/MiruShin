import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'catalog_request_context.dart';

/// One budget for every AniList client, including unauthenticated enrichment.
/// Only AniList traffic is queued; other providers keep their independent lanes.
class AniListRequestScheduler {
  AniListRequestScheduler({
    this.requestLimit = 28,
    this.window = const Duration(minutes: 1),
    this.minimumSpacing = const Duration(milliseconds: 600),
    this.maxConcurrentRequests = 3,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final shared = AniListRequestScheduler();
  final int requestLimit;
  final Duration window;
  final Duration minimumSpacing;
  final DateTime Function() _now;
  final Queue<DateTime> _starts = Queue();
  final int maxConcurrentRequests;
  final List<_Waiter> _waiting = [];
  Timer? _wake;
  int _active = 0;
  int _activeBackground = 0;
  DateTime? _blockedUntil;
  DateTime? _lastStart;
  int? _serverLimit;

  void install(Dio dio) {
    if (dio.interceptors.any((value) => value is _AniListBudgetInterceptor)) {
      return;
    }
    dio.interceptors.add(_AniListBudgetInterceptor(this));
  }

  Future<_Permit> _acquire(RequestOptions options) {
    final token = options.cancelToken;
    if (token?.isCancelled == true) return Future.error(token!.cancelError!);
    final waiter = _Waiter(options, _now().toUtc());
    _waiting.add(waiter);
    token?.whenCancel.then((error) {
      if (_waiting.remove(waiter)) {
        waiter.result.completeError(error);
        _drain();
      } else {
        // Cancellation may beat onRequest's assignment of the granted permit
        // into RequestOptions. Release here too; close() is idempotent.
        waiter.permit?.close();
      }
    });
    _drain();
    return waiter.result.future;
  }

  void _drain() {
    _wake?.cancel();
    _wake = null;
    if (_waiting.isEmpty || _active >= maxConcurrentRequests) return;
    // Keep a launch slot available for a user search even when two slow
    // background reads are still awaiting their responses.
    final backgroundLimit = maxConcurrentRequests > 1
        ? maxConcurrentRequests - 1
        : 1;
    final eligible = _waiting
        .where(
          (waiter) =>
              waiter.priority > 0 || _activeBackground < backgroundLimit,
        )
        .toList();
    if (eligible.isEmpty) return;
    final now = _now().toUtc();
    while (_starts.isNotEmpty && !now.isBefore(_starts.first.add(window))) {
      _starts.removeFirst();
    }
    DateTime ready = now;
    void waitUntil(DateTime? at) {
      if (at != null && at.isAfter(ready)) ready = at;
    }

    waitUntil(_blockedUntil);
    waitUntil(_lastStart?.add(minimumSpacing));
    final limit = (_serverLimit ?? requestLimit).clamp(1, requestLimit);
    if (_starts.length >= limit) waitUntil(_starts.first.add(window));
    if (ready.isAfter(now)) {
      for (final waiter in _waiting) {
        CatalogRequestContext.fromOptions(waiter.options)?.waitingUntil(ready);
      }
      _wake = Timer(ready.difference(now), _drain);
      return;
    }
    // Age waiting work so continuous foreground searches cannot starve sync.
    _Waiter selected = eligible.first;
    if (now.difference(selected.queuedAt) < const Duration(seconds: 5)) {
      for (final waiter in eligible) {
        if (waiter.priority > selected.priority) selected = waiter;
      }
    }
    _waiting.remove(selected);
    if (selected.options.cancelToken?.isCancelled == true) {
      selected.result.completeError(selected.options.cancelToken!.cancelError!);
    } else {
      _active++;
      final background = selected.priority == 0;
      if (background) _activeBackground++;
      _lastStart = now;
      _starts.addLast(now);
      final permit = _Permit(() {
        _active--;
        if (background) _activeBackground--;
        _drain();
      });
      selected.permit = permit;
      selected.result.complete(permit);
    }
    // Release the launch lane independently of the response lifetime.
    // A microtask also lets a synchronous response publish its rate headers.
    scheduleMicrotask(_drain);
  }

  void _observe(Response<dynamic>? response) {
    if (response == null) return;
    final now = _now().toUtc();
    final headers = response.headers;
    final limit = int.tryParse(headers.value('x-ratelimit-limit') ?? '');
    if (limit != null && limit > 0) _serverLimit = limit;
    final remaining = int.tryParse(
      headers.value('x-ratelimit-remaining') ?? '',
    );
    final body = response.data;
    final errors = body is Map ? body['errors'] : null;
    final limited =
        response.statusCode == 429 ||
        (errors is List &&
            errors.any(
              (error) => error is Map && '${error['status']}' == '429',
            ));
    if (!limited && remaining != 0) return;

    DateTime? until;
    final retry = headers.value('retry-after');
    final seconds = int.tryParse(retry ?? '');
    if (seconds != null) {
      until = now.add(Duration(seconds: seconds.clamp(0, 86400)));
    } else if (retry != null) {
      try {
        until = parseHttpDate(retry).toUtc();
      } on FormatException {
        /* Fall back to the reset header. */
      }
    }
    final reset = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
    if (reset != null) {
      final resetAt = DateTime.fromMillisecondsSinceEpoch(
        (reset * 1000).clamp(
          0,
          now.add(const Duration(days: 1)).millisecondsSinceEpoch,
        ),
        isUtc: true,
      );
      if (until == null || resetAt.isAfter(until)) until = resetAt;
    }
    if (until == null || !until.isAfter(now)) until = now.add(window);
    final maximum = now.add(const Duration(days: 1));
    if (until.isAfter(maximum)) until = maximum;
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) {
      _blockedUntil = until;
    }
  }
}

class _Waiter {
  _Waiter(this.options, this.queuedAt);
  final RequestOptions options;
  final DateTime queuedAt;
  final result = Completer<_Permit>();
  _Permit? permit;
  int get priority =>
      CatalogRequestContext.fromOptions(options)?.priority.index ?? 0;
}

class _Permit {
  _Permit(this.release);
  final void Function() release;
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    release();
  }
}

class _AniListBudgetInterceptor extends Interceptor {
  _AniListBudgetInterceptor(this.scheduler);
  final AniListRequestScheduler scheduler;
  static const _permitKey = 'mirushin.anilist.requestPermit';

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.uri.host != 'graphql.anilist.co') {
      handler.next(options);
      return;
    }
    try {
      options.extra[_permitKey] = await scheduler._acquire(options);
      handler.next(options);
    } catch (error) {
      handler.reject(
        error is DioException
            ? error
            : DioException(requestOptions: options, error: error),
      );
    }
  }

  void _finish(RequestOptions options, Response<dynamic>? response) {
    final permit = options.extra.remove(_permitKey) as _Permit?;
    if (permit == null) return;
    try {
      scheduler._observe(response);
      final blockedUntil = scheduler._blockedUntil;
      if (blockedUntil != null) {
        CatalogRequestContext.fromOptions(options)?.waitingUntil(blockedUntil);
      }
    } finally {
      permit.close();
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _finish(response.requestOptions, response);
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _finish(error.requestOptions, error.response);
    handler.next(error);
  }
}

/// Injected Dio instances own their transport configuration. All default app
/// clients use this factory and therefore share the same server budget.
Dio createAniListDio(BaseOptions options) {
  final dio = Dio(options);
  AniListRequestScheduler.shared.install(dio);
  return dio;
}
