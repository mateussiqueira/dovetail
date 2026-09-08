#!/bin/bash
# =============================================================================
# Coverage Gate — piso de cobertura de testes
# =============================================================================
# `flutter test --coverage` só registra no lcov os arquivos que algum teste
# importou, o que inflava o total (96% medindo 31 de 134 arquivos). Este script
# gera um barril temporário importando toda a lib antes de medir, então
# arquivos sem teste aparecem como 0% e entram na conta.
#
# Uso:  bash scripts/checks/flutter/check_coverage.sh
#       MIN_COVERAGE=40 bash scripts/checks/flutter/check_coverage.sh
#
# MIN_COVERAGE é uma catraca: só sobe. Ao elevar a cobertura, suba o piso
# junto, para que nunca seja possível regredir.
# =============================================================================

set -euo pipefail

MIN_COVERAGE=${MIN_COVERAGE:-25}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COVERAGE_FILE="$PROJECT_DIR/coverage/lcov.info"
BARREL="$PROJECT_DIR/test/coverage_barrel_test.dart"
TEST_LOG="$(mktemp -t example-app_coverage)"

cd "$PROJECT_DIR"

cleanup() { rm -f "$BARREL" "$TEST_LOG"; }
trap cleanup EXIT

echo "🔍 Coverage Gate — piso de ${MIN_COVERAGE}%"
echo "======================================"

resolved_package_config() {
  local dir="$PROJECT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.dart_tool/package_config.json" ]; then
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if ! resolved_package_config; then
  echo "❌ Dependências não resolvidas — rode 'flutter pub get' antes de medir cobertura."
  exit 1
fi

echo "▶ Gerando barril de cobertura..."
python3 - "$BARREL" <<'PY'
import pathlib, sys
barrel = pathlib.Path(sys.argv[1])
files = sorted(p for p in pathlib.Path('lib').rglob('*.dart'))
lines = ['// GERADO AUTOMATICAMENTE por check_coverage.sh — não versionar.']
lines += [f"import 'package:{{name}}/{p.relative_to('lib')}';" for p in files]
lines += ['', 'void main() {}', '']
barrel.write_text('\n'.join(lines))
print(f'   {len(files)} arquivos de lib/ incluídos na medição')
PY

echo "▶ Rodando testes com cobertura..."
flutter test --coverage --no-pub > "$TEST_LOG" 2>&1 || {
  if grep -qE 'version solving failed|Failed to update packages|pub (get|upgrade) failed' "$TEST_LOG"; then
    echo "❌ A resolução de dependências falhou — rode 'flutter pub get' antes de medir cobertura."
  else
    # Este e O passo de testes do pre-push, nao um passo "antes" dele. E a
    # suite aqui inclui um barril gerado que importa todo arquivo de lib/ —
    # um arquivo que nao compila sozinho falha aqui e passaria num
    # `flutter test` puro. O log abaixo diz qual.
    echo "❌ A suíte de testes falhou. Se só o coverage_barrel_test falhou, um arquivo de lib/ não compila isolado."
  fi
  echo "── últimas linhas de 'flutter test --coverage --no-pub' ──"
  tail -n 20 "$TEST_LOG"
  exit 1
}

if [ ! -f "$COVERAGE_FILE" ]; then
  echo "❌ lcov não gerado em $COVERAGE_FILE"
  exit 1
fi

MIN_COVERAGE="$MIN_COVERAGE" python3 - "$COVERAGE_FILE" <<'PY'
import collections, os, re, sys

minimum = float(os.environ['MIN_COVERAGE'])
content = open(sys.argv[1]).read()

total = hit = 0
per_file = []
for block in content.split('end_of_record'):
    match = re.search(r'SF:(.*)', block)
    if not match:
        continue
    das = re.findall(r'DA:(\d+),(\d+)', block)
    if not das:
        continue
    covered = sum(1 for _, count in das if int(count) > 0)
    total += len(das)
    hit += covered
    per_file.append((covered / len(das) * 100,
                     match.group(1).replace('lib/', ''),
                     covered, len(das)))

if total == 0:
    print('❌ Nenhuma linha medida — lcov vazio.')
    sys.exit(1)

by_layer = collections.defaultdict(lambda: [0, 0])
for _, name, covered, count in per_file:
    layer = name.split('/')[0] if '/' in name else 'raiz'
    by_layer[layer][0] += covered
    by_layer[layer][1] += count

print()
print('Cobertura por camada:')
for layer, (covered, count) in sorted(by_layer.items(),
                                      key=lambda item: item[1][0] / item[1][1]):
    print(f'  {layer:<14} {covered:>4}/{count:<5} {covered / count * 100:>5.1f}%')

uncovered = [item for item in sorted(per_file) if item[0] == 0]
if uncovered:
    print()
    print(f'Sem nenhuma cobertura ({len(uncovered)} arquivos):')
    for _, name, _, count in uncovered[:12]:
        print(f'  {count:>4} linhas  {name}')
    if len(uncovered) > 12:
        print(f'  ... e outros {len(uncovered) - 12}')

overall = hit / total * 100
print()
print(f'TOTAL: {hit}/{total} linhas = {overall:.1f}% (piso {minimum:.0f}%)')

if overall + 1e-9 < minimum:
    print(f'❌ Cobertura {overall:.1f}% abaixo do piso de {minimum:.0f}%')
    sys.exit(1)

print(f'✅ Cobertura {overall:.1f}% atende o piso de {minimum:.0f}%')
PY
