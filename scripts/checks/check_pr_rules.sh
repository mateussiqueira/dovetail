#!/bin/bash

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
ERRORS=0; WARNINGS=0
DIFF_MODE="staged"
RANGE=(--cached)
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PR_SIZE_IGNORE_FILE="${PR_SIZE_IGNORE_FILE:-$RAIZ/.pr_size_ignore.list}"
MEASURED=""; IGNORED=""

resolve_base() {
  local base="" candidate merge_base
  if [ -n "${PR_BASE:-}" ]; then
    base="$PR_BASE"
  elif [ -n "${GITHUB_BASE_REF:-}" ]; then
    base="origin/$GITHUB_BASE_REF"
  else
    for candidate in origin/main origin/master main master; do
      git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1 && { base="$candidate"; break; }
    done
  fi
  [ -z "$base" ] || git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 \
    || { echo "❌ a base '$base' não resolve; confira PR_BASE ou GITHUB_BASE_REF."; exit 1; }
  merge_base="$(git merge-base "$base" HEAD 2>/dev/null)" || return 0
  if [ -n "$merge_base" ] && [ "$(git rev-list --count "$merge_base..HEAD")" -gt 0 ]; then
    DIFF_MODE="range"
    RANGE=("$merge_base..HEAD")
  fi
}

is_size_ignored() {
  local pattern
  [ -f "$PR_SIZE_IGNORE_FILE" ] || return 1
  while IFS= read -r pattern; do
    case "$pattern" in ''|'#'*) continue ;; esac
    case "$1" in *"$pattern"*) return 0 ;; esac
  done < "$PR_SIZE_IGNORE_FILE"
  return 1
}

measure() {
  local added removed file
  while IFS=$'\t' read -r added removed file; do
    [ -n "$file" ] || continue
    if is_size_ignored "$file"; then
      IGNORED="$IGNORED$file"$'\n'
    else
      MEASURED="$MEASURED$added"$'\t'"$removed"$'\t'"$file"$'\n'
    fi
  done < <(git diff --numstat "${RANGE[@]}" 2>/dev/null)
}

print_check() {
  case "$1" in
    OK) echo -e "  ${GREEN}✅${NC} $2" ;;
    WARN) echo -e "  ${YELLOW}⚠️${NC}  $2"; WARNINGS=$((WARNINGS + 1)) ;;
    *) echo -e "  ${RED}❌${NC} $2"; ERRORS=$((ERRORS + 1)) ;;
  esac
}

size_error() {
  if [ -n "${PR_SIZE_EXEMPT:-}" ]; then
    print_check WARN "$1"
    echo "        ↳ isento por PR_SIZE_EXEMPT: ${PR_SIZE_EXEMPT}"
  else
    print_check ERROR "$1"
  fi
}

check_size() {
  local total count ignored
  total="$(printf '%s' "$MEASURED" | awk -F'\t' '{s += $1 + $2} END {print s + 0}')"
  count="$(printf '%s' "$MEASURED" | awk 'NF {n++} END {print n + 0}')"
  ignored="$(printf '%s' "$IGNORED" | awk 'NF {n++} END {print n + 0}')"
  echo -e "${BLUE}📏 Verificando tamanho do PR...${NC}"
  if [ "$ignored" -gt 0 ]; then
    print_check OK "$ignored arquivo(s) gerado(s) fora da medição:"
    printf '%s' "$IGNORED" | sed 's/^/        - /'
  fi
  if [ "$total" -le 25 ]; then print_check OK "Tamanho ideal: $total linhas (≤25)"
  elif [ "$total" -le 100 ]; then print_check OK "Tamanho bom: $total linhas (≤100)"
  elif [ "$total" -le 250 ]; then print_check WARN "PR grande: $total linhas (recomendado ≤100, máx 250)"
  else size_error "PR muito grande: $total linhas (máx 250). Divida em PRs menores."
  fi
  echo -e "${BLUE}📁 Verificando número de arquivos...${NC}"
  if [ "$count" -le 2 ]; then print_check OK "PR focado: $count arquivos (≤2)"
  elif [ "$count" -le 5 ]; then print_check OK "PR aceitável: $count arquivos (≤5)"
  elif [ "$count" -le 7 ]; then print_check WARN "PR com muitos arquivos: $count (recomendado ≤5, máx 7)"
  else size_error "PR com $count arquivos (máx 7). Divida em PRs menores."
  fi
}

check_commits() {
  local types='feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert'
  local hash msg invalid=0
  echo -e "${BLUE}📝 Verificando conventional commits...${NC}"
  if [ "$DIFF_MODE" != "range" ]; then
    print_check WARN "Nenhum commit à frente da base para verificar"
    return
  fi
  while IFS= read -r hash; do
    msg="$(git log -1 --format='%s' "$hash")"
    if ! grep -qE "^($types)(\(.+\))?!?: .+" <<<"$msg"; then
      [ "$invalid" -eq 0 ] && print_check ERROR "Commits não seguem Conventional Commits:"
      echo "        - ${hash:0:7}: $msg"
      invalid=$((invalid + 1))
    fi
    [ "${#msg}" -le 72 ] || print_check WARN "Mensagem longa (${#msg} chars, máx 72): ${hash:0:7}"
  done < <(git rev-list "${RANGE[0]}")
  [ "$invalid" -gt 0 ] || print_check OK "Commits seguem Conventional Commits"
  [ "$invalid" -le 1 ] || ERRORS=$((ERRORS + invalid - 1))
}

check_branch_name() {
  local branch="${PR_BRANCH:-$(git branch --show-current 2>/dev/null)}"
  echo -e "${BLUE}🌿 Verificando nome da branch...${NC}"
  if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    print_check WARN "Sem branch de feature (main ou HEAD destacado); o push informa PR_BRANCH."
  elif grep -qE '^(feat|fix|docs|style|refactor|test|chore|perf|ci|build)/.+$' <<<"$branch"; then
    print_check OK "Branch naming correto: $branch"
  else
    print_check ERROR "Branch naming incorreto: $branch (use feat/nome, fix/nome, etc)"
  fi
}

resolve_base
measure
echo ""
echo -e "${BLUE}📋 PR RULES — Validação de Pull Requests${NC}"
if [ "$DIFF_MODE" = "range" ]; then
  echo "  Escopo: $(git rev-list --count "${RANGE[0]}") commit(s) desde ${RANGE[0]:0:12}"
else
  echo "  Escopo: índice (staged) — sem commits à frente da base"
fi
check_size
check_commits
check_branch_name
echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}🚫 BLOQUEADO — $ERRORS erro(s) encontrado(s). Corrija antes de abrir o PR.${NC}"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  AVISO — $WARNINGS aviso(s) encontrado(s); não bloqueia.${NC}"
else
  echo -e "${GREEN}✅ APROVADO — PR dentro das boas práticas!${NC}"
fi
