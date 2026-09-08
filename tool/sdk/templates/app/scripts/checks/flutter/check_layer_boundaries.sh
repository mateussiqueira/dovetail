#!/bin/bash
# Verifica as dependências entre camadas da Clean Architecture.
#
#   domain  ←  data  ←  infra  ←  presentation  ←  main
#   Nenhuma camada pode depender de uma camada mais externa.
#
# Uso: ./check_layer_boundaries.sh [diretório lib]

DIR="${1:-lib}"
PKG="{{name}}"
VIOLATIONS=0

echo "🔍 Verificando fronteiras entre camadas..."

report() {
  echo "❌ $1:$2"
  echo "     $3"
  echo "     ↳ $4"
  VIOLATIONS=$((VIOLATIONS + 1))
}

layer_files() {
  find "$DIR/$1" -name '*.dart' -not -path '*/build/*' 2>/dev/null
}

# Lê os imports de um arquivo, um por linha, já sem o `import '...';`
imports_of() {
  grep -oE "^import '[^']+'" "$1" 2>/dev/null | sed "s/^import '//; s/'$//"
}

# ── domain: Dart puro. Só pode enxergar o próprio domain. ───────────────────
while IFS= read -r file; do
  [ -z "$file" ] && continue
  while IFS= read -r imp; do
    [ -z "$imp" ] && continue
    case "$imp" in
      dart:*|package:$PKG/domain/*) ;;
      package:flutter/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "domain é Dart puro: não pode importar Flutter" ;;
      package:$PKG/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "domain não pode depender de camadas externas" ;;
      package:*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "domain não pode depender de pacotes externos" ;;
    esac
  done < <(imports_of "$file")
done < <(layer_files domain)

# ── data: domain + shared. Sem Flutter, sem infra/presentation/main. ────────
while IFS= read -r file; do
  [ -z "$file" ] && continue
  while IFS= read -r imp; do
    [ -z "$imp" ] && continue
    case "$imp" in
      dart:*|package:$PKG/data/*|package:$PKG/domain/*|package:$PKG/shared/*) ;;
      package:flutter/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "data não pode importar Flutter" ;;
      package:$PKG/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "data só pode depender de domain e shared" ;;
      package:*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "dependências de terceiros pertencem a infra/, não a data/" ;;
    esac
  done < <(imports_of "$file")
done < <(layer_files data)

# ── presentation: domain + shared + Flutter. Nunca data/infra/main. ─────────
while IFS= read -r file; do
  [ -z "$file" ] && continue
  while IFS= read -r imp; do
    [ -z "$imp" ] && continue
    case "$imp" in
      dart:*|package:flutter/*|package:$PKG/presentation/*|package:$PKG/domain/*|package:$PKG/shared/*) ;;
      package:$PKG/data/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "presentation consome entidades de domain, não models de data" ;;
      package:$PKG/infra/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "presentation não conhece implementações de infra" ;;
      package:$PKG/main/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "main é o composition root: só ele importa as outras camadas" ;;
    esac
  done < <(imports_of "$file")
done < <(layer_files presentation)

# ── infra: implementa contratos de data. Não pode subir para presentation. ──
while IFS= read -r file; do
  [ -z "$file" ] && continue
  while IFS= read -r imp; do
    [ -z "$imp" ] && continue
    case "$imp" in
      package:$PKG/presentation/*|package:$PKG/main/*)
        report "$file" "$(grep -n "$imp" "$file" | head -1 | cut -d: -f1)" "$imp" \
          "infra não pode depender de presentation nem de main" ;;
    esac
  done < <(imports_of "$file")
done < <(layer_files infra)

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "🚨 $VIOLATIONS violação(ões) de fronteira entre camadas"
  echo "💡 Regra: domain ← data ← infra ← presentation ← main"
  exit 1
fi

echo "✅ Fronteiras entre camadas respeitadas"
exit 0
