#!/bin/bash
# Verifica presença de comentários em código de produção.
# Regra: Nenhum comentário é permitido (exceto documentação ///).
# Uso: ./check_no_comments.sh [diretório]

DIR="${1:-lib}"
VIOLATIONS=0

echo "🔍 Verificando comentários em código de produção..."

for file in $(find "$DIR" -name "*.dart" -not -name "*_test.dart" -not -path "*/build/*" -not -path "*/.dart_tool/*" 2>/dev/null); do
  while IFS= read -r match; do
    line_num=$(echo "$match" | cut -d: -f1)
    content=$(echo "$match" | cut -d: -f2-)
    
    # Ignorar linhas de import/export
    if echo "$content" | grep -qE '^\s*(import|export) '; then
      continue
    fi
    
    # Ignorar documentação (///)
    if echo "$content" | grep -qE '^\s*///'; then
      continue
    fi
    
    # Ignorar linhas vazias ou apenas espaços
    if echo "$content" | grep -qE '^\s*$'; then
      continue
    fi
    
    # Ignorar URLs (http:// ou https://)
    if echo "$content" | grep -qE "https?://"; then
      continue
    fi
    
    # Ignorar strings que contêm //
    if echo "$content" | grep -qE "'[^']*//[^']*'"; then
      continue
    fi
    
    echo "❌ $file:$line_num - $content"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -nE '//[^/]' "$file" 2>/dev/null || true)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "🚨 $VIOLATIONS comentários detectados em código de produção"
  echo "💡 Dica: o código deve ser autoexplicativo, sem comentários"
  exit 1
else
  echo "✅ Nenhum comentário encontrado em código de produção"
  exit 0
fi
