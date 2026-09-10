#ifndef DOVETAIL_WINDOWS_SERVICE_H_
#define DOVETAIL_WINDOWS_SERVICE_H_

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

/*
 * Windows exports from a DLL loaded beside the executable. The header lives
 * at the package root rather than under windows/, the way the appearance
 * probe's does next door, so that a second platform reaching for this ABI
 * reads the same file instead of a copy that drifts.
 */
#if defined(_WIN32)
#if defined(DOVETAIL_BUILDING_DLL)
#define DOVETAIL_SERVICE_EXPORT __declspec(dllexport)
#else
#define DOVETAIL_SERVICE_EXPORT __declspec(dllimport)
#endif
#else
#define DOVETAIL_SERVICE_EXPORT __attribute__((visibility("default")))
#endif

/*
 * Every function returns a Win32 error code, zero for success, and that is
 * the whole of the contract.
 *
 * No translation happens on this side. `ERROR_SERVICE_DOES_NOT_EXIST` means
 * "offer to install", `ERROR_ACCESS_DENIED` means one thing for a read and
 * another for a write, and a start type of SERVICE_DISABLED means an
 * administrator has forbidden it — reading all that is the Dart side's job,
 * in WindowsServiceStatus, where a test can put any code in and see what
 * comes out. This code has never run on a Windows machine; that one runs on
 * every machine the gate touches.
 */

/*
 * Writes the service's start type and returns the error that reading it
 * produced. `start_type` is one of the SERVICE_*_START values from winsvc.h,
 * or SERVICE_DISABLED.
 */
DOVETAIL_SERVICE_EXPORT int32_t
DovetailWindowsServiceQuery(const char* name, int32_t* start_type);

/*
 * Creates a demand-start, own-process service running `image_path`.
 *
 * Needs an elevated caller; an ordinary app gets ERROR_ACCESS_DENIED, which
 * is the expected answer and not a fault.
 */
DOVETAIL_SERVICE_EXPORT int32_t DovetailWindowsServiceCreate(
    const char* name,
    const char* display_name,
    const char* image_path);

/* Marks the service for deletion. Also needs an elevated caller. */
DOVETAIL_SERVICE_EXPORT int32_t DovetailWindowsServiceDelete(const char* name);

#if defined(__cplusplus)
}
#endif

#endif
