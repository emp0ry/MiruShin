import 'dart:async';

import '../data/cloudflare_cookie_store.dart';

/// Result of solving a Cloudflare challenge in the interactive WebView.
typedef CloudflareSolveResult = ({String cookies, String userAgent});

/// Presents the interactive challenge WebView and returns the captured cookies,
/// or null if the user cancelled / no solver is available (e.g. on Linux).
typedef CloudflareSolver =
    Future<CloudflareSolveResult?> Function({
      required Uri url,
      required String userAgent,
    });

/// Context-less bridge between the Sora JS runtime (a data-layer service) and
/// the UI that can show a WebView.
///
/// The widget tree registers a [CloudflareSolver] at app start (it pushes the
/// challenge page over the root navigator). The runtime, on detecting a
/// Cloudflare challenge, asks this service to solve it. Concurrent solves for
/// the same host are de-duplicated so only one WebView is ever open at a time.
class CloudflareChallengeService {
  CloudflareChallengeService._();

  static final CloudflareChallengeService instance =
      CloudflareChallengeService._();

  final CloudflareCookieStore cookies = CloudflareCookieStore();

  CloudflareSolver? _solver;
  final Map<String, Future<CloudflareSolveResult?>> _inFlight =
      <String, Future<CloudflareSolveResult?>>{};

  /// Whether an interactive solver is available on this platform.
  bool get canSolve => _solver != null;

  /// Registered by the UI layer (see app bootstrap). Passing null unregisters.
  void registerSolver(CloudflareSolver? solver) => _solver = solver;

  /// Solves the challenge for [url] (interactively if needed), persists the
  /// captured cookies, and returns them. Returns null when there is no solver or
  /// the user cancelled. Solves for the same host share one WebView/Future.
  Future<CloudflareSolveResult?> solve({
    required Uri url,
    required String userAgent,
  }) {
    final CloudflareSolver? solver = _solver;
    if (solver == null) return Future<CloudflareSolveResult?>.value();

    final String host = url.host.toLowerCase();
    final Future<CloudflareSolveResult?>? pending = _inFlight[host];
    if (pending != null) return pending;

    final Future<CloudflareSolveResult?> future = () async {
      try {
        final CloudflareSolveResult? result = await solver(
          url: url,
          userAgent: userAgent,
        );
        if (result != null && result.cookies.trim().isNotEmpty) {
          await cookies.save(url, result.cookies, result.userAgent);
        }
        return result;
      } finally {
        _inFlight.remove(host);
      }
    }();

    _inFlight[host] = future;
    return future;
  }
}
