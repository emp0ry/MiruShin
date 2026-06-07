import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'player_engine.dart';

class YoutubeEmbedPlayerEngine extends PlayerEngine {
  YoutubeEmbedPlayerEngine({double? initialAspectRatio})
    : _state = ValueNotifier<PlayerEngineState>(
        PlayerEngineState(
          aspectRatio: _usableAspectRatio(initialAspectRatio) ?? 16 / 9,
        ),
      );

  static const String _embedOrigin = 'https://mirushin.app';
  static const MethodChannel _webViewChannel = MethodChannel(
    'mirushin/webview',
  );

  final ValueNotifier<PlayerEngineState> _state;
  final StreamController<PlayerEngineUiCommand> _uiCommands =
      StreamController<PlayerEngineUiCommand>.broadcast();
  WebViewController? _controller;
  bool _disposed = false;
  double _volume = 1;
  double _playbackSpeed = 1;

  @override
  ValueListenable<PlayerEngineState> get state => _state;

  @override
  Stream<PlayerEngineUiCommand> get uiCommands => _uiCommands.stream;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Widget buildVideoSurface(BuildContext context) {
    final WebViewController? controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return ColoredBox(
      color: const Color(0xFF000000),
      child: WebViewWidget(controller: controller),
    );
  }

  @override
  Future<void> open(
    PlayerSource source, {
    Duration? startAt,
    bool autoplay = true,
  }) async {
    final String videoId = _youtubeVideoId(source.url);
    if (videoId.isEmpty) {
      throw const FormatException('Invalid YouTube trailer URL.');
    }

    _disposed = false;
    _state.value = _state.value.copyWith(
      isBuffering: true,
      isInitialized: false,
      hasVideoSurface: false,
      hasError: false,
      clearError: true,
    );

    final WebViewController controller = _createController();
    await _enableElementFullscreen(controller);
    _controller = controller;
    await controller.loadHtmlString(
      _youtubeHtml(
        videoId: videoId,
        startAt: startAt ?? Duration.zero,
        autoplay: autoplay,
      ),
      baseUrl: _embedOrigin,
    );

    if (_disposed) return;
    _state.value = _state.value.copyWith(
      isInitialized: true,
      hasVideoSurface: true,
      isBuffering: false,
      isPlaying: autoplay,
      aspectRatio: 16 / 9,
    );
  }

  WebViewController _createController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..addJavaScriptChannel(
            'MiruShinYoutubeState',
            onMessageReceived: (JavaScriptMessage message) {
              _handleYoutubeState(message.message);
            },
          )
          ..addJavaScriptChannel(
            'MiruShinYoutubeError',
            onMessageReceived: (JavaScriptMessage message) {
              _handleYoutubeError(message.message);
            },
          )
          ..addJavaScriptChannel(
            'MiruShinYoutubeCommand',
            onMessageReceived: (JavaScriptMessage message) {
              _handleYoutubeCommand(message.message);
            },
          );

    if (controller.platform is AndroidWebViewController) {
      unawaited(
        (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false),
      );
    }

    return controller;
  }

  Future<void> _enableElementFullscreen(WebViewController controller) async {
    final Object platform = controller.platform;
    if (platform is! WebKitWebViewController) return;
    try {
      await _webViewChannel.invokeMethod<bool>(
        'enableElementFullscreen',
        platform.webViewIdentifier,
      );
    } on MissingPluginException {
      // Non-macOS WebKit hosts can still use the inline YouTube player.
    } on PlatformException catch (error) {
      debugPrint('YouTube WebView fullscreen setup failed: $error');
    }
  }

  void _handleYoutubeState(String raw) {
    if (_disposed) return;
    final int state = int.tryParse(raw.trim()) ?? -1;
    _state.value = _state.value.copyWith(
      isInitialized: true,
      hasVideoSurface: true,
      isPlaying: state == 1,
      isBuffering: state == 3,
      hasError: false,
      clearError: true,
    );
  }

  void _handleYoutubeError(String raw) {
    if (_disposed) return;
    final String code = raw.trim();
    debugPrint('YouTube embedded player error: $code');
    _state.value = _state.value.copyWith(
      isBuffering: false,
      isPlaying: false,
      hasError: false,
      clearError: true,
    );
  }

  void _handleYoutubeCommand(String raw) {
    if (_disposed || _uiCommands.isClosed) return;
    switch (raw.trim()) {
      case 'activity':
        _uiCommands.add(PlayerEngineUiCommand.showControls);
        break;
      case 'toggleFullscreen':
        _uiCommands.add(PlayerEngineUiCommand.toggleFullscreen);
        break;
      case 'exitFullscreen':
        _uiCommands.add(PlayerEngineUiCommand.exitFullscreen);
        break;
    }
  }

  @override
  Future<void> play() async {
    _state.value = _state.value.copyWith(isPlaying: true);
    await _runPlayerCommand('playVideo()');
  }

  @override
  Future<void> pause() async {
    _state.value = _state.value.copyWith(isPlaying: false);
    await _runPlayerCommand('pauseVideo()');
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _runPlayerCommand('seekTo(${position.inSeconds}, true)');
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    _state.value = _state.value.copyWith(playbackSpeed: speed);
    await _runJavaScript('''
      window.mirushinPlaybackRate = $speed;
      if (window.player && window.player.setPlaybackRate) {
        window.player.setPlaybackRate($speed);
      }
    ''');
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    _state.value = _state.value.copyWith(volume: _volume);
    final int playerVolume = (_volume * 100).round();
    await _runJavaScript('''
      window.mirushinVolume = $playerVolume;
      if (window.player && window.player.setVolume) {
        window.player.setVolume($playerVolume);
      }
    ''');
  }

  Future<void> _runPlayerCommand(String command) async {
    await _runJavaScript('''
      if (window.player) {
        window.player.$command;
      }
    ''');
  }

  Future<void> _runJavaScript(String script) async {
    final WebViewController? controller = _controller;
    if (controller == null || _disposed) return;
    try {
      await controller.runJavaScript(script);
    } catch (_) {
      // The iframe API may still be loading; the embedded player remains usable.
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final WebViewController? controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.runJavaScript(
          'if (window.player && window.player.stopVideo) window.player.stopVideo();',
        );
      } catch (_) {}
      try {
        await controller.loadHtmlString('<html><body></body></html>');
      } catch (_) {}
    }
    await _uiCommands.close();
    _state.dispose();
  }

  static String _youtubeVideoId(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return '';

    final String host = uri.host.toLowerCase();
    if (host == 'youtu.be') {
      return uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    }
    if (host.endsWith('youtube.com')) {
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'embed') {
        return uri.pathSegments.length >= 2 ? uri.pathSegments[1] : '';
      }
      return uri.queryParameters['v'] ?? '';
    }
    return '';
  }

  String _youtubeHtml({
    required String videoId,
    required Duration startAt,
    required bool autoplay,
  }) {
    final int start = startAt.inSeconds;
    final int autoplayFlag = autoplay ? 1 : 0;
    final String embedUrl = _htmlAttribute(
      Uri.https('www.youtube.com', '/embed/$videoId', <String, String>{
        'autoplay': '$autoplayFlag',
        'controls': '1',
        'disablekb': '1',
        'enablejsapi': '1',
        'fs': '0',
        'playsinline': '1',
        'rel': '0',
        'start': '$start',
        'origin': _embedOrigin,
        'widget_referrer': _embedOrigin,
      }).toString(),
    );
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    html, body, #player {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: #000;
    }
    iframe {
      display: block;
      border: 0;
    }
  </style>
</head>
<body>
  <iframe
    id="player"
    type="text/html"
    width="100%"
    height="100%"
    src="$embedUrl"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
    referrerpolicy="strict-origin-when-cross-origin"></iframe>
  <script src="https://www.youtube.com/iframe_api"></script>
  <script>
    var player;
    window.mirushinVolume = ${(_volume * 100).round()};
    window.mirushinPlaybackRate = $_playbackSpeed;
    function mirushinPostCommand(command) {
      if (window.MiruShinYoutubeCommand &&
          window.MiruShinYoutubeCommand.postMessage) {
        window.MiruShinYoutubeCommand.postMessage(command);
      }
    }
    function mirushinHandleKey(event) {
      if (event.defaultPrevented || event.repeat) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      var key = String(event.key || '').toLowerCase();
      if (key === 'f') {
        event.preventDefault();
        event.stopPropagation();
        mirushinPostCommand('toggleFullscreen');
        return false;
      }
      if (key === 'escape' || key === 'esc') {
        event.preventDefault();
        event.stopPropagation();
        mirushinPostCommand('exitFullscreen');
        return false;
      }
    }
    window.addEventListener('keydown', mirushinHandleKey, true);
    document.addEventListener('keydown', mirushinHandleKey, true);
    window.addEventListener('mousemove', function() {
      mirushinPostCommand('activity');
    }, { passive: true });
    window.addEventListener('pointerdown', function() {
      mirushinPostCommand('activity');
    }, true);
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        events: {
          onReady: function(event) {
            event.target.setVolume(window.mirushinVolume || 100);
            event.target.setPlaybackRate(window.mirushinPlaybackRate || 1);
            if ($autoplayFlag === 1) {
              event.target.playVideo();
            }
          },
          onStateChange: function(event) {
            MiruShinYoutubeState.postMessage(String(event.data));
          },
          onError: function(event) {
            MiruShinYoutubeError.postMessage(String(event.data));
          }
        }
      });
    }
  </script>
</body>
</html>
''';
  }

  static String _htmlAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static double? _usableAspectRatio(double? value) {
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    return value;
  }
}
