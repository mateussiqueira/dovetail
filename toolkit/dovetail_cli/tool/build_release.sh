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

source "$here/tool/release_platform.sh"
release_platform "$cross_target"
dart="${DOVETAIL_DART:-dart}"
if [ "$host_os" = windows ] && [ -z "${DOVETAIL_DART:-}" ]; then dart=dart.exe; fi
version="$(awk '/^version:/ {gsub(/\r/, ""); print $2; exit}' "$here/pubspec.yaml")"
dart_version="$("$dart" --version 2>&1 | awk '{print $4}')"

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
sdk_pub="$(sed -n '2p' "$here/../../tool/sdk/sdk_release.pub" | tr -d '\r')"

echo "building $name"
"$dart" compile exe "$here/bin/dovetail.dart" \
  --define=dovetail.os="$target_os" \
  --define=dovetail.arch="$target_arch" \
  --define=dovetail.dart="$dart_version" \
  --define=dovetail.commit="$(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  --define=dovetail.sdk_pubkey="$sdk_pub" \
  ${cross:+--target-os "$target_os" --target-arch "$target_arch"} \
  -o "$out/$binary"

if [ -n "$cross" ]; then
  echo "cross build: this host cannot run it, so nothing checked its --version"
elif [ "$("$out/$binary" --version | awk '{print $2}')" != "$version" ]; then
  echo "the built binary does not report $version" >&2
  exit 1
fi

if [ "$extension" = zip ]; then
  "$release_tar" -a -cf "$out/$name.$extension" -C "$out" "$binary"
else
  "$release_tar" -czf "$out/$name.$extension" -C "$out" "$binary"
fi
release_checksum "$out/$name.$extension"

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
  install -m 0755 "$out/$binary" "$install_to/$binary"
  echo
  echo "installed  $install_to/$binary"
  echo "reports    $("$install_to/$binary" --version)"
  exit 0
fi

echo
echo "binary   $out/$binary  ($(wc -c < "$out/$binary" | tr -d ' ') bytes)"
echo "archive  $out/$name.$extension"
echo "sha256   $(cat "$out/$name.$extension.sha256")"
if [ -z "$cross" ]; then
  echo "reports  $("$out/$binary" --version)"
fi
