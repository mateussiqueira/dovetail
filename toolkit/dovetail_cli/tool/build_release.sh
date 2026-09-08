#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install_to=""
cross_target=""
while true; do
  case "${1:-}" in
    --install)
      install_to="${2:-$HOME/.local/bin}"
      case "${2:-}" in --*|"") shift ;; *) shift 2 ;; esac
      ;;
    --target)
      cross_target="${2:-}"
      if [ -z "$cross_target" ]; then
        echo "--target takes <os>-<arch>, for example linux-arm64" >&2
        exit 1
      fi
      shift 2
      ;;
    *) break ;;
  esac
done
out="${1:-$here/dist}"

version="$(grep -m1 '^version:' "$here/pubspec.yaml" | awk '{print $2}')"
dart_version="$(dart --version 2>&1 | awk '{print $4}')"
host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
host_arch="$(uname -m)"

case "$host_os" in
  darwin) target_os=macos ;;
  linux)  target_os=linux ;;
  *) echo "dovetail is built on macOS or Linux; this is $host_os" >&2; exit 1 ;;
esac

case "$host_arch" in
  arm64|aarch64) target_arch=arm64 ;;
  x86_64) target_arch=x64 ;;
  *) echo "no dovetail build for $host_arch" >&2; exit 1 ;;
esac

cross=""
if [ -n "$cross_target" ]; then
  target_os="${cross_target%-*}"
  target_arch="${cross_target##*-}"
  if [ "$target_os" != "linux" ]; then
    echo "dart compile exe cross-compiles to linux only; asked for $target_os" >&2
    echo "  A macOS or Windows binary is built on that system." >&2
    exit 1
  fi
  cross="yes"
fi

if ! grep -qE "^## $version( |\$)" "$here/CHANGELOG.md"; then
  echo "CHANGELOG.md has no '## $version' entry" >&2
  echo "  A binary goes to a machine you cannot see. Shipping a version" >&2
  echo "  nobody wrote down is a support call with nothing to read." >&2
  exit 1
fi

name="dovetail-$version-$target_os-$target_arch"
mkdir -p "$out"

# A chave pública do SDK, embutida para o self-install/self-update verificarem
# a assinatura do tarball. O arquivo é versionado; a privada fica em keys/.
sdk_pub="$(sed -n '2p' "$here/../../tool/sdk/sdk_release.pub")"

echo "building $name"
dart compile exe "$here/bin/dovetail.dart" \
  --define=dovetail.os="$target_os" \
  --define=dovetail.arch="$target_arch" \
  --define=dovetail.dart="$dart_version" \
  --define=dovetail.commit="$(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  --define=dovetail.sdk_pubkey="$sdk_pub" \
  ${cross:+--target-os "$target_os" --target-arch "$target_arch"} \
  -o "$out/dovetail"

if [ -n "$cross" ]; then
  echo "cross build: this host cannot run it, so nothing checked its --version"
elif [ "$("$out/dovetail" --version | awk '{print $2}')" != "$version" ]; then
  echo "the built binary does not report $version" >&2
  exit 1
fi

tar -czf "$out/$name.tar.gz" -C "$out" dovetail
shasum -a 256 "$out/$name.tar.gz" | awk '{print $1}' > "$out/$name.tar.gz.sha256"

if [ -n "$install_to" ] && [ -n "$cross" ]; then
  echo "refusing to install a $target_os binary on $host_os" >&2
  exit 1
fi

if [ -n "$install_to" ]; then
  if [ ! -d "$install_to" ]; then
    echo "$install_to does not exist" >&2
    exit 1
  fi
  if ! printf '%s' ":$PATH:" | grep -q ":$install_to:"; then
    echo "warning: $install_to is not on PATH, so dovetail will not be found" >&2
  fi
  install -m 0755 "$out/dovetail" "$install_to/dovetail"
  echo
  echo "installed  $install_to/dovetail"
  echo "reports    $("$install_to/dovetail" --version)"
  exit 0
fi

echo
echo "binary   $out/dovetail  ($(wc -c < "$out/dovetail" | tr -d ' ') bytes)"
echo "archive  $out/$name.tar.gz"
echo "sha256   $(cat "$out/$name.tar.gz.sha256")"
if [ -z "$cross" ]; then
  echo "reports  $("$out/dovetail" --version)"
fi
