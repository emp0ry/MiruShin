// Floating PiP window for Linux.
// Uses a GTK popup with GtkGLArea providing the OpenGL context and the MDK
// C++ Player API for hardware-accelerated video decoding/rendering.
#include "pip_player.h"

#ifdef MIRUSHIN_PIP_LINUX
#include "mdk/Player.h"
#include "mdk/RenderAPI.h"
#include <epoxy/gl.h>
using namespace MDK_NS;
#endif

#include <gdk/gdkx.h>
#include <cstdlib>
#include <iostream>
#include <string>

namespace pip {

PipPlayer::PipPlayer() = default;

PipPlayer::~PipPlayer() {
  Close();
}

// ── GTK signal callbacks ─────────────────────────────────────────────────────

// static
gboolean PipPlayer::OnDeleteEvent(GtkWidget*, GdkEvent*, gpointer data) {
  auto* self = static_cast<PipPlayer*>(data);
  self->Dismiss(/*was_playing=*/true);
  return TRUE;  // prevent default destruction; we handle it in Dismiss/Cleanup
}

// static — called once when GtkGLArea creates its GL context.
void PipPlayer::OnRealize(GtkGLArea* area, gpointer data) {
  gtk_gl_area_make_current(area);
  if (gtk_gl_area_get_error(area)) return;

#ifdef MIRUSHIN_PIP_LINUX
  auto* self = static_cast<PipPlayer*>(data);
  if (!self->player_api_) return;

  // Use MDK OpenGL render API; fbo=0 means MDK renders to whatever FBO is
  // currently bound (GtkGLArea manages its own offscreen FBO).
  GLRenderAPI ra{};
  ra.fbo = 0;
  Player p(self->player_api_);
  p.setRenderAPI(&ra);
  gint w = gtk_widget_get_allocated_width(GTK_WIDGET(area));
  gint h = gtk_widget_get_allocated_height(GTK_WIDGET(area));
  p.setVideoSurfaceSize(w > 0 ? w : self->width_,
                        h > 0 ? h : self->height_);
#endif
}

// static — called each time GtkGLArea needs to draw a frame.
gboolean PipPlayer::OnRender(GtkGLArea* area, GdkGLContext*, gpointer data) {
#ifdef MIRUSHIN_PIP_LINUX
  auto* self = static_cast<PipPlayer*>(data);
  if (!self->player_api_) return FALSE;

  // Update the FBO in the render API in case it changed.
  GLint fbo = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);

  GLRenderAPI ra{};
  ra.fbo = static_cast<unsigned>(fbo);
  Player p(self->player_api_);
  p.setRenderAPI(&ra);
  p.renderVideo();
  return TRUE;
#else
  return FALSE;
#endif
}

// static — GLib idle callback, posted from MDK's thread when EOF fires.
gboolean PipPlayer::OnEndOfMedia(gpointer data) {
  auto* self = static_cast<PipPlayer*>(data);
  if (self->dismissed_) return G_SOURCE_REMOVE;
  if (self->on_complete_) {
    DismissedArgs args{};
#ifdef MIRUSHIN_PIP_LINUX
    if (self->player_api_) {
      Player p(self->player_api_);
      args.position_ms = p.position();
      args.duration_ms = p.mediaInfo().duration;
    }
#endif
    self->dismissed_ = true;
    self->Cleanup();
    self->on_complete_(args);
  }
  return G_SOURCE_REMOVE;
}

// ── PipPlayer implementation ─────────────────────────────────────────────────

void PipPlayer::SetupMdkPlayer(
    const std::string& url,
    const std::map<std::string, std::string>& headers,
    int64_t position_ms,
    float playback_rate,
    bool was_playing) {
#ifdef MIRUSHIN_PIP_LINUX
  player_api_ = mdkPlayerAPI_new();
  Player player(player_api_);

  // Apply HTTP headers (mirrors fvp_player_engine.dart).
  std::string user_agent;
  std::string referer;
  std::string avio_headers;

  for (auto& [k, v] : headers) {
    std::string lk = k;
    for (auto& c : lk) c = static_cast<char>(std::tolower(c));
    if (lk == "user-agent") {
      user_agent = v;
    } else if (lk == "referer" || lk == "referrer") {
      referer = v;
    } else {
      avio_headers += k + ": " + v + "\r\n";
    }
  }
  if (user_agent.empty()) {
    user_agent =
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36 MiruShin/1.0";
  }
  player.setProperty("avio.user_agent", user_agent.c_str());
  if (!referer.empty()) player.setProperty("avio.referer", referer.c_str());
  if (!avio_headers.empty())
    player.setProperty("avio.headers", avio_headers.c_str());

  player.setProperty("avio.reconnect", "1");
  player.setProperty("avio.reconnect_streamed", "1");
  player.setProperty("avio.reconnect_delay_max", "5");
  player.setProperty("avformat.strict", "experimental");
  player.setProperty("avformat.safe", "0");

  // When MDK has a new frame, ask GtkGLArea to redraw.
  GtkGLArea* area = gl_area_;
  player.setRenderCallback([area](void*) {
    if (area) {
      // Queue a render on the GTK main thread.
      g_idle_add_once(
          [](gpointer p) { gtk_gl_area_queue_render(GTK_GL_AREA(p)); },
          area);
    }
  });

  // Detect end-of-media.
  player.onMediaStatus(
      [this](MediaStatus /*old*/, MediaStatus new_st) -> bool {
        if ((new_st & MediaStatus::End) == MediaStatus::End &&
            !eof_posted_) {
          eof_posted_ = true;
          g_idle_add(OnEndOfMedia, this);
        }
        return true;
      });

  player.setMedia(url.c_str());
  player.setPlaybackRate(playback_rate);
  if (position_ms > 0)
    player.seek(position_ms, SeekFlag::FromStart | SeekFlag::InCache);
  if (was_playing)
    player.setState(PlaybackState::Playing);
  else
    player.setState(PlaybackState::Paused);
#endif
}

bool PipPlayer::Open(
    const std::string& url,
    const std::map<std::string, std::string>& headers,
    int64_t position_ms,
    float playback_rate,
    bool was_playing,
    const std::string& title,
    DismissCallback on_dismiss,
    CompletedCallback on_complete) {
  if (window_) return false;

  on_dismiss_ = std::move(on_dismiss);
  on_complete_ = std::move(on_complete);
  dismissed_ = false;
  eof_posted_ = false;

#ifndef MIRUSHIN_PIP_LINUX
  return false;
#else
  // Create GTK popup window.
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window_),
                       title.empty() ? "MiruShin PiP" : title.c_str());
  gtk_window_set_default_size(GTK_WINDOW(window_), width_, height_);
  gtk_window_set_resizable(GTK_WINDOW(window_), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), FALSE);

  // Position in the bottom-right of the primary monitor.
  GdkMonitor* mon =
      gdk_display_get_primary_monitor(gdk_display_get_default());
  GdkRectangle workarea;
  gdk_monitor_get_workarea(mon, &workarea);
  gtk_window_move(GTK_WINDOW(window_),
                  workarea.x + workarea.width - width_ - 16,
                  workarea.y + workarea.height - height_ - 16);

  // GtkGLArea for OpenGL rendering.
  GtkWidget* gl = gtk_gl_area_new();
  gl_area_ = GTK_GL_AREA(gl);
  gtk_container_add(GTK_CONTAINER(window_), gl);

  g_signal_connect(gl, "realize", G_CALLBACK(OnRealize), this);
  g_signal_connect(gl, "render", G_CALLBACK(OnRender), this);
  g_signal_connect(window_, "delete-event", G_CALLBACK(OnDeleteEvent), this);

  gtk_widget_show_all(window_);

  // MDK player is set up after the GL area is realized (realize signal fires
  // synchronously inside gtk_widget_show_all on X11).
  SetupMdkPlayer(url, headers, position_ms, playback_rate, was_playing);

  return true;
#endif
}

void PipPlayer::Dismiss(bool was_playing) {
  if (dismissed_) return;
  dismissed_ = true;

  DismissedArgs args{};
  args.was_playing = was_playing;
#ifdef MIRUSHIN_PIP_LINUX
  if (player_api_) {
    Player p(player_api_);
    args.position_ms = p.position();
    args.duration_ms = p.mediaInfo().duration;
  }
#endif

  Cleanup();

  if (on_dismiss_) on_dismiss_(args);
}

void PipPlayer::Cleanup() {
#ifdef MIRUSHIN_PIP_LINUX
  if (player_api_) {
    {
      Player p(player_api_);
      p.setRenderCallback(nullptr);
      p.setVideoSurfaceSize(-1, -1);
      p.setState(PlaybackState::Stopped);
    }
    mdkPlayerAPI_delete(&player_api_);
    player_api_ = nullptr;
  }
#endif
  gl_area_ = nullptr;
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

void PipPlayer::Close() {
  if (!window_) return;
  dismissed_ = true;
  Cleanup();
}

}  // namespace pip
