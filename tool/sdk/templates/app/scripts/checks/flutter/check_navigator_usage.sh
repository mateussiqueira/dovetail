#!/bin/bash
# Bloqueia uso direto de Navigator no código do app.
# Regra: usar WeaveNavigation (context.pushRoute/popRoute/etc).
# Exceção: mixins de dialog/snackbar podem usar Navigator diretamente.
# Uso: ./check_navigator_usage.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando uso direto de Navigator (deve usar Weave)..."

for file in $(find "$DIR" -name "*.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" -not -path "*/mixins/*" 2>/dev/null); do
  while IFS= read -r match; do
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)
    # Ignora linhas de comentário
    if echo "$content" | grep -qE '^\s*//|^\s*\*|^\s*///'; then
      continue
    fi
    # Ignora imports
    if echo "$content" | grep -qE "^\s*import "; then
      continue
    fi
    # Ignora Navigator em dialogs (pop de dialog)
    if echo "$content" | grep -qE 'Navigator\.of\(.*\)\.pop\(\)'; then
      continue
    fi
    echo "❌ $file:$line_num - Uso direto de Navigator: $content"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -nE '\bNavigator\b' "$file" 2>/dev/null || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS uso(s) direto(s) de Navigator detectado(s)"
  echo "💡 Use context.pushRoute() / context.popRoute() (Weave)"
  exit 1
else
  echo "✅ Nenhum uso direto de Navigator encontrado"
  exit 0
fi
