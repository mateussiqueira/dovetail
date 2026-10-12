#!/bin/bash
set -uo pipefail
unset PR_OPEN_LIMIT PR_LIMIT_REMOTE_URL

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/check_open_pr_limit.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/gh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" > "${FAKE_GH_ARGS:-/dev/null}"
[ "${FAKE_GH_FAILS:-0}" = "1" ] && exit 1
for ((i = 1; i <= ${FAKE_OPEN:-0}; i++)); do echo "$((100 + i)) feat/aberta-$i"; done
exit 0
FAKE
chmod +x "$WORK/gh"
mkdir -p "$WORK/fora" "$WORK/clone"
git -C "$WORK/clone" init -q
git -C "$WORK/clone" remote add origin https://github.com/mateussiqueira/dovetail.git
cd "$WORK/fora" || exit 1

PASS=0
FAIL=0
record() {
  if [ "$1" -eq 0 ]; then
    echo "  ✅ $2"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $2"
    sed 's/^/     /' "$WORK/out"
    FAIL=$((FAIL + 1))
  fi
}
expect() {
  local want="$1" name="$2"
  shift 2
  PR_LIMIT_GH="$WORK/gh" FAKE_GH_ARGS="$WORK/args" "$@" bash "$GATE" "${ARGS[@]+"${ARGS[@]}"}" >"$WORK/out" 2>&1
  local got=$?
  { [ "$want" = "passa" ] && [ "$got" -eq 0 ]; } || { [ "$want" = "barra" ] && [ "$got" -ne 0 ]; }
  record $? "$name"
}
repo_is() {
  grep -q -- "-R $1 " "$WORK/args"
  record $? "$2"
}

ARGS=(feat/nova); expect passa "2 abertos: branch nova cabe" env FAKE_OPEN=2
ARGS=(feat/nova); expect barra "3 abertos: branch nova é barrada" env FAKE_OPEN=3
ARGS=(feat/nova); expect barra "15 abertos: branch nova é barrada" env FAKE_OPEN=15
ARGS=(feat/aberta-7); expect passa "15 abertos: atualizar PR existente passa" env FAKE_OPEN=15
ARGS=(feat/aberta-1 feat/nova); expect barra "uma existente e uma nova com 3 abertos: barra" env FAKE_OPEN=3
ARGS=(feat/nova); expect barra "gh falha: não conta, barra" env FAKE_GH_FAILS=1
ARGS=(feat/nova); expect barra "teto configurável: PR_OPEN_LIMIT=1 com 1 aberto barra" env FAKE_OPEN=1 PR_OPEN_LIMIT=1
ARGS=(main); expect passa "main não abre PR" env FAKE_OPEN=15
ARGS=(); expect passa "sem branch (tag ou remoção) passa" env FAKE_OPEN=15
ARGS=(feat/nova); expect passa "remoto https conta no repositório do push" env FAKE_OPEN=0 PR_LIMIT_REMOTE_URL=https://github.com/mateussiqueira/dovetail.git
repo_is mateussiqueira/dovetail "https: gh recebe -R mateussiqueira/dovetail"
ARGS=(feat/nova); expect passa "remoto ssh com apelido de host" env FAKE_OPEN=0 PR_LIMIT_REMOTE_URL=git@dovetail.github.com:outra-conta/fork.git
repo_is outra-conta/fork "ssh com apelido: gh recebe -R outra-conta/fork"
ARGS=(feat/nova); expect barra "remoto que não é do GitHub barra" env FAKE_OPEN=0 PR_LIMIT_REMOTE_URL=/tmp/espelho-local
cd "$WORK/clone" || exit 1
ARGS=(feat/nova); expect passa "sem a URL do push, deriva do origin" env FAKE_OPEN=0
repo_is mateussiqueira/dovetail "origin: gh recebe -R mateussiqueira/dovetail"
ARGS=(feat/nova); expect passa "a URL do push vence o origin" env FAKE_OPEN=0 PR_LIMIT_REMOTE_URL=git@github.com:outra-conta/fork.git
repo_is outra-conta/fork "push: gh recebe -R outra-conta/fork"

echo "  $PASS ok, $FAIL falha(s)"
[ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]
