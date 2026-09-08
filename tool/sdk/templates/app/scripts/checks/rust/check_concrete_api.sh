#!/bin/bash
# Campo tipado com o tipo concreto de infra impede testar o fluxo sem ele.
# Adaptado do example-rust: lá o concreto era ApiClient; aqui a regra é
# genérica — dependa de um trait, nunca de um tipo concreto. Troque o alvo
# com CONCRETE_TYPE (regex) quando o produto tiver a sua infra.
source "$(dirname "${BASH_SOURCE[0]}")/_escopo.sh"
CONCRETE="${CONCRETE_TYPE:-ApiClient}"
V=0
echo "🔍 Verificando campo preso ao tipo concreto ($CONCRETE) em linhas novas..."
while IFS= read -r m; do
  [ -z "$m" ] && continue
  f="${m%%:*}"; r="${m#*:}"; n="${r%%:*}"; c="${r#*:}"
  case "$f" in */tests/*|*_test.rs) continue ;; esac
  echo "$c" | grep -qE "^[[:space:]]*[a-z_]+:[[:space:]]*(Arc<)?$CONCRETE" || continue
  echo "$c" | grep -qE 'dyn |impl |<[A-Z]' && continue
  echo "❌ $f:$n -$c"; V=$((V+1))
done < <(linhas_novas "rs")
[ "$V" -gt 0 ] && { echo; echo "🚨 $V campo(s) novo(s) preso(s) ao tipo concreto"; echo "💡 Dica: dependa de um trait"; exit 1; }
echo "✅ Nenhuma dependência concreta nova"; exit 0
