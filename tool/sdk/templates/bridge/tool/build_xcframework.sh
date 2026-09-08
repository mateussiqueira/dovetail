#!/usr/bin/env bash
set -euo pipefail

# Constrói o XCFramework deste plugin — o passo que o Swift Package Manager
# não pode fazer sozinho (o SPM não roda cargo durante o build). Rode depois
# de mudar Rust, para o Package.swift deste plugin continuar apontando para
# um binaryTarget que existe:
#
#   tool/build_xcframework.sh

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$(basename "$here")"
rust="$here/rust"
out="$here/macos/$name/$name.xcframework"
build_dir="$rust/target/xcframework"

(cd "$rust" && CARGO_TARGET_DIR="$build_dir" cargo build --release --target aarch64-apple-darwin)
(cd "$rust" && CARGO_TARGET_DIR="$build_dir" cargo build --release --target x86_64-apple-darwin)

# Um XCFramework carrega uma fatia por plataforma; no macOS a fatia é um
# dylib universal, então o lipo funde as duas arquiteturas antes.
lipo -create \
  "$build_dir/aarch64-apple-darwin/release/lib$name.dylib" \
  "$build_dir/x86_64-apple-darwin/release/lib$name.dylib" \
  -output "$build_dir/release/lib$name.dylib"

rm -rf "$out"
mkdir -p "$(dirname "$out")"
xcodebuild -create-xcframework \
  -library "$build_dir/release/lib$name.dylib" \
  -output "$out"

echo "$out"
