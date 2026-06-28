import Cocoa
import FlutterMacOS
import MediaPlayer
import AVKit
import WebKit
import webview_flutter_wkwebview

class MainFlutterWindow: NSWindow {
  private static let frameAutosaveName = NSWindow.FrameAutosaveName(
    "MiruShin.MainWindow"
  )
  private var windowChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var webViewChannel: FlutterMethodChannel?
  private var nativeMacPlayerCoordinator: NativeMacPlayerCoordinator?
  private var commandsRegistered = false
  private var lastArtworkUrl = ""
  private var cachedArtwork: NSImage?

  override func awakeFromNib() {
    _ = self.setFrameAutosaveName(Self.frameAutosaveName)
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger

    // Window channel (fullscreen management)
    let wch = FlutterMethodChannel(name: "mirushin/window", binaryMessenger: messenger)
    self.windowChannel = wch
    wch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "isFullscreen":
        result(self.styleMask.contains(.fullScreen))
      case "setFullscreen":
        guard let fullscreen = Self.boolArgument(call.arguments) else {
          result(FlutterError(code: "bad_args", message: "setFullscreen expects a Bool", details: nil))
          return
        }
        DispatchQueue.main.async {
          self.collectionBehavior.insert(.fullScreenPrimary)
          if !self.isKeyWindow { self.makeKeyAndOrderFront(nil) }
          let current = self.styleMask.contains(.fullScreen)
          if fullscreen != current { self.toggleFullScreen(nil) }
          result(fullscreen)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // WebView channel (YouTube trailer fullscreen support)
    let webch = FlutterMethodChannel(name: "mirushin/webview", binaryMessenger: messenger)
    self.webViewChannel = webch
    webch.setMethodCallHandler { call, result in
      switch call.method {
      case "enableElementFullscreen":
        guard let identifier = Self.int64Argument(call.arguments) else {
          result(FlutterError(code: "bad_args", message: "enableElementFullscreen expects a WebView identifier", details: nil))
          return
        }
        DispatchQueue.main.async {
          guard let webView = FWFWebViewFlutterWKWebViewExternalAPI.webView(
            forIdentifier: identifier,
            withPluginRegistry: flutterViewController
          ) else {
            result(false)
            return
          }
          if #available(macOS 12.3, *) {
            webView.configuration.preferences.isElementFullscreenEnabled = true
            result(true)
          } else {
            result(false)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Media session channel (Now Playing + remote commands)
    let mch = FlutterMethodChannel(name: "mirushin/media_session", binaryMessenger: messenger)
    self.mediaChannel = mch
    mch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "updateNowPlaying":
        if let args = call.arguments as? [String: Any] { self.updateNowPlaying(args) }
        result(nil)
      case "clearNowPlaying":
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        self.lastArtworkUrl = ""
        self.cachedArtwork  = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Native player channel (AVPlayerView + PiP handoff for macOS)
    let nch = FlutterMethodChannel(name: "mirushin/native_player", binaryMessenger: messenger)
    self.nativeMacPlayerCoordinator = NativeMacPlayerCoordinator(
      channel: nch,
      parentWindow: self
    )

    super.awakeFromNib()
  }

  // MARK: - Now Playing

  private func updateNowPlaying(_ args: [String: Any]) {
    let title      = args["title"]        as? String ?? ""
    let subtitle   = args["subtitle"]     as? String ?? ""
    let posMs      = args["positionMs"]   as? Double ?? 0
    let durMs      = args["durationMs"]   as? Double ?? 0
    let isPlaying  = args["isPlaying"]    as? Bool   ?? false
    let rate       = args["playbackRate"] as? Double ?? 1.0
    let hasNext    = args["hasNext"]      as? Bool   ?? false
    let artworkUrl = args["artworkUrl"]   as? String ?? ""

    var info: [String: Any] = [
      MPMediaItemPropertyTitle:                    title,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: posMs / 1000.0,
      MPMediaItemPropertyPlaybackDuration:         durMs / 1000.0,
      MPNowPlayingInfoPropertyPlaybackRate:        isPlaying ? rate : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: rate,
    ]
    if !subtitle.isEmpty {
      info[MPMediaItemPropertyArtist] = subtitle
    }
    if let image = cachedArtwork {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
        boundsSize: image.size) { _ in image }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    registerRemoteCommands(hasNext: hasNext)

    if !artworkUrl.isEmpty && artworkUrl != lastArtworkUrl {
      lastArtworkUrl = artworkUrl
      cachedArtwork  = nil
      loadArtwork(from: artworkUrl) { [weak self] image in
        guard let self = self, self.lastArtworkUrl == artworkUrl else { return }
        self.cachedArtwork = image
        if let image = image {
          var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
          updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
            boundsSize: image.size) { _ in image }
          MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
      }
    }
  }

  private func loadArtwork(from urlString: String, completion: @escaping (NSImage?) -> Void) {
    guard let url = URL(string: urlString) else { completion(nil); return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      let image = data.flatMap { NSImage(data: $0) }
      DispatchQueue.main.async { completion(image) }
    }.resume()
  }

  // MARK: - Remote commands

  private func registerRemoteCommands(hasNext: Bool) {
    let center = MPRemoteCommandCenter.shared()
    center.nextTrackCommand.isEnabled = hasNext

    guard !commandsRegistered else { return }
    commandsRegistered = true

    center.playCommand.isEnabled = true
    center.playCommand.addTarget { [weak self] _ in
      self?.mediaChannel?.invokeMethod("play", arguments: nil)
      return .success
    }
    center.pauseCommand.isEnabled = true
    center.pauseCommand.addTarget { [weak self] _ in
      self?.mediaChannel?.invokeMethod("pause", arguments: nil)
      return .success
    }
    center.togglePlayPauseCommand.isEnabled = true
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.mediaChannel?.invokeMethod("togglePlay", arguments: nil)
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      self?.mediaChannel?.invokeMethod("next", arguments: nil)
      return .success
    }
    center.previousTrackCommand.isEnabled = false
    center.changePlaybackPositionCommand.isEnabled = true
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self?.mediaChannel?.invokeMethod("seekTo", arguments: Int(e.positionTime * 1000))
      return .success
    }
  }

  // MARK: - Helpers

  private static func boolArgument(_ value: Any?) -> Bool? {
    if let bool = value as? Bool { return bool }
    if let number = value as? NSNumber { return number.boolValue }
    return nil
  }

  private static func int64Argument(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber { return number.int64Value }
    if let int = value as? Int { return Int64(int) }
    return nil
  }
}

// MARK: - NativeMacPlayerCoordinator
// macOS PiP requires AVPlayerLayer to be in a real, on-screen window with
// content rendered before isPictureInPicturePossible becomes true.
// Strategy: open a small source window off to the side, start playback,
// auto-trigger PiP once possible, then hide the source window.
// If PiP fails to start the source window stays visible as a fallback.

final class NativeMacPlayerCoordinator: NSObject, NSWindowDelegate, AVPictureInPictureControllerDelegate {
  private let channel: FlutterMethodChannel
  private weak var parentWindow: NSWindow?
  private var sourceWindow: NSWindow?
  private var pipController: AVPictureInPictureController?
  private var player: AVPlayer?
  private var endObserver: NSObjectProtocol?
  private var timeObserverToken: Any?
  private var pipPossibleObservation: NSKeyValueObservation?
  private var pipActive           = false
  private var didReachEnd         = false
  private var isCleaningUp        = false  // guards against cleanup re-entry via windowWillClose
  private var pendingSeekMs:      Double? = nil
  private var pendingPlaybackRate: Float  = 0

  init(channel: FlutterMethodChannel, parentWindow: NSWindow) {
    self.channel      = channel
    self.parentWindow = parentWindow
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "present":
        self.handlePresent(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handlePresent(call: FlutterMethodCall, result: FlutterResult) {
    guard sourceWindow == nil else {
      result(FlutterError(code: "ALREADY_ACTIVE", message: "Native player already active", details: nil))
      return
    }
    guard
      let args   = call.arguments as? [String: Any],
      let urlStr = args["url"] as? String,
      let url    = URL(string: urlStr)
    else {
      result(FlutterError(code: "BAD_ARGS", message: "Missing url", details: nil))
      return
    }

    didReachEnd         = false
    pipActive           = false
    pendingSeekMs       = nil
    pendingPlaybackRate = 0

    let posMs           = (args["positionMs"]    as? Double) ?? 0.0
    // AVPlayer caps HTTP streaming playback to 2x; clamp explicitly so the
    // source window and PiP controls never request an unsupported rate.
    let playbackRate    = min(Float((args["playbackRate"] as? Double) ?? 1.0), 2.0)
    let volume          = min(max(Float((args["volume"] as? Double) ?? 1.0), 0.0), 1.0)
    let wasPlaying      = (args["wasPlaying"]    as? Bool)   ?? true
    let title           = (args["title"]         as? String) ?? "MiruShin"
    let headers         = args["headers"]        as? [String: String]
    let openingStartMs  = args["openingStartMs"] as? Double
    let openingEndMs    = args["openingEndMs"]   as? Double
    let endingStartMs   = args["endingStartMs"]  as? Double
    let endingEndMs     = args["endingEndMs"]    as? Double
    let autoSkipOpening = (args["autoSkipOpening"] as? Bool) ?? false
    let autoSkipEnding  = (args["autoSkipEnding"]  as? Bool) ?? false

    // Build AVPlayer
    let assetOptions: [String: Any]? = headers.flatMap { h in
      h.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": h]
    }
    let asset  = assetOptions != nil
      ? AVURLAsset(url: url, options: assetOptions)
      : AVURLAsset(url: url)
    let item   = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    player.volume = volume
    player.isMuted = volume <= 0
    // defaultRate ensures that the PiP native play/pause controls use the
    // user's chosen speed when resuming, instead of hardcoded 1.0x.
    if #available(macOS 13.0, *) {
      player.defaultRate = playbackRate
    }
    self.player = player

    // Small source window: AVPlayerLayer needs a real on-screen window with
    // rendered content before isPictureInPicturePossible becomes true.
    // Position it in the bottom-right so it's briefly visible while buffering.
    let winW: CGFloat = 1
    let winH: CGFloat = 1
    let origin: NSPoint
    if let screen = NSScreen.main {
      let vf = screen.visibleFrame
      origin = NSPoint(x: vf.maxX - winW, y: vf.minY + winH)
    } else {
      origin = .zero
    }
    // Use a single AVPlayerLayer for both display and AVPictureInPictureController.
    // (AVPlayerView.playerLayer was removed from the macOS 26 SDK.)
    let playerLayer = AVPlayerLayer(player: player)
    playerLayer.videoGravity = .resizeAspect

    let hostView = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
    hostView.wantsLayer = true
    hostView.layer = playerLayer

    let win = NSWindow(
      contentRect: NSRect(origin: origin, size: CGSize(width: winW, height: winH)),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    win.title                = title
    win.contentView          = hostView
    win.delegate             = self
    win.isReleasedWhenClosed = false
    win.orderFront(nil)
    self.sourceWindow = win

    // Auto-skip OP/ED periodic observer
    if autoSkipOpening || autoSkipEnding {
      var didSkipOpening = false
      var didSkipEnding  = false
      var seekInFlight   = false
      let token = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
        queue: .main
      ) { [weak player] time in
        guard let player = player, !seekInFlight else { return }
        let ms = CMTimeGetSeconds(time) * 1000.0
        func seekAndResume(toMs target: Double) {
          seekInFlight = true
          let t = CMTime(seconds: target / 1000.0, preferredTimescale: 600)
          let r = player.rate > 0 ? player.rate : playbackRate
          player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            seekInFlight = false
            if r > 0 { player.playImmediately(atRate: r) }
          }
        }
        if autoSkipOpening, let s = openingStartMs, let e = openingEndMs,
           !didSkipOpening, ms >= s && ms < e {
          didSkipOpening = true; seekAndResume(toMs: e)
        }
        if autoSkipEnding, let s = endingStartMs, let e = endingEndMs,
           !didSkipEnding, ms >= s && ms < e {
          didSkipEnding = true; seekAndResume(toMs: e)
        }
      }
      self.timeObserverToken = token
    }

    // End-of-episode notification (2 s tolerance)
    let endObs = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      let posMs2 = CMTimeGetSeconds(player.currentTime()) * 1000.0
      let durMs2 = CMTimeGetSeconds(player.currentItem?.duration ?? .zero) * 1000.0
      if durMs2.isFinite && durMs2 > 0 && posMs2 < durMs2 - 2000.0 { return }
      self.didReachEnd = true
      self.channel.invokeMethod("completed", arguments: [
        "positionMs": posMs2.isFinite ? posMs2 : 0.0,
        "durationMs": durMs2.isFinite ? durMs2 : 0.0,
      ])
      self.cleanup()
    }
    self.endObserver = endObs

    // Store where we want to land once PiP is active.
    pendingSeekMs       = posMs > 0 ? posMs : nil
    pendingPlaybackRate = wasPlaying ? playbackRate : 0

    // Start playing from position 0 at the user's chosen rate so buffering
    // begins immediately and isPictureInPicturePossible becomes true quickly.
    // We seek to the correct position once PiP has started.
    item.preferredForwardBufferDuration = 2
    player.playImmediately(atRate: wasPlaying ? playbackRate : 1.0)

    // Auto-start PiP once the player layer has rendered enough content.
    // Falls back to leaving the source window open if PiP is unavailable.
    if AVPictureInPictureController.isPictureInPictureSupported(),
       let pip = AVPictureInPictureController(playerLayer: playerLayer) {
      pip.delegate = self
      self.pipController = pip

      if pip.isPictureInPicturePossible {
        pip.startPictureInPicture()
      } else {
        let obs: NSKeyValueObservation = pip.observe(
          \.isPictureInPicturePossible, options: [.new]
        ) { [weak self, weak pip] (_: AVPictureInPictureController,
                                   change: NSKeyValueObservedChange<Bool>) in
          guard change.newValue == true, let pip = pip else { return }
          self?.pipPossibleObservation = nil
          DispatchQueue.main.async { pip.startPictureInPicture() }
        }
        pipPossibleObservation = obs
      }
    }
    // If PiP is not supported the source window stays open as a plain player.

    result(nil)
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerWillStartPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    pipActive = true
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    // Seek to the user's actual position now that PiP is running.
    if let seekTarget = pendingSeekMs {
      pendingSeekMs = nil
      let t = CMTime(seconds: seekTarget / 1000.0, preferredTimescale: 600)
      player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        guard let self = self, let player = self.player else { return }
        if self.pendingPlaybackRate > 0 { player.playImmediately(atRate: self.pendingPlaybackRate) }
        else { player.pause() }
        self.pendingPlaybackRate = 0
      }
    }
    // Hide source window — player layer stays alive in the hierarchy while PiP is active.
    sourceWindow?.orderOut(nil)
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    // PiP failed to start — show the source window as a plain player fallback.
    pipActive = false
    sourceWindow?.makeKeyAndOrderFront(nil)
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    pipActive = false
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    if !didReachEnd { sendDismissedAndCleanup() }
    else            { cleanup() }
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    // Expand: bring parent Flutter window to front; PiP then stops -> didStop fires.
    parentWindow?.makeKeyAndOrderFront(nil)
    completionHandler(true)
  }

  // MARK: - NSWindowDelegate (source window closed manually)

  func windowWillClose(_ notification: Notification) {
    // Guard: cleanup() nils sourceWindow before calling close(), so this
    // fires synchronously from within cleanup(). Bail immediately.
    guard !isCleaningUp else { return }
    if !pipActive && !didReachEnd { sendDismissedAndCleanup() }
    else if !pipActive            { cleanup() }
    // If pipActive: PiP keeps running; handle it in the PiP delegate.
  }

  // MARK: - Helpers

  private func sendDismissedAndCleanup() {
    guard !isCleaningUp else { return }
    let wasPlaying = (player?.rate ?? 0) > 0
    player?.pause()
    let posMs = CMTimeGetSeconds(player?.currentTime() ?? .zero) * 1000.0
    let durMs = CMTimeGetSeconds(player?.currentItem?.duration ?? .zero) * 1000.0
    channel.invokeMethod("dismissed", arguments: [
      "positionMs": posMs.isFinite ? posMs : 0.0,
      "durationMs": durMs.isFinite ? durMs : 0.0,
      "wasPlaying": wasPlaying,
    ])
    cleanup()
  }

  private func cleanup() {
    guard !isCleaningUp else { return }
    isCleaningUp = true
    defer { isCleaningUp = false }

    pipPossibleObservation = nil
    if let token = timeObserverToken {
      player?.removeTimeObserver(token)
      timeObserverToken = nil
    }
    if let eo = endObserver {
      NotificationCenter.default.removeObserver(eo)
      endObserver = nil
    }
    player?.pause()
    player = nil

    // Nil pipController before stopping (prevents re-entrant delegate call).
    let pip = pipController
    pipController = nil
    pip?.stopPictureInPicture()

    // Nil sourceWindow before closing (prevents re-entrant windowWillClose).
    let win = sourceWindow
    sourceWindow = nil
    win?.close()

    pipActive           = false
    didReachEnd         = false
    pendingSeekMs       = nil
    pendingPlaybackRate = 0
  }
}
