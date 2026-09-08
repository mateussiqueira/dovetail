#!/bin/bash
# Verifica se as dependências estão injetadas corretamente.
# Regra: a camada de apresentação recebe dependências via construtor — nunca
# instancia estado (presenter/controller) nem infraestrutura concreta. Quem
# monta o grafo é o container Weave, nos módulos de main/di/.
#
# Adaptado do check do mobile: lá a lista era Dio/FlutterSecureStorage/
# WireguardChannel. Aqui o alvo são os holders de estado e adaptadores
# concretos do próprio app — a regra vale sem conhecer o produto.
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

# Factories resolvem do container — é onde a composição acontece.
FACTORIES_DIR="$DIR/main/factories"
if [ -d "$FACTORIES_DIR" ]; then
  for factory in $(find "$FACTORIES_DIR" -name "*.dart" -not -path "*/build/*" 2>/dev/null); do
    head -1 "$factory" 2>/dev/null | grep -qE '^export ' && continue

    FACTORY_NAME=$(basename "$factory" .dart)
    if grep -qE 'c\.get<' "$factory" 2>/dev/null; then
      echo "✅ $FACTORY_NAME resolve dependências do container corretamente"
    fi
  done
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS violação(ões) de injeção de dependências"
  echo "💡 Injete dependências via construtor; a composição mora em main/di/ e main/factories/"
  exit 1
else
  echo "✅ Injeção de dependências está correta"
  exit 0
fi
