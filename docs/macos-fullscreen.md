# macOS player fullscreen

**Settings → Player → Use the entire display in fullscreen** is an opt-in macOS
setting. The same switch is available in the player's Settings sheet. It is off
by default and persists with the other player preferences.

When enabled, the player uses a borderless window on the **current desktop**,
covering the entire display including the regions beside the camera housing.
The standard mode still uses macOS's fullscreen Space. Switching the preference
while watching converts between these modes without reopening the stream.

The video initially fills the display with its aspect ratio preserved, cropping
the edges when necessary. Pinch inward or choose Normal to fit the entire frame.
This fullscreen zoom choice does not overwrite the normal-window zoom preference.
Controls use the display's safe-area insets while the video retains the whole
viewport. The camera housing itself remains physically obscured.

Implementation uses public AppKit APIs, `NSScreen.frame`, `safeAreaInsets`,
borderless `NSWindow` geometry and app presentation options. It does not modify
SIP or other processes. A session identifier prevents cleanup from a previous
episode from changing the next player's mode. Window style, position, autosave
name and presentation options are restored on exit or termination. A removed or
rescaled display restores the window into an available visible frame.

Native PiP handoff restores the regular desktop first. Returning to the player
restores fullscreen and the fit/fill choice; the existing PiP progress handoff
continues to restore playback position.

## Validation

Flutter regression tests cover the persisted setting, macOS-only visibility,
live mode changes, safe-area layout without reducing the video viewport,
fit/fill, Escape, PiP position/zoom restoration and desktop continuation.

To check the AppKit controller on a Mac with a WindowServer session:

```sh
swiftc macos/Runner/PlayerFullscreenController.swift \
  test/native/macos_fullscreen_smoke.swift -o /tmp/mirushin-fullscreen-check
/tmp/mirushin-fullscreen-check
```

The check creates a temporary test window, exercises geometry, ordered native
transitions, stale session cleanup, failure handling and frame restoration, then
closes it. Display hot-plug fallback geometry is checked without requiring an
actual monitor disconnection.

A separate Flutter/AppKit profile probe was run on a camera-equipped display
with **SIP enabled**. The full-display viewport measured `1710×1107` logical
pixels; standard fullscreen measured `1710×1073`. Switching both ways, rapid
toggles and session cleanup restored the original `800×600` viewport. No second
video decoder is introduced by the fullscreen mode.
