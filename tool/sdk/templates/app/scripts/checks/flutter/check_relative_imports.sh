#!/bin/bash
# Verifica uso de imports relativos (../) em vez de package: imports.
# Uso: ./check_relative_imports.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando imports relativos (deve usar package: em vez de ../)..."

# Detect package name
if [ -z "${CHECK_PACKAGE:-}" ]; then
  CHECK_PACKAGE="${MELOS_PACKAGE_NAME:-}"
fi
if [ -z "$CHECK_PACKAGE" ] && [ -f pubspec.yaml ]; then
  CHECK_PACKAGE="$(grep -m1 '^name:' pubspec.yaml | awk '{print $2}')"
fi
if [ -z "$CHECK_PACKAGE" ] && [ -f "$DIR/pubspec.yaml" ]; then
  CHECK_PACKAGE="$(grep -m1 '^name:' "$DIR/pubspec.yaml" | awk '{print $2}')"
fi

for file in $(find "$DIR" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" 2>/dev/null); do
  while IFS= read -r match; do
    line_num=$(echo "$match" | cut -d: -f1)
    echo "❌ $file:$line_num - Import relativo: $match"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -n "import '\\.\\." "$file" 2>/dev/null || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS imports relativos detectados"
  echo "💡 Dica: use 'package:${CHECK_PACKAGE:-<nome_do_package>}/...' em vez de '../'"
  exit 1
else
  echo "✅ Todos os imports usam package: corretamente"
  exit 0
fi
