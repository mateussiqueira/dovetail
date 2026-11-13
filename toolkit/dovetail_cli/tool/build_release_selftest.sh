#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
version="$(awk '/^version:/ {gsub(/\r/, ""); print $2; exit}' "$here/../pubspec.yaml")"
export TEST_VERSION="$version" TEST_TRACE="$tmp/trace"
cat > "$tmp/bin/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in -s) echo "$TEST_OS" ;; -m) echo "$TEST_ARCH" ;; esac
SH
cat > "$tmp/bin/dart" <<'SH'
#!/usr/bin/env bash
if [ "$1" = --version ]; then echo 'Dart SDK version: 3.11.0'; exit; fi
printf '%s\n' "$@" > "$TEST_TRACE.compile"
while [ "$1" != -o ]; do shift; done
printf '#!/usr/bin/env bash\necho "dovetail %s"\necho ran >> "%s.run"\n' "$TEST_VERSION" "$TEST_TRACE" > "$2"
chmod +x "$2"
SH
cat > "$tmp/bin/tar" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_TRACE.archive"
if [ "$1" = -a ]; then shift; fi
shift
printf 'archive\n' > "$1"
SH
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" DOVETAIL_DART="$tmp/bin/dart" DOVETAIL_TAR="$tmp/bin/tar"
export TEST_OS TEST_ARCH
check() {
  local target="$1" extension="$2" binary="$3"
  rm -f "$TEST_TRACE.run"
  bash "$here/build_release.sh" --target "$target" "$tmp/out" > "$tmp/output" 2>&1 || { cat "$tmp/output"; exit 1; }
  test -f "$tmp/out/dovetail-$version-$target.$extension"
  grep -Fxq -- "$binary" "$TEST_TRACE.archive"
  grep -Eq '^[0-9a-f]{64}$' "$tmp/out/dovetail-$version-$target.$extension.sha256"
}
for target in windows-x64 windows-arm64 macos-arm64 macos-x64 linux-x64 linux-arm64; do
  case "$target" in macos-*) TEST_OS=Darwin ;; windows-*) TEST_OS=MINGW64_NT-10.0 ;; linux-*) TEST_OS=Linux ;; esac
  case "$target" in *-arm64) TEST_ARCH=aarch64 ;; *) TEST_ARCH=x86_64 ;; esac
  case "$target" in windows-*) check "$target" zip dovetail.exe ;; *) check "$target" tar.gz dovetail ;; esac
  test -f "$TEST_TRACE.run"
done
TEST_OS=Darwin TEST_ARCH=arm64
check linux-x64 tar.gz dovetail
test ! -f "$TEST_TRACE.run"
grep -Fxq -- --target-os "$TEST_TRACE.compile"
check linux-arm64 tar.gz dovetail
test ! -f "$TEST_TRACE.run"
for target in windows-x64 macos-x64 linux-mips; do
  if bash "$here/build_release.sh" --target "$target" "$tmp/rejected" > "$tmp/output" 2>&1; then
    echo "unexpectedly accepted $target" >&2; exit 1
  fi
done
(
  source "$here/release_platform.sh"
  command() { if [ "$*" = '-v shasum' ]; then return 1; else builtin command "$@"; fi; }
  release_checksum "$TEST_TRACE.archive"
  expected="$(sha256sum "$TEST_TRACE.archive" | awk '{print $1}')"
  test "$(cat "$TEST_TRACE.archive.sha256")" = "$expected"
)
echo 'release platform matrix: 6 native, 2 Linux cross, 3 refusals, checksum fallback passed'
