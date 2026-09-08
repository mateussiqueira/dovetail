#!/bin/bash
# Verifica se cada arquivo na pasta widgets/ tem no máximo 1 tipo público.
# Regra: 1 classe pública por arquivo (critério rigoroso para widgets).
# Uso: ./check_widgets_one_class_per_file.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando 1 classe pública por arquivo na pasta widgets..."

PATTERN='^[[:space:]]*(sealed[[:space:]]+|abstract[[:space:]]+|final[[:space:]]+|base[[:space:]]+|interface[[:space:]]+)?(class|mixin|enum|typedef)[[:space:]]+[A-Z]'

WIDGETS_DIR="$DIR/presentation/ui/widgets"

if [ ! -d "$WIDGETS_DIR" ]; then
  echo "❌ Diretório widgets/ não encontrado"
  exit 1
fi

while IFS= read -r -d '' file; do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  
  matches=$(grep -nE "$PATTERN" "$file" 2>/dev/null || true)
  
  if [ -n "$matches" ]; then
    count=$(printf '%s\n' "$matches" | grep -c ':' || true)
    count=${count:-0}
    
    if [ "$count" -gt 1 ]; then
      echo "❌ $file — $count tipos públicos (máximo: 1)"
      printf '%s\n' "$matches" | sed 's/^/      /'
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
done < <(find "$WIDGETS_DIR" -name '*.dart' -type f \
  -not -path '*/build/*' \
  -not -path '*/.dart_tool/*' \
  -print0)

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS arquivo(s) na pasta widgets/ violam a regra de 1 tipo público"
  echo "💡 Extraia cada widget para seu próprio arquivo"
  exit 1
else
  echo "✅ Todos os arquivos na pasta widgets/ seguem a regra de 1 tipo público"
  exit 0
fi
