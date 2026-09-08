#!/bin/bash
# Arquivo grande esconde responsabilidade demais.
# Uso: ./check_file_size.sh [limite_rs]
source "$(dirname "${BASH_SOURCE[0]}")/_escopo.sh"
LIM_RS="${1:-400}"; V=0
echo "🔍 Verificando tamanho de arquivos NOVOS (rs<=$LIM_RS)..."
while IFS= read -r f; do
  [ -z "$f" ] && continue
  n=$(wc -l < "$f" | tr -d ' ')
  if [ "$n" -gt "$LIM_RS" ]; then echo "❌ $f — $n linhas (limite $LIM_RS)"; V=$((V+1)); fi
done < <(arquivos_novos "rs")
[ "$V" -gt 0 ] && { echo; echo "🚨 $V arquivo(s) acima do limite"; echo "💡 Dica: separe por responsabilidade, não por tamanho"; exit 1; }
echo "✅ Arquivos novos dentro do limite"; exit 0
