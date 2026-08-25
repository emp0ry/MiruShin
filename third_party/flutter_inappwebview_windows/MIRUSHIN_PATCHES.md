# MiruShin Windows backports

This package is `flutter_inappwebview_windows` 0.6.0 from the
`flutter_inappwebview` 6.1.5 dependency family used by MiruShin 2.5.0.

MiruShin carries Windows bridge fixes:

- Cookie operations include the active WebView ID and use that visible or
  headless WebView's DevTools session. This fixes `CookieManager.getCookies`
  returning an empty list for cookies created by the challenge WebView.
- Controller IDs are decoded by their actual Flutter value type. Numeric
  platform-view IDs and string headless/keep-alive IDs are both supported
  without invoking an incompatible native variant accessor.
- The hidden platform-view window class uses `CS_NOCLOSE`, matching the upstream
  guard against the OS unexpectedly closing a WebView window.
- WebView2 environment and controller creation retain a thread-local STA COM
  apartment for the full asynchronous lifetime. This prevents
  `CO_E_NOTINITIALIZED` when a platform call is dispatched on a different
  thread or another native component unbalances the runner's COM reference.
- WinRT cleanup calls `RoUninitialize` only when this plugin successfully
  initialized WinRT, never after `RPC_E_CHANGED_MODE`.
- Platform-view creation no longer force-unwraps a missing texture ID. Native
  startup failures complete the creation/disposal lifecycle safely instead of
  escaping as an uncaught asynchronous exception.

Android, iOS, and macOS continue to use the unmodified stable packages resolved
from pub.dev.
