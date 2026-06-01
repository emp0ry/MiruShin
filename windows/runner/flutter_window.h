#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "pip_player.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupWindowChannel();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  void SetupPipChannel();

  // mirushin/window method channel for fullscreen / window management.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // mirushin/native_player method channel for desktop PiP.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      pip_channel_;

  // Desktop PiP player instance (at most one at a time).
  std::unique_ptr<pip::PipPlayer> pip_player_;

  // Fullscreen state and saved window geometry for restore.
  bool is_fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{};

  // Borderless (title-bar-less) state for the Windows mini-player PiP.
  bool is_borderless_ = false;
  LONG_PTR pip_saved_style_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
