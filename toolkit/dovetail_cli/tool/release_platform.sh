#!/usr/bin/env bash
release_platform() {
  local requested="$1" machine
  machine="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$machine" in
    darwin) host_os=macos ;;
    linux) host_os=linux ;;
    mingw*|msys*|cygwin*) host_os=windows ;;
    *) echo "unsupported release host: $machine" >&2; return 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) host_arch=arm64 ;;
    x86_64|amd64) host_arch=x64 ;;
    *) echo 'unsupported release host architecture' >&2; return 1 ;;
  esac
  requested="${requested:-$host_os-$host_arch}"
  case "$requested" in
    macos-arm64|macos-x64|windows-x64|windows-arm64|linux-x64|linux-arm64) ;;
    *) echo "unsupported release target: $requested" >&2; return 1 ;;
  esac
  target_os="${requested%-*}" target_arch="${requested##*-}" cross=""
  if [ "$requested" != "$host_os-$host_arch" ]; then
    if [ "$target_os" != linux ]; then
      echo "dart compile exe cross-compiles to Linux only; build $requested on its native host" >&2
      return 1
    fi
    cross=yes
  fi
  binary=dovetail extension=tar.gz
  if [ "$target_os" = windows ]; then binary=dovetail.exe; extension=zip; fi
  release_tar="${DOVETAIL_TAR:-tar}"
  if [ "$host_os" = windows ] && [ -z "${DOVETAIL_TAR:-}" ]; then
    release_tar="${SYSTEMROOT:-${WINDIR:-C:/Windows}}/System32/tar.exe"
  fi
}
release_checksum() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1"
  else
    sha256sum "$1"
  fi | awk '{print $1}' > "$1.sha256"
}
