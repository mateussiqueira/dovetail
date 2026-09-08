#!/bin/bash
# Endereço de servidor mora em configuração de ambiente e em mais lugar nenhum.
# O domínio é de produto: defina URL_HOST (fragmento de regex) no ambiente do
# gate. Vazio desativa o check — um scaffold genérico não tem domínio.
source "$(dirname "${BASH_SOURCE[0]}")/_escopo.sh"
HOST="${URL_HOST:-}"
V=0
if [ -z "$HOST" ]; then
  echo "ℹ️ URL_HOST não definido — check de URLs desativado"
  exit 0
fi
echo "🔍 Verificando URLs fixas ($HOST) em linhas novas..."
while IFS= read -r m; do
  [ -z "$m" ] && continue
  f="${m%%:*}"; r="${m#*:}"; n="${r%%:*}"; c="${r#*:}"
  case "$f" in */tests/*|*_test.rs) continue ;; esac
  corte=$(grep -n '#\[cfg(test)\]' "$f" 2>/dev/null | head -1 | cut -d: -f1)
  [ -n "$corte" ] && [ "$n" -ge "$corte" ] && continue
  echo "$c" | grep -qE "https?://[a-z0-9.-]*($HOST)" || continue
  echo "❌ $f:$n -$c"; V=$((V+1))
done < <(linhas_novas "rs")
[ "$V" -gt 0 ] && { echo; echo "🚨 $V endereço(s) fixo(s) novo(s)"; echo "💡 Dica: mova para a configuração de ambiente"; exit 1; }
echo "✅ Nenhum endereço fixo novo"; exit 0
