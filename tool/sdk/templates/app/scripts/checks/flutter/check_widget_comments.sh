#!/bin/bash
# Verifica que widgets não carreguem comentário nenhum, nem documentação ///.
# Regra: o widget diz o quê; o porquê mora em docs/DESIGN_SYSTEM.md.
# O check_no_comments.sh cobre // em todo o lib mas libera /// de propósito;
# dentro de presentation/ui/widgets/ nem /// é permitido.
# Uso: ./check_widget_comments.sh [diretório]

DIR="${1:-lib}"
WIDGETS_DIR="$DIR/presentation/ui/widgets"
VIOLATIONS=0

echo "🔍 Verificando comentários em widgets..."

if [ ! -d "$WIDGETS_DIR" ]; then
  echo "✅ Diretório widgets/ não existe (ok)"
  exit 0
fi

while IFS= read -r -d '' file; do
  while IFS= read -r match; do
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)

    if echo "$content" | grep -qE '^\s*(import|export) '; then
      continue
    fi
    if echo "$content" | grep -qE "https?://"; then
      continue
    fi
    if echo "$content" | grep -qE "'[^']*//[^']*'"; then
      continue
    fi

    echo "❌ $file:$line_num - $content"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -nE '//' "$file" 2>/dev/null || true)
done < <(find "$WIDGETS_DIR" -name '*.dart' -type f \
  -not -path '*/build/*' \
  -not -path '*/.dart_tool/*' \
  -print0)

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS comentário(s) em widgets"
  echo "💡 Widget não comenta. Mova o porquê para docs/DESIGN_SYSTEM.md"
  exit 1
else
  echo "✅ Nenhum comentário encontrado em widgets"
  exit 0
fi
