#!/usr/bin/env bash
set -euo pipefail

# Runs the Windows single instance guard on a machine that is not Windows.
#
# The guard is 200 lines of Win32 that no compiler had ever seen. Compiling it
# is what toolkit/dovetail_platform_channel/tool/build_guard_probe.sh does; this
# goes further and exercises the two process handshake, because "it compiles"
# never proved that a second launch reaches the first one.
#
# The route is Wine in an emulated amd64 container: the wine-stable cask was
# disabled on 2026-09-01 for failing the macOS Gatekeeper check, so there is no
# host Wine to point at. Wine is not Windows — it is a second opinion, and the
# Windows runner is still what signs off on the real thing.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker="${DOCKER:-docker}"
# A tag e movel: `debian:12` de hoje nao e a de amanha, e uma prova que muda
# de base sozinha nao prova a mesma coisa duas vezes. `DOVETAIL_WINE_IMAGE`
# existe para o dia em que a base precise subir — de proposito, e num commit.
image="${DOVETAIL_WINE_IMAGE:-debian:12}"
container="dovetail-wine"

if ! command -v "$docker" > /dev/null 2>&1; then
  echo "no docker on PATH; set DOCKER to the client you use" >&2
  exit 1
fi
if ! "$docker" version > /dev/null 2>&1; then
  echo "docker is installed but no daemon answered" >&2
  exit 1
fi

echo "==> compiling the guard"
DOVETAIL_GUARD_DRIVER=1 \
  "$here/toolkit/dovetail_platform_channel/tool/build_guard_probe.sh" \
  "$here/dist/guard-probe" | sed 's/^/    /'

echo "==> an amd64 linux with a wine in it"
"$docker" rm -f "$container" > /dev/null 2>&1 || true
# O pull e explicito e com retry, e nao embutido no `run`, por um motivo de
# leitura: sem isso um registry fora do ar produz um vermelho que parece um
# vermelho de codigo, e alguem vai procurar o bug no guarda. Tres tentativas,
# e a recusa diz que foi a rede.
pulled=0
for attempt in 1 2 3; do
  if "$docker" pull --platform linux/amd64 "$image" > /dev/null 2>&1; then
    pulled=1
    break
  fi
  echo "    pull failed (attempt $attempt/3)" >&2
  sleep $((attempt * 5))
done
if [ "$pulled" -ne 1 ]; then
  echo "could not pull $image after 3 attempts — this is the network, not the guard" >&2
  exit 1
fi
"$docker" run -d --name "$container" --platform linux/amd64 "$image" \
  sleep 3600 > /dev/null
if [ "$("$docker" exec "$container" uname -m)" != "x86_64" ]; then
  echo "this docker has no amd64 emulation, so it cannot run an amd64 wine" >&2
  "$docker" rm -f "$container" > /dev/null
  exit 1
fi

"$docker" exec "$container" sh -c \
  'DEBIAN_FRONTEND=noninteractive apt-get -qq update &&
   DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends \
     wine64 xvfb xauth procps' > "$here/dist/guard-probe/wine-deps.log" 2>&1 \
  || { echo "installing wine failed; see dist/guard-probe/wine-deps.log" >&2
       "$docker" rm -f "$container" > /dev/null; exit 1; }

"$docker" exec "$container" mkdir -p /probe
"$docker" cp "$here/dist/guard-probe/dovetail_platform_channel.dll" \
  "$container:/probe/" > /dev/null
"$docker" cp "$here/dist/guard-probe/guard_probe.exe" \
  "$container:/probe/" > /dev/null
"$docker" cp "$here/tool/windows/check_guard.sh" \
  "$container:/tmp/check_guard.sh" > /dev/null

echo "==> the scenario"
set +e
"$docker" exec "$container" bash /tmp/check_guard.sh | sed 's/^/    /'
outcome=${PIPESTATUS[0]}
set -e
"$docker" rm -f "$container" > /dev/null

echo
if [ "$outcome" -eq 0 ]; then
  echo "the guard behaved on a machine that is not Windows"
else
  echo "the guard did not behave" >&2
fi
exit "$outcome"
