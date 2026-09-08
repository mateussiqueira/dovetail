#!/usr/bin/env bash
set -euo pipefail

# Runs the shortcut channel against four real Linux sessions, one of them a
# Wayland compositor.
#
# The roadmap carried an open question for weeks: does GlobalHotKeyManager::new()
# fail on Wayland? Measured here, the answer is no — it succeeds, and the bind
# reports ok, on a session whose keys the compositor delivers elsewhere. It
# succeeds with no display at all, too. So the backend the probe reports is not
# advisory: it is the only thing between the user and a shortcut that says it
# worked and never fires.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker="${DOCKER:-docker}"
image="debian:12"
container="dovetail-session"

if ! command -v "$docker" > /dev/null 2>&1; then
  echo "no docker on PATH; set DOCKER to the client you use" >&2
  exit 1
fi
if ! "$docker" version > /dev/null 2>&1; then
  echo "docker is installed but no daemon answered" >&2
  exit 1
fi

stage="$here/dist/session-proof"
rm -rf "$stage"
mkdir -p "$stage"

echo "==> a linux with a compositor in it"
"$docker" rm -f "$container" > /dev/null 2>&1 || true
"$docker" run -d --name "$container" --memory 4g "$image" sleep 3600 > /dev/null
"$docker" exec "$container" sh -c \
  'DEBIAN_FRONTEND=noninteractive apt-get -qq update &&
   DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends \
     curl ca-certificates build-essential pkg-config sway xwayland xvfb xauth \
     libx11-6 libxcb1 libxkbcommon0 procps &&
   curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup.sh &&
   sh /tmp/rustup.sh -y --profile minimal --default-toolchain stable' \
  > "$stage/deps.log" 2>&1 \
  || { echo "installing the session tooling failed; see dist/session-proof/deps.log" >&2
       "$docker" rm -f "$container" > /dev/null; exit 1; }

echo "==> the probe, built where it will run"
"$docker" exec "$container" mkdir -p /src
"$docker" cp "$here/toolkit/dovetail_shortcut_channel/rust" "$container:/src/rust" > /dev/null
"$docker" exec "$container" rm -rf /src/rust/target
"$docker" exec "$container" bash -lc \
  '. "$HOME/.cargo/env" && cd /src/rust && cargo build --example session_probe' \
  > "$stage/build.log" 2>&1 \
  || { echo "the probe did not build; see dist/session-proof/build.log" >&2
       "$docker" rm -f "$container" > /dev/null; exit 1; }

"$docker" cp "$here/tool/linux/check_session.sh" \
  "$container:/tmp/check_session.sh" > /dev/null

echo "==> the sessions"
set +e
"$docker" exec "$container" bash /tmp/check_session.sh | sed 's/^/    /'
outcome=${PIPESTATUS[0]}
set -e
"$docker" rm -f "$container" > /dev/null

echo
if [ "$outcome" -eq 0 ]; then
  echo "the channel told the truth about every session"
else
  echo "the channel did not tell the truth about every session" >&2
fi
exit "$outcome"
