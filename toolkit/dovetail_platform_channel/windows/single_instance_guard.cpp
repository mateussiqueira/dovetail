#include "include/dovetail_platform_channel/single_instance_guard.h"

#include <windows.h>

#include <string>

#include "guard_window.h"
#include "launch_payload.h"

namespace {

constexpr int kForwardAttempts = 40;
constexpr DWORD kForwardWaitMs = 50;
constexpr DWORD kAnswerTimeoutMs = 3000;

HANDLE g_mutex = nullptr;

bool Deliver(HWND primary, const std::wstring& payload) {
  DWORD owner = 0;
  GetWindowThreadProcessId(primary, &owner);
  if (owner != 0) {
    AllowSetForegroundWindow(owner);
  }

  COPYDATASTRUCT data = {};
  data.dwData = 0;
  data.cbData = static_cast<DWORD>((payload.size() + 1) * sizeof(wchar_t));
  data.lpData = const_cast<wchar_t*>(payload.c_str());

  DWORD_PTR answered = 0;
  return SendMessageTimeoutW(primary, WM_COPYDATA, 0,
                             reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                             kAnswerTimeoutMs, &answered) != 0;
}

bool ForwardToPrimary(const std::wstring& key, const std::wstring& payload) {
  const std::wstring class_name = dovetail::ClassName(key);
  const std::wstring window_name = dovetail::WindowName(key);

  for (int attempt = 0; attempt < kForwardAttempts; attempt++) {
    HWND primary = FindWindowExW(nullptr, nullptr, class_name.c_str(),
                                 window_name.c_str());
    if (primary != nullptr) {
      return Deliver(primary, payload);
    }
    Sleep(kForwardWaitMs);
  }
  return false;
}

}  // namespace

int32_t DovetailClaimPrimaryInstance(const wchar_t* instance_key,
                                     const wchar_t* const* arguments,
                                     int32_t count) {
  if (instance_key == nullptr) {
    return DovetailInstanceUnavailable;
  }
  if (g_mutex != nullptr) {
    return DovetailInstancePrimary;
  }

  const std::wstring key(instance_key);
  HANDLE claimed =
      CreateMutexW(nullptr, FALSE, dovetail::MutexName(key).c_str());
  if (claimed == nullptr) {
    return DovetailInstanceUnavailable;
  }

  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(claimed);
    const std::wstring payload = dovetail::EncodeLaunch(
        dovetail::CurrentDirectory(), arguments, count);
    return ForwardToPrimary(key, payload) ? DovetailInstanceSecondary
                                          : DovetailInstanceUnavailable;
  }

  if (!dovetail::OpenGuardWindow(key)) {
    CloseHandle(claimed);
    return DovetailInstanceUnavailable;
  }

  g_mutex = claimed;
  return DovetailInstancePrimary;
}

wchar_t* DovetailTakeForwardedLaunch(int32_t* length) {
  if (length != nullptr) {
    *length = 0;
  }

  std::wstring payload;
  if (!dovetail::TakeForwardedLaunch(&payload)) {
    return nullptr;
  }

  const size_t bytes = (payload.size() + 1) * sizeof(wchar_t);
  auto* copy = static_cast<wchar_t*>(CoTaskMemAlloc(bytes));
  if (copy == nullptr) {
    return nullptr;
  }
  memcpy(copy, payload.data(), payload.size() * sizeof(wchar_t));
  copy[payload.size()] = L'\0';
  if (length != nullptr) {
    *length = static_cast<int32_t>(payload.size());
  }
  return copy;
}

void DovetailFreeForwardedLaunch(wchar_t* payload) {
  if (payload != nullptr) {
    CoTaskMemFree(payload);
  }
}

void DovetailReleasePrimaryInstance(void) {
  dovetail::CloseGuardWindow();
  if (g_mutex != nullptr) {
    CloseHandle(g_mutex);
    g_mutex = nullptr;
  }
}
