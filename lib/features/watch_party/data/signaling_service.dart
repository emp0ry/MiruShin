import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/auth_worker_proof.dart';

/// Thin client over the mirushin-auth Worker's `/watch-party/*` routes. The
/// Worker only brokers the WebRTC handshake (offer / answer / ICE candidates)
/// and stores it briefly with a TTL; no video ever flows through it.
class SignalingService {
  SignalingService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConstants.watchPartyBaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
              headers: <String, String>{'content-type': 'application/json'},
              // Never throw on an HTTP status (including 5xx): each method
              // inspects the status itself and degrades gracefully. Only genuine
              // transport errors (no network / timeout) surface as DioException.
              validateStatus: (int? status) => status != null && status < 600,
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          options.headers.addAll(AuthWorkerProof.headers());
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  /// Creates a room from the host SDP offer and returns the room code.
  Future<String> createRoom(Map<String, dynamic> offer) async {
    final Response<dynamic> res = await _dio.post<dynamic>(
      '/rooms',
      data: <String, dynamic>{'offer': offer},
    );
    final Object? data = res.data;
    if (res.statusCode == 200 && data is Map && data['code'] is String) {
      return data['code'] as String;
    }
    throw SignalingException('Failed to create room (${res.statusCode}).');
  }

  /// Fetches the host offer for [code], or null if the room is gone/expired.
  Future<Map<String, dynamic>?> fetchOffer(String code) async {
    final Response<dynamic> res = await _dio.get<dynamic>('/rooms/$code');
    final Object? data = res.data;
    if (res.statusCode == 200 && data is Map && data['offer'] is Map) {
      return Map<String, dynamic>.from(data['offer'] as Map);
    }
    return null;
  }

  Future<void> postAnswer(String code, Map<String, dynamic> answer) async {
    final Response<dynamic> res = await _dio.post<dynamic>(
      '/rooms/$code/answer',
      data: <String, dynamic>{'answer': answer},
    );
    final int status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw SignalingException('Failed to send answer ($status).');
    }
  }

  /// Fetches the guest answer, or null while none has been posted yet.
  Future<Map<String, dynamic>?> fetchAnswer(
    String code, {
    bool wait = false,
  }) async {
    final Response<dynamic> res = await _dio.get<dynamic>(
      '/rooms/$code/answer',
      queryParameters: wait ? <String, String>{'wait': '1'} : null,
    );
    final Object? data = res.data;
    if (res.statusCode == 200 && data is Map && data['answer'] is Map) {
      return Map<String, dynamic>.from(data['answer'] as Map);
    }
    return null;
  }

  /// Best-effort ICE trickle: candidates are retried as the connection settles,
  /// so a single failed post (transport error or transient 5xx) is swallowed
  /// rather than thrown — it must never crash the app from a fire-and-forget call.
  Future<void> postCandidate(
    String code,
    String role,
    Map<String, dynamic> candidate,
  ) async {
    try {
      await _dio.post<dynamic>(
        '/rooms/$code/candidates',
        data: <String, dynamic>{'role': role, 'candidate': candidate},
      );
    } on DioException {
      // Ignore; ICE gathering produces multiple candidates and the connection
      // can still succeed without every one of them being relayed.
    }
  }

  /// Fetches all candidates posted by [forRole] (the *other* peer).
  Future<List<Map<String, dynamic>>> fetchCandidates(
    String code,
    String forRole,
  ) async {
    final Response<dynamic> res = await _dio.get<dynamic>(
      '/rooms/$code/candidates',
      queryParameters: <String, String>{'for': forRole},
    );
    final Object? data = res.data;
    if (res.statusCode == 200 && data is Map && data['candidates'] is List) {
      return (data['candidates'] as List)
          .whereType<Map>()
          .map((Map m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> deleteRoom(String code) async {
    try {
      await _dio.delete<dynamic>('/rooms/$code');
    } on DioException {
      // Best-effort cleanup; the room also self-expires via KV TTL.
    }
  }
}

class SignalingException implements Exception {
  const SignalingException(this.message);
  final String message;

  @override
  String toString() => message;
}
