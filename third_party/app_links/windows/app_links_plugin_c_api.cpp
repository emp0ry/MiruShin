#include "include/app_links/app_links_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "app_links_plugin.h"

void AppLinksPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
    applinks::AppLinksPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

// Method to dispatch new arguments to launched app
void SendAppLink(HWND hwnd) {
    auto link = applinks::AppLinksPlugin::GetLink();
    if (!link.has_value()) {
        return;
    }

    // WM_COPYDATA defines wParam as a window owned by the sending process.
    // The upstream helper historically passed the recipient window instead,
    // which made its same-executable check inspect the wrong process.
    HWND sender = CreateWindowExW(
        0, L"STATIC", L"MiruShin app-link sender", 0, 0, 0, 0, 0,
        HWND_MESSAGE, nullptr, GetModuleHandleW(nullptr), nullptr);
    if (sender == nullptr) {
        return;
    }

    COPYDATASTRUCT cds = { 0 };
    cds.dwData = APPLINK_MSG_ID;
    cds.cbData = (DWORD)(link.value().size() + 1);
    cds.lpData = (PVOID)link.value().c_str();

    SendMessage(hwnd, WM_COPYDATA, (WPARAM)sender, (LPARAM)(LPVOID)&cds);
    DestroyWindow(sender);
}
