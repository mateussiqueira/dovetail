#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell_scripts_kept.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
MANIFESTO=scripts/checks/shell_scripts.manifest
PASS=0; FAIL=0; RC=0; OUT=""

roda() { OUT="$(bash "$CHECK" "$@" 2>&1)"; RC=$?; }
expect() {
  if [ "$RC" -eq "$1" ] && grep -qF -- "$3" <<<"$OUT"; then echo "  ✅ $2"; PASS=$((PASS + 1))
  else echo "  ❌ $2 (rc=$RC, esperava $1)"; sed 's/^/     /' <<<"$OUT"; FAIL=$((FAIL + 1)); fi
}
confere() {
  local nome="$1"
  shift
  if "$@"; then echo "  ✅ $nome"; PASS=$((PASS + 1))
  else echo "  ❌ $nome"; FAIL=$((FAIL + 1)); fi
}
reinicia() { git reset -q --hard && git clean -qdf; }
script() { mkdir -p "$(dirname "$1")" && printf '#!/bin/sh\n' > "$1"; }

mkdir -p "$WORK/repo" && cd "$WORK/repo" || exit 1
git init -q -b main
script tool/a.sh
script scripts/checks/b.sh
script .githooks/pre-push
printf 'texto\n' > README.md
git add -A
roda
expect 1 "sem manifesto reprova" "$MANIFESTO não existe; crie-o com --update"
roda --update
expect 0 "--update cria o manifesto com os scripts e os hooks" '➕ entrou no manifesto: .githooks/pre-push'
git add -A && git -c user.name=selftest -c user.email=selftest@example.com commit -qm base

roda
expect 0 "árvore em ordem passa" '✅ 3 script(s) rastreado(s), nenhum faltando'
roda --strict
expect 0 "árvore em ordem passa com --strict" '✅ 3 script(s) rastreado(s), nenhum faltando'

git rm -q tool/a.sh
roda
expect 1 "script apagado reprova nomeando o arquivo" '❌ tool/a.sh sumiu'
roda --update
expect 1 "--update não perdoa o script apagado" '❌ tool/a.sh sumiu'
confere "--update mantém no manifesto o script apagado" grep -qxF tool/a.sh "$MANIFESTO"
reinicia

git rm -q .githooks/pre-push
roda
expect 1 "hook apagado reprova nomeando o hook" '❌ .githooks/pre-push sumiu'
reinicia

script tool/novo.sh && git add tool/novo.sh
roda
expect 0 "script novo fora do manifesto só avisa" '⚠️  tool/novo.sh fora de'
roda --strict
expect 1 "script novo fora do manifesto reprova com --strict" '❌ tool/novo.sh fora de'
roda --update
expect 0 "--update acrescenta o script novo" '➕ entrou no manifesto: tool/novo.sh'
cp "$MANIFESTO" "$WORK/depois"
roda --update
confere "--update de novo não muda o manifesto" cmp -s "$MANIFESTO" "$WORK/depois"
roda --strict
expect 0 "depois do --update o --strict passa" '✅ 4 script(s) rastreado(s)'
reinicia

script tool/solto.sh
roda --strict
expect 0 "script fora do git não conta" '✅ 3 script(s) rastreado(s)'
reinicia

roda --qualquer
expect 2 "opção desconhecida mostra o uso" 'uso: bash scripts/checks/shell_scripts_kept.sh'

echo "  $PASS ok, $FAIL falha(s)"
[ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]
