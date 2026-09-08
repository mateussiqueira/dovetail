#!/bin/bash
# Verifica a regra de estado da camada de apresentação.
# Regra: page é sempre StatelessWidget e lê tudo do presenter. Page só tem
#        controller se tiver presenter — e o preferível é o presenter possuir
#        os controllers dos widgets.
#
# Confere três coisas:
#   1. nenhuma page é StatefulWidget;
#   2. page que recebe Controller também recebe Presenter;
#   3. presenter concreto não é StatefulWidget nem guarda BuildContext.
#
# A outra metade da regra — widget com lógica usa Controller — não é
# detectável por script: "lógica" não tem assinatura no código. Ela é revisada
# no code review, com docs/CONVENTIONS.md 4.1 como referência.
# Uso: ./check_page_presenter.sh [diretório]

DIR="${1:-lib}"
PAGES_DIR="$DIR/presentation/ui/pages"
VIOLATIONS=0

echo "🔍 Verificando page sem estado e posse de controller..."

if [ ! -d "$PAGES_DIR" ]; then
  echo "✅ Diretório pages/ não existe (ok)"
  exit 0
fi

for file in $(find "$PAGES_DIR" -name "*_page.dart" -not -path "*/build/*" 2>/dev/null); do
  if grep -qE 'class[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]+extends[[:space:]]+StatefulWidget' "$file"; then
    echo "❌ $file — page é StatefulWidget"
    echo "      page é StatelessWidget lendo do presenter (CONVENTIONS.md 4.1)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  if grep -qE 'final[[:space:]]+[A-Z][A-Za-z0-9_]*Controller[[:space:]]' "$file"; then
    if ! grep -qE 'final[[:space:]]+[A-Z][A-Za-z0-9_]*Presenter[[:space:]]' "$file"; then
      echo "❌ $file — recebe Controller sem receber Presenter"
      echo "      page só tem controller se tiver presenter"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
done

PRESENTERS_DIR="$DIR/presentation/presenters"
if [ -d "$PRESENTERS_DIR" ]; then
  for file in $(find "$PRESENTERS_DIR" -name "*.dart" -not -name "presenters.dart" 2>/dev/null); do
    head -1 "$file" | grep -qE '^export ' && continue

    if grep -qE 'extends[[:space:]]+StatefulWidget' "$file"; then
      echo "❌ $file — presenter não é widget"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi

    if grep -qE '\bBuildContext\b' "$file"; then
      echo "❌ $file — presenter guarda ou recebe BuildContext"
      echo "      presenter não conhece a árvore de widgets"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS violação(ões) da regra de page/presenter/controller"
  echo "💡 Veja docs/CONVENTIONS.md, seção 4.1"
  exit 1
else
  echo "✅ Pages sem estado e posse de controller respeitadas"
  exit 0
fi
