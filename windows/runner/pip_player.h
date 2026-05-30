#pragma once
#ifndef RUNNER_PIP_PLAYER_H_
#define RUNNER_PIP_PLAYER_H_

#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <cstdint>
#include <functional>
#include <map>
#include <string>

// Forward-declare the MDK C struct so we don't pull in mdk headers here.
struct mdkPlayerAPI;

namespace pip {

struct DismissedArgs {
  int64_t position_ms;
  int64_t duration_ms;
  bool was_playing;
};

// Floating always-on-top Win32 window that plays a video using a separate MDK
// player rendered via D3D11 swap chain. Mirrors the iOS NativePlayerService
// so the same Dart-side NativePlayerService / _handOffToNativePip flow works.
class PipPlayer {
 public:
  using DismissCallback = std::function<void(DismissedArgs)>;
  using CompletedCallback = std::function<void(DismissedArgs)>;

  PipPlayer();
  ~PipPlayer();

  // Non-copyable.
  PipPlayer(const PipPlayer&) = delete;
  PipPlayer& operator=(const PipPlayer&) = delete;

  // Open the PiP window and start playback. Returns false on failure.
  bool Open(const std::string& url,
            const std::map<std::string, std::string>& headers,
            int64_t position_ms,
            float playback_rate,
            bool was_playing,
            const std::wstring& title,
            DismissCallback on_dismiss,
            CompletedCallback on_complete);

  // Close the window and stop playback without firing the dismiss callback.
  void Close();

  bool IsOpen() const { return hwnd_ != nullptr; }

 private:
  static ATOM RegisterClass();
  static LRESULT CALLBACK WndProc(HWND hwnd,
                                  UINT msg,
                                  WPARAM wp,
                                  LPARAM lp) noexcept;

  LRESULT HandleMessage(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) noexcept;

  // Do not name this CreateWindow. Windows defines CreateWindow as a macro.
  bool CreatePipWindow(const std::wstring& title);

  bool SetupD3D11();
  void ResizeSwapChain(int w, int h);

  void SetupMdkPlayer(const std::string& url,
                      const std::map<std::string, std::string>& headers,
                      int64_t position_ms,
                      float playback_rate,
                      bool was_playing);

  void Dismiss(bool was_playing);
  void Cleanup();

  HWND hwnd_ = nullptr;
  int width_ = 640;
  int height_ = 392;  // 360 client + title bar area.

  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> ctx_;
  Microsoft::WRL::ComPtr<IDXGISwapChain> swap_chain_;
  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> rtv_;

  // Newer MDK headers return const mdkPlayerAPI*.
  const mdkPlayerAPI* player_api_ = nullptr;

  DismissCallback on_dismiss_;
  CompletedCallback on_complete_;
  bool dismissed_ = false;
};

}  // namespace pip

#endif  // RUNNER_PIP_PLAYER_H_