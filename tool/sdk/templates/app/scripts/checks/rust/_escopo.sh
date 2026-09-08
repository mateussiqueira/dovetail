#!/bin/bash
# Fonte comum de "quais arquivos checar" no Rust do projeto.
#
# Por padrão só o que EU alterei desde a base — o legado do repositório não
# reprova nada. Com ESCOPO_TUDO=1, varre tudo (medir dívida, não barrar push).
#
# Adaptado do example-rust: lá o escopo era crates/, app-tauri/ e
# frontend/src; aqui o Rust mora em core/ (o núcleo) e core_bridge/ (o
# repasse FFI). Com ESCOPO_TUDO=1 a raiz é o cwd, então o gate roda também
# em projeto recém-gerado, antes do primeiro commit.
#
# Onde o Rust mora. O default e o layout do scaffold; o dovetail aponta para
# as crates dele. Uma fonte, dois consumidores — copiar este arquivo criaria
# duas verdades que divergem no primeiro conserto.
RUST_DIRS="${RUST_DIRS:-core core_bridge}"

# Uso: source _escopo.sh; arquivos_alvo "rs"

BASE_REF="${BASE_REF:-}"

if [ "${ESCOPO_TUDO:-0}" = "1" ]; then
  RAIZ="$(pwd)"
else
  # Ancora na raiz do repositório. Sem isto, rodar de outro diretório faz o
  # find não achar nada e o check APROVAR em silêncio — falso negativo é pior
  # que check nenhum.
  RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    # Sem git nao ha diff, e sem diff nao ha escopo parcial: o que sobra e a
    # varredura inteira, que e o gate honesto do dia zero. Era um `exit 1` — e
    # `make quality` num projeto recem-gerado, antes do primeiro `git init`,
    # morria aqui. O run_app.sh ja tomou esta decisao (ESCOPO_TUDO=1 por
    # padrao); a regra fica num lugar so, que e este.
    echo "ℹ️  fora de um repositório git — sem diff, o escopo é tudo" >&2
    ESCOPO_TUDO=1
    RAIZ="$(pwd)"
  }

fi
cd "$RAIZ" || exit 1

_base() {
  if [ -n "$BASE_REF" ]; then echo "$BASE_REF"; return; fi
  for c in origin/develop develop origin/main main; do
    if git rev-parse --verify --quiet "$c" >/dev/null 2>&1; then
      git merge-base "$c" HEAD 2>/dev/null && return
    fi
  done
  echo ""
}

# Fonte única da lista de arquivos .rs do projeto, para o modo completo:
# código gerado (frb_generated) e artefatos (target/) saem — quem mede a
# dívida mede o que alguém escreve à mão.
_rs_completo() {
  # shellcheck disable=SC2086  # RUST_DIRS e uma lista de pastas, de proposito
  find $RUST_DIRS -type f -name "*.rs" 2>/dev/null \
    | grep -vE 'frb_generated|/target/' || true
}

arquivos_alvo() {
  local ext="$1"
  if [ "${ESCOPO_TUDO:-0}" = "1" ]; then
    # shellcheck disable=SC2086
    find $RUST_DIRS -type f 2>/dev/null | grep -E "\.($ext)$" | grep -vE 'frb_generated|/target/' || true
    return
  fi
  local base; base="$(_base)"
  if [ -z "$base" ]; then
    # shellcheck disable=SC2086
    find $RUST_DIRS -type f 2>/dev/null | grep -E "\.($ext)$" | grep -vE 'frb_generated|/target/' || true
    return
  fi
  { git diff --name-only --diff-filter=ACMR "$base"...HEAD 2>/dev/null
    git diff --name-only --diff-filter=ACMR 2>/dev/null
    git diff --name-only --diff-filter=ACMR --cached 2>/dev/null
  } | sort -u | grep -E "\.($ext)$" | while IFS= read -r f; do
    [ -f "$f" ] && echo "$f"
  done
}

# Arquivos NOVOS nesta task. Regra de arquivo inteiro (tamanho, formatação) só
# vale para eles: tocar uma linha num arquivo legado não deve arrastar a dívida
# dele para dentro da minha task.
arquivos_novos() {
  local ext="$1" base
  if [ "${ESCOPO_TUDO:-0}" = "1" ]; then
    find core core_bridge -type f 2>/dev/null | grep -E "\\.($ext)$" | grep -vE 'frb_generated|/target/' || true
    return
  fi
  base="$(_base)"
  [ -z "$base" ] && return
  { git diff --name-only --diff-filter=A "$base"...HEAD 2>/dev/null
    git diff --name-only --diff-filter=A 2>/dev/null
    git diff --name-only --diff-filter=A --cached 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | grep -E "\\.($ext)$" | while IFS= read -r f; do
    [ -f "$f" ] && echo "$f"
  done
}

# Linhas ADICIONADAS nesta task, no formato  arquivo:linha:conteudo
#
# É a unidade certa para regra de conteúdo: "código que eu escrevo não leva
# comentário" não é o mesmo que "arquivo que eu toco não pode ter comentário".
# Tocar uma linha num arquivo legado não deve arrastar a dívida dele.
#
# No modo completo, sem diff, cada linha de cada arquivo escrito à mão conta.
linhas_novas() {
  local ext="$1" base
  if [ "${ESCOPO_TUDO:-0}" = "1" ]; then
    _rs_completo | while IFS= read -r f; do
      [ -f "$f" ] || continue
      awk -v arq="$f" '{print arq ":" NR ":" $0}' "$f"
    done | sort -u
    return
  fi
  base="$(_base)"
  local difs=()
  [ -n "$base" ] && difs+=("$base...HEAD")
  difs+=("" "--cached")
  { for d in "${difs[@]}"; do
      # shellcheck disable=SC2086
      git diff -U0 --diff-filter=ACMR $d 2>/dev/null
    done
    for f in $(git ls-files --others --exclude-standard 2>/dev/null); do
      [ -f "$f" ] && git diff -U0 --no-index /dev/null "$f" 2>/dev/null
    done
  } | awk -v ext="$ext" '
      /^\+\+\+ / { arq=substr($0,7); if (arq=="/dev/null") arq=""; next }
      /^@@ / { split($3,h,","); ln=h[1]+0; if(ln<0) ln=-ln; next }
      /^\+/ && arq!="" {
        if (arq ~ ("\\.(" ext ")$")) printf "%s:%d:%s\n", arq, ln, substr($0,2)
        ln++
      }
    ' | sort -u
}
