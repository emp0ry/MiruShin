import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'player_engine.dart';

class YoutubeTrailerFallbackPlayerEngine extends PlayerEngine {
  YoutubeTrailerFallbackPlayerEngine({double? initialAspectRatio})
    : _state = ValueNotifier<PlayerEngineState>(
        PlayerEngineState(
          aspectRatio: _usableAspectRatio(initialAspectRatio) ?? 16 / 9,
        ),
      );

  final ValueNotifier<PlayerEngineState> _state;
  String? _url;

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.ondemand_video_rounded,
                  color: Colors.white70,
                  size: 48,
                ),
                const SizedBox(height: 18),
                const Text(
                  'YouTube trailer playback is not available in-app on this platform.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use Android, iOS, or macOS for the embedded YouTube player.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _url == null
                      ? null
                      : () => unawaited(
                          launchUrl(
                            Uri.parse(_url!),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open in YouTube'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    _url = _watchUrlFor(source.url);
    _state.value = _state.value.copyWith(
      isInitialized: true,
      hasVideoSurface: true,
      isBuffering: false,
      isPlaying: false,
      hasError: false,
      clearError: true,
      aspectRatio: 16 / 9,
    );
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _state.value = _state.value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> setVolume(double volume) async {
    _state.value = _state.value.copyWith(
      volume: volume.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  Future<void> dispose() async {
    _state.dispose();
  }

  static double? _usableAspectRatio(double? value) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    return value;
  }

  static String _watchUrlFor(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final String host = uri.host.toLowerCase();
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return Uri.https('www.youtube.com', '/watch', <String, String>{
        'v': uri.pathSegments.first,
      }).toString();
    }
    if (host.endsWith('youtube.com')) {
      if (uri.pathSegments.length >= 2 && uri.pathSegments.first == 'embed') {
        return Uri.https('www.youtube.com', '/watch', <String, String>{
          'v': uri.pathSegments[1],
        }).toString();
      }
      if (uri.queryParameters['v'] != null) return url;
    }
    return url;
  }
}
