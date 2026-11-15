import Cocoa

/// Own-window fullscreen only. No private APIs, screen capture, or system
/// modifications are needed to draw beside the camera housing.
final class PlayerFullscreenController {
  enum Mode { case windowed, system, edgeToEdge }
  struct State {
    let mode: Mode
    let safeInsets: NSEdgeInsets
    var fullscreen: Bool { mode != .windowed }
    var dictionary: [String: Any] {
      [
        "fullscreen": fullscreen,
        "edgeToEdge": mode == .edgeToEdge,
        "top": Double(safeInsets.top), "left": Double(safeInsets.left),
        "bottom": Double(safeInsets.bottom), "right": Double(safeInsets.right),
      ]
    }
  }
  enum Failure: Error, Equatable { case transitionFailed, windowClosed }
  typealias Completion = (Result<State, Failure>) -> Void
  private struct Request {
    let mode: Mode
    var completions: [Completion]
  }
  private struct SavedWindow {
    let frame: NSRect
    let screenID: Int?
    let style: NSWindow.StyleMask
    let collection: NSWindow.CollectionBehavior
    let level: NSWindow.Level
    let shadow: Bool
    let movable: Bool
    let autosave: NSWindow.FrameAutosaveName
    let presentation: NSApplication.PresentationOptions
  }

  private weak var window: NSWindow?
  private let toggleNative: () -> Void
  private let onChange: (State) -> Void
  private var systemFullscreen: Bool
  private var nativeTransition: Bool?
  private var requestedNativeTransition: Bool?
  private var requests: [Request] = []
  private var sessionID: String?
  private var edgeToEdgeEnabled = false
  private var saved: SavedWindow?
  private var displayID: Int?
  private var updatingFrame = false
  private var observers: [NSObjectProtocol] = []
  private var closed = false

  init(window: NSWindow, toggleNative: @escaping () -> Void,
       onChange: @escaping (State) -> Void) {
    self.window = window
    self.toggleNative = toggleNative
    self.onChange = onChange
    systemFullscreen = window.styleMask.contains(.fullScreen)
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil, queue: .main
    ) { [weak self] _ in self?.updateScreen() })
    observers.append(center.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil, queue: .main
    ) { [weak self] _ in self?.close() })
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  var isEdgeToEdge: Bool { saved != nil }
  var hasPlayerSession: Bool { sessionID != nil }
  var mode: Mode { isEdgeToEdge ? .edgeToEdge : systemFullscreen ? .system : .windowed }
  var pendingFullscreen: Bool {
    if let request = requests.last { return request.mode != .windowed }
    return state.fullscreen
  }
  var state: State {
    var insets = NSEdgeInsetsZero
    if isEdgeToEdge, #available(macOS 12.0, *), let screen = fullscreenScreen {
      insets = screen.safeAreaInsets
    }
    return State(mode: mode, safeInsets: insets)
  }

  func configure(session: String, enabled: Bool, completion: @escaping Completion) {
    guard !closed else { completion(.failure(.windowClosed)); return }
    let changed = edgeToEdgeEnabled != enabled
    sessionID = session
    edgeToEdgeEnabled = enabled
    if changed && pendingFullscreen {
      request(true, completion: completion)
    } else {
      completion(.success(state))
    }
  }

  func endSession(_ session: String, completion: @escaping Completion) {
    guard sessionID == session else { completion(.success(state)); return }
    sessionID = nil
    edgeToEdgeEnabled = false
    // An older route's disposal cannot reset the next episode's configuration.
    if isEdgeToEdge || requests.contains(where: { $0.mode == .edgeToEdge }) {
      request(false, completion: completion)
    } else {
      completion(.success(state))
    }
  }

  func request(_ fullscreen: Bool, completion: @escaping Completion) {
    guard !closed else { completion(.failure(.windowClosed)); return }
    let target: Mode = !fullscreen ? .windowed
      : hasPlayerSession && edgeToEdgeEnabled ? .edgeToEdge : .system
    if requests.last?.mode == target {
      requests[requests.count - 1].completions.append(completion)
    } else {
      requests.append(Request(mode: target, completions: [completion]))
    }
    advance()
  }

  private func advance() {
    guard nativeTransition == nil, let next = requests.first, !closed else { return }
    if next.mode == mode {
      let completed = requests.removeFirst()
      let confirmed = state
      completed.completions.forEach { $0(.success(confirmed)) }
      advance()
      return
    }
    if isEdgeToEdge {
      restoreWindow()
      onChange(state)
      advance()
    } else if systemFullscreen {
      // A standard fullscreen Space must finish exiting before a borderless
      // window can cover the entire display. Keep the same request pending.
      startNativeTransition(false)
    } else if next.mode == .edgeToEdge {
      guard enterEdgeToEdge() else {
        failFirst(.transitionFailed)
        return
      }
      onChange(state)
      advance()
    } else {
      startNativeTransition(true)
    }
  }

  private func startNativeTransition(_ target: Bool) {
    nativeTransition = target
    requestedNativeTransition = target
    window?.makeKeyAndOrderFront(nil)
    toggleNative()
  }

  func nativeWillChange(to fullscreen: Bool) { nativeTransition = fullscreen }

  func nativeDidChange(to fullscreen: Bool) {
    let expected = requestedNativeTransition
    systemFullscreen = fullscreen
    nativeTransition = nil
    requestedNativeTransition = nil
    onChange(state)
    if let expected = expected, expected != fullscreen {
      failFirst(.transitionFailed)
    } else {
      advance()
    }
  }

  func nativeDidFail() {
    systemFullscreen = window?.styleMask.contains(.fullScreen) ?? false
    nativeTransition = nil
    requestedNativeTransition = nil
    onChange(state)
    failFirst(.transitionFailed)
  }

  private func failFirst(_ failure: Failure) {
    if !requests.isEmpty {
      requests.removeFirst().completions.forEach { $0(.failure(failure)) }
    }
    advance()
  }

  private static func screenID(_ screen: NSScreen?) -> Int? {
    (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
  }

  private var fullscreenScreen: NSScreen? {
    NSScreen.screens.first(where: { Self.screenID($0) == displayID })
      ?? window?.screen ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func enterEdgeToEdge() -> Bool {
    guard let window = window, let screen = window.screen ?? NSScreen.main else { return false }
    let firstResponder = window.firstResponder
    saved = SavedWindow(
      frame: window.frame, screenID: Self.screenID(screen), style: window.styleMask,
      collection: window.collectionBehavior, level: window.level, shadow: window.hasShadow,
      movable: window.isMovable, autosave: window.frameAutosaveName,
      presentation: NSApp.presentationOptions
    )
    displayID = Self.screenID(screen)
    // Do not let fullscreen geometry overwrite the normal launch position.
    _ = window.setFrameAutosaveName("")
    updatingFrame = true
    window.styleMask = [.borderless]
    window.hasShadow = false
    window.isMovable = false
    window.collectionBehavior.remove([.fullScreenPrimary, .fullScreenAuxiliary])
    NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
    window.setFrame(screen.frame, display: true)
    updatingFrame = false
    window.makeKeyAndOrderFront(nil)
    restoreFirstResponder(firstResponder, in: window)
    return true
  }

  private func restoreFirstResponder(_ responder: NSResponder?, in window: NSWindow) {
    // Changing styleMask replaces the content's first responder with NSWindow.
    // Making the window key alone does not return keyboard input to Flutter.
    if let responder = responder, responder.acceptsFirstResponder {
      window.makeFirstResponder(responder)
    }
  }

  /// Called on hot-plug, display scaling changes, and moves between displays.
  func updateScreen(preferred: NSScreen? = nil) {
    guard isEdgeToEdge, !updatingFrame, let window = window else { return }
    if let preferred = preferred { displayID = Self.screenID(preferred) }
    guard let screen = fullscreenScreen else { return }
    displayID = Self.screenID(screen)
    updatingFrame = true
    if !NSEqualRects(window.frame, screen.frame) {
      window.setFrame(screen.frame, display: true)
    }
    updatingFrame = false
    onChange(state)
  }

  static func restoredFrame(_ frame: NSRect, visibleFrame: NSRect) -> NSRect {
    let size = NSSize(width: min(frame.width, visibleFrame.width),
                      height: min(frame.height, visibleFrame.height))
    return NSRect(
      x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
      y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
      width: size.width, height: size.height
    )
  }

  private func restoreWindow(foreground: Bool = true) {
    guard let saved = saved, let window = window else { return }
    let firstResponder = window.firstResponder
    updatingFrame = true
    window.styleMask = saved.style
    window.collectionBehavior = saved.collection
    window.level = saved.level
    window.hasShadow = saved.shadow
    window.isMovable = saved.movable
    NSApp.presentationOptions = saved.presentation
    let screen = NSScreen.screens.first(where: { Self.screenID($0) == saved.screenID })
      ?? window.screen ?? NSScreen.main
    let frame = screen.map { Self.restoredFrame(saved.frame, visibleFrame: $0.visibleFrame) }
      ?? saved.frame
    self.saved = nil
    displayID = nil
    window.setFrame(frame, display: true)
    _ = window.setFrameAutosaveName(saved.autosave)
    if !saved.autosave.isEmpty { window.saveFrame(usingName: saved.autosave) }
    updatingFrame = false
    if foreground { window.makeKeyAndOrderFront(nil) }
    restoreFirstResponder(firstResponder, in: window)
  }

  func close() {
    guard !closed else { return }
    closed = true
    restoreWindow(foreground: false)
    let pending = requests
    requests.removeAll()
    pending.flatMap(\.completions).forEach { $0(.failure(.windowClosed)) }
  }
}
