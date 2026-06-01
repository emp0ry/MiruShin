#pragma once
#ifndef RUNNER_PIP_PLAYER_H_
#define RUNNER_PIP_PLAYER_H_

#include <gtk/gtk.h>
#include <functional>
#include <map>
#include <mutex>
#include <string>

#ifdef MIRUSHIN_PIP_LINUX
#include "mdk/Player.h"
#include "mdk/RenderAPI.h"

using MiruShinMdkPlayerApiPtr = decltype(mdkPlayerAPI_new());
#else
struct mdkPlayerAPI;
using MiruShinMdkPlayerApiPtr = mdkPlayerAPI*;
#endif

#if defined(__clang__) || defined(__GNUC__)
#define MIRUSHIN_UNUSED_PRIVATE_FIELD __attribute__((unused))
#else
#define MIRUSHIN_UNUSED_PRIVATE_FIELD
#endif

namespace pip {

struct DismissedArgs {
  int64_t position_ms;
  int64_t duration_ms;
  bool was_playing;
};

// Legacy native Linux PiP player. The app currently uses the Dart-side desktop
// mini-player on Linux, so this compiles as a stub unless explicitly enabled.
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

  MiruShinMdkPlayerApiPtr player_api_ MIRUSHIN_UNUSED_PRIVATE_FIELD = nullptr;
  int width_ MIRUSHIN_UNUSED_PRIVATE_FIELD = 640;
  int height_ MIRUSHIN_UNUSED_PRIVATE_FIELD = 360;

#ifdef MIRUSHIN_PIP_LINUX
  MDK_NS::GLRenderAPI render_api_ MIRUSHIN_UNUSED_PRIVATE_FIELD;
#endif

  DismissCallback on_dismiss_;
  CompletedCallback on_complete_;
  std::mutex widget_mutex_;
  bool dismissed_ = false;
  bool eof_posted_ = false;
  guint eof_source_id_ = 0;
};

}  // namespace pip

#undef MIRUSHIN_UNUSED_PRIVATE_FIELD

#endif  // RUNNER_PIP_PLAYER_H_
