#!/usr/bin/env bash
set -euo pipefail

# Builds the Linux side of the toolchain on this host and proves it on a real
# dpkg and a real rpm, in containers. The target is the HOST's own
# architecture by default: the container is pulled at the host's arch, so the
# artifacts and the validator always match. This machine (arm64) proves arm64;
# an x86_64 Linux runner proves the other one — set DOVETAIL_PROVE_ARCH to
# override when the two ever disagree.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker="${DOCKER:-docker}"
stage="${1:-$here/dist/linux-proof}"
debian_image="debian:12"
fedora_image="fedora:41"

case "$(uname -m)" in
  arm64|aarch64) default_arch=arm64 ;;
  x86_64) default_arch=x86_64 ;;
  *) echo "no linux proof for host arch $(uname -m)" >&2; exit 1 ;;
esac
arch="${DOVETAIL_PROVE_ARCH:-$default_arch}"
case "$arch" in
  arm64) cli_target=linux-arm64; dart_arch=arm64; runtime_asset=runtime-aarch64 ;;
  x86_64) cli_target=linux-x64; dart_arch=x64; runtime_asset=runtime-x86_64 ;;
  *) echo "DOVETAIL_PROVE_ARCH must be arm64 or x86_64, not $arch" >&2; exit 1 ;;
esac
echo "==> proving the $arch linux target (host: $(uname -m))"

if ! command -v "$docker" > /dev/null 2>&1; then
  echo "no docker on PATH; set DOCKER to the client you use" >&2
  exit 1
fi
if ! "$docker" version > /dev/null 2>&1; then
  echo "docker is installed but no daemon answered" >&2
  exit 1
fi

rm -rf "$stage"
mkdir -p "$stage/work/appdir/data/flutter_assets" "$stage/work/appdir/lib"

echo "==> the cli, cross compiled for linux"
"$here/toolkit/dovetail_cli/tool/build_release.sh" --target "$cli_target" \
  "$stage/cli" | sed 's/^/    /'
cp "$stage/cli/dovetail" "$stage/work/dovetail"

echo "==> the updater probe, cross compiled for linux"
(cd "$here/toolkit/dovetail_updater" && dart compile exe tool/install_probe.dart \
  --target-os linux --target-arch "$dart_arch" -o "$stage/work/install_probe") \
  | sed 's/^/    /'

echo "==> an app directory shaped like a flutter linux build"
(cd "$here/tool/linux" && dart compile exe probe_app.dart --target-os linux \
  --target-arch "$dart_arch" -o "$stage/work/appdir/vpn_desktop") \
  | sed 's/^/    /'
chmod 755 "$stage/work/appdir/vpn_desktop"
printf '{"AssetManifest.json":["AssetManifest.json"]}' \
  > "$stage/work/appdir/data/flutter_assets/AssetManifest.json"
head -c 4096 /dev/urandom > "$stage/work/appdir/lib/libapp.so"
chmod 644 "$stage/work/appdir/data/flutter_assets/AssetManifest.json" \
  "$stage/work/appdir/lib/libapp.so"
cp "$here/tool/linux/dovetail.yaml" "$stage/work/dovetail.yaml"
# The same project without the service: the AppImage suite proves the format
# with it, after proving that the service-bearing one is refused.
cp "$here/tool/linux/dovetail-appimage.yaml" "$stage/work/dovetail-appimage.yaml"

runtime="${DOVETAIL_APPIMAGE_RUNTIME:-$stage/$runtime_asset}"
if [ ! -f "$runtime" ]; then
  echo "==> the AppImage runtime, which is not ours to carry"
  if curl -fsSL -o "$runtime" \
    "https://github.com/AppImage/type2-runtime/releases/download/continuous/$runtime_asset"
  then
    echo "    fetched $(wc -c < "$runtime" | tr -d ' ') bytes"
  else
    rm -f "$runtime"
    echo "    could not fetch it, so the AppImage suite will report SKIPPED"
  fi
fi
[ -f "$runtime" ] && cp "$runtime" "$stage/work/$runtime_asset"

run_suite() {
  local name="$1" image="$2" install="$3"
  echo
  echo "==> $name"
  "$docker" rm -f "dovetail-$name" > /dev/null 2>&1 || true
  # An AppImage mounts itself, so its suite needs a /dev/fuse to mount on. A
  # host that cannot hand one over still runs everything else, and
  # check_appimage says out loud that it could not launch the image.
  "$docker" run -d --name "dovetail-$name" --device /dev/fuse \
    --cap-add SYS_ADMIN --security-opt apparmor:unconfined "$image" \
    sleep 3600 > /dev/null 2>&1 ||
    "$docker" run -d --name "dovetail-$name" "$image" sleep 3600 > /dev/null
  "$docker" exec "dovetail-$name" sh -c "$install" > "$stage/$name-deps.log" 2>&1 \
    || { echo "    installing the distro tooling failed; see $stage/$name-deps.log" >&2; return 1; }
  "$docker" cp "$stage/work" "dovetail-$name:/work" > /dev/null
  for each in "${@:4}"; do
    "$docker" cp "$here/tool/linux/$each" "dovetail-$name:/tmp/$each" > /dev/null
  done
  local outcome=0
  for each in "${@:4}"; do
    "$docker" exec -e "DOVETAIL_PROVE_ARCH=$arch" "dovetail-$name" \
      bash "/tmp/$each" | sed 's/^/    /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || outcome=1
  done
  "$docker" rm -f "dovetail-$name" > /dev/null
  return $outcome
}

failures=0
run_suite deb "$debian_image" \
  'apt-get -qq update && apt-get -qq install -y desktop-file-utils systemd libxml2-utils libgtk-3-0 libegl1 libgles2 polkitd pkexec dbus dpkg-dev squashfs-tools fuse3 libfuse2' \
  check_deb.sh check_appimage.sh || failures=$((failures + 1))
run_suite rpm "$fedora_image" \
  'dnf -y -q install rpm-build systemd-rpm-macros desktop-file-utils polkit systemd libxml2 dbus-daemon gtk3 libglvnd-egl libglvnd-gles' \
  check_rpm.sh || failures=$((failures + 1))

echo
if [ "$failures" -eq 0 ]; then
  echo "both suites passed"
else
  echo "$failures of 2 runs failed" >&2
fi
exit "$failures"
