import Flutter
import UIKit
import MediaPlayer
import AVFoundation
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mediaChannel: FlutterMethodChannel?
  private var nativePlayerCoordinator: NativePlayerCoordinator?
  private var commandsRegistered = false
  private var lastArtworkUrl = ""
  private var cachedArtwork: UIImage?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Enable background audio + PiP audio continuation.
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: .moviePlayback, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // Non-fatal; FVP configures its own session for normal playback.
    }
    registerAudioObservers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Media session channel (Now Playing + remote commands)
    guard let msReg = engineBridge.pluginRegistry.registrar(forPlugin: "MiruShinMediaSession") else {
      return
    }
    let ch = FlutterMethodChannel(
      name: "mirushin/media_session",
      binaryMessenger: msReg.messenger()
    )
    mediaChannel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handleCall(call, result: result)
    }

    // Native player channel (AVPlayerViewController handoff for iOS PiP)
    guard let npReg = engineBridge.pluginRegistry.registrar(forPlugin: "MiruShinNativePlayer") else {
      return
    }
    let nativeCh = FlutterMethodChannel(
      name: "mirushin/native_player",
      binaryMessenger: npReg.messenger()
    )
    nativePlayerCoordinator = NativePlayerCoordinator(channel: nativeCh, appDelegate: self)
  }

  // MARK: - Media session method handler

  private func handleCall(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "updateNowPlaying":
      if let args = call.arguments as? [String: Any] { updateNowPlaying(args) }
      result(nil)
    case "clearNowPlaying":
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      lastArtworkUrl = ""
      cachedArtwork = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

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

  private func loadArtwork(from urlString: String, completion: @escaping (UIImage?) -> Void) {
    guard let url = URL(string: urlString) else { completion(nil); return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      let image = data.flatMap { UIImage(data: $0) }
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

  // MARK: - Audio route / interruption observers

  private func registerAudioObservers() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(audioRouteChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(audioInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: nil
    )
  }

  @objc private func audioRouteChanged(_ n: Notification) {
    guard
      let info = n.userInfo,
      let raw  = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
    else { return }
    DispatchQueue.main.async {
      self.mediaChannel?.invokeMethod("audioRouteChanged", arguments: true)
    }
  }

  @objc private func audioInterruption(_ n: Notification) {
    guard
      let info = n.userInfo,
      let raw  = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }
    DispatchQueue.main.async {
      self.mediaChannel?.invokeMethod("audioInterruption", arguments: type == .began)
    }
  }
}

// MARK: - MiruShinAVPlayerViewController

final class MiruShinAVPlayerViewController: AVPlayerViewController {
  weak var channel: FlutterMethodChannel?
  var onDismissed: ((MiruShinAVPlayerViewController) -> Void)?
  var pipActive = false
  var didReachEnd = false
  var didSendTerminalEvent = false
  var pipRestoreInFlight = false
  var didRestoreFromPip = false
  var desiredRate: Float = 1.0
  var programmaticSeekInFlight = false

  var statusObserver: NSKeyValueObservation?
  var rateObserver: NSKeyValueObservation?
  var timeObserverToken: Any?
  var endObserver: NSObjectProtocol?

  deinit {
    cleanupForRelease()
  }

  func cleanupForRelease() {
    if let token = timeObserverToken {
      player?.removeTimeObserver(token)
      timeObserverToken = nil
    }
    statusObserver?.invalidate()
    statusObserver = nil
    rateObserver?.invalidate()
    rateObserver = nil
    if let eo = endObserver {
      NotificationCenter.default.removeObserver(eo)
      endObserver = nil
    }
    player?.pause()
    player = nil
    channel = nil
    onDismissed = nil
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // PiP causes a fake dismissal — ignore it.
    if pipActive { return }
    if didReachEnd || didSendTerminalEvent { return }
    let actuallyDismissing = isBeingDismissed || view.window == nil
    guard actuallyDismissing, let player = player else { return }

    let posMs = CMTimeGetSeconds(player.currentTime()) * 1000.0
    let durMs = CMTimeGetSeconds(player.currentItem?.duration ?? .zero) * 1000.0
    didSendTerminalEvent = true
    channel?.invokeMethod("dismissed", arguments: [
      "positionMs": posMs.isFinite ? posMs : 0.0,
      "durationMs": durMs.isFinite ? durMs : 0.0,
      "wasPlaying": player.rate > 0,
    ])
    onDismissed?(self)
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return [.landscapeLeft, .landscapeRight, .portrait]
  }

  override var prefersHomeIndicatorAutoHidden: Bool { true }
}

// MARK: - NativePlayerCoordinator

final class NativePlayerCoordinator: NSObject, AVPlayerViewControllerDelegate {
  private let channel: FlutterMethodChannel
  private weak var appDelegate: AppDelegate?
  private var currentVC: MiruShinAVPlayerViewController?

  init(channel: FlutterMethodChannel, appDelegate: AppDelegate) {
    self.channel = channel
    self.appDelegate = appDelegate
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

  private func rootVC() -> UIViewController? {
    if let win = appDelegate?.window { return win.rootViewController }
    if #available(iOS 15.0, *) {
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.keyWindow?.rootViewController
    }
    return UIApplication.shared.windows.first?.rootViewController
  }

  private func handlePresent(call: FlutterMethodCall, result: FlutterResult) {
    guard currentVC == nil else {
      result(FlutterError(code: "ALREADY_ACTIVE", message: "Native player already active", details: nil))
      return
    }
    guard
      let args    = call.arguments as? [String: Any],
      let urlStr  = args["url"] as? String,
      let url     = URL(string: urlStr),
      let root    = rootVC()
    else {
      result(FlutterError(code: "BAD_ARGS", message: "Missing url or root VC", details: nil))
      return
    }

    let posMs           = (args["positionMs"]    as? Double) ?? 0.0
    let playbackRate    = Float((args["playbackRate"] as? Double) ?? 1.0)
    let volume          = min(max(Float((args["volume"] as? Double) ?? 1.0), 0.0), 1.0)
    let wasPlaying      = (args["wasPlaying"]    as? Bool)   ?? true
    let title           = (args["title"]         as? String) ?? ""
    let headers         = args["headers"]        as? [String: String]
    let openingStartMs  = args["openingStartMs"] as? Double
    let openingEndMs    = args["openingEndMs"]   as? Double
    let endingStartMs   = args["endingStartMs"]  as? Double
    let endingEndMs     = args["endingEndMs"]    as? Double
    let autoSkipOpening = (args["autoSkipOpening"] as? Bool) ?? false
    let autoSkipEnding  = (args["autoSkipEnding"]  as? Bool) ?? false

    // Build asset, injecting HTTP headers when present.
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

    let vc        = MiruShinAVPlayerViewController()
    vc.player     = player
    vc.title      = title
    vc.channel    = channel
    vc.delegate   = self
    vc.modalPresentationStyle = .fullScreen
    vc.allowsPictureInPicturePlayback = true
    if #available(iOS 14.2, *) {
      vc.canStartPictureInPictureAutomaticallyFromInline = true
    }
    vc.entersFullScreenWhenPlaybackBegins = true
    // We handle dismissal ourselves so we control the event timing.
    vc.exitsFullScreenWhenPlaybackEnds = false
    vc.desiredRate = playbackRate
    vc.onDismissed = { [weak self] dismissedVC in
      guard let self = self else { return }
      if let active = self.currentVC, active === dismissedVC {
        self.currentVC = nil
      }
      dismissedVC.cleanupForRelease()
    }
    currentVC = vc

    // Track non-zero rate so skip/stall resume preserves user intent.
    vc.rateObserver = player.observe(\.rate, options: [.new]) { [weak vc] p, _ in
      guard let vc = vc else { return }
      if p.rate > 0 { vc.desiredRate = p.rate }
    }

    // Periodic observer: auto-skip OP/ED with millisecond precision.
    if autoSkipOpening || autoSkipEnding {
      var didSkipOpening = false
      var didSkipEnding  = false
      let token = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
        queue: .main
      ) { [weak vc] time in
        guard let vc = vc, !vc.programmaticSeekInFlight else { return }
        let ms = CMTimeGetSeconds(time) * 1000.0

        func seekAndResume(toMs target: Double) {
          vc.programmaticSeekInFlight = true
          let t = CMTime(seconds: target / 1000.0, preferredTimescale: 600)
          let r = (vc.player?.rate ?? 0) > 0 ? (vc.player?.rate ?? vc.desiredRate) : vc.desiredRate
          vc.player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            vc.programmaticSeekInFlight = false
            if r > 0 { vc.player?.playImmediately(atRate: r) }
          }
        }

        if autoSkipOpening, let s = openingStartMs, let e = openingEndMs,
           !didSkipOpening, ms >= s && ms < e {
          didSkipOpening = true
          seekAndResume(toMs: e)
        }
        if autoSkipEnding, let s = endingStartMs, let e = endingEndMs,
           !didSkipEnding, ms >= s && ms < e {
          didSkipEnding = true
          seekAndResume(toMs: e)
        }
      }
      vc.timeObserverToken = token
    }

    // End-of-episode notification (2 s tolerance to avoid false triggers).
    let endObs = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self, weak vc] _ in
      guard let self = self, let vc = vc else { return }
      let posMs2 = CMTimeGetSeconds(player.currentTime()) * 1000.0
      let durMs2 = CMTimeGetSeconds(player.currentItem?.duration ?? .zero) * 1000.0
      // Ignore spurious end signals that fire well before the real end.
      if durMs2.isFinite && durMs2 > 0 && posMs2 < durMs2 - 2000.0 { return }
      vc.didReachEnd = true
      vc.didSendTerminalEvent = true
      self.channel.invokeMethod("completed", arguments: [
        "positionMs": posMs2.isFinite ? posMs2 : 0.0,
        "durationMs": durMs2.isFinite ? durMs2 : 0.0,
      ])
      self.currentVC = nil
      if vc.presentingViewController != nil {
        vc.dismiss(animated: true)
      }
    }
    vc.endObserver = endObs

    // Present and seek/play once the item is ready.
    root.present(vc, animated: true) { [weak vc] in
      guard let vc = vc else { return }

      let startPlayback = { [weak vc] in
        guard let vc = vc else { return }
        if posMs > 0 {
          vc.programmaticSeekInFlight = true
          player.seek(
            to: CMTime(seconds: posMs / 1000.0, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
          ) { _ in
            vc.programmaticSeekInFlight = false
            if wasPlaying { player.playImmediately(atRate: playbackRate) }
          }
        } else {
          if wasPlaying { player.playImmediately(atRate: playbackRate) }
        }
      }

      if item.status == .readyToPlay {
        startPlayback()
      } else {
        vc.statusObserver = item.observe(\.status, options: [.new]) { _, _ in
          if item.status == .readyToPlay {
            DispatchQueue.main.async {
              startPlayback()
              vc.statusObserver?.invalidate()
              vc.statusObserver = nil
            }
          }
        }
      }
    }

    result(nil)
  }

  // MARK: - AVPlayerViewControllerDelegate (PiP lifecycle)

  func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
    _ playerViewController: AVPlayerViewController
  ) -> Bool {
    if let vc = playerViewController as? MiruShinAVPlayerViewController {
      vc.pipActive = true
      vc.didRestoreFromPip = false
    }
    return true
  }

  func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
    if let vc = playerViewController as? MiruShinAVPlayerViewController {
      vc.pipActive = true
      vc.didRestoreFromPip = false
    }
  }

  func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
    if let vc = playerViewController as? MiruShinAVPlayerViewController {
      vc.pipActive = true
      vc.didRestoreFromPip = false
    }
  }

  func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
    (playerViewController as? MiruShinAVPlayerViewController)?.pipActive = false
  }

  func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
    guard let vc = playerViewController as? MiruShinAVPlayerViewController else { return }
    vc.pipActive = false

    // Re-arm PiP so it can be started AGAIN after returning to fullscreen.
    // After the first auto-dismiss + re-present cycle AVPlayerViewController
    // leaves its internal PiP controller stale, so the PiP button silently
    // stops working on the second attempt unless we toggle the capability off
    // and back on. Only do this when the player is still on screen (a restore),
    // never when PiP was simply closed.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak vc] in
      guard let vc = vc, vc.player != nil, vc.presentingViewController != nil else { return }
      vc.allowsPictureInPicturePlayback = false
      DispatchQueue.main.async {
        guard vc.player != nil, vc.presentingViewController != nil else { return }
        vc.allowsPictureInPicturePlayback = true
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, vc] in
      guard let self = self else { return }
      if vc.didReachEnd || vc.didSendTerminalEvent || vc.pipRestoreInFlight || vc.didRestoreFromPip { return }
      self.emitDismissed(vc, wasPlaying: false, pause: true)
      vc.cleanupForRelease()
    }
  }

  // Restore native player UI when user exits PiP (unless episode already ended).
  func playerViewController(
    _ playerViewController: AVPlayerViewController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    guard let vc = playerViewController as? MiruShinAVPlayerViewController else {
      completionHandler(false); return
    }
    // Don't re-present if the episode already completed during PiP.
    if vc.didReachEnd || vc.didSendTerminalEvent { completionHandler(true); return }
    // Already on screen — nothing to do.
    if vc.presentingViewController != nil {
      vc.didRestoreFromPip = true
      completionHandler(true)
      return
    }

    guard let root = rootVC() else { completionHandler(false); return }

    vc.pipRestoreInFlight = true
    root.present(vc, animated: true) { [weak self] in
      guard let self = self else { return }
      let posMs = CMTimeGetSeconds(vc.player?.currentTime() ?? .zero) * 1000.0
      let durMs = CMTimeGetSeconds(vc.player?.currentItem?.duration ?? .zero) * 1000.0
      self.channel.invokeMethod("pipRestored", arguments: [
        "positionMs": posMs.isFinite ? posMs : 0.0,
        "durationMs": durMs.isFinite ? durMs : 0.0,
      ])
      vc.didRestoreFromPip = true
      vc.pipRestoreInFlight = false
      completionHandler(true)
    }
  }

  private func emitDismissed(
    _ vc: MiruShinAVPlayerViewController,
    wasPlaying: Bool,
    pause: Bool
  ) {
    guard !vc.didReachEnd && !vc.didSendTerminalEvent else { return }
    if pause { vc.player?.pause() }
    let posMs = CMTimeGetSeconds(vc.player?.currentTime() ?? .zero) * 1000.0
    let durMs = CMTimeGetSeconds(vc.player?.currentItem?.duration ?? .zero) * 1000.0
    vc.didSendTerminalEvent = true
    channel.invokeMethod("dismissed", arguments: [
      "positionMs": posMs.isFinite ? posMs : 0.0,
      "durationMs": durMs.isFinite ? durMs : 0.0,
      "wasPlaying": wasPlaying,
    ])
    if let active = currentVC, active === vc {
      currentVC = nil
    }
  }
}
