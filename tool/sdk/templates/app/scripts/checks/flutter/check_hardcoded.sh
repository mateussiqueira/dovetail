#!/bin/bash
# Verifica cores e strings hardcoded no código.
# Deve usar AppColors do theme ao invés de Colors.xxx ou 0xFFxxx.
# Uso: ./check_hardcoded.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando cores/strings hardcoded..."

# Verificar cores hardcoded (0xFF...)
for file in $(find "$DIR" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" 2>/dev/null); do
  # Pular arquivos de tema e constants
  case "$file" in
    *theme*|*color*|*constants*) continue ;;
  esac

  while IFS= read -r match; do
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)
    # Ignora comentários
    if echo "$content" | grep -qE '^\s*//'; then
      continue
    fi
    echo "⚠️  $file:$line_num - Cor hardcoded: $content"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -nE "Color\(0x[0-9A-Fa-f]+\)" "$file" 2>/dev/null || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "⚠️  $VIOLATIONS ocorrência(s) de cores hardcoded"
  echo "💡 Dica: use AppColors do theme ao invés de Color(0xFF...)"
  echo "   (warnings não bloqueiam, apenas recomendam)"
  exit 0
else
  echo "✅ Nenhuma cor hardcoded encontrada"
  exit 0
fi
