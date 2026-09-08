#!/bin/bash
# TODO/FIXME/HACK não entram em código novo.
source "$(dirname "${BASH_SOURCE[0]}")/_escopo.sh"
V=0
echo "🔍 Verificando TODO/FIXME/HACK em linhas novas..."
while IFS= read -r m; do
  [ -z "$m" ] && continue
  f="${m%%:*}"; r="${m#*:}"; n="${r%%:*}"; c="${r#*:}"
  echo "$c" | grep -qE '(TODO|FIXME|HACK)' || continue
  echo "❌ $f:$n -$c"; V=$((V+1))
done < <(linhas_novas "rs")
[ "$V" -gt 0 ] && { echo; echo "🚨 $V marcador(es) novo(s)"; echo "💡 Dica: resolva ou abra card"; exit 1; }
echo "✅ Nenhum TODO/FIXME/HACK novo"; exit 0
