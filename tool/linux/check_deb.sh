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
app_mock="/tmp/App-${bundle_arch}.AppImage"

dpkg -P vpn_desktop > /dev/null 2>&1

./dovetail --version > /tmp/ver.log 2>&1
check "the linux cli cross built on the host runs here" "$?" "0"
say "  it reports" "$(cat /tmp/ver.log)"

./dovetail bundle --target linux --arch "$bundle_arch" --product-name VPN \
  --manufacturer Example Org --identifier com.example.vpnDesktop --version 1.2.0 \
  --main-binary vpn_desktop --app-dir appdir --out-dir out \
  --linux-format deb --deb-depends libgtk-3-0 > /tmp/bundle.log 2>&1
check "bundle with a service exits 0" "$?" "0"
[ -s /tmp/bundle.log ] && sed 's/^/  /' /tmp/bundle.log

./dovetail bundle --target linux --arch "$bundle_arch" --product-name VPN \
  --manufacturer Example Org --identifier com.example.vpnDesktop --version 1.2.0 \
  --main-binary vpn_desktop --app-dir appdir --out-dir out-both \
  --linux-format both > /tmp/norpm.log 2>&1
check "asking for an rpm where there is no rpmbuild fails" "$?" "1"
grep -q 'there is no rpmbuild on this host' /tmp/norpm.log
check "  and it says which package to install" "$?" "0"
if grep -q 'ProcessException' /tmp/norpm.log; then
  say "  and not with a dart stack trace" "FAIL"
  fail=1
else
  say "  and not with a dart stack trace" "ok"
fi

pkg=$(ls out/*.deb 2>/dev/null | head -1)
[ -n "$pkg" ] || { say "a deb came out" "FAIL"; exit 1; }

dpkg-deb --field "$pkg" Depends | grep -q libgtk-3-0
check "Depends names the debian package" "$?" "0"
dpkg-deb --field "$pkg" Depends | grep -q libegl1
check "  and the library the engine dlopens" "$?" "0"
dpkg-deb --field "$pkg" Depends | grep -q libc6
check "  and what dpkg-shlibdeps derived" "$?" "0"
apt-cache policy libgtk-3-0 | grep -q 'Installed: [0-9]'
check "that debian package is really installed here" "$?" "0"

dpkg -i "$pkg" > /tmp/install.log 2>&1
check "dpkg --install exits 0" "$?" "0"
grep -q "Setting up vpn_desktop" /tmp/install.log
check "the maintainer script ran" "$?" "0"
[ -s /tmp/install.log ] && sed 's/^/  /' /tmp/install.log

check "package status" "$(dpkg-query -W -f='${Status}' vpn_desktop)" "install ok installed"
check "binary mode" "$(stat -c %a /usr/lib/vpn_desktop/vpn_desktop)" "755"
check "nested library mode" "$(stat -c %a /usr/lib/vpn_desktop/lib/libapp.so)" "644"
check "nested asset mode" "$(stat -c %a /usr/lib/vpn_desktop/data/flutter_assets/AssetManifest.json)" "644"

/usr/lib/vpn_desktop/vpn_desktop --installed > /tmp/run.log 2>&1
check "the installed binary runs" "$?" "0"
check "the installed binary output" "$(cat /tmp/run.log)" "vpn_desktop up --installed"

desktop-file-validate /usr/share/applications/com.example.vpnDesktop.desktop > /tmp/dfv.log 2>&1
check "desktop-file-validate" "$?" "0"
[ -s /tmp/dfv.log ] && sed 's/^/  /' /tmp/dfv.log

systemd-analyze verify /usr/lib/systemd/system/vpn-desktop-helper.service > /tmp/unit.log 2>&1
check "systemd-analyze verify" "$?" "0"
[ -s /tmp/unit.log ] && sed 's/^/  /' /tmp/unit.log

[ -e /var/lib/systemd/deb-systemd-helper-enabled/vpn-desktop-helper.service.dsh-also ]
check "the maintainer script registered the unit" "$?" "0"
[ -L /etc/systemd/system/multi-user.target.wants/vpn-desktop-helper.service ]
check "the maintainer script enabled the unit" "$?" "0"

xmllint --noout --dtdvalid /usr/share/polkit-1/policyconfig-1.dtd \
  /usr/share/polkit-1/actions/com.example.vpnDesktop.policy > /tmp/dtd.log 2>&1
check "the polkit policy is valid against the dtd" "$?" "0"

mkdir -p /run/dbus
pgrep dbus-daemon > /dev/null 2>&1 || dbus-daemon --system --fork
pgrep polkitd > /dev/null 2>&1 || (/usr/lib/polkit-1/polkitd --no-debug > /tmp/polkitd.log 2>&1 &)
sleep 3
check "polkit itself reads our action" "$(pkaction --action-id com.example.vpnDesktop.manage 2>/dev/null)" "com.example.vpnDesktop.manage"

dpkg -P vpn_desktop > /dev/null 2>&1
./install_probe package "$pkg" > /tmp/probe.log 2>&1
check "the updater installs it through dpkg" "$?" "0"
sed 's/^/  /' /tmp/probe.log
[ -x /usr/lib/vpn_desktop/vpn_desktop ]
check "the updater left an executable behind" "$?" "0"

printf 'the build that is running' > "$app_mock"
chmod 644 "$app_mock"
head -c 2048 /dev/urandom > /tmp/new.AppImage
./install_probe appimage /tmp/new.AppImage "$app_mock" > /tmp/appimage.log 2>&1
check "the updater replaces a running AppImage" "$?" "0"
check "the replacement is executable" "$(stat -c %a "$app_mock")" "755"
check "the replacement is the new bytes" "$(stat -c %s "$app_mock")" "2048"
[ ! -e "$app_mock.previous" ]
check "the backup was dropped once it was safe" "$?" "0"

mkdir -p /var/lib/vpn-desktop && touch /var/lib/vpn-desktop/state
dpkg -r vpn_desktop > /tmp/remove.log 2>&1
check "dpkg --remove exits 0" "$?" "0"
[ ! -e /usr/lib/vpn_desktop/vpn_desktop ]
check "remove took the binary away" "$?" "0"
[ -d /var/lib/vpn-desktop ]
check "remove kept the state directory" "$?" "0"

dpkg -P vpn_desktop > /tmp/purge.log 2>&1
check "dpkg --purge exits 0" "$?" "0"
[ ! -d /var/lib/vpn-desktop ]
check "purge removed the state directory" "$?" "0"

exit $fail
