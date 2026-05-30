#pragma once
#ifndef RUNNER_PIP_PLAYER_H_
#define RUNNER_PIP_PLAYER_H_

#include <gtk/gtk.h>
#include <functional>
#include <map>
#include <string>

struct mdkPlayerAPI;

namespace pip {

struct DismissedArgs {
  int64_t position_ms;
  int64_t duration_ms;
  bool was_playing;
};

// Floating always-on-top GTK window that plays a video using a separate MDK
// player rendered via GtkGLArea (OpenGL).  Mirrors the Windows pip_player so
// the same Dart-side NativePlayerService flow works on Linux.
class PipPlayer {
 public:
  using DismissCallback = std::function<void(DismissedArgs)>;
  using CompletedCallback = std::function<void(DismissedArgs)>;

  PipPlayer();
  ~PipPlayer();

  PipPlayer(const PipPlayer&) = delete;
  PipPlayer& operator=(const PipPlayer&) = delete;

  bool Open(const std::string& url,
            const std::map<std::string, std::string>& headers,
            int64_t position_ms,
            float playback_rate,
            bool was_playing,
            const std::string& title,
            DismissCallback on_dismiss,
            CompletedCallback on_complete);

  void Close();

  bool IsOpen() const { return window_ != nullptr; }

 private:
  void Dismiss(bool was_playing);
  void Cleanup();
  void SetupMdkPlayer(const std::string& url,
                      const std::map<std::string, std::string>& headers,
                      int64_t position_ms,
                      float playback_rate,
                      bool was_playing);

  // GTK signal callbacks.
  static gboolean OnDeleteEvent(GtkWidget*, GdkEvent*, gpointer);
  static gboolean OnRender(GtkGLArea*, GdkGLContext*, gpointer);
  static void OnRealize(GtkGLArea*, gpointer);
  static gboolean OnEndOfMedia(gpointer);  // idle callback

  GtkWidget* window_ = nullptr;
  GtkGLArea* gl_area_ = nullptr;

  mdkPlayerAPI* player_api_ = nullptr;
  int width_ = 640;
  int height_ = 360;

  DismissCallback on_dismiss_;
  CompletedCallback on_complete_;
  bool dismissed_ = false;
  bool eof_posted_ = false;
};

}  // namespace pip

#endif  // RUNNER_PIP_PLAYER_H_
