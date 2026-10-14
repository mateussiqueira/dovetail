#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C

uso() {
  echo "uso: bash scripts/checks/shell_scripts_kept.sh [--update] [--strict]"
  echo "   confere os .sh e os hooks rastreados contra scripts/checks/shell_scripts.manifest"
  echo "   --update  acrescenta ao manifesto os scripts novos; nunca tira um que sumiu"
  echo "   --strict  script novo fora do manifesto reprova em vez de avisar"
  exit 2
}

atualiza=0
estrito=0
for arg in "$@"; do
  case "$arg" in
    --update) atualiza=1 ;;
    --strict) estrito=1 ;;
    *) uso ;;
  esac
done

raiz="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "❌ fora de um repositório git"; exit 2; }
cd "$raiz" || exit 2
manifesto=scripts/checks/shell_scripts.manifest
dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$dir"' EXIT

git -c core.quotePath=false ls-files -- '*.sh' '*githooks/*' | sort -u > "$dir/rastreados"
if [ -f "$manifesto" ]; then
  grep -v '^[[:space:]]*$' "$manifesto" | sort -u > "$dir/listados"
elif [ "$atualiza" -eq 1 ]; then
  : > "$dir/listados"
else
  echo "❌ $manifesto não existe; crie-o com --update"
  exit 1
fi

comm -23 "$dir/listados" "$dir/rastreados" > "$dir/faltando"
comm -13 "$dir/listados" "$dir/rastreados" > "$dir/novos"
if [ "$atualiza" -eq 1 ]; then
  sort -u "$dir/listados" "$dir/rastreados" > "$manifesto"
  sed "s|^|➕ entrou no manifesto: |" "$dir/novos"
  : > "$dir/novos"
fi

falhas=0
while IFS= read -r arquivo; do
  echo "❌ $arquivo sumiu: script .sh nunca é apagado, e ele está em $manifesto"
  falhas=$((falhas + 1))
done < "$dir/faltando"
while IFS= read -r arquivo; do
  if [ "$estrito" -eq 1 ]; then
    echo "❌ $arquivo fora de $manifesto; rode bash scripts/checks/shell_scripts_kept.sh --update"
    falhas=$((falhas + 1))
  else
    echo "⚠️  $arquivo fora de $manifesto; rode bash scripts/checks/shell_scripts_kept.sh --update"
  fi
done < "$dir/novos"

if [ "$falhas" -gt 0 ]; then
  echo "🚫 $falhas problema(s) nos scripts rastreados"
  exit 1
fi
echo "✅ $(wc -l < "$dir/rastreados" | tr -d ' ') script(s) rastreado(s), nenhum faltando"
