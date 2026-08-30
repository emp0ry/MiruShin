#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <app_links/app_links_plugin_c_api.h>
#include <windows.h>

#include <optional>
#include <string>

#include "flutter_window.h"
#include "protocol_registration.h"
#include "utils.h"
#include "window_geometry.h"

namespace {

bool HandleProtocolMaintenanceCommand() {
  int argument_count = 0;
  wchar_t** arguments =
      ::CommandLineToArgvW(::GetCommandLineW(), &argument_count);
  if (arguments == nullptr) return false;
  bool handled = false;
  if (argument_count == 2 &&
      ::wcscmp(arguments[1], L"--register-protocol") == 0) {
    RepairMiruShinProtocolRegistration();
    handled = true;
  } else if (argument_count == 2 &&
             ::wcscmp(arguments[1], L"--unregister-protocol-if-owned") == 0) {
    RemoveMiruShinProtocolRegistrationIfOwned();
    handled = true;
  }
  ::LocalFree(arguments);
  return handled;
}

bool SendAppLinkToInstance(const std::wstring& window_title) {
  HWND existing =
      ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", window_title.c_str());
  if (existing == nullptr) return false;

  SendAppLink(existing);
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  }
  ::SetForegroundWindow(existing);
  ::BringWindowToTop(existing);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (HandleProtocolMaintenanceCommand()) {
    return EXIT_SUCCESS;
  }

  RepairMiruShinProtocolRegistration();
  if (SendAppLinkToInstance(L"MiruShin")) {
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  std::optional<RECT> saved_bounds = LoadWindowGeometry();
  if (!(saved_bounds ? window.Create(L"MiruShin", *saved_bounds)
                     : window.Create(L"MiruShin", origin, size))) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
