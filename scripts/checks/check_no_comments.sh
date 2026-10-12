#!/bin/bash

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTS="dart|rs|sh"
MODO="base"
case "${1:-}" in
  "") ;;
  --staged) MODO="staged" ;;
  *)
    echo "uso: scripts/checks/check_no_comments.sh [--staged]"
    echo "   sem argumento: linhas novas desde o merge-base com origin/main (ou BASE_REF)"
    echo "   --staged:      só as linhas novas do índice, para o pre-commit"
    exit 2
    ;;
esac

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "❌ fora de um repositório git"; exit 1; }
ESCOPO_TUDO=0
source "$AQUI/../../tool/sdk/templates/app/scripts/checks/rust/_escopo.sh"

RE_DIRETIVA='^[[:space:]]*(ignore:|ignore_for_file:|coverage:|dart format|@dart|SAFETY:)'
RE_SH_DIRETIVA='^[[:space:]]*#(!|[[:space:]]*shellcheck)'
RE_SH_COMENTARIO='(^|[[:space:]])#'
INDICE=""
trap '[ -z "$INDICE" ] || rm -f "$INDICE"' EXIT

sem_strings() {
  printf '%s\n' "$1" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g"
}

aparado() {
  local t="$1"
  t="${t#"${t%%[![:space:]]*}"}"
  printf '%s' "${t%"${t##*[![:space:]]}"}"
}

comentario() {
  local ext="$1" linha="$2" codigo
  if [ "$ext" = "sh" ]; then
    [[ $linha == *'#'* ]] || return 1
    [[ $linha =~ $RE_SH_DIRETIVA ]] && return 1
    codigo="$(sem_strings "$linha")"
    [[ $codigo =~ $RE_SH_COMENTARIO ]]
    return
  fi
  [[ $linha == *'/'* ]] || return 1
  codigo="$(sem_strings "$linha")"
  [[ $codigo == *'/*'* ]] && return 0
  [[ $codigo == *'//'* ]] || return 1
  [[ ${codigo#*//} =~ $RE_DIRETIVA ]] && return 1
  return 0
}

ja_existia() {
  local t
  t="$(aparado "$1")"
  [ -n "$t" ] || return 1
  if [ -z "$INDICE" ]; then
    INDICE="$(mktemp)"
    git grep -h -I -e . "$REF_BASE" -- '*.dart' '*.rs' '*.sh' 2>/dev/null \
      | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | sort -u > "$INDICE"
  fi
  grep -qxF -- "$t" "$INDICE"
}

novas() {
  if [ "$MODO" = "base" ]; then
    linhas_novas "$EXTS"
    return
  fi
  git diff --cached -U0 --diff-filter=ACMR | awk -v ext="$EXTS" '
    /^\+\+\+ / { arq=substr($0,7); if (arq=="/dev/null") arq=""; next }
    /^@@ / { split($3,h,","); ln=h[1]+0; if(ln<0) ln=-ln; next }
    /^\+/ && arq!="" {
      if (arq ~ ("\\.(" ext ")$")) printf "%s:%d:%s\n", arq, ln, substr($0,2)
      ln++
    }
  '
}

if [ "$MODO" = "base" ]; then
  BASE="$(_base)"
  if [ -z "$BASE" ] || ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    echo "❌ base da comparação indisponível: '${BASE:-origin/main}' não resolve aqui."
    echo "   O portão não trata o repositório inteiro como código novo."
    echo "   Aponte a base: BASE_REF=<commit> bash scripts/checks/check_no_comments.sh"
    exit 1
  fi
  REF_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"
  echo "🔍 Verificando comentários nas linhas novas desde ${REF_BASE:0:12} ($EXTS)..."
else
  REF_BASE="HEAD"
  echo "🔍 Verificando comentários nas linhas novas do índice ($EXTS)..."
fi

V=0
while IFS= read -r m; do
  [ -n "$m" ] || continue
  f="${m%%:*}"; r="${m#*:}"; n="${r%%:*}"; c="${r#*:}"
  case "$f" in
    cargokit/*|*/cargokit/*|*.g.dart|*.freezed.dart|*.mocks.dart|*frb_generated*) continue ;;
  esac
  comentario "${f##*.}" "$c" || continue
  ja_existia "$c" && continue
  echo "❌ $f:$n - $(aparado "$c")"
  V=$((V + 1))
done < <(novas)

if [ "$V" -gt 0 ]; then
  echo ""
  echo "🚨 $V comentário(s) em código novo"
  echo "💡 Dica: o porquê vai para o corpo do commit ou do PR."
  echo "   Passam só diretivas: // ignore:, // ignore_for_file:, // coverage:, // dart format,"
  echo "   // @dart, // SAFETY:, #! e # shellcheck."
  exit 1
fi
echo "✅ Nenhum comentário em código novo"
