#include <windows.h>

#include <stdio.h>
#include <string>
#include <vector>

#include "../include/dovetail_platform_channel/single_instance_guard.h"

namespace {

constexpr int kPollMs = 50;

std::string Narrow(const wchar_t* text, int32_t length) {
  if (length <= 0) {
    return std::string();
  }
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, text, length, nullptr, 0,
                                        nullptr, nullptr);
  std::string narrow(static_cast<size_t>(bytes), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, length, narrow.data(), bytes, nullptr,
                      nullptr);
  return narrow;
}

void Report(const char* label, int32_t verdict) {
  const char* name = verdict == DovetailInstancePrimary
                         ? "primary"
                         : (verdict == DovetailInstanceSecondary ? "secondary"
                                                                 : "unavailable");
  printf("%s verdict=%s\n", label, name);
  fflush(stdout);
}

int Drain(int expected, int budget_ms) {
  int seen = 0;
  for (int waited = 0; waited < budget_ms && seen < expected;
       waited += kPollMs) {
    int32_t length = 0;
    wchar_t* payload = DovetailTakeForwardedLaunch(&length);
    if (payload == nullptr) {
      Sleep(kPollMs);
      continue;
    }

    std::string narrow = Narrow(payload, length);
    for (char& character : narrow) {
      if (character == '\0') {
        character = '|';
      }
    }
    printf("primary took=%s\n", narrow.c_str());
    fflush(stdout);
    DovetailFreeForwardedLaunch(payload);
    seen++;
  }
  return seen;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc < 3) {
    printf("usage: guard_probe <primary|secondary|orphan> <key> [args...]\n");
    return 2;
  }

  const std::wstring role(argv[1]);
  const wchar_t* key = argv[2];
  std::vector<const wchar_t*> arguments;
  for (int index = 3; index < argc; index++) {
    arguments.push_back(argv[index]);
  }

  const int32_t verdict = DovetailClaimPrimaryInstance(
      key, arguments.empty() ? nullptr : arguments.data(),
      static_cast<int32_t>(arguments.size()));

  if (role == L"primary") {
    Report("primary", verdict);
    const int taken = Drain(1, 8000);
    printf("primary drained=%d\n", taken);
    DovetailReleasePrimaryInstance();
    printf("primary released\n");
    return taken == 1 ? 0 : 1;
  }

  if (role == L"orphan") {
    Report("orphan", verdict);
    fflush(stdout);
    ExitProcess(0);
  }

  Report("secondary", verdict);
  DovetailReleasePrimaryInstance();
  return verdict == DovetailInstanceSecondary ? 0 : 1;
}
