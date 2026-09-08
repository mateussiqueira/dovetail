#!/bin/bash
# Verifica se algum arquivo .dart em lib/ ou test/ ultrapassa o limite de linhas.
# Arquivos listados em .file_size_ignore.list (substring match) são ignorados.
# Uso: ./check_file_size.sh [limite] [dir1] [dir2 ...]

LIMIT="${1:-200}"
DIRS=("${@:2}")
if [ ${#DIRS[@]} -eq 0 ]; then
  DIRS=(lib test)
fi

IGNORE_FILE=".file_size_ignore.list"
VIOLATIONS=0

echo "📏 Verificando tamanho de arquivos .dart (limite: $LIMIT linhas)..."

is_ignored() {
  local file="$1"
  if [ -f "$IGNORE_FILE" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      echo "$pattern" | grep -q "^#" && continue
      if echo "$file" | grep -qF "$pattern"; then
        return 0
      fi
    done < "$IGNORE_FILE"
  fi
  return 1
}

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for file in $(find "$dir" -name "*.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" 2>/dev/null); do
    lines=$(wc -l < "$file")
    if [ "$lines" -gt "$LIMIT" ]; then
      if is_ignored "$file"; then
        continue
      fi
      echo "❌ $file — $lines linhas (limite: $LIMIT)"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS arquivo(s) ultrapassam $LIMIT linhas"
  echo "💡 Dica: refactor para arquivos menores ou adicione ao .file_size_ignore.list"
  exit 1
else
  echo "✅ Todos os arquivos .dart respeitam o limite de $LIMIT linhas"
  exit 0
fi
