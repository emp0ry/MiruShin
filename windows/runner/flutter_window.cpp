#include "flutter_window.h"

#include <dwmapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "window_geometry.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupWindowChannel();
  SetupPipChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupWindowChannel() {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "mirushin/window",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        HWND hwnd = GetHandle();

        if (call.method_name() == "isFullscreen") {
          result->Success(flutter::EncodableValue(is_fullscreen_));
          return;
        }

        if (call.method_name() == "setFullscreen") {
          const flutter::EncodableValue* arg = call.arguments();
          const bool* want_fullscreen = std::get_if<bool>(arg);
          if (!want_fullscreen) {
            result->Error("bad_args", "setFullscreen expects a bool");
            return;
          }

          if (*want_fullscreen && !is_fullscreen_) {
            saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
            saved_placement_.length = sizeof(WINDOWPLACEMENT);
            GetWindowPlacement(hwnd, &saved_placement_);

            SetWindowLongPtr(hwnd, GWL_STYLE,
                             saved_style_ & ~WS_OVERLAPPEDWINDOW);

            MONITORINFO mi{sizeof(mi)};
            GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY),
                           &mi);
            SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                         mi.rcMonitor.right - mi.rcMonitor.left,
                         mi.rcMonitor.bottom - mi.rcMonitor.top,
                         SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
            is_fullscreen_ = true;
          } else if (!*want_fullscreen && is_fullscreen_) {
            SetWindowLongPtr(hwnd, GWL_STYLE, saved_style_);
            SetWindowPlacement(hwnd, &saved_placement_);
            SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                             SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
            is_fullscreen_ = false;
          }

          result->Success(flutter::EncodableValue(is_fullscreen_));
          return;
        }

        // ── PiP / window-management helpers ──────────────────────────────

        if (call.method_name() == "getWindowRect") {
          RECT wr{};
          GetWindowRect(hwnd, &wr);
          flutter::EncodableMap map;
          map[flutter::EncodableValue("x")] =
              flutter::EncodableValue(static_cast<int>(wr.left));
          map[flutter::EncodableValue("y")] =
              flutter::EncodableValue(static_cast<int>(wr.top));
          map[flutter::EncodableValue("width")] =
              flutter::EncodableValue(static_cast<int>(wr.right - wr.left));
          map[flutter::EncodableValue("height")] =
              flutter::EncodableValue(static_cast<int>(wr.bottom - wr.top));
          result->Success(flutter::EncodableValue(map));
          return;
        }

        if (call.method_name() == "setWindowSize") {
          const auto* map =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!map) {
            result->Error("bad_args", "setWindowSize expects a map");
            return;
          }
          auto w_it = map->find(flutter::EncodableValue("width"));
          auto h_it = map->find(flutter::EncodableValue("height"));
          if (w_it == map->end() || h_it == map->end()) {
            result->Error("bad_args", "width and height required");
            return;
          }
          int w = std::get<int>(w_it->second);
          int h = std::get<int>(h_it->second);
          // Restore from maximised state so SetWindowPos takes effect.
          if (IsZoomed(hwnd)) {
            ShowWindow(hwnd, SW_RESTORE);
          }
          SetWindowPos(hwnd, nullptr, 0, 0, w, h,
                       SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
          result->Success();
          return;
        }

        if (call.method_name() == "setWindowRect") {
          const auto* map =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!map) {
            result->Error("bad_args", "setWindowRect expects a map");
            return;
          }
          auto x_it = map->find(flutter::EncodableValue("x"));
          auto y_it = map->find(flutter::EncodableValue("y"));
          auto w_it = map->find(flutter::EncodableValue("width"));
          auto h_it = map->find(flutter::EncodableValue("height"));
          if (x_it == map->end() || y_it == map->end() ||
              w_it == map->end() || h_it == map->end()) {
            result->Error("bad_args", "x, y, width and height required");
            return;
          }
          int x = std::get<int>(x_it->second);
          int y = std::get<int>(y_it->second);
          int w = std::get<int>(w_it->second);
          int h = std::get<int>(h_it->second);
          SetWindowPos(hwnd, nullptr, x, y, w, h,
                       SWP_NOZORDER | SWP_NOACTIVATE);
          result->Success();
          return;
        }

        if (call.method_name() == "moveToCorner") {
          HMONITOR mon =
              MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
          MONITORINFO mi{sizeof(mi)};
          GetMonitorInfo(mon, &mi);
          RECT wr{};
          GetWindowRect(hwnd, &wr);
          int w = wr.right - wr.left;
          int h = wr.bottom - wr.top;
          int x = mi.rcWork.right - w - 16;
          int y = mi.rcWork.bottom - h - 16;
          SetWindowPos(hwnd, nullptr, x, y, 0, 0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
          result->Success();
          return;
        }

        if (call.method_name() == "setBorderless") {
          const bool* borderless = std::get_if<bool>(call.arguments());
          if (!borderless) {
            result->Error("bad_args", "setBorderless expects a bool");
            return;
          }
          if (*borderless && !is_borderless_) {
            pip_saved_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
            // Strip the caption/title bar and resize frame so the mini-player
            // is a clean borderless video surface.
            SetWindowLongPtr(
                hwnd, GWL_STYLE,
                pip_saved_style_ & ~(WS_CAPTION | WS_THICKFRAME |
                                     WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
                                     WS_SYSMENU));
            SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                             SWP_NOOWNERZORDER | SWP_FRAMECHANGED |
                             SWP_NOACTIVATE);
            // macOS-like softly rounded corners (Windows 11; no-op on older).
            const DWM_WINDOW_CORNER_PREFERENCE round = DWMWCP_ROUND;
            DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &round,
                                  sizeof(round));
            is_borderless_ = true;
          } else if (!*borderless && is_borderless_) {
            const DWM_WINDOW_CORNER_PREFERENCE def = DWMWCP_DEFAULT;
            DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &def,
                                  sizeof(def));
            SetWindowLongPtr(hwnd, GWL_STYLE, pip_saved_style_);
            SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                             SWP_NOOWNERZORDER | SWP_FRAMECHANGED |
                             SWP_NOACTIVATE);
            is_borderless_ = false;
          }
          result->Success();
          return;
        }

        if (call.method_name() == "startWindowDrag") {
          // Hand the drag off to the OS so the borderless mini-player can be
          // moved by grabbing anywhere on it, like a native title bar.
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
          return;
        }

        if (call.method_name() == "setAlwaysOnTop") {
          const bool* on_top = std::get_if<bool>(call.arguments());
          if (!on_top) {
            result->Error("bad_args", "setAlwaysOnTop expects a bool");
            return;
          }
          SetWindowPos(hwnd, *on_top ? HWND_TOPMOST : HWND_NOTOPMOST,
                       0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  window_channel_ = std::move(channel);
}

void FlutterWindow::SetupPipChannel() {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "mirushin/native_player",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "present") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("bad_args", "present expects a map");
            return;
          }

          auto str = [&](const char* key) -> std::string {
            auto it = args->find(flutter::EncodableValue(key));
            if (it == args->end()) return {};
            const auto* s = std::get_if<std::string>(&it->second);
            return s ? *s : std::string{};
          };
          auto dbl = [&](const char* key) -> double {
            auto it = args->find(flutter::EncodableValue(key));
            if (it == args->end()) return 0.0;
            const auto* d = std::get_if<double>(&it->second);
            return d ? *d : 0.0;
          };
          auto boolean = [&](const char* key) -> bool {
            auto it = args->find(flutter::EncodableValue(key));
            if (it == args->end()) return false;
            const auto* b = std::get_if<bool>(&it->second);
            return b ? *b : false;
          };

          // Parse headers map.
          std::map<std::string, std::string> headers;
          {
            auto it =
                args->find(flutter::EncodableValue("headers"));
            if (it != args->end()) {
              const auto* hmap =
                  std::get_if<flutter::EncodableMap>(&it->second);
              if (hmap) {
                for (auto& [k, v] : *hmap) {
                  const auto* ks = std::get_if<std::string>(&k);
                  const auto* vs = std::get_if<std::string>(&v);
                  if (ks && vs) headers[*ks] = *vs;
                }
              }
            }
          }

          const std::string url = str("url");
          const int64_t pos_ms =
              static_cast<int64_t>(dbl("positionMs"));
          const float rate =
              static_cast<float>(dbl("playbackRate"));
          const bool was_playing = boolean("wasPlaying");
          const std::wstring title =
              [&]() -> std::wstring {
            std::string t = str("title");
            int n = MultiByteToWideChar(CP_UTF8, 0, t.c_str(), -1,
                                        nullptr, 0);
            std::wstring ws(n, L'\0');
            MultiByteToWideChar(CP_UTF8, 0, t.c_str(), -1, ws.data(), n);
            return ws;
          }();

          if (pip_player_ && pip_player_->IsOpen()) {
            pip_player_->Close();
          }
          pip_player_ = std::make_unique<pip::PipPlayer>();

          // Capture the channel pointer for callbacks.
          auto* ch = pip_channel_.get();

          bool ok = pip_player_->Open(
              url, headers, pos_ms, rate, was_playing, title,
              /*on_dismiss=*/[ch](pip::DismissedArgs a) {
                if (!ch) return;
                flutter::EncodableMap ev;
                ev[flutter::EncodableValue("positionMs")] =
                    flutter::EncodableValue(
                        static_cast<double>(a.position_ms));
                ev[flutter::EncodableValue("durationMs")] =
                    flutter::EncodableValue(
                        static_cast<double>(a.duration_ms));
                ev[flutter::EncodableValue("wasPlaying")] =
                    flutter::EncodableValue(a.was_playing);
                ch->InvokeMethod(
                    "dismissed",
                    std::make_unique<flutter::EncodableValue>(ev));
              },
              /*on_complete=*/[ch](pip::DismissedArgs a) {
                if (!ch) return;
                flutter::EncodableMap ev;
                ev[flutter::EncodableValue("positionMs")] =
                    flutter::EncodableValue(
                        static_cast<double>(a.position_ms));
                ev[flutter::EncodableValue("durationMs")] =
                    flutter::EncodableValue(
                        static_cast<double>(a.duration_ms));
                ch->InvokeMethod(
                    "completed",
                    std::make_unique<flutter::EncodableValue>(ev));
              });

          if (ok) {
            result->Success();
          } else {
            result->Error("pip_failed",
                          "Failed to open PiP window (mdk-sdk unavailable "
                          "or D3D11 error)");
          }
          return;
        }

        result->NotImplemented();
      });

  pip_channel_ = std::move(channel);
}

void FlutterWindow::OnDestroy() {
  pip_channel_ = nullptr;
  if (pip_player_) { pip_player_->Close(); pip_player_ = nullptr; }
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
    case WM_EXITSIZEMOVE:
    case WM_MOVE:
      SaveWindowGeometry(hwnd);
      break;
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) {
        SaveWindowGeometry(hwnd);
      }
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
