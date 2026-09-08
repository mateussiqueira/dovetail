#!/bin/bash
fail=0
say() { printf '%-52s %s\n' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then say "$1" "ok"; else say "$1" "FAIL ($2 != $3)"; fail=1; fi; }

cd /work || exit 2

# DOVETAIL_PROVE_ARCH is injected by prove_on_linux.sh (arm64 default).
case "${DOVETAIL_PROVE_ARCH:-arm64}" in
  arm64) runtime_name=runtime-aarch64; bundle_arch=arm64 ;;
  x86_64) runtime_name=runtime-x86_64; bundle_arch=x86_64 ;;
  *) echo "DOVETAIL_PROVE_ARCH must be arm64 or x86_64" >&2; exit 1 ;;
esac

if [ ! -f "$runtime_name" ]; then
  say "no AppImage runtime was staged" "SKIPPED"
  say "  so nothing here ran" "see prove_on_linux.sh"
  exit 0
fi

# The product yaml declares the privileged helper service, and an AppImage
# installs nothing — so the toolkit refuses it, and the refusal names the
# service. Prove that boundary first, then prove the format itself with the
# same project minus the service.
./dovetail bundle --target linux --arch "$bundle_arch" --product-name VPN \
  --manufacturer Example Org --identifier com.example.vpnDesktop --version 1.2.0 \
  --main-binary vpn_desktop --app-dir appdir --out-dir out-refused \
  --linux-format appimage --appimage-runtime "$runtime_name" > /tmp/ai_refuse.log 2>&1
grep -q 'declares a service (vpn-desktop-helper.service)' /tmp/ai_refuse.log
check "a service-bearing config refuses appimage" "$?" "0"
check "  and names the service it saw" \
  "$(grep -c 'vpn-desktop-helper.service' /tmp/ai_refuse.log)" "2"
check "  and produced no AppImage" \
  "$(ls out-refused/*.AppImage 2>/dev/null | wc -l)" "0"

cp dovetail-appimage.yaml dovetail.yaml
./dovetail bundle --target linux --arch "$bundle_arch" --product-name VPN \
  --manufacturer Example Org --identifier com.example.vpnDesktop --version 1.2.0 \
  --main-binary vpn_desktop --app-dir appdir --out-dir out-appimage \
  --linux-format appimage --appimage-runtime "$runtime_name" > /tmp/ai.log 2>&1
check "bundle --linux-format appimage exits 0" "$?" "0"
[ -s /tmp/ai.log ] && sed 's/^/  /' /tmp/ai.log

image=$(ls out-appimage/*.AppImage 2>/dev/null | head -1)
[ -n "$image" ] || { say "an AppImage came out" "FAIL"; exit 1; }
check "it is executable" "$(stat -c %a "$image")" "755"

head -c 4 "$image" | grep -q "ELF"
check "the kernel sees an ELF at byte zero" "$?" "0"

fuse=no
if [ -e /dev/fuse ] &&
  { command -v fusermount > /dev/null 2>&1 ||
    command -v fusermount3 > /dev/null 2>&1; }
then
  fuse=yes
fi

if [ "$fuse" = yes ]; then
  "./$image" --installed > /tmp/ai_run.log 2>&1
  check "the AppImage mounts itself and runs" "$?" "0"
  check "  and the app inside it answered" "$(grep -o 'vpn_desktop up --installed' /tmp/ai_run.log | head -1)" "vpn_desktop up --installed"
else
  say "the AppImage mounts itself and runs" "NOT RUN"
  say "  no /dev/fuse here, and an AppImage mounts itself" "the format needs it, not us"
fi

rm -rf squashfs-root
"./$image" --appimage-extract > /dev/null 2>&1
check "it extracts without fuse" "$?" "0"
check "AppRun mode" "$(stat -c %a squashfs-root/AppRun)" "755"
check "the payload binary mode" "$(stat -c %a squashfs-root/usr/bin/vpn_desktop)" "755"
check "a payload data file mode" "$(stat -c %a squashfs-root/usr/bin/lib/libapp.so)" "644"

desktop-file-validate squashfs-root/com.example.vpnDesktop.desktop > /tmp/ai_dfv.log 2>&1
check "the bundled desktop entry validates" "$?" "0"
[ -s /tmp/ai_dfv.log ] && sed 's/^/  /' /tmp/ai_dfv.log
check "  and its Exec is relative, as the spec wants" "$(grep '^Exec=' squashfs-root/com.example.vpnDesktop.desktop)" "Exec=vpn_desktop"

check "every file inside is owned by root" "$(find squashfs-root -newer /dev/null -printf '%u\n' 2>/dev/null | sort -u | tr '\n' ' ' | tr -d ' ')" "root"

./install_probe appimage "$image" "$image" > /tmp/ai_upd.log 2>&1
check "the updater replaces it in place" "$?" "0"
sed 's/^/  /' /tmp/ai_upd.log
check "  and what it left behind is still executable" "$(stat -c %a "$image")" "755"
if [ "$fuse" = yes ]; then
  "./$image" --after-update > /tmp/ai_after.log 2>&1
  check "  and still runs after being replaced" "$?" "0"
fi

exit $fail
