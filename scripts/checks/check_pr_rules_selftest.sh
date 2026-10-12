#!/bin/bash
set -uo pipefail
unset PR_BASE PR_BRANCH PR_SIZE_EXEMPT PR_SIZE_IGNORE_FILE GITHUB_BASE_REF

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_pr_rules.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; RC=0; OUT=""

run_rules() { OUT="$(cd "$WORK/repo" && env "$@" bash "$CHECK" 2>&1)"; RC=$?; }
expect() {
  local ok=0
  grep -qF -- "$3" <<<"$OUT" || ok=1
  { [ "$1" = passa ] && [ "$RC" -ne 0 ]; } && ok=1
  { [ "$1" = barra ] && [ "$RC" -eq 0 ]; } && ok=1
  if [ "$ok" -eq 0 ]; then echo "  ✅ $2"; PASS=$((PASS + 1))
  else echo "  ❌ $2 (rc=$RC)"; sed 's/^/     /' <<<"$OUT"; FAIL=$((FAIL + 1)); fi
}
branch() { git checkout -qf main && git clean -qdf && git checkout -qB "$1"; }
lines() { seq 1 "$1" > "$2"; }
commit() { git add -A && git -c user.name=selftest -c user.email=selftest@example.com commit -qm "$1"; }

mkdir -p "$WORK/repo" && cd "$WORK/repo" || exit 1
git init -q -b main
printf 'Cargo.lock\n' > .pr_size_ignore.list
printf 'base\n' > base.txt
lines 300 old.txt
commit "chore: base"

branch build/pequeno
lines 10 a.txt; commit "build: add ten lines"
run_rules
expect passa "10 linhas num arquivo passam" 'Tamanho ideal: 10 linhas'

branch build/grande
lines 300 a.txt; commit "build: add three hundred lines"
run_rules
expect barra "300 linhas reprovam" 'PR muito grande: 300 linhas (máx 250)'
run_rules PR_SIZE_EXEMPT="sweep de formatação"
expect passa "PR_SIZE_EXEMPT rebaixa as 300 linhas a aviso" 'isento por PR_SIZE_EXEMPT: sweep de formatação'

branch build/limite
lines 250 a.txt; commit "build: add exactly the limit"
run_rules
expect passa "250 linhas é aviso, não erro" 'PR grande: 250 linhas'

branch build/muitos
for i in 1 2 3 4 5 6 7 8; do lines 2 "f$i.txt"; done; commit "build: touch eight files"
run_rules
expect barra "8 arquivos reprovam" 'PR com 8 arquivos (máx 7)'
run_rules PR_SIZE_EXEMPT="migração de caminho"
expect passa "PR_SIZE_EXEMPT rebaixa os 8 arquivos a aviso" 'isento por PR_SIZE_EXEMPT: migração de caminho'
git rm -q f8.txt && commit "build: back to seven files"
run_rules
expect passa "7 arquivos é aviso, não erro" 'PR com muitos arquivos: 7'

branch build/lock
lines 400 Cargo.lock; lines 5 a.txt; commit "build: bump a lockfile"
run_rules
expect passa "lockfile listado fica fora da medição" '1 arquivo(s) gerado(s) fora da medição'

branch build/mensagem
lines 3 a.txt; commit "wip: update stuff"
run_rules
expect barra "tipo fora do Conventional Commits reprova" 'wip: update stuff'

branch build/remocao
git rm -q old.txt; commit "build: drop the old file"
run_rules
expect barra "linhas removidas também contam" 'PR muito grande: 300 linhas'

branch minha-branch
lines 3 a.txt; commit "build: valid message"
run_rules
expect barra "branch sem prefixo reprova" 'Branch naming incorreto: minha-branch'
git checkout -q --detach
run_rules PR_BRANCH=build/destacada
expect passa "HEAD destacado usa o PR_BRANCH do push" 'Branch naming correto: build/destacada'

branch build/indice
lines 300 a.txt; git add a.txt
run_rules
expect barra "sem commit à frente, mede o índice" 'PR muito grande: 300 linhas'

branch build/mae
lines 200 a.txt; commit "build: parent of a stack"
git checkout -qb build/filha
lines 100 b.txt; commit "build: child of a stack"
run_rules
expect barra "a pilha medida contra a main soma mãe e filha" 'PR muito grande: 300 linhas'
run_rules PR_BASE=build/mae
expect passa "PR_BASE mede só a filha contra a mãe" 'Tamanho bom: 100 linhas'
run_rules PR_BASE=nao-existe
expect barra "PR_BASE que não resolve recusa em vez de medir o índice" "a base 'nao-existe' não resolve"

echo "  $PASS ok, $FAIL falha(s)"
[ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]
