#!/bin/bash
# Verifica se há lógica hardcoded em presenters.
# Regra: presenters devem usar usecases, não ter lógica hardcoded.
# Uso: ./check_no_hardcoded_logic.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando lógica hardcoded em presenters..."

PRESENTERS_DIR="$DIR/presentation/presenters"

for presenter in $(find "$PRESENTERS_DIR" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$presenter" 2>/dev/null | grep -qE '^export ' && continue
  
  # Verificar se é uma implementação (não abstração)
  if grep -qE 'class ChangeNotifier' "$presenter" 2>/dev/null; then
    PRESENTER_NAME=$(basename "$presenter" .dart)
    
    # Verificar se tem Future.delayed (indicativo de lógica hardcoded)
    if grep -qE 'Future\.delayed' "$presenter" 2>/dev/null; then
      echo "❌ $PRESENTER_NAME contém Future.delayed (lógica hardcoded)"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
    
    # Verificar se tem dados hardcoded (const [...])
    if grep -qE 'const \[.*ServerModel\|const \[.*UserModel' "$presenter" 2>/dev/null; then
      echo "❌ $PRESENTER_NAME contém dados hardcoded"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
    
    # Verificar se tem lógica de negócio (if/else complexo sem usecase)
    if grep -qE 'if.*&&|if.*\|\||switch.*case' "$presenter" 2>/dev/null; then
      if ! grep -qE "import.*usecases" "$presenter" 2>/dev/null; then
        echo "⚠️  $PRESENTER_NAME pode ter lógica de negócio sem usar usecases"
      fi
    fi
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS violação(ões) de lógica hardcoded detectada(s)"
  echo "💡 Extraia a lógica para usecases e injete nos presenters"
  exit 1
else
  echo "✅ Nenhuma lógica hardcoded encontrada em presenters"
  exit 0
fi
