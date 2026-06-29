import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../constants/app_constants.dart';

/// Lightweight proof added to calls that hit the mirushin-auth Worker.
///
/// This is intentionally frictionless for the app and returns 401 for generic
/// unauthenticated scripts. It is not a replacement for Cloudflare WAF/rate
/// limiting because the bundled secret can be extracted from a released app.
abstract final class AuthWorkerProof {
  static const String timestampHeader = 'x-mirushin-timestamp';
  static const String signatureHeader = 'x-mirushin-signature';
  static const String timestampQuery = 'ms_ts';
  static const String signatureQuery = 'ms_sig';

  static Map<String, String> headers() {
    final String timestamp = _timestamp();
    return <String, String>{
      timestampHeader: timestamp,
      signatureHeader: _signature(timestamp),
    };
  }

  static Map<String, String> queryParameters() {
    final String timestamp = _timestamp();
    return <String, String>{
      timestampQuery: timestamp,
      signatureQuery: _signature(timestamp),
    };
  }

  static String _timestamp() {
    return (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  }

  static String _signature(String timestamp) {
    return Hmac(
      sha256,
      utf8.encode(AppConstants.authWorkerProofSecret),
    ).convert(utf8.encode(timestamp)).toString();
  }
}
