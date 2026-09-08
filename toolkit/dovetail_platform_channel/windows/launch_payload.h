#ifndef DOVETAIL_LAUNCH_PAYLOAD_H_
#define DOVETAIL_LAUNCH_PAYLOAD_H_

#include <stdint.h>

#include <string>

namespace dovetail {

std::wstring CurrentDirectory();

std::wstring EncodeLaunch(const std::wstring& directory,
                          const wchar_t* const* arguments,
                          int32_t count);

std::wstring MutexName(const std::wstring& key);

std::wstring ClassName(const std::wstring& key);

std::wstring WindowName(const std::wstring& key);

}  // namespace dovetail

#endif
