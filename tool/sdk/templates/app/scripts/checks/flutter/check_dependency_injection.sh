#!/bin/bash
# Verifica se as dependências estão injetadas corretamente.
# Uso: ./check_dependency_injection.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando injeção de dependências..."

# Apresentação não instancia implementação concreta: nem presenter/controller
# (o estado entra pronto), nem adaptador/serviço (infra não vaza para a UI).
CONCRETE='= ChangeNotifier[A-Za-z0-9_]+(Presenter|Controller)[[:space:]]*\(|= [A-Za-z0-9_]+(Adapter|Service)[[:space:]]*\('

for file in $(find "$DIR/presentation" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" 2>/dev/null); do
  # Ignorar barrel files
  head -1 "$file" 2>/dev/null | grep -qE '^export ' && continue

  if grep -qE "$CONCRETE" "$file" 2>/dev/null; then
    FILE_NAME=$(basename "$file" .dart)
    echo "❌ $FILE_NAME instancia classe concreta diretamente"
    echo "      apresentação recebe dependências via construtor, nunca as cria"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS violação(ões) de injeção de dependências"
  echo "💡 Injete dependências via construtor; a composição mora em main/di/ e main/factories/"
  exit 1
else
  echo "✅ Injeção de dependências está correta"
  exit 0
fi
