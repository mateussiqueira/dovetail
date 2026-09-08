#!/bin/bash
# Verifica se cada arquivo .dart tem no máximo 1 tipo PÚBLICO de nível superior.
# Permitido: 1 tipo público + N tipos privados (prefixo `_").
# Uso: ./check_one_class_per_file.sh [dir1] [dir2 ...]

TARGETS=("$@")
if [ "${#TARGETS[@]}" -eq 0 ]; then
  TARGETS=(lib)
fi

VIOLATIONS=0

echo "🔍 Verificando regra de 1 tipo público por arquivo..."

PATTERN='^[[:space:]]*(sealed[[:space:]]+|abstract[[:space:]]+|final[[:space:]]+|base[[:space:]]+|interface[[:space:]]+)?(class|mixin|enum|typedef)[[:space:]]+[A-Z]|^[[:space:]]*extension[[:space:]]+(type[[:space:]]+)?[A-Z]'

for DIR in "${TARGETS[@]}"; do
  if [ ! -d "$DIR" ]; then
    echo "⚠️  Diretório não encontrado: $DIR (ignorado)"
    continue
  fi

  while IFS= read -r -d '' file; do
    case "$file" in
      *_test.dart) continue ;;
    esac
    head -1 "$file" 2>/dev/null | grep -qE '^\s*part\s+of\s+' && continue

    matches=$(grep -nE "$PATTERN" "$file" 2>/dev/null || true)

    if [ -n "$matches" ]; then
      count=$(printf '%s\n' "$matches" | grep -c ':' || true)
      count=${count:-0}

      if [ "$count" -gt 1 ]; then
        echo "❌ $file — $count tipos públicos (máximo: 1)"
        printf '%s\n' "$matches" | sed 's/^/      /'
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
    fi
  done < <(find "$DIR" -name '*.dart' -type f \
    -not -path '*/build/*' \
    -not -path '*/.dart_tool/*' \
    -print0)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS arquivo(s) violam a regra de 1 tipo público por arquivo"
  exit 1
fi

echo "✅ Todos os arquivos seguem a regra de 1 tipo público por arquivo"
exit 0
