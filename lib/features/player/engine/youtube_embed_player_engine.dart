import 'dart:async';
import 'dart:io'
    show ContentType, HttpRequest, HttpServer, InternetAddress, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:webview_win_floating/webview_win_floating.dart'
    as desktop_webview;

import 'player_engine.dart';

class YoutubeEmbedPlayerEngine extends PlayerEngine {
  YoutubeEmbedPlayerEngine({
    double? initialAspectRatio,
    bool renderControlsInHtml = false,
  }) : _renderControlsInHtml = renderControlsInHtml,
       _state = ValueNotifier<PlayerEngineState>(
         PlayerEngineState(
           aspectRatio: _usableAspectRatio(initialAspectRatio) ?? 16 / 9,
         ),
       );

  final bool _renderControlsInHtml;

  @override
  bool get rendersOwnTrailerControls => _renderControlsInHtml;

  @override
  Future<void> setHostFullscreen(bool fullscreen) async {
    await _runJavaScript(
      'if (window.mirushinSetFullscreenState) '
      'window.mirushinSetFullscreenState(${fullscreen ? 'true' : 'false'});',
    );
  }

  static const String _embedOrigin = 'https://mirushin.app';
  static const MethodChannel _webViewChannel = MethodChannel(
    'mirushin/webview',
  );

  final ValueNotifier<PlayerEngineState> _state;
  final StreamController<PlayerEngineUiCommand> _uiCommands =
      StreamController<PlayerEngineUiCommand>.broadcast();
  WebViewController? _controller;
  HttpServer? _htmlServer;
  StreamSubscription<HttpRequest>? _htmlServerSub;
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

    final WebViewController controller = await _createController();
    await _enableElementFullscreen(controller);
    _controller = controller;
    final Duration safeStartAt = startAt ?? Duration.zero;
    if (_usesHostedTrailerPage) {
      final Uri pageUri = await _serveTrailerPage((String origin) {
        return _youtubeHtml(
          videoId: videoId,
          startAt: safeStartAt,
          autoplay: autoplay,
          embedOrigin: origin,
        );
      });
      await controller.loadRequest(pageUri);
    } else {
      await _stopHtmlServer();
      await controller.loadHtmlString(
        _youtubeHtml(
          videoId: videoId,
          startAt: safeStartAt,
          autoplay: autoplay,
          embedOrigin: _embedOrigin,
        ),
        baseUrl: _embedOrigin,
      );
    }

    if (_disposed) return;
    _state.value = _state.value.copyWith(
      isInitialized: true,
      hasVideoSurface: true,
      isBuffering: false,
      isPlaying: autoplay,
      aspectRatio: 16 / 9,
    );
  }

  Future<WebViewController> _createController() async {
    if (Platform.isWindows || Platform.isLinux) {
      desktop_webview.WindowsWebViewPlatform.registerWith();
    }

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is desktop_webview.WindowsWebViewPlatform) {
      params = await _desktopCreationParams();
    } else if (WebViewPlatform.instance is WebKitWebViewPlatform) {
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

    if (controller.platform
        is desktop_webview.WindowsPlatformWebViewController) {
      unawaited(
        (controller.platform
                as desktop_webview.WindowsPlatformWebViewController)
            .enableZoom(false),
      );
    }

    return controller;
  }

  Future<PlatformWebViewControllerCreationParams>
  _desktopCreationParams() async {
    String? userDataFolder;
    String? profileName;
    if (Platform.isWindows) {
      final directory = await getApplicationSupportDirectory();
      userDataFolder = p.join(directory.path, 'youtube_trailer_webview');
      profileName = 'MiruShinYoutubeTrailer';
    }
    return desktop_webview.WindowsWebViewControllerCreationParams(
      userDataFolder: userDataFolder,
      profileName: profileName,
      suspendDuringDeactive: false,
    );
  }

  bool get _usesHostedTrailerPage => Platform.isWindows || Platform.isLinux;

  Future<Uri> _serveTrailerPage(String Function(String origin) buildHtml) async {
    await _stopHtmlServer();
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final String origin = 'http://${server.address.address}:${server.port}';
    final String html = buildHtml(origin);
    _htmlServer = server;
    _htmlServerSub = server.listen((HttpRequest request) {
      final String path = request.uri.path;
      if (path == '/favicon.ico') {
        request.response.statusCode = 204;
        unawaited(request.response.close());
        return;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set(
        'Referrer-Policy',
        'strict-origin-when-cross-origin',
      );
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(html);
      unawaited(request.response.close());
    });
    return Uri.parse('$origin/trailer.html');
  }

  Future<void> _stopHtmlServer() async {
    final StreamSubscription<HttpRequest>? sub = _htmlServerSub;
    final HttpServer? server = _htmlServer;
    _htmlServerSub = null;
    _htmlServer = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      await server?.close(force: true);
    } catch (_) {}
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
      hasError: true,
      errorDescription: 'YouTube embedded player error: $code',
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
      case 'exitPlayer':
        _uiCommands.add(PlayerEngineUiCommand.exitPlayer);
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
    await _stopHtmlServer();
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
    required String embedOrigin,
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
        'origin': embedOrigin,
        'widget_referrer': embedOrigin,
      }).toString(),
    );
    final String trailerControlsCss = _renderControlsInHtml
        ? '''
    #mirushinWakeLayer {
      position: fixed;
      inset: 0;
      z-index: 20;
      pointer-events: none;
    }
    .mirushin-trailer-button {
      position: fixed;
      width: 36px;
      height: 36px;
      border: 1px solid rgba(255, 255, 255, 0.24);
      border-radius: 999px;
      background: rgba(0, 0, 0, 0.55);
      color: #fff;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 0;
      z-index: 31;
      cursor: default;
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      opacity: 1;
      transition: opacity 160ms ease;
      appearance: none;
      -webkit-appearance: none;
      box-sizing: border-box;
    }
    .mirushin-trailer-button svg {
      width: 26px;
      height: 26px;
      fill: currentColor;
      pointer-events: none;
    }
    #mirushinBackButton {
      top: 15px;
      left: 29px;
    }
    #mirushinFullscreenButton {
      right: 29px;
      bottom: 85px;
    }
    .mirushin-controls-hidden {
      cursor: none;
    }
    .mirushin-controls-hidden #mirushinWakeLayer {
      pointer-events: auto;
      cursor: none;
    }
    .mirushin-controls-hidden .mirushin-trailer-button {
      opacity: 0;
      pointer-events: none;
    }
    .mirushin-fullscreen-exit-icon {
      display: none;
    }
    body[data-mirushin-fullscreen="1"] .mirushin-fullscreen-enter-icon {
      display: none;
    }
    body[data-mirushin-fullscreen="1"] .mirushin-fullscreen-exit-icon {
      display: block;
    }
'''
        : '';
    final String trailerControlsHtml = _renderControlsInHtml
        ? '''
  <div id="mirushinWakeLayer" aria-hidden="true"></div>
  <button id="mirushinBackButton" class="mirushin-trailer-button" aria-label="Back" type="button">
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M20 11H7.8l5.6-5.6L12 4 4 12l8 8 1.4-1.4L7.8 13H20v-2z"></path>
    </svg>
  </button>
  <button id="mirushinFullscreenButton" class="mirushin-trailer-button" aria-label="Fullscreen" type="button">
    <svg class="mirushin-fullscreen-enter-icon" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M5 5h6v2H7v4H5V5zm8 0h6v6h-2V7h-4V5zM5 13h2v4h4v2H5v-6zm12 0h2v6h-6v-2h4v-4z"></path>
    </svg>
    <svg class="mirushin-fullscreen-exit-icon" viewBox="0 0 24 24" aria-hidden="true">
      <path d="M9 5h2v6H5V9h4V5zm4 0h2v4h4v2h-6V5zM5 13h6v6H9v-4H5v-2zm8 0h6v2h-4v4h-2v-6z"></path>
    </svg>
  </button>
'''
        : '';
    final String trailerControlsJs = _renderControlsInHtml
        ? '''
    var mirushinControlsTimer;
    function mirushinShowControls() {
      document.body.classList.remove('mirushin-controls-hidden');
      mirushinPostCommand('activity');
      window.clearTimeout(mirushinControlsTimer);
      mirushinControlsTimer = window.setTimeout(function() {
        document.body.classList.add('mirushin-controls-hidden');
      }, 4000);
    }
    window.mirushinSetFullscreenState = function(active) {
      document.body.dataset.mirushinFullscreen = active ? '1' : '0';
    };
    function mirushinBindButton(id, command) {
      var button = document.getElementById(id);
      if (!button) return;
      button.addEventListener('click', function(event) {
        event.preventDefault();
        event.stopPropagation();
        mirushinShowControls();
        mirushinPostCommand(command);
      }, true);
      button.addEventListener('pointerdown', function(event) {
        event.stopPropagation();
        mirushinShowControls();
      }, true);
    }
    var wakeLayer = document.getElementById('mirushinWakeLayer');
    if (wakeLayer) {
      wakeLayer.addEventListener('mousemove', mirushinShowControls, true);
      wakeLayer.addEventListener('pointerdown', function(event) {
        event.preventDefault();
        mirushinShowControls();
      }, true);
      wakeLayer.addEventListener('touchstart', function(event) {
        event.preventDefault();
        mirushinShowControls();
      }, true);
    }
    mirushinBindButton('mirushinBackButton', 'exitPlayer');
    mirushinBindButton('mirushinFullscreenButton', 'toggleFullscreen');
    window.addEventListener('mousemove', mirushinShowControls, true);
    window.addEventListener('pointerdown', mirushinShowControls, true);
    document.addEventListener('visibilitychange', mirushinShowControls, true);
    mirushinShowControls();
'''
        : '''
    window.mirushinSetFullscreenState = function(active) {};
''';
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
$trailerControlsCss
  </style>
</head>
<body>
  <iframe
    id="player"
    title="YouTube trailer player"
    type="text/html"
    width="100%"
    height="100%"
    src="$embedUrl"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; fullscreen; gyroscope; picture-in-picture; web-share"
    allowfullscreen
    referrerpolicy="strict-origin-when-cross-origin"></iframe>
$trailerControlsHtml
  <script src="https://www.youtube.com/iframe_api"></script>
  <script>
    var player;
    window.mirushinVolume = ${(_volume * 100).round()};
    window.mirushinPlaybackRate = $_playbackSpeed;
    function mirushinPostCommand(command) {
      mirushinPostToFlutter('MiruShinYoutubeCommand', command);
    }
    function mirushinPostToFlutter(channelName, message) {
      var channel = window[channelName];
      if (!channel) {
        try {
          channel = window.eval(channelName);
        } catch (error) {}
      }
      if (channel && channel.postMessage) {
        channel.postMessage(message);
        return true;
      }
      if (window.chrome &&
          window.chrome.webview &&
          window.chrome.webview.postMessage) {
        window.chrome.webview.postMessage({
          JkChannelName: channelName,
          msg: message
        });
        return true;
      }
      return false;
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
$trailerControlsJs
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
            mirushinPostToFlutter('MiruShinYoutubeState', String(event.data));
          },
          onError: function(event) {
            mirushinPostToFlutter('MiruShinYoutubeError', String(event.data));
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
