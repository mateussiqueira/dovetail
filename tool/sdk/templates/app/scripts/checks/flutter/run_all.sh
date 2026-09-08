#!/bin/bash
# Orquestrador dos checks de arquitetura Flutter.
# Uso: ./run_all.sh [dir lib] [dir test]

LIB_DIR="${1:-lib}"
TEST_DIR="${2:-test}"
FAILED=0

echo "══════════════════════════════════════════════════════"
echo "🧪 Checks Flutter — LIB=$LIB_DIR TEST=$TEST_DIR"
echo "══════════════════════════════════════════════════════"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_check() {
  local name="$1"; shift
  echo ""
  echo "────────────── $name ──────────────"
  if bash "$SCRIPT_DIR/$name" "$@"; then
    echo ""
    echo "✅ $name: OK"
  else
    echo ""
    echo "❌ $name: FALHOU"
    FAILED=1
  fi
}

run_check check_layer_boundaries.sh "$LIB_DIR"
run_check check_relative_imports.sh "$LIB_DIR"
run_check check_file_size.sh 200 "$LIB_DIR" "$TEST_DIR"
run_check check_one_class_per_file.sh "$LIB_DIR"
run_check check_naming_conventions.sh "$LIB_DIR"
run_check check_todo_comments.sh "$LIB_DIR"
run_check check_no_comments.sh "$LIB_DIR"
run_check check_navigator_usage.sh "$LIB_DIR"
run_check check_hardcoded.sh "$LIB_DIR"
run_check check_no_private_widgets.sh "$LIB_DIR"
run_check check_widgets_folder_structure.sh "$LIB_DIR"
run_check check_widgets_one_class_per_file.sh "$LIB_DIR"
run_check check_page_presenter.sh "$LIB_DIR"
run_check check_abstract_interfaces.sh "$LIB_DIR"
run_check check_widget_components.sh "$LIB_DIR"
run_check check_widget_comments.sh "$LIB_DIR"
run_check check_shared_widgets_usage.sh "$LIB_DIR"
run_check check_solid_dip.sh "$LIB_DIR"
run_check check_no_hardcoded_logic.sh "$LIB_DIR"
run_check check_dependency_injection.sh "$LIB_DIR"
if [ -d .git ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
  run_check check_pr_rules.sh
else
  echo ""
  echo "ℹ️ check_pr_rules: fora de um repo git com commits — pulado"
fi

echo ""
echo "══════════════════════════════════════════════════════"
if [ "$FAILED" -eq 0 ]; then
  echo "✅ Todos os checks Flutter passaram"
  exit 0
else
  echo "❌ Alguns checks Flutter falharam"
  exit 1
fi
