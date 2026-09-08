#!/usr/bin/env bash
# Regrava tool/skip_baseline.json a partir de uma árvore FRIA, como docs/ci.md
# descreve: os arquivos rastreados (o índice do git — novos arquivos precisam
# de `git add` antes) copiados para um irmão deste repositório, sem .dart_tool,
# sem build/ e sem target/; `verify test` lá; o run file volta; `bless --force`
# (o commit do irmão é outro, por isso o force).
#
# Irmão, e não qualquer lugar: os `../../../` de product/ precisam alcançar
# example-rust e example-design-system ao lado deste repositório.
#
# Por que frio: o baseline guarda `declared` por suíte e cada skip com motivo.
# Gravado nesta máquina quente, ele descreve o que ESTA máquina pula (2 ou 3),
# e um runner limpo — sem .app construído, sem fatias Apple, sem a crate do
# atalho — pula 44. Frio fica verde nos dois lados: aqui, um skip que deixa de
# acontecer é `skip gone`, notícia e não problema.
#
# Uso: tool/rebless_cold.sh            (irmão em ../dovetail-frio)
#      DOVETAIL_COLD_DIR=/x tool/rebless_cold.sh
set -euo pipefail

warm="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cold="${DOVETAIL_COLD_DIR:-$warm/../dovetail-frio}"
cold="$(cd "$(dirname "$cold")" && pwd)/$(basename "$cold")"

if [ "$cold" = "$warm" ]; then
  echo "refusing: the cold dir is this repository" >&2
  exit 1
fi

if [ -e "$cold" ]; then
  # Só apaga o que é uma cópia fria anterior: tem o portão e um .git próprio.
  if [ -f "$cold/tool/verify.dart" ] && [ -d "$cold/.git" ]; then
    rm -rf "$cold"
  else
    echo "refusing: $cold exists and is not a previous cold copy" >&2
    echo "  (expected tool/verify.dart and a .git of its own)" >&2
    exit 1
  fi
fi
mkdir -p "$cold"

cd "$warm"
untracked="$(git status --porcelain --untracked-files=all | grep '^??' | grep -v '\.omo/' || true)"
if [ -n "$untracked" ]; then
  echo "note: untracked files will NOT travel to the cold tree (git add them first if they count):" >&2
  while IFS= read -r line; do echo "  $line" >&2; done <<<"$untracked"
fi

git ls-files -z | rsync -a --files-from=- --from0 ./ "$cold"/
cd "$cold"
git init -q
git add -A
git -c user.name=cold -c user.email=cold@local commit -qm cold
echo "cold tree  $cold ($(git rev-parse --short HEAD))"

set +e
env -u DOVETAIL_WEAVE_PATH dart tool/verify.dart test
code=$?
set -e
if [ "$code" -ne 0 ]; then
  echo "the cold run was not green; not blessing (fix the tree, then run this again)" >&2
  exit "$code"
fi

mkdir -p "$warm/dist"
cp "$cold/dist/verify-run.json" "$warm/dist/verify-run.json"
cd "$warm"
dart tool/verify.dart bless --force

echo
echo "baseline totals:"
python3 - <<'EOF'
import json
b = json.load(open('tool/skip_baseline.json'))
declared = skips = 0
for pkg, v in sorted(b['packages'].items()):
    d = sum(s['declared'] for s in v['suites'].values())
    k = sum(len(s['skips']) for s in v['suites'].values())
    declared += d
    skips += k
    print(f"  {pkg:40s} {d:5d} declared  {k:3d} skipped")
print(f"  {'TOTAL':40s} {declared:5d} declared  {skips:3d} skipped")
print()
print(f"README headline should read: {declared} testes Dart declarados, {skips} pulados")
EOF
echo "read the diff before committing it:  git diff tool/skip_baseline.json"
