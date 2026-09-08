#!/bin/bash

# ============================================================
# check_pr_rules.sh — Validação de Regras de Pull Request
# ============================================================
# Baseado em best practices:
# - PRs ideais: 25-100 linhas (máx 250)
# - Máximo 7 arquivos por PR
# - Arquivos gerados (.pr_size_ignore.list) ficam fora da medição de tamanho
# - PR_SIZE_EXEMPT="motivo" rebaixa erro de tamanho a aviso, para sweep mecânico
# - Conventional Commits obrigatório
# - Descrição do PR obrigatória
#
# Escopo medido (em ordem de precedência):
#   1. PR_BASE=<ref>            — explícito
#   2. GITHUB_BASE_REF          — quando roda no GitHub Actions
#   3. merge-base com origin/main (ou origin/master) — uso normal local
#   4. índice (git diff --cached) — quando não há commits à frente da base
# ============================================================

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

# ============================================================
# RESOLUÇÃO DO ESCOPO A MEDIR
# ============================================================
# Antes este script media apenas `git diff --cached`, o que zerava todas as
# métricas fora de um `git commit` (inclusive em CI e no pre-push).
BASE_REF=""
DIFF_MODE="staged"

resolve_base() {
  if [ -n "${PR_BASE:-}" ]; then
    BASE_REF="$PR_BASE"
  elif [ -n "${GITHUB_BASE_REF:-}" ]; then
    BASE_REF="origin/$GITHUB_BASE_REF"
  else
    for candidate in origin/main origin/master main master; do
      if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
        BASE_REF="$candidate"
        break
      fi
    done
  fi

  if [ -z "$BASE_REF" ]; then
    return 0
  fi

  local merge_base
  merge_base=$(git merge-base "$BASE_REF" HEAD 2>/dev/null) || return 0
  if [ -z "$merge_base" ]; then
    return 0
  fi

  # Só usa o range se houver commits à frente da base; caso contrário o
  # trabalho ainda está no índice e o modo staged é o correto.
  if [ "$(git rev-list --count "$merge_base..HEAD" 2>/dev/null || echo 0)" -gt 0 ]; then
    BASE_REF="$merge_base"
    DIFF_MODE="range"
  fi
}

resolve_base

changed_files() {
  if [ "$DIFF_MODE" = "range" ]; then
    git diff --name-only "$BASE_REF..HEAD" 2>/dev/null
  else
    git diff --cached --name-only 2>/dev/null
  fi
}

changed_numstat() {
  if [ "$DIFF_MODE" = "range" ]; then
    git diff --numstat "$BASE_REF..HEAD" 2>/dev/null
  else
    git diff --cached --numstat 2>/dev/null
  fi
}

range_commits() {
  if [ "$DIFF_MODE" = "range" ]; then
    git rev-list "$BASE_REF..HEAD" 2>/dev/null
  fi
}

# ============================================================
# ARQUIVOS FORA DA MEDIÇÃO DE TAMANHO
# ============================================================
# Arquivo gerado (lockfile, codegen) não tem como ser dividido em PR menor:
# contá-lo só faz a régua reprovar mudança legítima. Os padrões vivem em
# .pr_size_ignore.list, mesmo formato do .file_size_ignore.list usado pelo
# check_file_size.sh (substring match, # é comentário).
#
# A exclusão vale SÓ para os checks de tamanho. Arquivo gerado continua
# passando por sensíveis, config, conventional commits e afins.
PR_SIZE_IGNORE_FILE="${PR_SIZE_IGNORE_FILE:-.pr_size_ignore.list}"

is_size_ignored() {
  local file="$1"
  [ -f "$PR_SIZE_IGNORE_FILE" ] || return 1
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    case "$pattern" in \#*) continue ;; esac
    if echo "$file" | grep -qF "$pattern"; then
      return 0
    fi
  done < "$PR_SIZE_IGNORE_FILE"
  return 1
}

measured_files() {
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    is_size_ignored "$file" || echo "$file"
  done < <(changed_files)
}

measured_numstat() {
  while IFS=$'\t' read -r added removed file; do
    [ -z "$file" ] && continue
    is_size_ignored "$file" || printf '%s\t%s\t%s\n' "$added" "$removed" "$file"
  done < <(changed_numstat)
}

ignored_files() {
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    is_size_ignored "$file" && echo "$file"
  done < <(changed_files)
}

# PR_SIZE_EXEMPT="motivo" rebaixa os erros de tamanho a aviso. Existe para o
# sweep mecânico que não tem como ser dividido (dart format no repo inteiro,
# migração de path em massa). Exige motivo — e ele aparece no relatório.
size_verdict() {
  if [ -n "${PR_SIZE_EXEMPT:-}" ]; then
    echo "WARN"
  else
    echo "ERROR"
  fi
}

report_size_exemption() {
  if [ -n "${PR_SIZE_EXEMPT:-}" ]; then
    echo -e "        ↳ isento por PR_SIZE_EXEMPT: ${PR_SIZE_EXEMPT}"
  fi
}

print_header() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  📋 PR RULES — Validação de Pull Requests                      ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
  if [ "$DIFF_MODE" = "range" ]; then
    echo -e "  Escopo: $(git rev-list --count "$BASE_REF..HEAD") commit(s) desde ${BASE_REF:0:12}"
  else
    echo -e "  Escopo: índice (staged) — sem commits à frente da base"
  fi
  echo ""
}

print_check() {
  local status=$1
  local message=$2
  if [ "$status" = "OK" ]; then
    echo -e "  ${GREEN}✅${NC} $message"
  elif [ "$status" = "WARN" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $message"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "  ${RED}❌${NC} $message"
    ERRORS=$((ERRORS + 1))
  fi
}

# ============================================================
# CHECK 1: Tamanho do PR (linhas alteradas)
# ============================================================
check_pr_size() {
  echo -e "${BLUE}📏 Verificando tamanho do PR...${NC}"
  
  local added=$(measured_numstat | awk '{s+=$1} END {print s+0}')
  local removed=$(measured_numstat | awk '{s+=$2} END {print s+0}')
  local total=$((added + removed))
  
  local ignored_count=$(ignored_files | awk 'NF{n++} END {print n+0}')
  if [ "$ignored_count" -gt 0 ]; then
    print_check "OK" "$ignored_count arquivo(s) gerado(s) fora da medição:"
    ignored_files | sed 's/^/        - /'
  fi
  
  if [ "$total" -le 25 ]; then
    print_check "OK" "Tamanho ideal: $total linhas (≤25)"
  elif [ "$total" -le 100 ]; then
    print_check "OK" "Tamanho bom: $total linhas (≤100)"
  elif [ "$total" -le 250 ]; then
    print_check "WARN" "PR grande: $total linhas (recomendado ≤100, máx 250)"
  else
    print_check "$(size_verdict)" "PR muito grande: $total linhas (máx 250). Divida em PRs menores."
    report_size_exemption
  fi
}

# ============================================================
# CHECK 2: Número de arquivos
# ============================================================
check_file_count() {
  echo -e "${BLUE}📁 Verificando número de arquivos...${NC}"
  
  local file_count=$(measured_files | awk 'NF{n++} END {print n+0}')
  
  if [ "$file_count" -le 2 ]; then
    print_check "OK" "PR focado: $file_count arquivos (≤2)"
  elif [ "$file_count" -le 5 ]; then
    print_check "OK" "PR aceitável: $file_count arquivos (≤5)"
  elif [ "$file_count" -le 7 ]; then
    print_check "WARN" "PR com muitos arquivos: $file_count (recomendado ≤5, máx 7)"
  else
    print_check "$(size_verdict)" "PR com $file_count arquivos (máx 7). Divida em PRs menores."
    report_size_exemption
  fi
}

# ============================================================
# CHECK 3: Tamanho máximo por arquivo
# ============================================================
check_file_sizes() {
  echo -e "${BLUE}📄 Verificando tamanho dos arquivos...${NC}"
  
  local large_files=0
  local max_lines=250
  
  while IFS= read -r file; do
    if [ -f "$file" ]; then
      local lines=$(wc -l < "$file" | tr -d ' ')
      if [ "$lines" -gt "$max_lines" ]; then
        if [ "$large_files" -eq 0 ]; then
          print_check "ERROR" "Arquivos muito grandes (>$max_lines linhas):"
        fi
        echo "        - $file ($lines linhas)"
        large_files=$((large_files + 1))
      fi
    fi
  done < <(measured_files)
  
  if [ "$large_files" -eq 0 ]; then
    print_check "OK" "Todos os arquivos dentro do limite (≤$max_lines linhas)"
  else
    ERRORS=$((ERRORS + large_files))
  fi
}

# ============================================================
# CHECK 4: Conventional Commits
# ============================================================
check_conventional_commits() {
  echo -e "${BLUE}📝 Verificando conventional commits...${NC}"
  
  local valid_types="feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert"
  local invalid_commits=0
  
  local commits
  commits=$(range_commits)

  if [ -z "$commits" ]; then
    print_check "WARN" "Nenhum commit à frente da base para verificar"
    return
  fi

  while IFS= read -r hash; do
    [ -z "$hash" ] && continue
    local msg=$(git log -1 --format='%s' "$hash" 2>/dev/null)

    if ! echo "$msg" | grep -qE "^($valid_types)(\(.+\))?!?: .+"; then
      if [ "$invalid_commits" -eq 0 ]; then
        print_check "ERROR" "Commits não seguem Conventional Commits:"
      fi
      echo "        - ${hash:0:7}: $msg"
      invalid_commits=$((invalid_commits + 1))
    fi
  done <<< "$commits"
  
  if [ "$invalid_commits" -eq 0 ]; then
    print_check "OK" "Commits seguem Conventional Commits"
  else
    ERRORS=$((ERRORS + invalid_commits))
  fi
}

# ============================================================
# CHECK 5: Mensagem de commit (primeira linha ≤50 chars)
# ============================================================
check_commit_message_length() {
  echo -e "${BLUE}📏 Verificando tamanho das mensagens de commit...${NC}"
  
  local long_messages=0
  local commits
  commits=$(range_commits)

  if [ -z "$commits" ]; then
    print_check "WARN" "Nenhum commit à frente da base para verificar"
    return
  fi
  
  while IFS= read -r hash; do
    local msg=$(git log -1 --format='%s' "$hash" 2>/dev/null)
    local msg_len=${#msg}
    
    if [ "$msg_len" -gt 72 ]; then
      if [ "$long_messages" -eq 0 ]; then
        print_check "WARN" "Commits com mensagem longa (>72 chars):"
      fi
      echo "        - ${hash:0:7}: $msg_len chars"
      long_messages=$((long_messages + 1))
    fi
  done <<< "$commits"
  
  if [ "$long_messages" -eq 0 ]; then
    print_check "OK" "Mensagens de commit dentro do limite (≤72 chars)"
  fi
}

# ============================================================
# CHECK 6: Tipos de arquivo misturados
# ============================================================
check_mixed_changes() {
  echo -e "${BLUE}🔀 Verificando tipos de alteração...${NC}"
  
  local has_dart=false
  local has_yaml=false
  local has_sh=false
  local has_test=false
  local has_other=false
  
  while IFS= read -r file; do
    case "$file" in
      *.dart) has_dart=true ;;
      *.yaml|*.yml) has_yaml=true ;;
      *.sh) has_sh=true ;;
      *test*) has_test=true ;;
      *) has_other=true ;;
    esac
  done < <(changed_files)
  
  local types=0
  $has_dart && types=$((types + 1))
  $has_yaml && types=$((types + 1))
  $has_sh && types=$((types + 1))
  $has_test && types=$((types + 1))
  $has_other && types=$((types + 1))
  
  if [ "$types" -le 2 ]; then
    print_check "OK" "PR focado: alterações em poucos tipos de arquivo"
  elif [ "$types" -le 3 ]; then
    print_check "WARN" "PR com $types tipos de arquivo. Considere separar."
  else
    print_check "ERROR" "PR muito disperso: $types tipos de arquivo diferentes"
  fi
}

# ============================================================
# CHECK 7: Arquivos de configuração alterados
# ============================================================
check_config_files() {
  echo -e "${BLUE}⚙️  Verificando alterações em configs...${NC}"
  
  local config_files=0
  local config_patterns="pubspec.yaml|analysis_options.yaml|melos.yaml|.gitignore|build.gradle|Info.plist"
  
  while IFS= read -r file; do
    if echo "$file" | grep -qE "($config_patterns)"; then
      config_files=$((config_files + 1))
    fi
  done < <(changed_files)
  
  if [ "$config_files" -eq 0 ]; then
    print_check "OK" "Nenhuma alteração em arquivos de configuração"
  elif [ "$config_files" -le 2 ]; then
    print_check "WARN" "$config_files arquivo(s) de config alterado(s). Verifique se é necessário."
  else
    print_check "ERROR" "$config_files arquivos de config alterados. PR deve ser revisado cuidadosamente."
  fi
}

# ============================================================
# CHECK 8: Arquivos sensíveis
# ============================================================
check_sensitive_files() {
  echo -e "${BLUE}🔒 Verificando arquivos sensíveis...${NC}"
  
  # Artefato de segredo: o próprio arquivo é o risco, qualquer extensão.
  local artifact_patterns="(^|/)\.env($|\.)|\.pem$|\.p12$|\.jks$|\.keystore$|key\.properties$"
  # Palavra no nome: indício fraco. Em código-fonte é vocabulário normal de
  # domínio — TokenStorage, PasswordField, SecretRotationService — então aqui
  # o padrão vale só para arquivo que NÃO é fonte.
  local name_word_patterns="secret|password|token|api.key|credentials"
  local source_extensions="\.(dart|kt|java|swift|m|h|gradle|sh|ya?ml|md|json)$"
  # Templates versionados de propósito: só nomes, nunca valores.
  local template_patterns="\.example$|\.sample$|\.template$|\.dist$"
  local sensitive_found=0

  is_sensitive_path() {
    local candidate="$1"
    if echo "$candidate" | grep -qiE "$artifact_patterns"; then
      return 0
    fi
    if echo "$candidate" | grep -qiE "$source_extensions"; then
      return 1
    fi
    echo "$candidate" | grep -qiE "$name_word_patterns"
  }

  while IFS= read -r file; do
    if echo "$file" | grep -qiE "$template_patterns"; then
      continue
    fi
    if is_sensitive_path "$file"; then
      if [ "$sensitive_found" -eq 0 ]; then
        print_check "ERROR" "Possíveis arquivos sensíveis detectados:"
      fi
      echo "        - $file"
      sensitive_found=$((sensitive_found + 1))
    fi
  done < <(changed_files)

  if [ "$sensitive_found" -eq 0 ]; then
    print_check "OK" "Nenhum arquivo sensível detectado"
  else
    # print_check "ERROR" já contou 1; soma apenas os arquivos extras.
    ERRORS=$((ERRORS + sensitive_found - 1))
  fi
}

# ============================================================
# CHECK 9: Branch naming
# ============================================================
check_branch_name() {
  echo -e "${BLUE}🌿 Verificando nome da branch...${NC}"
  
  local branch=$(git branch --show-current 2>/dev/null)
  
  if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    print_check "WARN" "Você está na branch principal. Crie uma branch de feature."
    return
  fi
  
  if echo "$branch" | grep -qE "^(feat|fix|docs|style|refactor|test|chore|perf|ci|build)/.+$"; then
    print_check "OK" "Branch naming correto: $branch"
  elif echo "$branch" | grep -qE "^(feature|bugfix|hotfix|release)/.+$"; then
    print_check "WARN" "Branch naming aceitável mas não padrão: $branch (use feat/, fix/, etc)"
  else
    print_check "ERROR" "Branch naming incorreto: $branch (use feat/nome, fix/nome, etc)"
  fi
}

# ============================================================
# CHECK 10: Código morto (imports não usados)
# ============================================================
check_dead_code() {
  echo -e "${BLUE}💀 Verificando possíveis imports não usados...${NC}"
  
  local unused_imports=0
  
  while IFS= read -r file; do
    if [[ "$file" == *.dart ]]; then
      if [ -f "$file" ]; then
        local imports=$(grep -c "^import " "$file" 2>/dev/null || echo 0)
        local lines=$(wc -l < "$file" 2>/dev/null || echo 0)
        
        # Se tem muitos imports para poucas linhas, pode ter código morto
        if [ "$imports" -gt 15 ] && [ "$lines" -lt 100 ]; then
          if [ "$unused_imports" -eq 0 ]; then
            print_check "WARN" "Possíveis imports não usados:"
          fi
          echo "        - $file ($imports imports em $lines linhas)"
          unused_imports=$((unused_imports + 1))
        fi
      fi
    fi
  done < <(changed_files)
  
  if [ "$unused_imports" -eq 0 ]; then
    print_check "OK" "Imports parece OK"
  fi
}

# ============================================================
# EXECUÇÃO PRINCIPAL
# ============================================================
print_header

check_pr_size
check_file_count
check_file_sizes
check_conventional_commits
check_commit_message_length
check_mixed_changes
check_config_files
check_sensitive_files
check_branch_name
check_dead_code

# ============================================================
# RESUMO
# ============================================================
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}║  🚫 BLOQUEADO — $ERRORS erro(s) encontrado(s)                    ║${NC}"
  echo -e "${RED}║  Corrija os erros antes de criar o PR.                         ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}║  ⚠️  AVISO — $WARNINGS aviso(s) encontrado(s)                      ║${NC}"
  echo -e "${YELLOW}║  Considere corrigir, mas não é bloqueante.                     ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
  exit 0
else
  echo -e "${GREEN}║  ✅ APROVADO — PR dentro das boas práticas!                    ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  exit 0
fi
