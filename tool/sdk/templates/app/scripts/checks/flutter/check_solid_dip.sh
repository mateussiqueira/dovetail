#!/bin/bash
# Verifica se presenters usam usecases (DIP).
# Regra: presenters não devem ter lógica hardcoded, devem usar usecases.
# Uso: ./check_solid_dip.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando Dependency Inversion Principle (DIP)..."

PRESENTERS_DIR="$DIR/presentation/presenters"
USECASES_DIR="$DIR/domain/usecases"

# Verificar se há usecases implementados
if [ ! -d "$USECASES_DIR" ]; then
  echo "⚠️  Diretório de usecases não encontrado"
  exit 0
fi

USECASE_COUNT=$(find "$USECASES_DIR" -name "*.dart" -not -path "*/build/*" 2>/dev/null | wc -l)

if [ "$USECASE_COUNT" -eq 0 ]; then
  echo "⚠️  Nenhum usecase encontrado"
  exit 0
fi

echo "   Usecases encontrados: $USECASE_COUNT"

# Verificar se presenters importam usecases
for presenter in $(find "$PRESENTERS_DIR" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$presenter" 2>/dev/null | grep -qE '^export ' && continue
  
  # Verificar se é uma implementação (não abstração)
  if grep -qE 'class ChangeNotifier' "$presenter" 2>/dev/null; then
    # Verificar se importa usecases
    if ! grep -qE "import.*usecases" "$presenter" 2>/dev/null; then
      PRESENTER_NAME=$(basename "$presenter" .dart)
      echo "⚠️  $PRESENTER_NAME não importa usecases"
    fi
  fi
done

# Verificar se há implementações de usecases na data
IMPLEMENTED_USECASES=$(find "$DIR/data/usecases" -name "*.dart" -not -path "*/build/*" 2>/dev/null | wc -l)

echo "   Usecases implementados na data: $IMPLEMENTED_USECASES"

if [ "$IMPLEMENTED_USECASES" -lt "$USECASE_COUNT" ]; then
  echo ""
  echo "⚠️  Há usecases no domain sem implementação na data"
  echo "💡 Implemente os usecases faltantes em data/usecases/"
fi

echo "✅ Verificação DIP concluída"
exit 0
