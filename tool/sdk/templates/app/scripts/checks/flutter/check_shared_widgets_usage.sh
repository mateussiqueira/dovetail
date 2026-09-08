#!/bin/bash
# Verifica se widgets na pasta shared/ são realmente usados em múltiplas telas.
# Regra: widgets shared devem ser usados em 2+ telas diferentes.
# Arquivos listados em .shared_widgets_ignore.list (substring match) são ignorados.
# Uso: ./check_shared_widgets_usage.sh [diretório]

DIR="${1:-lib}"
IGNORE_FILE=".shared_widgets_ignore.list"
VIOLATIONS=0
IGNORED=0

echo "🔍 Verificando uso de widgets compartilhados..."

is_ignored() {
  local file="$1"
  if [ -f "$IGNORE_FILE" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      echo "$pattern" | grep -q "^#" && continue
      if echo "$file" | grep -qF "$pattern"; then
        return 0
      fi
    done < "$IGNORE_FILE"
  fi
  return 1
}

SHARED_DIR="$DIR/presentation/ui/widgets/shared"
WIDGETS_DIR="$DIR/presentation/ui/widgets"

if [ ! -d "$SHARED_DIR" ]; then
  echo "✅ Pasta shared/ não existe (ok)"
  exit 0
fi

for file in $(find "$SHARED_DIR" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  
  if is_ignored "$file"; then
    IGNORED=$((IGNORED + 1))
    continue
  fi

  WIDGET_NAME=$(basename "$file" .dart)
  
  # Contar usos em diferentes pastas de tela
  USAGE_COUNT=0
  USED_IN=""
  
  for screen_dir in "$WIDGETS_DIR"/*/; do
    if [ -d "$screen_dir" ] && [ "$screen_dir" != "$SHARED_DIR/" ]; then
      SCREEN_NAME=$(basename "$screen_dir")
      if grep -rl "$WIDGET_NAME" "$screen_dir" >/dev/null 2>&1; then
        USAGE_COUNT=$((USAGE_COUNT + 1))
        USED_IN="$USED_IN $SCREEN_NAME"
      fi
    fi
  done
  
  # Também verificar nas páginas
  if grep -rl "$WIDGET_NAME" "$DIR/presentation/ui/pages" >/dev/null 2>&1; then
    USAGE_COUNT=$((USAGE_COUNT + 1))
    USED_IN="$USED_IN pages"
  fi
  
  if [ "$USAGE_COUNT" -lt 2 ]; then
    echo "❌ Widget $WIDGET_NAME na pasta shared/ mas usado em apenas $USAGE_COUNT local(is):$USED_IN"
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo "✅ Widget $WIDGET_NAME compartilhado em $USAGE_COUNT telas:$USED_IN"
  fi
done

if [ "$IGNORED" -gt 0 ]; then
  echo "ℹ️  $IGNORED arquivo(s) ignorados via $IGNORE_FILE"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS widget(s) na pasta shared/ não são compartilhados"
  echo "💡 Mova widgets usados em apenas 1 tela para a pasta específica da tela"
  echo "💡 Ou, se for parte interna de um widget shared, adicione ao $IGNORE_FILE"
  exit 1
else
  echo "✅ Todos os widgets compartilhados são usados em múltiplas telas"
  exit 0
fi
