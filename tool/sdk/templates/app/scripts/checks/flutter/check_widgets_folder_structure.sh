#!/bin/bash
# Verifica que todos os widgets estejam organizados na pasta widgets/.
# Regra: widgets públicos devem estar em presentation/ui/widgets/<tela>/
# Uso: ./check_widgets_folder_structure.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando estrutura de pastas dos widgets..."

# Verificar se widgets existem na estrutura correta
WIDGETS_DIR="$DIR/presentation/ui/widgets"
PAGES_DIR="$DIR/presentation/ui/pages"

if [ ! -d "$WIDGETS_DIR" ]; then
  echo "❌ Diretório widgets/ não encontrado"
  exit 1
fi

# Verificar se há widgets soltos na pasta pages (fora dos arquivos de página)
for file in $(find "$PAGES_DIR" -name "*.dart" -not -name "*_page.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue
  
  echo "❌ Widget encontrado fora de widgets/: $file"
  VIOLATIONS=$((VIOLATIONS + 1))
done

# Verificar se widgets compartilhados estão na pasta shared
SHARED_DIR="$WIDGETS_DIR/shared"
if [ -d "$SHARED_DIR" ]; then
  for file in $(find "$SHARED_DIR" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
    # Verificar se o widget é usado em mais de uma tela
    WIDGET_NAME=$(basename "$file" .dart)
    
    # Contar usos em diferentes pastas de tela
    USAGE_COUNT=0
    for screen_dir in "$WIDGETS_DIR"/*/; do
      if [ -d "$screen_dir" ] && [ "$screen_dir" != "$SHARED_DIR/" ]; then
        if grep -rl "$WIDGET_NAME" "$screen_dir" >/dev/null 2>&1; then
          USAGE_COUNT=$((USAGE_COUNT + 1))
        fi
      fi
    done
    
    if [ "$USAGE_COUNT" -lt 2 ]; then
      echo "⚠️  Widget $WIDGET_NAME na pasta shared/ mas usado em apenas $USAGE_COUNT tela(s)"
    fi
  done
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS widget(s) fora da estrutura correta"
  echo "💡 Mova os widgets para presentation/ui/widgets/<tela>/"
  exit 1
else
  echo "✅ Estrutura de pastas dos widgets está correta"
  exit 0
fi
