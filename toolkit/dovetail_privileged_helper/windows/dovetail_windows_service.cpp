#include "dovetail_windows_service.h"

#include <windows.h>

#include <string>
#include <vector>

namespace {

/*
 * UTF-8 in, UTF-16 out, because every call below is a W entry point.
 *
 * The A entry points would be one conversion shorter and would put a service
 * name or an install path through whatever code page this machine happens to
 * have. A path under a user folder named in Cyrillic or Japanese survives the
 * round trip here and does not survive it there, and the failure looks like
 * "the service is not installed" rather than like a mangled name.
 */
std::wstring Widen(const char* utf8) {
  if (utf8 == nullptr) {
    return std::wstring();
  }
  const int needed = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
  if (needed <= 1) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(needed - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &wide[0], needed);
  return wide;
}

/* Closes an SC_HANDLE on every path out, including the early returns. */
class ScopedServiceHandle {
 public:
  explicit ScopedServiceHandle(SC_HANDLE handle) : handle_(handle) {}
  ~ScopedServiceHandle() {
    if (handle_ != nullptr) {
      CloseServiceHandle(handle_);
    }
  }

  ScopedServiceHandle(const ScopedServiceHandle&) = delete;
  ScopedServiceHandle& operator=(const ScopedServiceHandle&) = delete;

  SC_HANDLE get() const { return handle_; }
  bool valid() const { return handle_ != nullptr; }

 private:
  SC_HANDLE handle_;
};

}  // namespace

int32_t DovetailWindowsServiceQuery(const char* name, int32_t* start_type) {
  if (name == nullptr || start_type == nullptr) {
    return static_cast<int32_t>(ERROR_INVALID_PARAMETER);
  }
  *start_type = 0;

  const std::wstring wide_name = Widen(name);
  if (wide_name.empty()) {
    return static_cast<int32_t>(ERROR_INVALID_PARAMETER);
  }

  /*
   * SC_MANAGER_CONNECT and SERVICE_QUERY_CONFIG: the least this needs.
   *
   * Both are granted to authenticated users by the default security
   * descriptor, so an ordinary app reads a service's configuration without
   * elevation. That is what lets the Dart side read ERROR_ACCESS_DENIED here
   * as a machine that was deliberately locked down, rather than as the
   * everyday "you are not an administrator".
   */
  ScopedServiceHandle manager(OpenSCManagerW(nullptr, nullptr,
                                             SC_MANAGER_CONNECT));
  if (!manager.valid()) {
    return static_cast<int32_t>(GetLastError());
  }

  ScopedServiceHandle service(
      OpenServiceW(manager.get(), wide_name.c_str(), SERVICE_QUERY_CONFIG));
  if (!service.valid()) {
    return static_cast<int32_t>(GetLastError());
  }

  /*
   * The first QueryServiceConfigW is expected to fail. There is no way to ask
   * how big the configuration is other than to ask for it into nothing and
   * read the size out of the failure, so ERROR_INSUFFICIENT_BUFFER here is
   * the success path and anything else is not.
   */
  DWORD needed = 0;
  if (QueryServiceConfigW(service.get(), nullptr, 0, &needed)) {
    return static_cast<int32_t>(ERROR_INVALID_DATA);
  }
  const DWORD sizing_error = GetLastError();
  if (sizing_error != ERROR_INSUFFICIENT_BUFFER || needed == 0) {
    return static_cast<int32_t>(sizing_error);
  }

  std::vector<unsigned char> buffer(needed);
  LPQUERY_SERVICE_CONFIGW config =
      reinterpret_cast<LPQUERY_SERVICE_CONFIGW>(buffer.data());
  if (!QueryServiceConfigW(service.get(), config, needed, &needed)) {
    return static_cast<int32_t>(GetLastError());
  }

  *start_type = static_cast<int32_t>(config->dwStartType);
  return 0;
}

int32_t DovetailWindowsServiceCreate(const char* name,
                                     const char* display_name,
                                     const char* image_path) {
  const std::wstring wide_name = Widen(name);
  const std::wstring wide_display = Widen(display_name);
  const std::wstring wide_image = Widen(image_path);
  if (wide_name.empty() || wide_display.empty() || wide_image.empty()) {
    return static_cast<int32_t>(ERROR_INVALID_PARAMETER);
  }

  ScopedServiceHandle manager(
      OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE));
  if (!manager.valid()) {
    return static_cast<int32_t>(GetLastError());
  }

  /*
   * SERVICE_DEMAND_START, not SERVICE_AUTO_START.
   *
   * This is the one policy this file cannot avoid choosing — CreateServiceW
   * has no "unspecified" — and demand start is the smaller promise: a root
   * process that exists when the application asks for it, rather than one on
   * every boot of a machine whose owner may never open the app again. An
   * installer that wants otherwise is the right place to say so, and it can,
   * because it created the service in the first place.
   */
  ScopedServiceHandle service(CreateServiceW(
      manager.get(), wide_name.c_str(), wide_display.c_str(),
      SERVICE_CHANGE_CONFIG, SERVICE_WIN32_OWN_PROCESS, SERVICE_DEMAND_START,
      SERVICE_ERROR_NORMAL, wide_image.c_str(), nullptr, nullptr, nullptr,
      nullptr, nullptr));
  if (!service.valid()) {
    return static_cast<int32_t>(GetLastError());
  }
  return 0;
}

int32_t DovetailWindowsServiceDelete(const char* name) {
  const std::wstring wide_name = Widen(name);
  if (wide_name.empty()) {
    return static_cast<int32_t>(ERROR_INVALID_PARAMETER);
  }

  ScopedServiceHandle manager(OpenSCManagerW(nullptr, nullptr,
                                             SC_MANAGER_CONNECT));
  if (!manager.valid()) {
    return static_cast<int32_t>(GetLastError());
  }

  ScopedServiceHandle service(
      OpenServiceW(manager.get(), wide_name.c_str(), DELETE));
  if (!service.valid()) {
    return static_cast<int32_t>(GetLastError());
  }

  /*
   * DeleteService MARKS the service for deletion. It disappears when the last
   * open handle to it closes, which may be after this function returns and
   * may be after the caller has read the status again. A read taken
   * immediately afterwards can still find the service, and that is Windows
   * behaving as documented rather than the deletion having failed.
   */
  if (!DeleteService(service.get())) {
    return static_cast<int32_t>(GetLastError());
  }
  return 0;
}
