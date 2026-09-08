#!/bin/bash
fail=0
say() { printf '%-52s %s\n' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then say "$1" "ok"; else say "$1" "FAIL ($2 != $3)"; fail=1; fi; }
holds() { if grep -q -e "$2" "$3"; then say "$1" "ok"; else say "$1" "FAIL"; fail=1; fi; }
lacks() { if grep -q -e "$2" "$3"; then say "$1" "FAIL"; fail=1; else say "$1" "ok"; fi; }

export WINEPREFIX=/root/.wine
export WINEDEBUG=-all
cd /probe || exit 2

guard() {
  xvfb-run -a /usr/lib/wine/wine64 guard_probe.exe "$@" 2>&1 \
    | grep -v '^wine:' | grep -v 'X connection to'
}

guard orphan first-claim > /tmp/a.log
holds "a fresh key claims the guard" "orphan verdict=primary" /tmp/a.log
lacks "  and the process exits without aborting" "terminate called" /tmp/a.log

guard orphan first-claim > /tmp/b.log
holds "the same key claims again after that exit" "orphan verdict=primary" /tmp/b.log
say "  which is the mutex dying with its process" "ok"

(guard primary second-launch > /tmp/primary.log 2>&1 &)
sleep 8
guard secondary second-launch --quiet myid://pair/9f2c > /tmp/secondary.log
holds "a second launch is told it is secondary" "secondary verdict=secondary" /tmp/secondary.log
sleep 4

holds "the first launch held the guard" "primary verdict=primary" /tmp/primary.log
holds "  and received the forwarded launch" "primary took=" /tmp/primary.log
holds "  with the argument the second one carried" "myid://pair/9f2c" /tmp/primary.log
holds "  and the flag before it" "--quiet" /tmp/primary.log
holds "  exactly one launch, not two" "primary drained=1" /tmp/primary.log
holds "  and released the guard on the way out" "primary released" /tmp/primary.log
lacks "  without aborting at exit" "terminate called" /tmp/primary.log

say "  the payload it read" "$(grep 'primary took=' /tmp/primary.log | head -1)"

exit $fail
