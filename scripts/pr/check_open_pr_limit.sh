#!/bin/bash
set -uo pipefail

MAX="${PR_OPEN_LIMIT:-3}"
GH="${PR_LIMIT_GH:-gh}"
REPO_FLAG=()
PR_LIMIT_REMOTE_URL="${PR_LIMIT_REMOTE_URL:-$(git remote get-url origin 2>/dev/null)}"

if [ -n "${PR_LIMIT_REMOTE_URL:-}" ]; then
  slug=""
  case "$PR_LIMIT_REMOTE_URL" in
    *github.com[:/]*/*)
      slug="$(printf '%s' "$PR_LIMIT_REMOTE_URL" | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##')"
      ;;
  esac
  case "$slug" in
    ?*/?*) REPO_FLAG=(-R "$slug") ;;
    *)
      echo "❌ não reconheço o repositório do GitHub no remoto: $PR_LIMIT_REMOTE_URL"
      exit 1
      ;;
  esac
fi

open_prs() {
  "$GH" pr list "${REPO_FLAG[@]+"${REPO_FLAG[@]}"}" --state open --limit 500 \
    --json number,headRefName --jq '.[] | "\(.number) \(.headRefName)"'
}

if ! listing="$(open_prs 2>/dev/null)"; then
  echo "❌ não consegui contar os PRs abertos (gh ausente, sem login ou sem rede)."
  echo "   O teto de $MAX PRs abertos não pode ser conferido, então o push para aqui."
  exit 1
fi

total="$(printf '%s\n' "$listing" | grep -c '^[0-9]')"

if [ "$#" -eq 0 ]; then
  echo "✅ nenhuma branch a publicar (tag ou remoção) — $total PR(s) aberto(s)."
  exit 0
fi

blocked=0
for branch in "$@"; do
  if [ "$branch" = "main" ]; then
    echo "⏭️  $branch não abre PR."
    continue
  fi
  if printf '%s\n' "$listing" | awk '{print $2}' | grep -qx -- "$branch"; then
    echo "✅ $branch já tem PR aberto — atualizar PR existente é sempre permitido."
    continue
  fi
  if [ "$total" -ge "$MAX" ]; then
    echo "❌ $branch seria o PR nº $((total + 1)); o teto é $MAX abertos por repositório."
    blocked=1
  else
    echo "✅ $branch cabe no teto: $total de $MAX PR(s) aberto(s)."
  fi
done

if [ "$blocked" -ne 0 ]; then
  echo ""
  echo "   PRs abertos agora:"
  printf '%s\n' "$listing" | sed 's/^/     #/'
  echo "   Mescle ou feche um deles antes de publicar branch nova. Commite e espere."
  exit 1
fi
exit 0
