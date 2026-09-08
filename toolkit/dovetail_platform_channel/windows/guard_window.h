#ifndef DOVETAIL_GUARD_WINDOW_H_
#define DOVETAIL_GUARD_WINDOW_H_

#include <string>

namespace dovetail {

bool OpenGuardWindow(const std::wstring& key);

void CloseGuardWindow();

bool TakeForwardedLaunch(std::wstring* payload);

}  // namespace dovetail

#endif
