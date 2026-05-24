import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;

/// Call once in main(), before creating any VideoPlayerController.
/// Stable defaults for VOD HLS streams.
void configureMiruShinFvp() {
  // Player-side buffer: keep a small minimum buffer and a larger forward buffer.
  // This reduces random HLS stalls/skips after pause/resume or CDN jitter.
  mdk.setGlobalOption('buffer.range', '3000+60000');

  // Enable demux packet cache for HTTP/HTTPS. This helps seeking and prevents
  // already-downloaded packet ranges from being downloaded again.
  mdk.setGlobalOption('demux.buffer.protocols', 'http,https');
  mdk.setGlobalOption('demux.buffer.ranges', '8');

  // Let demux survive short network/CDN read errors instead of jumping forward.
  mdk.setGlobalOption('demux.max_errors', '64');
  mdk.setGlobalOption('demuxer.max_errors', '64');

  fvp.registerWith(
    options: {
      'platforms': ['macos', 'windows', 'linux'],

      // Important for your case: VOD anime HLS should not run in low-latency mode.
      // Low latency can reduce useful buffering and make pause/resume less stable.
      'lowLatency': 0,

      // Keep accurate seeks. Do not use fastSeek for anime/VOD HLS.
      'fastSeek': false,

      // Stable Apple path first, software fallback second.
      'video.decoders': ['VT', 'FFmpeg'],

      // Same options through registerWith backend maps as an extra safety net.
      'global': {
        'buffer.range': '3000+60000',
        'demux.buffer.protocols': 'http,https',
        'demux.buffer.ranges': '8',
        'demux.max_errors': '64',
        'demuxer.max_errors': '64',
      },
      'player': {
        'buffer': '3000+60000',
        'buffer.range': '3000+60000',
        'demux.buffer.protocols': 'http,https',
        'demux.buffer.ranges': '8',
        'demux.max_errors': '64',
      },
    },
  );
}
