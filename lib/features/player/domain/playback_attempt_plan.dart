import 'player_models.dart';

enum PlaybackRoute { localProxy, direct }

class PlaybackAttempt {
  const PlaybackAttempt({required this.backend, required this.route});

  final PlayerBackend backend;
  final PlaybackRoute route;

  bool get disableProxy => route == PlaybackRoute.direct;

  String get label {
    final String backendLabel = backend == PlayerBackend.auto
        ? 'browser'
        : backend.name.toUpperCase();
    final String routeLabel = route == PlaybackRoute.localProxy
        ? 'local proxy'
        : 'direct';
    return '$backendLabel + $routeLabel';
  }
}

/// Whether [url] is downloaded segmented media represented by a local HLS
/// playlist. Downloaded DASH presentations use the same `.m3u8` container, so
/// this intentionally classifies by the stored URL rather than stream type.
bool isLocalSegmentedPlaybackSource(String url) {
  final Uri? uri = Uri.tryParse(url);
  return uri?.scheme.toLowerCase() == 'file' &&
      (uri?.path.toLowerCase().endsWith('.m3u8') ?? false);
}

/// Whether a playback source can use MiruShin's loopback media proxy.
///
/// Local HLS needs this route too: some native backends accept its segments
/// over HTTP but reject the exact same playlist when opened as a `file://` URL.
bool isPlaybackSourceProxyEligible({
  required String url,
  required bool inlineDash,
  required bool usesBrowserBackend,
}) {
  if (usesBrowserBackend) return false;
  final String scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
  return scheme == 'http' ||
      scheme == 'https' ||
      inlineDash ||
      isLocalSegmentedPlaybackSource(url);
}

/// Produces one immutable, deterministic attempt sequence for a stream open.
///
/// Auto prefers MPV and exhausts its proxy/direct routes before trying FVP.
/// An explicitly selected backend stays explicit. If a persisted backend is
/// unavailable on the current platform (MPV on Linux), the available native
/// backend is used instead. Web has one browser-native direct attempt.
List<PlaybackAttempt> buildPlaybackAttemptPlan({
  required PlayerBackend preference,
  required bool mpvAvailable,
  required bool fvpAvailable,
  required bool proxyEligible,
  required bool directEligible,
  bool? mpvProxyEligible,
  bool? mpvDirectEligible,
  bool? fvpProxyEligible,
  bool? fvpDirectEligible,
  bool usesBrowserBackend = false,
}) {
  if (usesBrowserBackend) {
    return const <PlaybackAttempt>[
      PlaybackAttempt(backend: PlayerBackend.auto, route: PlaybackRoute.direct),
    ];
  }

  final List<PlayerBackend> backends = switch (preference) {
    PlayerBackend.auto => <PlayerBackend>[
      if (mpvAvailable) PlayerBackend.mpv,
      if (fvpAvailable) PlayerBackend.fvp,
    ],
    PlayerBackend.mpv => <PlayerBackend>[
      if (mpvAvailable) PlayerBackend.mpv,
      if (!mpvAvailable && fvpAvailable) PlayerBackend.fvp,
    ],
    PlayerBackend.fvp => <PlayerBackend>[
      if (fvpAvailable) PlayerBackend.fvp,
      if (!fvpAvailable && mpvAvailable) PlayerBackend.mpv,
    ],
  };

  return <PlaybackAttempt>[
    for (final PlayerBackend backend in backends) ...<PlaybackAttempt>[
      if (proxyEligible &&
          switch (backend) {
            PlayerBackend.mpv => mpvProxyEligible ?? true,
            PlayerBackend.fvp => fvpProxyEligible ?? true,
            PlayerBackend.auto => true,
          })
        PlaybackAttempt(backend: backend, route: PlaybackRoute.localProxy),
      if (directEligible &&
          switch (backend) {
            PlayerBackend.mpv => mpvDirectEligible ?? true,
            PlayerBackend.fvp => fvpDirectEligible ?? true,
            PlayerBackend.auto => true,
          })
        PlaybackAttempt(backend: backend, route: PlaybackRoute.direct),
    ],
  ];
}
