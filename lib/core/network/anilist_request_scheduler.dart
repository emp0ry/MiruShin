import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' show parseHttpDate;

/// One budget for every AniList client, including unauthenticated enrichment.
/// Only AniList traffic is queued; other providers keep their independent lanes.
class AniListRequestScheduler {
  AniListRequestScheduler({
    this.requestLimit = 28,
    this.window = const Duration(minutes: 1),
    this.minimumSpacing = const Duration(milliseconds: 600),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final shared = AniListRequestScheduler();
  final int requestLimit;
  final Duration window;
  final Duration minimumSpacing;
  final DateTime Function() _now;
  final Queue<DateTime> _starts = Queue();
  Future<void> _tail = Future.value();
  DateTime? _blockedUntil;
  DateTime? _lastStart;
  int? _serverLimit;

  void install(Dio dio) {
    if (dio.interceptors.any((value) => value is _AniListBudgetInterceptor)) {
      return;
    }
    dio.interceptors.add(_AniListBudgetInterceptor(this));
  }

  Future<_Permit> _acquire(CancelToken? token) async {
    final previous = _tail;
    final release = Completer<void>();
    // A cancelled waiter cannot release the next request ahead of its predecessor.
    _tail = previous.then((_) => release.future);
    try {
      await _cancellable(previous, token);
      while (true) {
        if (token?.isCancelled == true) throw token!.cancelError!;
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
        if (!ready.isAfter(now)) {
          _lastStart = now;
          _starts.addLast(now);
          return _Permit(release);
        }
        final wake = Completer<void>();
        final timer = Timer(ready.difference(now), wake.complete);
        try {
          await _cancellable(wake.future, token);
        } finally {
          timer.cancel();
        }
      }
    } catch (_) {
      release.complete();
      rethrow;
    }
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

Future<void> _cancellable(Future<void> future, CancelToken? token) =>
    token == null
    ? future
    : Future.any([future, token.whenCancel.then<void>((error) => throw error)]);

class _Permit {
  _Permit(this.release);
  final Completer<void> release;
  void close() {
    if (!release.isCompleted) release.complete();
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
      options.extra[_permitKey] = await scheduler._acquire(options.cancelToken);
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
