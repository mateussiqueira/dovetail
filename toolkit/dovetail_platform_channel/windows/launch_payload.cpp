#include "launch_payload.h"

#include <windows.h>

#include <vector>

namespace dovetail {

namespace {

constexpr wchar_t kSeparator = L'\0';

}  // namespace

std::wstring CurrentDirectory() {
  const DWORD needed = GetCurrentDirectoryW(0, nullptr);
  if (needed == 0) {
    return std::wstring();
  }

  std::vector<wchar_t> buffer(needed);
  const DWORD written = GetCurrentDirectoryW(needed, buffer.data());
  if (written == 0 || written >= needed) {
    return std::wstring();
  }
  return std::wstring(buffer.data(), written);
}

std::wstring EncodeLaunch(const std::wstring& directory,
                          const wchar_t* const* arguments,
                          int32_t count) {
  std::wstring payload(directory);
  payload.push_back(kSeparator);
  payload.push_back(kSeparator);
  if (arguments == nullptr) {
    return payload;
  }

  for (int32_t index = 0; index < count; index++) {
    if (index > 0) {
      payload.push_back(kSeparator);
    }
    if (arguments[index] != nullptr) {
      payload.append(arguments[index]);
    }
  }
  return payload;
}

std::wstring MutexName(const std::wstring& key) { return key + L"-sim"; }

std::wstring ClassName(const std::wstring& key) { return key + L"-sic"; }

std::wstring WindowName(const std::wstring& key) { return key + L"-siw"; }

}  // namespace dovetail
