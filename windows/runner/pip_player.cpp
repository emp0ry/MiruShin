// Floating PiP window for Windows.
// Uses the MDK C++ Player API, same as the fvp plugin, with a D3D11 swap
// chain so each rendered frame is presented directly to the HWND.

#include "pip_player.h"

#include <d3d10.h>
#include <d3d11.h>
#include <dxgi.h>

#ifdef MIRUSHIN_PIP_WIN32
#include "mdk/Player.h"
#include "mdk/RenderAPI.h"
using namespace MDK_NS;
#endif

#include <algorithm>
#include <iostream>
#include <string>
#include <utility>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace pip {

// ── Helpers ─────────────────────────────────────────────────────────────────

static std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) {
    return {};
  }

  int n = MultiByteToWideChar(
      CP_UTF8,
      0,
      s.c_str(),
      -1,
      nullptr,
      0
  );

  if (n <= 0) {
    return {};
  }

  std::wstring ws(static_cast<size_t>(n), L'\0');

  MultiByteToWideChar(
      CP_UTF8,
      0,
      s.c_str(),
      -1,
      ws.data(),
      n
  );

  if (!ws.empty() && ws.back() == L'\0') {
    ws.pop_back();
  }

  return ws;
}

// ── PipPlayer ───────────────────────────────────────────────────────────────

PipPlayer::PipPlayer() = default;

PipPlayer::~PipPlayer() {
  Close();
}

// static
ATOM PipPlayer::RegisterClass() {
  static ATOM cls = 0;

  if (cls) {
    return cls;
  }

  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  wc.lpszClassName = L"MiruShinPipWindow";

  cls = RegisterClassExW(&wc);
  return cls;
}

bool PipPlayer::CreatePipWindow(const std::wstring& title) {
  RegisterClass();

  // Position in the bottom-right of the primary work area.
  MONITORINFO mi{sizeof(mi)};
  GetMonitorInfo(
      MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY),
      &mi
  );

  int x = mi.rcWork.right - width_ - 16;
  int y = mi.rcWork.bottom - height_ - 16;

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_NOACTIVATE,
      L"MiruShinPipWindow",
      title.empty() ? L"MiruShin PiP" : title.c_str(),
      WS_OVERLAPPEDWINDOW,
      x,
      y,
      width_,
      height_,
      nullptr,
      nullptr,
      GetModuleHandleW(nullptr),
      this
  );

  return hwnd_ != nullptr;
}

bool PipPlayer::SetupD3D11() {
  HRESULT hr = D3D11CreateDevice(
      nullptr,
      D3D_DRIVER_TYPE_HARDWARE,
      nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      nullptr,
      0,
      D3D11_SDK_VERSION,
      &device_,
      nullptr,
      &ctx_
  );

  if (FAILED(hr)) {
    return false;
  }

  // Enable multi-thread protection so MDK can render from its own thread.
  ComPtr<ID3D10Multithread> mt;
  if (SUCCEEDED(device_.As(&mt))) {
    mt->SetMultithreadProtected(TRUE);
  }

  // Create a swap chain for the PiP HWND.
  ComPtr<IDXGIDevice> dxgi_dev;
  if (FAILED(device_.As(&dxgi_dev))) {
    return false;
  }

  ComPtr<IDXGIAdapter> adapter;
  if (FAILED(dxgi_dev->GetAdapter(&adapter))) {
    return false;
  }

  ComPtr<IDXGIFactory> factory;
  if (FAILED(adapter->GetParent(IID_PPV_ARGS(&factory)))) {
    return false;
  }

  DXGI_SWAP_CHAIN_DESC scd{};
  scd.BufferDesc.Width = static_cast<UINT>(width_);
  scd.BufferDesc.Height = static_cast<UINT>(height_);
  scd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  scd.SampleDesc.Count = 1;
  scd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  scd.BufferCount = 2;
  scd.OutputWindow = hwnd_;
  scd.Windowed = TRUE;
  scd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

  hr = factory->CreateSwapChain(device_.Get(), &scd, &swap_chain_);
  if (FAILED(hr)) {
    return false;
  }

  // Block ALT+ENTER fullscreen toggle on the swap chain.
  factory->MakeWindowAssociation(hwnd_, DXGI_MWA_NO_ALT_ENTER);

  // Create the render target view from the back buffer.
  ComPtr<ID3D11Texture2D> back;
  if (FAILED(swap_chain_->GetBuffer(0, IID_PPV_ARGS(&back)))) {
    return false;
  }

  hr = device_->CreateRenderTargetView(back.Get(), nullptr, &rtv_);
  if (FAILED(hr)) {
    return false;
  }

  return rtv_ != nullptr;
}

void PipPlayer::ResizeSwapChain(int w, int h) {
  if (!swap_chain_) {
    return;
  }

  width_ = w;
  height_ = h;

  // Release the RTV before resizing.
  rtv_.Reset();

#ifdef MIRUSHIN_PIP_WIN32
  if (player_api_) {
    Player p(player_api_);
    p.setVideoSurfaceSize(-1, -1);
  }
#endif

  swap_chain_->ResizeBuffers(
      0,
      static_cast<UINT>(w),
      static_cast<UINT>(h),
      DXGI_FORMAT_UNKNOWN,
      0
  );

  ComPtr<ID3D11Texture2D> back;
  if (FAILED(swap_chain_->GetBuffer(0, IID_PPV_ARGS(&back)))) {
    return;
  }

  if (FAILED(device_->CreateRenderTargetView(back.Get(), nullptr, &rtv_))) {
    return;
  }

#ifdef MIRUSHIN_PIP_WIN32
  if (player_api_ && rtv_) {
    Player p(player_api_);

    D3D11RenderAPI ra{};
    ra.rtv = rtv_.Get();

    p.setRenderAPI(&ra);
    p.setVideoSurfaceSize(w, h);
  }
#endif
}

void PipPlayer::SetupMdkPlayer(
    const std::string& url,
    const std::map<std::string, std::string>& headers,
    int64_t position_ms,
    float playback_rate,
    bool was_playing) {
#ifdef MIRUSHIN_PIP_WIN32
  player_api_ = mdkPlayerAPI_new();

  if (!player_api_) {
    return;
  }

  Player player(player_api_);

  // Apply HTTP headers the same way fvp_player_engine.dart does.
  std::string user_agent;
  std::string referer;
  std::string avio_headers;

  for (const auto& kv : headers) {
    const std::string& k = kv.first;
    const std::string& v = kv.second;

    std::string lk = k;
    std::transform(lk.begin(), lk.end(), lk.begin(), ::tolower);

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
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 "
        "Safari/537.36 MiruShin/1.0";
  }

  player.setProperty("avio.user_agent", user_agent.c_str());

  if (!referer.empty()) {
    player.setProperty("avio.referer", referer.c_str());
  }

  if (!avio_headers.empty()) {
    player.setProperty("avio.headers", avio_headers.c_str());
  }

  // Streaming reconnect.
  player.setProperty("avio.reconnect", "1");
  player.setProperty("avio.reconnect_streamed", "1");
  player.setProperty("avio.reconnect_delay_max", "5");
  player.setProperty("avformat.strict", "experimental");
  player.setProperty("avformat.safe", "0");

  // Hook up D3D11 render API.
  D3D11RenderAPI ra{};
  ra.rtv = rtv_.Get();

  player.setRenderAPI(&ra);
  player.setVideoSurfaceSize(width_, height_);

  // When MDK has decoded a new frame, blit it to the swap chain.
  player.setRenderCallback([this](void*) {
    if (!player_api_ || !swap_chain_) {
      return;
    }

    Player p(player_api_);
    p.renderVideo();

    swap_chain_->Present(0, 0);
  });

  // Detect end-of-media.
  player.onMediaStatus([this](MediaStatus old_st, MediaStatus new_st) -> bool {
    if ((new_st & MediaStatus::End) == MediaStatus::End) {
      // Post to the window thread so we do not call Dart APIs from MDK thread.
      if (hwnd_) {
        PostMessage(hwnd_, WM_APP + 1, 0, 0);
      }
    }

    return true;
  });

  player.setMedia(url.c_str());
  player.setPlaybackRate(playback_rate);

  if (position_ms > 0) {
    player.seek(position_ms, SeekFlag::FromStart | SeekFlag::InCache);
  }

  if (was_playing) {
    player.setState(PlaybackState::Playing);
  } else {
    player.setState(PlaybackState::Paused);
  }
#endif  // MIRUSHIN_PIP_WIN32
}

bool PipPlayer::Open(
    const std::string& url,
    const std::map<std::string, std::string>& headers,
    int64_t position_ms,
    float playback_rate,
    bool was_playing,
    const std::wstring& title,
    DismissCallback on_dismiss,
    CompletedCallback on_complete) {
  if (hwnd_) {
    return false;
  }

  on_dismiss_ = std::move(on_dismiss);
  on_complete_ = std::move(on_complete);
  dismissed_ = false;

#ifndef MIRUSHIN_PIP_WIN32
  // mdk-sdk not available: PiP is a no-op at runtime.
  return false;
#else
  if (!CreatePipWindow(title)) {
    return false;
  }

  if (!SetupD3D11()) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    return false;
  }

  SetupMdkPlayer(
      url,
      headers,
      position_ms,
      playback_rate,
      was_playing
  );

  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  UpdateWindow(hwnd_);

  return true;
#endif
}

void PipPlayer::Dismiss(bool was_playing) {
  if (dismissed_) {
    return;
  }

  dismissed_ = true;

  DismissedArgs args{};
  args.was_playing = was_playing;

#ifdef MIRUSHIN_PIP_WIN32
  if (player_api_) {
    Player p(player_api_);
    args.position_ms = p.position();
    args.duration_ms = p.mediaInfo().duration;
  }
#endif

  Cleanup();

  if (on_dismiss_) {
    on_dismiss_(args);
  }
}

void PipPlayer::Cleanup() {
#ifdef MIRUSHIN_PIP_WIN32
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

  rtv_.Reset();
  swap_chain_.Reset();
  ctx_.Reset();
  device_.Reset();

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void PipPlayer::Close() {
  if (!hwnd_) {
    return;
  }

  // Suppress callback on explicit close from native service.
  dismissed_ = true;
  Cleanup();
}

// ── Win32 message handling ──────────────────────────────────────────────────

// static
LRESULT CALLBACK PipPlayer::WndProc(HWND hwnd,
                                    UINT msg,
                                    WPARAM wp,
                                    LPARAM lp) noexcept {
  PipPlayer* self = nullptr;

  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
    self = static_cast<PipPlayer*>(cs->lpCreateParams);

    SetWindowLongPtrW(
        hwnd,
        GWLP_USERDATA,
        reinterpret_cast<LONG_PTR>(self)
    );
  } else {
    self = reinterpret_cast<PipPlayer*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA)
    );
  }

  if (self) {
    return self->HandleMessage(hwnd, msg, wp, lp);
  }

  return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT PipPlayer::HandleMessage(HWND hwnd,
                                 UINT msg,
                                 WPARAM wp,
                                 LPARAM lp) noexcept {
  switch (msg) {
    case WM_CLOSE:
      Dismiss(/*was_playing=*/true);
      return 0;

    case WM_SIZE:
      if (wp != SIZE_MINIMIZED) {
        int w = LOWORD(lp);
        int h = HIWORD(lp);

        if (w > 0 && h > 0) {
          ResizeSwapChain(w, h);
        }
      }
      return 0;

    case WM_APP + 1: {
      // End-of-media posted by MDK callback.
      if (on_complete_) {
        DismissedArgs args{};

#ifdef MIRUSHIN_PIP_WIN32
        if (player_api_) {
          Player p(player_api_);
          args.position_ms = p.position();
          args.duration_ms = p.mediaInfo().duration;
        }
#endif

        dismissed_ = true;
        Cleanup();

        on_complete_(args);
      }

      return 0;
    }

    case WM_KEYDOWN:
      if (wp == VK_ESCAPE) {
        Dismiss(/*was_playing=*/true);
        return 0;
      }
      break;

    default:
      break;
  }

  return DefWindowProcW(hwnd, msg, wp, lp);
}

}  // namespace pip