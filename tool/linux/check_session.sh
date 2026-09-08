#!/bin/bash
# Runs the shortcut session probe under four real sessions.
#
# The question this exists for: global-hotkey opens and binds on an X server
# whose keys a Wayland compositor never delivers — and, as this measures, even
# with no server at all. The backend the probe reports is the only thing
# standing between the user and a shortcut that reports success and never
# fires, so what detect() answers has to be right, and open() has to consult it.
fail=0
say() { printf '%-54s %s\n' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then say "$1" "ok"; else say "$1" "FAIL ($2 != $3)"; fail=1; fi; }

probe=/src/rust/target/debug/examples/session_probe
[ -x "$probe" ] || { say "the probe was not built" "FAIL"; exit 1; }

user=dtsession
runtime=/run/user/4242
id "$user" > /dev/null 2>&1 || useradd -u 4242 -m "$user"
mkdir -p "$runtime" /tmp/swaycfg
chown "$user" "$runtime"
chmod 700 "$runtime"
chmod -R a+rX /src/rust/target
field() { grep -m1 "^$2=" "$1" | cut -d= -f2- | cut -d' ' -f1; }
asuser() { su "$user" -s /bin/bash -c "$1"; }

echo "-- a session with nothing running"
env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_SESSION_TYPE "$probe" > /tmp/none.log 2>&1
check "no session reports no backend" "$(field /tmp/none.log backend)" "none"
check "  and open refuses, rather than reporting success" \
  "$(field /tmp/none.log open)" "refused"
say "  the reason" "$(grep -m1 '^open_reason=' /tmp/none.log | cut -d= -f2- | cut -c1-64)"

echo "-- an X11 session, which is the one that works"
Xvfb :99 -screen 0 800x600x24 > /tmp/xvfb.log 2>&1 &
sleep 2
env -u WAYLAND_DISPLAY XDG_SESSION_TYPE=x11 DISPLAY=:99 "$probe" > /tmp/x11.log 2>&1
check "an X display reports x11GrabKey" "$(field /tmp/x11.log backend)" "x11GrabKey"
check "  opens" "$(field /tmp/x11.log open)" "accepted"
check "  and binds" "$(field /tmp/x11.log bind)" "ok"
pkill -x Xvfb > /dev/null 2>&1

printf 'exec sleep infinity\n' > /tmp/swaycfg/config
chmod a+r /tmp/swaycfg/config
swaylog=/home/$user/sway.log
asuser "XDG_RUNTIME_DIR=$runtime WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
  nohup sway -c /tmp/swaycfg/config > $swaylog 2>&1 &"
sock=""
for _ in $(seq 1 60); do
  for n in wayland-0 wayland-1; do
    [ -S "$runtime/$n" ] && sock="$n"
  done
  [ -n "$sock" ] && break
  sleep 0.5
done

if [ -z "$sock" ]; then
  say "sway did not come up headless" "FAIL"
  tail -4 "$swaylog" | sed 's/^/    /'
  exit 1
fi

echo "-- a Wayland session with XWayland, the trap"
say "  the compositor came up on" "$sock"
asuser "XDG_RUNTIME_DIR=$runtime WAYLAND_DISPLAY=$sock XDG_SESSION_TYPE=wayland \
  DISPLAY=:0 $probe" > /tmp/way.log 2>&1
check "a Wayland session reports waylandPortal" "$(field /tmp/way.log backend)" "waylandPortal"
check "  and open refuses, with XWayland right there" \
  "$(field /tmp/way.log open)" "refused"
say "  the reason" "$(grep -m1 '^open_reason=' /tmp/way.log | cut -d= -f2- | cut -c1-64)"

echo "-- the same compositor, launched from a console"
asuser "XDG_RUNTIME_DIR=$runtime WAYLAND_DISPLAY=$sock XDG_SESSION_TYPE=tty \
  DISPLAY=:0 $probe" > /tmp/tty.log 2>&1
check "a tty-launched compositor is still Wayland" "$(field /tmp/tty.log backend)" "waylandPortal"

echo "-- and with XWayland out of the picture"
asuser "XDG_RUNTIME_DIR=$runtime WAYLAND_DISPLAY=$sock XDG_SESSION_TYPE=tty $probe" \
  > /tmp/noxw.log 2>&1
check "no X display does not make it no session" "$(field /tmp/noxw.log backend)" "waylandPortal"
check "  and open refuses there too" "$(field /tmp/noxw.log open)" "refused"

pkill -x sway > /dev/null 2>&1
exit $fail
