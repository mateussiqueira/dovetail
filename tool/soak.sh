#!/usr/bin/env bash
set -euo pipefail

# Roda o alvo `test` N vezes e conta quantas voltaram verdes.
#
# Existe porque "o portão é confiável" não é uma coisa que se afirme: uma
# corrida verde não distingue um portão determinístico de um que falha uma vez
# em duas. Este repositório mediu 1 vermelho em 2 — `product/vpn_desktop`
# reportando FAILED com zero testes rodados, e `dovetail_signer` caindo no
# nested_code_folder_test, os dois passando sozinhos logo depois.
#
# A saída é uma linha só, comparável entre corridas e entre máquinas:
#
#   10/10 green
#
# Qualquer coisa diferente de N/N é motivo para não confiar no verde de uma
# corrida única, e as corridas vermelhas ficam em $out para serem lidas.
#
# Uso:
#   bash tool/soak.sh [N]              # N corridas, default 10
#   DOVETAIL_LANES=1 bash tool/soak.sh # sob outra concorrência
#
# Sob carga é onde o flake aparece — `tool/verify.dart` diz isso no comentário
# das lanes —, então para exercitar de verdade vale rodar com a máquina
# ocupada, não numa ociosa.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runs="${1:-10}"
if ! [ "$runs" -gt 0 ] 2>/dev/null; then
  echo "usage: bash tool/soak.sh [runs]   (runs must be a positive integer)" >&2
  exit 64
fi

out="$(mktemp -d /tmp/dovetail-soak.XXXXXX)"
green=0
red=0

for i in $(seq 1 "$runs"); do
  log="$out/run-$i.log"
  if dart tool/verify.dart test >"$log" 2>&1; then
    green=$((green + 1))
    printf '  run %2d/%d  green\n' "$i" "$runs"
    rm -f "$log"
  else
    red=$((red + 1))
    printf '  run %2d/%d  RED    %s\n' "$i" "$runs" "$log"
    grep -E "FAILED|LOAD FAILED|UNRESOLVED" "$log" | head -5 | sed 's/^/        /' || true
  fi
done

echo
echo "$green/$runs green"

if [ "$red" -ne 0 ]; then
  echo "  $red red run(s) kept in $out"
  exit 1
fi

rmdir "$out" 2>/dev/null || true
