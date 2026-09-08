#!/bin/bash
# Verifica que não existam classes de widget privadas (prefixo _) nas páginas.
# Regra: widgets devem estar em presentation/ui/widgets/, nunca nas páginas.
# Exceção: State classes (_State) são permitidas para StatefulWidget.
# Uso: ./check_no_private_widgets.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando widgets privados nas páginas..."

# Padrão para classes privadas (exceto State classes)
PATTERN='^[[:space:]]*(sealed[[:space:]]+|abstract[[:space:]]+|final[[:space:]]+|base[[:space:]]+|interface[[:space:]]+)?(class|mixin|enum|typedef)[[:space:]]+_[A-Z]'

# Padrão para State classes (permitidas)
STATE_PATTERN='^[[:space:]]*class[[:space:]]+_[A-Za-z]+State[[:space:]]+extends[[:space:]]+State'

for file in $(find "$DIR/presentation/ui/pages" -name "*.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  
  matches=$(grep -nE "$PATTERN" "$file" 2>/dev/null || true)
  
  if [ -n "$matches" ]; then
    # Filtrar State classes
    filtered_matches=""
    while IFS= read -r match; do
      line_num=$(echo "$match" | cut -d: -f1)
      content=$(echo "$match" | cut -d: -f2-)
      
      # Verificar se é uma State class
      if echo "$content" | grep -qE 'class[[:space:]]+_[A-Za-z]+State[[:space:]]+extends[[:space:]]+State'; then
        continue
      fi
      
      filtered_matches="$filtered_matches$match\n"
    done <<< "$matches"
    
    if [ -n "$filtered_matches" ]; then
      echo "❌ $file — widgets privados encontrados:"
      printf '%s' "$filtered_matches" | sed 's/^/      /'
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS arquivo(s) contêm widgets privados nas páginas"
  echo "💡 Extraia os widgets para presentation/ui/widgets/"
  exit 1
else
  echo "✅ Nenhum widget privado encontrado nas páginas"
  exit 0
fi
