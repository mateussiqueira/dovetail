#!/bin/bash
# Verifica presença de comentários TODO, FIXME, HACK em código de produção.
# Uso: ./check_todo_comments.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando comentários TODO/FIXME/HACK..."

for file in $(find "$DIR" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" 2>/dev/null); do
  while IFS= read -r match; do
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)
    echo "❌ $file:$line_num - $content"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -nE '(TODO|FIXME|HACK)' "$file" 2>/dev/null || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS comentários de TODO/FIXME/HACK detectados"
  echo "💡 Dica: resolva ou mova para issues do GitHub"
  exit 1
else
  echo "✅ Nenhum TODO/FIXME/HACK encontrado"
  exit 0
fi
