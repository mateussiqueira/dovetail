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

rpm -e vpn_desktop > /dev/null 2>&1

./dovetail --version > /tmp/ver.log 2>&1
check "the linux cli cross built on the host runs here" "$?" "0"
say "  it reports" "$(cat /tmp/ver.log)"

./dovetail bundle --target linux --arch "$bundle_arch" --product-name VPN \
  --manufacturer Example Org --identifier com.example.vpnDesktop --version 1.2.0 \
  --main-binary vpn_desktop --app-dir appdir --out-dir out \
  --deb-depends libgtk-3-0 --rpm-requires gtk3 > /tmp/bundle.log 2>&1
check "bundle with a service exits 0" "$?" "0"
[ -s /tmp/bundle.log ] && sed 's/^/  /' /tmp/bundle.log

pkg=$(ls out/*.rpm 2>/dev/null | head -1)
[ -n "$pkg" ] || { say "an rpm came out" "FAIL"; exit 1; }

rpm -q --requires -p "$pkg" 2>/dev/null | grep -q '^gtk3'
check "Requires names the fedora package" "$?" "0"
rpm -q --requires -p "$pkg" 2>/dev/null | grep -q '^libglvnd-egl'
check "  and the library the engine dlopens, by its fedora name" "$?" "0"
rpm -q --scripts -p "$pkg" 2>/dev/null | grep -q 'systemd-update-helper'
check "the scriptlets expanded the systemd macros" "$?" "0"

rpm -i "$pkg" > /tmp/install.log 2>&1
check "rpm --install exits 0 with dependencies resolved" "$?" "0"
[ -s /tmp/install.log ] && sed 's/^/  /' /tmp/install.log

check "binary mode" "$(stat -c %a /usr/lib/vpn_desktop/vpn_desktop)" "755"
check "nested library mode" "$(stat -c %a /usr/lib/vpn_desktop/lib/libapp.so)" "644"

/usr/lib/vpn_desktop/vpn_desktop --installed > /tmp/run.log 2>&1
check "the installed binary runs" "$?" "0"
check "the installed binary output" "$(cat /tmp/run.log)" "vpn_desktop up --installed"

desktop-file-validate /usr/share/applications/com.example.vpnDesktop.desktop > /tmp/dfv.log 2>&1
check "desktop-file-validate" "$?" "0"
[ -s /tmp/dfv.log ] && sed 's/^/  /' /tmp/dfv.log

systemd-analyze verify /usr/lib/systemd/system/vpn-desktop-helper.service > /tmp/unit.log 2>&1
check "systemd-analyze verify" "$?" "0"
[ -s /tmp/unit.log ] && sed 's/^/  /' /tmp/unit.log

xmllint --noout --dtdvalid /usr/share/polkit-1/policyconfig-1.dtd \
  /usr/share/polkit-1/actions/com.example.vpnDesktop.policy > /tmp/dtd.log 2>&1
check "the polkit policy is valid against the dtd" "$?" "0"

mkdir -p /run/dbus
pgrep dbus-daemon > /dev/null 2>&1 || dbus-daemon --system --fork
pgrep polkitd > /dev/null 2>&1 || (/usr/lib/polkit-1/polkitd --no-debug > /tmp/polkitd.log 2>&1 &)
sleep 3
check "polkit itself reads our action" "$(pkaction --action-id com.example.vpnDesktop.manage 2>/dev/null)" "com.example.vpnDesktop.manage"

rpm -e vpn_desktop > /dev/null 2>&1
./install_probe package "$pkg" > /tmp/probe.log 2>&1
check "the updater installs it through rpm" "$?" "0"
sed 's/^/  /' /tmp/probe.log
[ -x /usr/lib/vpn_desktop/vpn_desktop ]
check "the updater left an executable behind" "$?" "0"

./install_probe package "$pkg" > /tmp/again.log 2>&1
check "installing the same version again still exits 0" "$?" "0"
sed 's/^/  /' /tmp/again.log

rpm -e vpn_desktop > /tmp/erase.log 2>&1
check "rpm --erase exits 0" "$?" "0"
[ ! -e /usr/lib/vpn_desktop/vpn_desktop ]
check "erase took the binary away" "$?" "0"

exit $fail
