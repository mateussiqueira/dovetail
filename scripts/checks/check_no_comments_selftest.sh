#!/bin/bash
set -uo pipefail
unset BASE_REF

GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_no_comments.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; RC=0; OUT=""

run_gate() {
  local dir="$1"
  shift
  (cd "$dir" && bash "$GATE" "$@") >"$WORK/out" 2>&1
  RC=$?; OUT="$(cat "$WORK/out")"
}
expect() {
  local want="$1" name="$2" needle="$3" ok=0
  grep -qF -- "$needle" <<<"$OUT" || ok=1
  if [ "$want" = passa ] && [ "$RC" -ne 0 ]; then ok=1; fi
  if [ "$want" = barra ] && [ "$RC" -eq 0 ]; then ok=1; fi
  if [ "$ok" -eq 0 ]; then
    echo "  ✅ $name"; PASS=$((PASS + 1))
  else
    echo "  ❌ $name (rc=$RC)"; sed 's/^/     /' "$WORK/out"; FAIL=$((FAIL + 1))
  fi
}
novo_repo() {
  mkdir -p "$1" && git -C "$1" init -q -b "$2"
  git -C "$1" config user.email selftest@example.com
  git -C "$1" config user.name selftest
}
caso() {
  git -C "$WORK/repo" checkout -qf main && git -C "$WORK/repo" clean -qdf
  git -C "$WORK/repo" checkout -qB caso
}
commit() { git -C "$WORK/repo" add -A && git -C "$WORK/repo" commit -qm "test: caso"; }

novo_repo "$WORK/repo" main
cd "$WORK/repo" || exit 1
mkdir -p lib src tool
printf '// legado\nfinal int a = 1;\n' > lib/a.dart
printf '// legado\nfn a() {}\n' > src/a.rs
printf '#!/bin/bash\n# legado\necho a\n' > tool/a.sh
commit

caso
printf 'final int b = 2;\n' >> lib/a.dart; printf 'fn b() {}\n' >> src/a.rs; printf 'echo b\n' >> tool/a.sh; commit
run_gate "$WORK/repo"
expect passa "código novo sem comentário passa; o legado não conta" 'Nenhum comentário em código novo'

caso
printf '// novo no dart\n' >> lib/a.dart; printf '// novo no rust\n' >> src/a.rs; printf '# novo no shell\n' >> tool/a.sh; commit
run_gate "$WORK/repo"
expect barra "// novo no .dart reprova" 'lib/a.dart:3'
expect barra "// novo no .rs reprova" 'src/a.rs:3'
expect barra "# novo no .sh reprova" 'tool/a.sh:4'
expect barra "o resumo conta as três linhas" '3 comentário(s) em código novo'

caso
printf '/// doc nova\nfinal int c = 3; // no fim\n/* bloco */\n' >> lib/a.dart; printf 'echo c # no fim\n' >> tool/a.sh; commit
run_gate "$WORK/repo"
expect barra "/// de documentação também conta" 'lib/a.dart:3'
expect barra "comentário no fim da linha reprova" 'lib/a.dart:4'
expect barra "bloco /* */ reprova" 'lib/a.dart:5'
expect barra "# no fim da linha do shell reprova" 'tool/a.sh:4'

caso
printf "// ignore: unused_local_variable\nfinal u = 'https://example.com/a';\nfinal g = 'lib/**/*.dart'; // ignore: x\n" >> lib/a.dart
printf '// SAFETY: o handle vive enquanto a conexão viver\nlet s = "a // b /* c */";\n' >> src/a.rs
printf '#!/usr/bin/env bash\n# shellcheck disable=SC2086\necho "${#x}" "$#" "# x" ${y#*/}\n' >> tool/a.sh
commit
run_gate "$WORK/repo"
expect passa "diretivas, URLs, globs e # de expansão passam" 'Nenhum comentário em código novo'

caso
mkdir -p vendor/cargokit
printf '// legado\nfinal int d = 4;\n' > lib/b.dart; printf '// do upstream\n' > vendor/cargokit/c.dart; commit
run_gate "$WORK/repo"
expect passa "linha que já existia na base e o cargokit vendorizado não contam" 'Nenhum comentário em código novo'
printf '// do upstream\n' > lib/c.dart; commit
run_gate "$WORK/repo"
expect barra "a mesma linha fora do cargokit reprova" 'lib/c.dart:1'

caso
printf '// fora do índice\n' >> lib/a.dart
run_gate "$WORK/repo" --staged
expect passa "--staged ignora o que não foi para o índice" 'linhas novas do índice'
git add lib/a.dart
run_gate "$WORK/repo" --staged
expect barra "--staged pega a linha nova do índice" 'lib/a.dart:3'
run_gate "$WORK/repo"
expect barra "sem argumento, o índice também entra na conta" 'lib/a.dart:3'
run_gate "$WORK/repo" --tudo
expect barra "argumento desconhecido reprova com o uso" 'uso: scripts/checks/check_no_comments.sh'

caso
printf '// novo no dart\n' >> lib/a.dart; commit
export BASE_REF=nao-existe
run_gate "$WORK/repo"
unset BASE_REF
expect barra "BASE_REF que não resolve recusa em vez de aprovar" 'nao-existe'

novo_repo "$WORK/sem-base" trunk
printf 'x\n' > "$WORK/sem-base/a.txt" && git -C "$WORK/sem-base" add -A && git -C "$WORK/sem-base" commit -qm "chore: x"
run_gate "$WORK/sem-base"
expect barra "sem main nem origin/main, recusa em vez de aprovar" 'base da comparação indisponível'

echo "  $PASS ok, $FAIL falha(s)"
[ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]
