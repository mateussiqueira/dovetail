#!/bin/bash
# Verifica que toda implementação concreta de presenter e de controller
# implemente uma interface.
# Regra: presenter e controller têm classe abstrata; a implementação concreta
#        declara `implements` nela. A UI depende da interface, nunca da
#        implementação.
#
#   home_presenter.dart                 abstract class HomePresenter
#   change_notifier_home_presenter.dart class ChangeNotifierHomePresenter
#                                             implements HomePresenter
# Uso: ./check_abstract_interfaces.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando interfaces de presenters e controllers..."

while IFS= read -r -d '' file; do
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue

  BASE=$(basename "$file" .dart)

  case "$BASE" in
    change_notifier_*)
      SUFFIX="${BASE#change_notifier_}"
      INTERFACE_FILE="$(dirname "$file")/$SUFFIX.dart"

      if [ ! -f "$INTERFACE_FILE" ]; then
        echo "❌ $file — não existe a interface $SUFFIX.dart ao lado"
        VIOLATIONS=$((VIOLATIONS + 1))
        continue
      fi

      if ! grep -qE 'implements[[:space:]]+[A-Z]' "$file"; then
        echo "❌ $file — implementação concreta sem 'implements'"
        echo "      declare implements na interface de $SUFFIX.dart"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
    *_presenter|*_controller)
      if ! grep -qE '^[[:space:]]*abstract[[:space:]]+(base[[:space:]]+|interface[[:space:]]+)?class' "$file"; then
        echo "❌ $file — presenter/controller sem classe abstrata"
        echo "      a interface fica em $BASE.dart e a implementação em"
        echo "      change_notifier_$BASE.dart"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
      ;;
  esac
done < <(find "$DIR" \( -name "*_presenter.dart" -o -name "*_controller.dart" \) \
  -not -path "*/build/*" -not -path "*/.dart_tool/*" -print0)

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS implementação(ões) sem interface"
  echo "💡 Veja docs/CONVENTIONS.md, seção 4.1"
  exit 1
else
  echo "✅ Presenters e controllers têm interface"
  exit 0
fi
