#!/bin/bash
# Gate de conformidade para rodar o app desktop.
#
# O mobile rodava o mesmo portão antes de subir o app, mais o flavor da marca;
# o desktop não tem flavor — o que vale é o mesmo gate, nas duas linguagens:
# a suite Flutter (convenção do app) e a suite Rust (core + bridge).
#
# Uso: ./run_app.sh            roda o gate e sobe o app no macOS
#      ./run_app.sh --check    só o gate, sem subir o app
#      ./run_app.sh --dart-define=FOO=bar   argumentos vão para o flutter run

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_gate() {
  bash "$SCRIPT_DIR/scripts/checks/flutter/run_all.sh" || return 1
  # Em projeto recém-gerado ainda não há git: o escopo do diff não existe, e
  # a varredura inteira é o gate honesto do dia zero.
  ESCOPO_TUDO="${ESCOPO_TUDO:-1}" bash "$SCRIPT_DIR/scripts/checks/rust/run_all.sh" || return 1
}

if ! run_gate; then
  echo ""
  echo "❌ Gate de arquitetura reprovou — corrija antes de rodar."
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  echo ""
  echo "✅ Gate verde."
  exit 0
fi

exec flutter run -d macos "$@"
