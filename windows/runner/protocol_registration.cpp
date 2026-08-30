#include "protocol_registration.h"

#include <windows.h>

#include <string>
#include <vector>

namespace {

constexpr wchar_t kProtocolKey[] = L"Software\\Classes\\mirushin";

std::wstring CurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (buffer.size() <= 32768) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return L"";
    if (length < buffer.size() - 1) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2);
  }
  return L"";
}

void SetStringValueIfNeeded(HKEY key, const wchar_t* name,
                            const std::wstring& expected) {
  DWORD type = 0;
  DWORD byte_count = 0;
  const LONG size_result =
      RegQueryValueExW(key, name, nullptr, &type, nullptr, &byte_count);
  if (size_result == ERROR_SUCCESS && type == REG_SZ && byte_count >= 2) {
    std::vector<wchar_t> current(byte_count / sizeof(wchar_t));
    DWORD read_count = byte_count;
    if (RegQueryValueExW(key, name, nullptr, &type,
                        reinterpret_cast<BYTE*>(current.data()),
                        &read_count) == ERROR_SUCCESS) {
      std::wstring current_value(current.data(),
                                 read_count / sizeof(wchar_t));
      while (!current_value.empty() && current_value.back() == L'\0') {
        current_value.pop_back();
      }
      if (current_value == expected) return;
    }
  }
  RegSetValueExW(
      key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(expected.c_str()),
      static_cast<DWORD>((expected.size() + 1) * sizeof(wchar_t)));
}

HKEY OpenWritableKey(const wchar_t* path) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, path, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_QUERY_VALUE | KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return nullptr;
  }
  return key;
}

std::wstring ProtocolCommand(const std::wstring& executable) {
  return L"\"" + executable + L"\" \"%1\"";
}

bool ReadStringValue(HKEY key, const wchar_t* name, std::wstring* value) {
  DWORD type = 0;
  DWORD byte_count = 0;
  if (RegQueryValueExW(key, name, nullptr, &type, nullptr, &byte_count) !=
          ERROR_SUCCESS ||
      type != REG_SZ || byte_count < sizeof(wchar_t)) {
    return false;
  }
  std::vector<wchar_t> buffer(byte_count / sizeof(wchar_t));
  DWORD read_count = byte_count;
  if (RegQueryValueExW(key, name, nullptr, &type,
                       reinterpret_cast<BYTE*>(buffer.data()),
                       &read_count) != ERROR_SUCCESS) {
    return false;
  }
  *value = std::wstring(buffer.data(), read_count / sizeof(wchar_t));
  while (!value->empty() && value->back() == L'\0') value->pop_back();
  return true;
}

}  // namespace

void RepairMiruShinProtocolRegistration() {
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) return;

  if (HKEY protocol = OpenWritableKey(kProtocolKey)) {
    SetStringValueIfNeeded(protocol, nullptr, L"URL:MiruShin Protocol");
    SetStringValueIfNeeded(protocol, L"URL Protocol", L"");
    RegCloseKey(protocol);
  }

  if (HKEY command = OpenWritableKey(
          L"Software\\Classes\\mirushin\\shell\\open\\command")) {
    SetStringValueIfNeeded(command, nullptr, ProtocolCommand(executable));
    RegCloseKey(command);
  }
}

void RemoveMiruShinProtocolRegistrationIfOwned() {
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) return;

  HKEY command = nullptr;
  if (RegOpenKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\mirushin\\shell\\open\\command", 0,
          KEY_QUERY_VALUE, &command) != ERROR_SUCCESS) {
    return;
  }
  std::wstring current;
  const bool owned = ReadStringValue(command, nullptr, &current) &&
                     _wcsicmp(current.c_str(),
                              ProtocolCommand(executable).c_str()) == 0;
  RegCloseKey(command);
  if (owned) {
    RegDeleteTreeW(HKEY_CURRENT_USER, kProtocolKey);
  }
}
