#!/bin/bash
set -uo pipefail
unset COVERAGE_LCOV COVERAGE_RUNNER

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_coverage.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; RC=0; OUT=""

confere() {
  local nome="$1"
  shift
  if "$@"; then echo "  ✅ $nome"; PASS=$((PASS + 1))
  else echo "  ❌ $nome"; FAIL=$((FAIL + 1)); fi
}
judge() { OUT="$(cd "$WORK/repo" && COVERAGE_LCOV="$WORK/$1" bash "$CHECK" pkg "$2" 2>&1)"; RC=$?; }
expect() {
  local ok=0
  grep -qF -- "$3" <<<"$OUT" || ok=1
  { [ "$1" = passa ] && [ "$RC" -ne 0 ]; } && ok=1
  { [ "$1" = barra ] && [ "$RC" -eq 0 ]; } && ok=1
  if [ "$ok" -eq 0 ]; then echo "  ✅ $2"; PASS=$((PASS + 1))
  else echo "  ❌ $2 (rc=$RC)"; sed 's/^/     /' <<<"$OUT"; FAIL=$((FAIL + 1)); fi
}

mkdir -p "$WORK/repo/pkg/lib/sub" "$WORK/repo/pkg/test" "$WORK/repo/sem_pubspec" && cd "$WORK/repo" || exit 1
git init -q
printf 'name: pkg\n' > pkg/pubspec.yaml
printf 'part %s;\n' "'parte.dart'" > pkg/lib/a.dart
printf 'part of %s;\n' "'a.dart'" > pkg/lib/parte.dart
printf 'int b() => 1;\n' > pkg/lib/sub/b.dart
cat > "$WORK/suite_falsa" <<'FAKE'
#!/bin/bash
for arg in "$@"; do case "$arg" in --coverage-path=*) lcov="${arg#--coverage-path=}" ;; esac; done
cp test/coverage_barrel_test.dart "$BARRIL_VISTO"
printf 'SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n' > "$lcov"
if [ "${SUITE_VERMELHA:-0}" = 1 ]; then echo "1 teste falhou"; exit 1; fi
FAKE
chmod +x "$WORK/suite_falsa"
printf 'SF:lib/a.dart\nDA:1,1\nDA:2,3\nDA:3,1\nDA:4,0\nend_of_record\n' > "$WORK/tres_de_quatro.info"
printf 'SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\nSF:test/a_test.dart\nDA:1,1\nDA:2,1\nDA:3,1\nend_of_record\n' > "$WORK/com_teste.info"
printf 'SF:%s/repo/pkg/lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n' "$WORK" > "$WORK/absoluto.info"
: > "$WORK/vazio.info"

judge tres_de_quatro.info 75
expect passa "75% no piso de 75 passa" 'pkg: 75.0% (3 de 4 linhas de lib/), piso 75%'
judge tres_de_quatro.info 76
expect barra "75% no piso de 76 barra" '❌ abaixo do piso'
judge tres_de_quatro.info 70
expect passa "75% acima do piso de 70 sugere subir o piso" 'suba-o para 75'
judge com_teste.info 51
expect barra "linhas de test/ não contam: 1 de 2 em lib/ barra o piso de 51" 'pkg: 50.0% (1 de 2 linhas de lib/)'
judge absoluto.info 50
expect passa "caminho absoluto de lib/ conta" 'pkg: 50.0% (1 de 2 linhas de lib/)'
judge vazio.info 0
expect barra "lcov sem linha de lib/ barra até com piso 0" 'nenhuma linha de lib/ no lcov'
judge tres_de_quatro.info ""
expect barra "sem piso: uso" 'uso: bash scripts/checks/check_coverage.sh'
judge tres_de_quatro.info 7.5
expect barra "piso fracionário: uso" 'uso: bash scripts/checks/check_coverage.sh'
OUT="$(cd "$WORK/repo" && COVERAGE_LCOV="$WORK/tres_de_quatro.info" bash "$CHECK" sem_pubspec 10 2>&1)"; RC=$?
expect barra "pasta sem pubspec.yaml barra" 'sem_pubspec não tem pubspec.yaml'

roda() { OUT="$(cd "$WORK/repo" && env COVERAGE_RUNNER="$WORK/suite_falsa" BARRIL_VISTO="$WORK/barril" "$@" bash "$CHECK" pkg 50 2>&1)"; RC=$?; }
roda
expect passa "sem COVERAGE_LCOV a suíte roda e o lcov dela é julgado" 'pkg: 50.0% (1 de 2 linhas de lib/)'
confere "o barril importa lib/a.dart" grep -qxF "import 'package:pkg/a.dart';" "$WORK/barril"
confere "o barril importa lib/sub/b.dart" grep -qxF "import 'package:pkg/sub/b.dart';" "$WORK/barril"
confere "o barril pula o part of" test -z "$(grep parte.dart "$WORK/barril")"
confere "o barril sai de test/ quando a medida acaba" test ! -e "$WORK/repo/pkg/test/coverage_barrel_test.dart"
roda SUITE_VERMELHA=1
expect barra "suíte vermelha barra sem medir" 'a suíte falhou'

echo "  $PASS ok, $FAIL falha(s)"
[ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]
