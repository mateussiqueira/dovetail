#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/repo"
mkdir -p "$fixture/tool/sdk/templates" "$fixture/toolkit/dovetail_cli/tool" "$fixture/keys" "$tmp/bin"
cp "$repo/tool/build_sdk.sh" "$fixture/tool/"
cp "$repo/toolkit/dovetail_cli/tool/"{build_release.sh,release_platform.sh} "$fixture/toolkit/dovetail_cli/tool/"
cp "$repo/toolkit/dovetail_cli/"{pubspec.yaml,CHANGELOG.md} "$fixture/toolkit/dovetail_cli/"
cp "$repo/tool/sdk/sdk_release.pub" "$fixture/tool/sdk/"
printf 'test-only fake key\n' > "$fixture/keys/sdk.key"
printf 'template\n' > "$fixture/tool/sdk/templates/fixture"
printf 'exit 0\n' > "$fixture/tool/build_xcframework.sh"
for package in dovetail dovetail_platform_channel dovetail_shortcut_channel dovetail_updater dovetail_form_validation dovetail_process_runner dovetail_rust_core; do
  directory="$fixture/toolkit/$package"
  mkdir -p "$directory/lib" "$directory/windows" "$directory/rust/target"
  printf 'name: %s\n' "$package" > "$directory/pubspec.yaml"
  printf 'fixture\n' | tee "$directory/pubspec.lock" "$directory/lib/fixture.dart" "$directory/windows/fixture.cc" "$directory/rust/target/excluded" >/dev/null
done
export TEST_VERSION="$(awk '/^version:/ {gsub(/\r/, "");print $2;exit}' "$fixture/toolkit/dovetail_cli/pubspec.yaml")"
cat > "$tmp/bin/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in -s) echo "$TEST_OS" ;; -m) echo "$TEST_ARCH" ;; esac
SH
cat > "$tmp/bin/dart" <<'SH'
#!/usr/bin/env bash
if [ "$1" = --version ]; then echo 'Dart SDK version: 3.11.0'; exit; fi
while [ "$1" != -o ]; do shift; done
printf '#!/usr/bin/env bash\necho "dovetail %s"\n' "$TEST_VERSION" > "$2"
chmod +x "$2"
SH
cat > "$tmp/bin/tar" <<'SH'
#!/usr/bin/env bash
if [ "$1" = -a ]; then shift; fi
shift; archive="$1"; shift 2; stage="$1"; shift
(cd "$stage"; find "$@" -type f | sort) > "$archive"
SH
cat > "$tmp/bin/minisign" <<'SH'
#!/usr/bin/env bash
test "$1" = -S && test "$2" = -x
printf 'test-only signature\n' > "$3"
SH
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" DOVETAIL_DART="$tmp/bin/dart" DOVETAIL_TAR="$tmp/bin/tar" TEST_OS TEST_ARCH
for target in windows-x64 windows-arm64 macos-arm64 macos-x64 linux-x64 linux-arm64; do
  case "$target" in windows-*) TEST_OS=MINGW64_NT-10.0; extension=zip; binary=dovetail.exe ;; macos-*) TEST_OS=Darwin; extension=tar.gz; binary=dovetail ;; linux-*) TEST_OS=Linux; extension=tar.gz; binary=dovetail ;; esac
  case "$target" in *-arm64) TEST_ARCH=aarch64 ;; *) TEST_ARCH=x86_64 ;; esac
  bash "$fixture/tool/build_sdk.sh" --target "$target" --out "$tmp/out" > "$tmp/output" 2>&1 || { cat "$tmp/output"; exit 1; }
  archive="$tmp/out/dovetail-sdk-$TEST_VERSION-$target.$extension"
  test -f "$archive.minisig"
  grep -Fxq "bin/$binary" "$archive"
  grep -Fxq "sdk/$TEST_VERSION/templates/fixture" "$archive"
  for package in dovetail dovetail_platform_channel dovetail_shortcut_channel dovetail_updater dovetail_form_validation dovetail_process_runner dovetail_rust_core; do
    for entry in pubspec.yaml pubspec.lock lib/fixture.dart windows/fixture.cc; do
      grep -Fxq "sdk/$TEST_VERSION/packages/$package/$entry" "$archive"
    done
  done
  if grep -q /target/ "$archive"; then echo 'SDK leaked build output' >&2; exit 1; fi
  test "$(cat "$archive.sha256")" = "$(sha256sum "$archive" | awk '{print $1}')"
done
TEST_OS=Darwin TEST_ARCH=aarch64
if bash "$fixture/tool/build_sdk.sh" --target windows-x64 --out "$tmp/rejected" > "$tmp/output" 2>&1; then
  echo 'SDK accepted impossible Windows cross target' >&2; exit 1
fi
grep -q 'build_release.sh' "$tmp/output"
TEST_OS=Linux TEST_ARCH=aarch64
rm "$fixture/keys/sdk.key"
if bash "$fixture/tool/build_sdk.sh" --target linux-arm64 --out "$tmp/missing-key" > "$tmp/output" 2>&1; then
  echo 'SDK release accepted a missing signing key' >&2; exit 1
fi
grep -q 'no SDK release key' "$tmp/output"
echo 'SDK matrix: 6 simulated layouts, runtime/templates, pruning, checksums and missing-key refusal passed'
