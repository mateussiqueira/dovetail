#!/bin/bash
# Comentário explicativo não entra em código NOVO — a explicação mora no PR.
# Olha linhas adicionadas, não arquivos: tocar um arquivo legado não arrasta a
# dívida dele. Documentação de API (/// e //!) passa.
source "$(dirname "${BASH_SOURCE[0]}")/_escopo.sh"
V=0
echo "🔍 Verificando comentários em linhas novas..."
while IFS= read -r m; do
  [ -z "$m" ] && continue
  f="${m%%:*}"; r="${m#*:}"; n="${r%%:*}"; c="${r#*:}"
  case "$f" in */tests/*|*_test.rs|*/examples/*) continue ;; esac
  echo "$c" | grep -qE '^\s*(///|//!)' && continue
  echo "$c" | grep -qE 'https?://' && continue
  echo "$c" | grep -qE '"[^"]*//[^"]*"' && continue
  echo "$c" | grep -qE '(^|[^:/])//([^/!]|$)' || continue
  echo "❌ $f:$n -$(echo "$c" | sed 's/^[[:space:]]*/ /')"; V=$((V+1))
done < <(linhas_novas "rs")
[ "$V" -gt 0 ] && { echo; echo "🚨 $V comentário(s) em código novo"; echo "💡 Dica: mova a explicação para o corpo do PR"; exit 1; }
echo "✅ Nenhum comentário em código novo"; exit 0
