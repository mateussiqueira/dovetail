#!/usr/bin/env bash
set -euo pipefail

# Constrói os XCFrameworks dos plugins Rust do framework — o passo que o
# Swift Package Manager não pode fazer sozinho: o SPM não roda cargo durante
# o build (build-tool plugins são sandboxed), então o dylib entra pré-
# construído como binaryTarget.
#
# Cada plugin vira um XCFramework com as duas fatias do macOS (aarch64 e
# x86_64), escrito em macos/<plugin>/<plugin>.xcframework — o caminho que o
# Package.swift do plugin referencia. O artefato NÃO é versionado: o repo
# guarda o script, e o .gitignore exclui o .xcframework.
#
#   tool/build_xcframework.sh [plugin...]
#
# Sem argumentos constrói os dois plugins. Com nomes, só os pedidos. Um dev
# de SPM roda o script depois de mudar Rust; quem fica no CocoaPods nem
# precisa dele — o cargokit continua reconstruindo dentro do build do Xcode.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

plugins="
desktop_core_bridge:$repo_root/product/desktop_core_bridge
dovetail_shortcut_channel:$repo_root/toolkit/dovetail_shortcut_channel
"

if [ $# -gt 0 ]; then
  selected=""
  for wanted in "$@"; do
    entry="$(printf '%s\n' "$plugins" | grep "^$wanted:" || true)"
    if [ -z "$entry" ]; then
      echo "no plugin named $wanted (have: desktop_core_bridge, dovetail_shortcut_channel)" >&2
      exit 2
    fi
    selected="$selected$entry
"
  done
  plugins="$selected"
fi

for entry in $plugins; do
  name="${entry%%:*}"
  dir="${entry##*:}"
  rust="$dir/rust"
  out="$dir/macos/$name/$name.xcframework"

  echo "==> $name (dylib universal, aarch64 + x86_64)"
  # O target dir é isolado: o target/ padrão do crate é o que os testes de
  # integração usam (a lib com a feature test-probe), e este build de
  # release sem a feature não pode sobrescrevê-lo.
  build_dir="$rust/target/xcframework"
  (cd "$rust" && CARGO_TARGET_DIR="$build_dir" cargo build --release --target aarch64-apple-darwin) | sed 's/^/    /'
  (cd "$rust" && CARGO_TARGET_DIR="$build_dir" cargo build --release --target x86_64-apple-darwin) | sed 's/^/    /'

  # Um XCFramework carrega uma fatia por plataforma; para o macOS a fatia é
  # um dylib universal, então o lipo funde as duas arquiteturas antes.
  lipo -create \
    "$build_dir/aarch64-apple-darwin/release/lib$name.dylib" \
    "$build_dir/x86_64-apple-darwin/release/lib$name.dylib" \
    -output "$build_dir/release/lib$name.dylib"

  rm -rf "$out"
  mkdir -p "$(dirname "$out")"
  xcodebuild -create-xcframework \
    -library "$build_dir/release/lib$name.dylib" \
    -output "$out"
  echo "    $out"
done
