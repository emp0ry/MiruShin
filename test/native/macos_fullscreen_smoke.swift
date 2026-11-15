// Run from the repository root on a Mac with a WindowServer session:
// swiftc macos/Runner/PlayerFullscreenController.swift \
//   test/native/macos_fullscreen_smoke.swift -o /tmp/mirushin-fullscreen-check
// /tmp/mirushin-fullscreen-check
import Cocoa

private final class TestWindow: NSWindow {
  weak var fullscreen: PlayerFullscreenController?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    if fullscreen?.isEdgeToEdge == true { return frameRect }
    return super.constrainFrameRect(frameRect, to: screen)
  }
}

@main
struct FullscreenSmoke {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    guard let screen = NSScreen.main else { fatalError("A screen is required") }
    let window = TestWindow(
      contentRect: NSRect(x: screen.visibleFrame.minX + 50,
                          y: screen.visibleFrame.minY + 60, width: 640, height: 360),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.title = "MiruShin fullscreen check"
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    let autosave = NSWindow.FrameAutosaveName("MiruShin.FullscreenCheck.\(UUID().uuidString)")
    _ = window.setFrameAutosaveName(autosave)
    window.makeKeyAndOrderFront(nil)
    let originalFrame = window.frame
    let originalStyle = window.styleMask
    let originalPresentation = app.presentationOptions
    var nativeCalls = 0
    var results: [PlayerFullscreenController.State] = []
    let fullscreen = PlayerFullscreenController(
      window: window, toggleNative: { nativeCalls += 1 }, onChange: { _ in }
    )
    window.fullscreen = fullscreen
    func success(_ value: Result<PlayerFullscreenController.State, PlayerFullscreenController.Failure>) {
      switch value {
      case .success(let state): results.append(state)
      case .failure(let failure): fatalError("Unexpected transition failure: \(failure)")
      }
    }
    defer {
      fullscreen.close()
      window.orderOut(nil)
      NSWindow.removeFrame(usingName: autosave)
    }

    fullscreen.configure(session: "first", enabled: true, completion: success)
    fullscreen.request(true, completion: success)
    precondition(fullscreen.mode == .edgeToEdge && nativeCalls == 0)
    precondition(window.frame == screen.frame, "Fullscreen must include the camera row")
    precondition(window.contentView?.bounds.size == screen.frame.size,
                 "The content view must use the entire display")
    precondition(window.frameAutosaveName.isEmpty)
    precondition(window.level == .normal, "The player must not cover other apps/Spaces")
    fullscreen.updateScreen(preferred: screen)

    fullscreen.configure(session: "first", enabled: false, completion: success)
    precondition(window.frame == originalFrame && window.styleMask == originalStyle)
    precondition(nativeCalls == 1, "Disabling while fullscreen must enter standard fullscreen")
    fullscreen.nativeWillChange(to: true)
    fullscreen.nativeDidChange(to: true)
    precondition(fullscreen.mode == .system)
    fullscreen.configure(session: "first", enabled: true, completion: success)
    precondition(nativeCalls == 2)
    fullscreen.nativeDidChange(to: false)
    precondition(fullscreen.mode == .edgeToEdge && window.frame == screen.frame)

    fullscreen.configure(session: "next-episode", enabled: true, completion: success)
    fullscreen.endSession("first", completion: success)
    precondition(fullscreen.mode == .edgeToEdge, "Old route cleanup must not exit the next episode")
    fullscreen.endSession("next-episode", completion: success)
    precondition(fullscreen.mode == .windowed)
    precondition(window.frame == originalFrame && window.styleMask == originalStyle)
    precondition(window.frameAutosaveName == autosave)
    precondition(app.presentationOptions == originalPresentation)

    // Rapid opposite requests retain native ordering and finish in windowed mode.
    fullscreen.configure(session: "rapid", enabled: false, completion: success)
    fullscreen.request(true, completion: success)
    fullscreen.request(false, completion: success)
    fullscreen.nativeDidChange(to: true)
    precondition(nativeCalls == 4)
    fullscreen.nativeDidChange(to: false)
    precondition(!fullscreen.state.fullscreen)
    var rejected = false
    fullscreen.request(true) { response in
      if case .failure(.transitionFailed) = response { rejected = true }
    }
    fullscreen.nativeDidFail()
    precondition(rejected && fullscreen.mode == .windowed)

    let recovered = PlayerFullscreenController.restoredFrame(
      NSRect(x: -3000, y: -1000, width: 1800, height: 1200),
      visibleFrame: NSRect(x: 0, y: 20, width: 800, height: 600)
    )
    precondition(recovered == NSRect(x: 0, y: 20, width: 800, height: 600),
                 "An unplugged display must leave a reachable normal window")
    fullscreen.configure(session: "close", enabled: true, completion: success)
    fullscreen.request(true, completion: success)
    fullscreen.close()
    precondition(window.frame == originalFrame && app.presentationOptions == originalPresentation)

    let top = fullscreen.state.safeInsets.top
    let cameraInset: CGFloat
    if #available(macOS 12.0, *) { cameraInset = screen.safeAreaInsets.top }
    else { cameraInset = 0 }
    print("PASS: edge-to-edge geometry, native mode conversion, ordered toggles, stale session, failure, restore and close; cameraInset=\(cameraInset), resetInset=\(top), completions=\(results.count)")
  }
}
