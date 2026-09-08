#!/bin/bash
# Verifica o padrão de componentes de widget.
# Regra: um widget composto guarda suas partes numa pasta com o nome dele,
#        um nível abaixo, e essas partes são internas ao widget.
#
#   shared/step_indicator.dart          <- widget público
#   shared/step_indicator/
#     step_progress_bar.dart            <- componente
#     step_indicator_components.dart    <- barril
#
# Confere quatro coisas:
#   1. toda pasta de componentes tem o widget de mesmo nome ao lado;
#   2. toda pasta de componentes tem barril <widget>_components.dart;
#   3. o barril exporta todos os .dart da pasta;
#   4. componente só é importado de dentro da própria pasta ou pelo pai.
# Uso: ./check_widget_components.sh [diretório]

DIR="${1:-lib}"
WIDGETS_DIR="$DIR/presentation/ui/widgets"
VIOLATIONS=0

echo "🔍 Verificando padrão de componentes de widget..."

if [ ! -d "$WIDGETS_DIR" ]; then
  echo "❌ Diretório widgets/ não encontrado"
  exit 1
fi

for screen_dir in "$WIDGETS_DIR"/*/; do
  [ -d "$screen_dir" ] || continue

  for component_dir in "$screen_dir"*/; do
    [ -d "$component_dir" ] || continue

    WIDGET=$(basename "$component_dir")
    PARENT="${screen_dir}${WIDGET}.dart"
    BARREL="${component_dir}${WIDGET}_components.dart"

    if [ ! -f "$PARENT" ]; then
      echo "❌ $component_dir — não existe o widget $PARENT ao lado"
      echo "      pasta de componentes precisa do widget de mesmo nome um nível acima"
      VIOLATIONS=$((VIOLATIONS + 1))
      continue
    fi

    if [ ! -f "$BARREL" ]; then
      echo "❌ $component_dir — falta o barril $(basename "$BARREL")"
      VIOLATIONS=$((VIOLATIONS + 1))
      continue
    fi

    for component in "$component_dir"*.dart; do
      [ -f "$component" ] || continue
      COMPONENT_FILE=$(basename "$component")
      [ "$component" = "$BARREL" ] && continue

      if ! grep -qF "export '$COMPONENT_FILE';" "$BARREL"; then
        echo "❌ $component — não exportado por $(basename "$BARREL")"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi

      IMPORT_PATH="widgets/$(basename "$screen_dir")/$WIDGET/$COMPONENT_FILE"
      while IFS= read -r importer; do
        [ -z "$importer" ] && continue
        case "$importer" in
          "$component_dir"*) continue ;;
          "$PARENT") continue ;;
        esac
        echo "❌ $importer — importa o componente $COMPONENT_FILE de fora de $WIDGET/"
        echo "      importe o widget $WIDGET.dart ou o barril da pasta"
        VIOLATIONS=$((VIOLATIONS + 1))
      done < <(grep -rlF "$IMPORT_PATH" "$DIR" --include="*.dart" 2>/dev/null || true)
    done
  done
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS violação(ões) do padrão de componentes"
  echo "💡 Veja docs/DESIGN_SYSTEM.md, seção 'O padrão de componentes'"
  exit 1
else
  echo "✅ Padrão de componentes respeitado"
  exit 0
fi
