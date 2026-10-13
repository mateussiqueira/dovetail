#!/usr/bin/env bash
set -uo pipefail

raiz="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "❌ fora de um repositório git"
  exit 2
}
pacote="${1:-}"
piso="${2:-}"
if [ -z "$pacote" ] || ! [[ $piso =~ ^[0-9]+$ ]]; then
  echo "uso: bash scripts/checks/check_coverage.sh <pacote> <piso em %, inteiro>"
  echo "     COVERAGE_LCOV=<arquivo> julga um lcov pronto, sem rodar a suíte"
  echo "     COVERAGE_RUNNER=<programa> roda a suíte no lugar do flutter ou do dart"
  exit 2
fi
dir="$raiz/$pacote"
if [ ! -f "$dir/pubspec.yaml" ]; then
  echo "❌ $pacote não tem pubspec.yaml"
  exit 2
fi

lcov="${COVERAGE_LCOV:-}"
if [ -z "$lcov" ]; then
  nome="$(sed -n 's/^name:[[:space:]]*\([a-z0-9_]*\).*/\1/p' "$dir/pubspec.yaml" | head -n 1)"
  barril="$dir/test/coverage_barrel_test.dart"
  saida="$(mktemp -d)"
  trap 'rm -rf "$barril" "$saida"' EXIT
  {
    (cd "$dir" && find lib -name '*.dart' | sort) | while IFS= read -r arquivo; do
      head -n 5 "$dir/$arquivo" | grep -q '^part of' && continue
      echo "import 'package:$nome/${arquivo#lib/}';"
    done
    echo
    echo 'void main() {}'
  } > "$barril"
  lcov="$saida/lcov.info"
  if grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter' "$dir/pubspec.yaml"; then
    suite=("${COVERAGE_RUNNER:-flutter}" test --no-pub --coverage --coverage-path="$lcov" --concurrency=2)
  else
    suite=("${COVERAGE_RUNNER:-dart}" test --coverage-path="$lcov" --concurrency=2)
  fi
  if ! (cd "$dir" && "${suite[@]}") > "$saida/log" 2>&1 || [ ! -f "$lcov" ]; then
    echo "❌ $pacote: a suíte falhou, e sem ela não há cobertura para medir"
    tail -n 20 "$saida/log"
    exit 1
  fi
fi

LC_ALL=C awk -v pacote="$pacote" -v piso="$piso" '
  /^SF:/ { dentro = ($0 ~ /^SF:(.*\/)?lib\//) }
  dentro && /^DA:/ {
    split(substr($0, 4), campo, ",")
    total++
    if (campo[2] + 0 > 0) cobertas++
  }
  END {
    if (total == 0) {
      print "❌ " pacote ": nenhuma linha de lib/ no lcov"
      exit 1
    }
    medida = cobertas * 100 / total
    printf "%s: %.1f%% (%d de %d linhas de lib/), piso %d%%\n", pacote, medida, cobertas, total, piso
    if (medida < piso) {
      print "❌ abaixo do piso"
      exit 1
    }
    if (int(medida) > piso) print "💡 a medida passou do piso: suba-o para " int(medida) " em scripts/checks/coverage_floors.txt"
    print "✅ no piso ou acima"
  }
' "$lcov"
