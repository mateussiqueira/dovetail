#!/bin/bash
# Orquestrador dos checks do Rust do projeto (core/ + core_bridge/rust/).
#
# Por padrão só olha o que EU alterei desde a base. Para varrer o projeto
# inteiro (medir dívida, não barrar push):  ESCOPO_TUDO=1 ./run_all.sh
#
# Adaptado do example-rust (que varria crates/, app-tauri/, frontend/src).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FALHOU=0

echo "══════════════════════════════════════════════════════"
if [ "${ESCOPO_TUDO:-0}" = "1" ]; then
  echo "🧪 Checks do Rust — PROJETO INTEIRO (core + core_bridge)"
else
  echo "🧪 Checks do Rust — apenas arquivos alterados"
fi
echo "══════════════════════════════════════════════════════"

source "$DIR/_escopo.sh"
ALVO="$(arquivos_alvo "rs")"
N=$(printf '%s\n' "$ALVO" | grep -c . || true)

if [ "$N" -eq 0 ]; then
  echo ""
  echo "Nenhum arquivo alterado nesta task — nada a checar."
  echo "(compare com: ESCOPO_TUDO=1 $0)"
  exit 0
fi

echo ""
echo "Arquivos desta task ($N):"
printf '%s\n' "$ALVO" | sed 's/^/   /'

# Checks que ESTE projeto nao adota, por decisao escrita e nao por
# esquecimento. O dovetail pula o de comentarios: la o comentario que registra
# o defeito que motivou o codigo e o valor do repositorio, e o porque mora no
# arquivo em vez do corpo do PR. Vazio em todo o resto.
PULAR="${PULAR_CHECKS:-}"

roda() {
  case " $PULAR " in
    *" $1 "*)
      echo ""
      echo "────────────── $1 ──────────────"
      echo "⏭️  $1: fora por decisão deste projeto (PULAR_CHECKS)"
      return
      ;;
  esac
  echo ""
  echo "────────────── $1 ──────────────"
  if bash "$DIR/$1"; then echo "✅ $1: OK"; else echo "❌ $1: FALHOU"; FALHOU=1; fi
}

roda check_no_comments.sh
roda check_todo_comments.sh
roda check_file_size.sh
roda check_english_identifiers.sh
roda check_hardcoded_urls.sh
roda check_concrete_api.sh

echo ""
echo "══════════════════════════════════════════════════════"
if [ "$FALHOU" -eq 0 ]; then echo "✅ Tudo conforme"; else echo "🚫 Há checks reprovando"; fi
echo "══════════════════════════════════════════════════════"
exit $FALHOU
