#include "guard_window.h"

#include <windows.h>

#include <process.h>

#include <atomic>
#include <deque>
#include <mutex>

#include "launch_payload.h"

namespace dovetail {

namespace {

constexpr wchar_t kSeparator = L'\0';
constexpr DWORD kOpenTimeoutMs = 5000;
constexpr DWORD kCloseTimeoutMs = 5000;

std::atomic<HWND> g_window{nullptr};
std::mutex g_queue_lock;
std::deque<std::wstring> g_queue;
std::wstring g_class_name;
std::wstring g_window_name;
HANDLE g_pump = nullptr;
HANDLE g_opened = nullptr;

void Enqueue(const COPYDATASTRUCT* data) {
  const size_t characters = data->cbData / sizeof(wchar_t);
  std::wstring payload(static_cast<const wchar_t*>(data->lpData), characters);
  if (!payload.empty() && payload.back() == kSeparator) {
    payload.pop_back();
  }

  const std::lock_guard<std::mutex> guard(g_queue_lock);
  g_queue.push_back(payload);
}

LRESULT CALLBACK GuardWindowProc(HWND window, UINT message, WPARAM w,
                                 LPARAM l) {
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  if (message != WM_COPYDATA) {
    return DefWindowProcW(window, message, w, l);
  }

  auto* data = reinterpret_cast<COPYDATASTRUCT*>(l);
  if (data != nullptr && data->lpData != nullptr && data->cbData != 0) {
    Enqueue(data);
  }
  return TRUE;
}

unsigned __stdcall Pump(void*) {
  WNDCLASSEXW description = {};
  description.cbSize = sizeof(WNDCLASSEXW);
  description.lpfnWndProc = GuardWindowProc;
  description.hInstance = GetModuleHandleW(nullptr);
  description.lpszClassName = g_class_name.c_str();

  if (RegisterClassExW(&description) == 0 &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    SetEvent(g_opened);
    return 1;
  }

  g_window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                             g_class_name.c_str(), g_window_name.c_str(), 0, 0,
                             0, 0, 0, nullptr, nullptr, description.hInstance,
                             nullptr);
  SetEvent(g_opened);
  if (g_window == nullptr) {
    return 1;
  }

  MSG message;
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  g_window = nullptr;
  return 0;
}

}  // namespace

bool OpenGuardWindow(const std::wstring& key) {
  if (g_window != nullptr) {
    return true;
  }

  g_class_name = ClassName(key);
  g_window_name = WindowName(key);
  g_opened = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_opened == nullptr) {
    return false;
  }

  g_pump = reinterpret_cast<HANDLE>(
      _beginthreadex(nullptr, 0, Pump, nullptr, 0, nullptr));
  if (g_pump == nullptr) {
    CloseGuardWindow();
    return false;
  }

  const DWORD waited = WaitForSingleObject(g_opened, kOpenTimeoutMs);
  if (waited != WAIT_OBJECT_0 || g_window == nullptr) {
    CloseGuardWindow();
    return false;
  }
  return true;
}

void CloseGuardWindow() {
  const HWND window = g_window.exchange(nullptr);
  if (window != nullptr) {
    PostMessageW(window, WM_CLOSE, 0, 0);
  }
  if (g_pump != nullptr) {
    WaitForSingleObject(g_pump, kCloseTimeoutMs);
    CloseHandle(g_pump);
    g_pump = nullptr;
  }
  if (g_opened != nullptr) {
    CloseHandle(g_opened);
    g_opened = nullptr;
  }
  if (!g_class_name.empty()) {
    UnregisterClassW(g_class_name.c_str(), GetModuleHandleW(nullptr));
    g_class_name.clear();
  }
  g_window_name.clear();

  const std::lock_guard<std::mutex> guard(g_queue_lock);
  g_queue.clear();
}

bool TakeForwardedLaunch(std::wstring* payload) {
  const std::lock_guard<std::mutex> guard(g_queue_lock);
  if (g_queue.empty()) {
    return false;
  }
  *payload = g_queue.front();
  g_queue.pop_front();
  return true;
}

}  // namespace dovetail
