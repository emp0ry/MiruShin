#include "window_geometry.h"

namespace {

constexpr const wchar_t kWindowGeometryRegKey[] =
    L"Software\\MiruShin\\Window";
constexpr int kMinimumWindowWidth = 640;
constexpr int kMinimumWindowHeight = 360;

bool ReadIntValue(HKEY key, const wchar_t* name, LONG* value) {
  DWORD raw_value = 0;
  DWORD value_size = sizeof(raw_value);
  LSTATUS result = RegGetValue(key, nullptr, name, RRF_RT_REG_DWORD, nullptr,
                               &raw_value, &value_size);
  if (result != ERROR_SUCCESS) {
    return false;
  }

  *value = static_cast<LONG>(raw_value);
  return true;
}

void WriteIntValue(HKEY key, const wchar_t* name, LONG value) {
  DWORD raw_value = static_cast<DWORD>(value);
  RegSetValueEx(key, name, 0, REG_DWORD,
                reinterpret_cast<const BYTE*>(&raw_value), sizeof(raw_value));
}

bool IsUsableRect(const RECT& rect) {
  const LONG width = rect.right - rect.left;
  const LONG height = rect.bottom - rect.top;
  if (width < kMinimumWindowWidth || height < kMinimumWindowHeight) {
    return false;
  }

  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONULL);
  if (monitor == nullptr) {
    return false;
  }

  MONITORINFO monitor_info;
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return true;
  }

  RECT visible_rect;
  return IntersectRect(&visible_rect, &rect, &monitor_info.rcWork) &&
         visible_rect.right > visible_rect.left &&
         visible_rect.bottom > visible_rect.top;
}

}  // namespace

std::optional<RECT> LoadWindowGeometry() {
  HKEY key = nullptr;
  LSTATUS result = RegOpenKeyEx(HKEY_CURRENT_USER, kWindowGeometryRegKey, 0,
                                KEY_READ, &key);
  if (result != ERROR_SUCCESS) {
    return std::nullopt;
  }

  RECT rect;
  bool success = ReadIntValue(key, L"Left", &rect.left) &&
                 ReadIntValue(key, L"Top", &rect.top) &&
                 ReadIntValue(key, L"Right", &rect.right) &&
                 ReadIntValue(key, L"Bottom", &rect.bottom);
  RegCloseKey(key);

  if (!success || !IsUsableRect(rect)) {
    return std::nullopt;
  }

  return rect;
}

void SaveWindowGeometry(HWND window) {
  if (!IsWindow(window)) {
    return;
  }

  WINDOWPLACEMENT placement;
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement) ||
      placement.showCmd == SW_SHOWMINIMIZED) {
    return;
  }

  RECT rect;
  if (placement.showCmd == SW_SHOWMAXIMIZED) {
    rect = placement.rcNormalPosition;
  } else if (!GetWindowRect(window, &rect)) {
    return;
  }

  if (!IsUsableRect(rect)) {
    return;
  }

  HKEY key = nullptr;
  LSTATUS result = RegCreateKeyEx(HKEY_CURRENT_USER, kWindowGeometryRegKey, 0,
                                  nullptr, 0, KEY_WRITE, nullptr, &key,
                                  nullptr);
  if (result != ERROR_SUCCESS) {
    return;
  }

  WriteIntValue(key, L"Left", rect.left);
  WriteIntValue(key, L"Top", rect.top);
  WriteIntValue(key, L"Right", rect.right);
  WriteIntValue(key, L"Bottom", rect.bottom);
  RegCloseKey(key);
}
