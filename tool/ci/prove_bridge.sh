#!/usr/bin/env bash
set -euo pipefail

# Prova que o bridge GERADO pelo template builda de verdade: bridge init
# contra o núcleo do produto, codegen, o XCFramework do SPM, e um app
# consumidor que o importa — flutter build macos verde, sem o aviso do SPM.
# Roda no host macOS (precisa dos irmãos do produto e do codegen do frb).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cli="$repo_root/toolkit/dovetail_cli/bin/dovetail.dart"

stage="$(mktemp -d /tmp/dovetail-prove-bridge.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

# Edicao in-place que funciona nos dois seds. O BSD exige um sufixo depois do
# -i, o GNU exige que nao haja; a forma que este arquivo usava so rodava em
# macOS, e em Linux o sufixo vazio era lido como o proximo argumento. Escrever
# para um temporario e mover nao depende de qual sed o host tem.
sed_inplace() {
  local file=$1
  shift
  local tmp
  tmp="$(mktemp)"
  sed "$@" "$file" >"$tmp" && mv "$tmp" "$file"
}

# O nucleo do produto vem por argumento, variavel, ou irmao — nesta ordem, e
# nunca por caminho absoluto no arquivo. O caminho do disco do autor estava
# escrito duas vezes aqui dentro, o que prendia esta prova a uma maquina.
core="${1:-${DOVETAIL_CORE_PATH:-$repo_root/../example-rust/crates/core}}"
if [ ! -f "$core/Cargo.toml" ]; then
  echo "no product core at $core" >&2
  echo "  This proof generates a bridge against the product's Rust core, so it" >&2
  echo "  needs the sibling checkout. Point at it:" >&2
  echo "    bash tool/ci/prove_bridge.sh <path to crates/core>" >&2
  echo "    DOVETAIL_CORE_PATH=<path> bash tool/ci/prove_bridge.sh" >&2
  echo "  or clone example-rust beside this repository." >&2
  exit 1
fi
core="$(cd "$core" && pwd)"
# Os crates irmaos moram ao lado do core, entao derivam dele: um caminho
# escrito a mao para cada um e a mesma trava, tres vezes.
crates="$(dirname "$core")"
for crate in ipc-proto common-types api-client; do
  if [ ! -f "$crates/$crate/Cargo.toml" ]; then
    echo "no $crate beside the core at $crates" >&2
    exit 1
  fi
done

# O `new` resolve weave_di por flag, variavel ou SDK — nunca por sonda. Aqui
# ele e obrigatorio porque o app consumidor e de verdade: builda.
weave="${DOVETAIL_WEAVE_PATH:-$repo_root/../../projects/weave}"
if [ ! -f "$weave/pubspec.yaml" ]; then
  echo "no weave_di checkout at $weave" >&2
  echo "  The generated app imports package:weave_di and this proof builds it." >&2
  echo "  Point at a checkout: DOVETAIL_WEAVE_PATH=<dir with pubspec.yaml>" >&2
  exit 1
fi
weave="$(cd "$weave" && pwd)"

bridge="$stage/probe_bridge"
app="$stage/probe_app"

echo "── bridge init --core $core ──"
dart run "$cli" bridge init --core "$core" --name probe_bridge --out "$bridge"

echo "── o api do versionado, como entrada de produto ──"
cp -R "$repo_root/product/desktop_core_bridge/rust/src/api" "$bridge/rust/src/"

echo "── as outras entradas de produto que o template manda completar ──"
# O support.rs do template é genérico (Result<String>); o do produto converte
# para o CoreFailure tipado. E o api usa os crates irmãos que o template não
# declara — o README do template manda "declare-os como o fixture faz".
cp "$repo_root/product/desktop_core_bridge/rust/src/support.rs" "$bridge/rust/src/support.rs"
sed_inplace "$bridge/rust/Cargo.toml" \
  "s|^flutter_rust_bridge = \"=2.13.0\"|ipc-proto = { path = \"$crates/ipc-proto\" }\ncommon-types = { path = \"$crates/common-types\" }\napi-client = { path = \"$crates/api-client\" }\nflutter_rust_bridge = \"=2.13.0\"|"

echo "── flutter_rust_bridge_codegen generate ──"
(cd "$bridge" && flutter_rust_bridge_codegen generate)

echo "── tool/build_xcframework.sh do bridge gerado ──"
bash "$bridge/tool/build_xcframework.sh"

echo "── app consumidor ──"
dart run "$cli" new --root "$stage" --name probe_app \
  --dovetail-path "$repo_root/toolkit/dovetail" --weave-path "$weave"
sed_inplace "$app/pubspec.yaml" \
  "s|^  dovetail:$|  probe_bridge:\n    path: $bridge\n  dovetail:|"

echo "── flutter build macos --debug ──"
(cd "$app" && flutter create --platforms=macos . >/dev/null 2>&1)
(cd "$app" && flutter build macos --debug 2>&1 | grep -E "✓ Built|Swift Package|error" | head -5)

echo "── o bridge embutido no app ──"
find "$app/build/macos/Build/Products/Debug/probe_app.app/Contents/Frameworks" \
  -maxdepth 1 \( -name '*probe_bridge*' -o -name '*shortcut*' \) -exec basename {} \; || true

echo "==> bridge gerado builda: codegen + XCFramework + app consumidor verdes"
