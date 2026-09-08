#!/usr/bin/env bash
set -euo pipefail

# Compiles the Windows single instance guard away from Windows, and runs the
# two process scenario if there is a Wine on this host to run it with. MSVC is
# what the Flutter build uses; this catches what a compiler catches, which is
# what "never compiled anywhere" cost us before.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$here/../../dist/guard-probe}"
cxx="${MINGW_CXX:-x86_64-w64-mingw32-g++}"
objdump="${MINGW_OBJDUMP:-x86_64-w64-mingw32-objdump}"

if ! command -v "$cxx" > /dev/null 2>&1; then
  echo "no $cxx on PATH" >&2
  echo "  brew install mingw-w64, or set MINGW_CXX" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$out"

echo "==> the dll"
"$cxx" -std=c++17 -Wall -Wextra -Werror -DDOVETAIL_BUILDING_DLL -shared \
  -o "$out/dovetail_platform_channel.dll" \
  "$here/windows/single_instance_guard.cpp" \
  "$here/windows/guard_window.cpp" \
  "$here/windows/launch_payload.cpp" \
  -lole32 -luser32 -static -Wl,--out-implib,"$out/libguard.a"

exports="$("$objdump" -p "$out/dovetail_platform_channel.dll")"
for exported in DovetailClaimPrimaryInstance DovetailTakeForwardedLaunch \
  DovetailFreeForwardedLaunch DovetailReleasePrimaryInstance; do
  case "$exports" in
    *"$exported"*) echo "    exports $exported" ;;
    *) echo "the dll does not export $exported" >&2; exit 1 ;;
  esac
done

echo "==> the probe"
"$cxx" -std=c++17 -Wall -Wextra -Werror -municode -o "$out/guard_probe.exe" \
  "$here/windows/test/guard_probe.cpp" -L"$out" -l:libguard.a -static

wine="${WINE:-wine}"
if ! command -v "$wine" > /dev/null 2>&1; then
  if [ -n "${DOVETAIL_GUARD_DRIVER:-}" ]; then
    echo "    compiled and linked"
    exit 0
  fi
  echo
  echo "compiled and linked, and nothing ran it."
  echo "  The scenario needs a Windows or a Wine. The wine-stable cask was"
  echo "  disabled on 2026-09-01 for failing the macOS Gatekeeper check, so"
  echo "  on this host the guard is compiled and not exercised. Set WINE to"
  echo "  run it, or run this on the Windows runner."
  exit 0
fi

key="dovetail-probe-$$"
echo
echo "==> a process that claims and dies without releasing"
"$wine" "$out/guard_probe.exe" orphan "$key-a" 2>/dev/null | sed 's/^/    /'
"$wine" "$out/guard_probe.exe" orphan "$key-a" 2>/dev/null | sed 's/^/    /'

echo "==> a second launch forwarded to the first"
"$wine" "$out/guard_probe.exe" primary "$key-b" > "$out/primary.log" 2>/dev/null &
primary=$!
sleep 2
"$wine" "$out/guard_probe.exe" secondary "$key-b" --quiet myid://pair/9f2c \
  2>/dev/null | sed 's/^/    /'
wait $primary
sed 's/^/    /' "$out/primary.log"

grep -q 'primary drained=1' "$out/primary.log"
echo "    the forwarded launch reached the first process"
