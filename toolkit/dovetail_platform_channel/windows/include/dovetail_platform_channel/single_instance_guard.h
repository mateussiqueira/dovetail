#ifndef DOVETAIL_SINGLE_INSTANCE_GUARD_H_
#define DOVETAIL_SINGLE_INSTANCE_GUARD_H_

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#if defined(DOVETAIL_BUILDING_DLL)
#define DOVETAIL_EXPORT __declspec(dllexport)
#else
#define DOVETAIL_EXPORT __declspec(dllimport)
#endif

typedef enum {
  DovetailInstancePrimary = 0,
  DovetailInstanceSecondary = 1,
  DovetailInstanceUnavailable = 2,
} DovetailInstanceVerdict;

DOVETAIL_EXPORT int32_t DovetailClaimPrimaryInstance(
    const wchar_t* instance_key,
    const wchar_t* const* arguments,
    int32_t count);

DOVETAIL_EXPORT wchar_t* DovetailTakeForwardedLaunch(int32_t* length);

DOVETAIL_EXPORT void DovetailFreeForwardedLaunch(wchar_t* payload);

DOVETAIL_EXPORT void DovetailReleasePrimaryInstance(void);

#if defined(__cplusplus)
}
#endif

#endif
