#!/usr/bin/env bash
set -euo pipefail

# Builds the installable release: the pipeline binary plus the runtime
# packages, in one tarball. The binary half is delegated to
# toolkit/dovetail_cli/tool/build_release.sh — same CHANGELOG gate, same
# compile, same sha256 — and this script adds sdk/<version>/packages, the
# runtime an app imports, so an install outside the monorepo carries
# everything the app needs.
#
# The tarball layout mirrors what install.sh unpacks into ~/.dovetail:
#
#   dovetail-sdk-<version>-<os>-<arch>.tar.gz
#   ├── bin/dovetail
#   └── sdk/<version>/
#       ├── packages/<cada package do runtime, com pubspec + lib>
#       └── templates/{bridge,app}/
#
# The relative paths between packages are preserved (dovetail depends on
# ../dovetail_platform_channel and so on), so `flutter pub get` resolves the
# runtime with no registry and no monorepo.
#
# Usage:
#   tool/build_sdk.sh [--out dist] [--target linux-arm64]
#

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli_dir="$repo_root/toolkit/dovetail_cli"
out="$repo_root/dist"
target=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="${2:?--out takes a directory}"; shift 2 ;;
    --target) target="${2:?--target takes <os>-<arch>}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

version="$(awk '/^version:/ {gsub(/\r/, ""); print $2; exit}' "$cli_dir/pubspec.yaml")"
source "$cli_dir/tool/release_platform.sh"
if ! release_platform "$target"; then
  echo 'SDK targets follow toolkit/dovetail_cli/tool/build_release.sh' >&2
  exit 1
fi
os="$target_os" arch="$target_arch"

name="dovetail-sdk-$version-$os-$arch"
stage="$out/$name"
rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/sdk/$version"

echo "==> the pipeline binary ($os-$arch)"
binary_dir="$stage/binary"
mkdir -p "$binary_dir"
if [ -n "$cross" ]; then
  bash "$cli_dir/tool/build_release.sh" --target "$os-$arch" "$binary_dir" | sed 's/^/    /'
else
  bash "$cli_dir/tool/build_release.sh" "$binary_dir" | sed 's/^/    /'
fi
mv "$binary_dir/$binary" "$stage/bin/$binary"
rm -f "$binary_dir"/*.tar.gz "$binary_dir"/*.zip "$binary_dir"/*.sha256
rmdir "$binary_dir"

# O macOS resolve os plugins Rust via SPM (default desde o Flutter 3.44), e o
# Package.swift do dovetail_shortcut_channel aponta para um .xcframework que o
# repo NÃO versiona — sem construí-lo aqui, um consumidor do SDK que builda
# para macOS com SPM quebra no binaryTarget inexistente. No linux o SPM não
# existe, então nada a fazer.
if [ "$os" = "macos" ]; then
  echo "==> the Swift Package artifacts (macOS)"
  bash "$repo_root/tool/build_xcframework.sh" dovetail_shortcut_channel | sed 's/^/    /'
fi

echo "==> the runtime packages"
# O barril e o que ele reexporta: é a lista que o barrel_test prende.
for package in \
  dovetail \
  dovetail_platform_channel \
  dovetail_shortcut_channel \
  dovetail_updater \
  dovetail_form_validation \
  dovetail_process_runner \
  dovetail_rust_core; do
  src="$repo_root/toolkit/$package"
  dst="$stage/sdk/$version/packages/$package"
  mkdir -p "$dst"
  cp "$src/pubspec.yaml" "$dst/pubspec.yaml"
  # The locks are versioned and consumption uses --enforce-lockfile: an SDK
  # without them fails pub get before anything runs.
  cp "$src/pubspec.lock" "$dst/pubspec.lock"
  # Tudo o que um package precisa para ser resolvido E compilado: o lib, os
  # platform dirs dos plugins nativos — o `flutter build` de um app
  # consumidor faz add_subdirectory no linux/macos/windows de cada plugin — o
  # cargokit vendored do ffiPlugin (o CMakeLists dele faz include nele) e o
  # crate rust do dovetail_rust_core, contra o qual o bridge gerado compila. Fica de
  # fora de propósito o que é só do desenvolvimento: test/, example/, build/.
  for dir in lib macos windows linux rust cargokit; do
    if [ -d "$src/$dir" ]; then
      cp -R "$src/$dir" "$dst/$dir"
    fi
  done
  # Artifacts de build nunca entram no SDK: o target/ do cargo de um plugin
  # rust ou o build/ de um plugin compilado são centenas de MB de sobra que o
  # consumidor não precisa e que travam o empacotamento.
  find "$dst" -type d \
    \( -name target -o -name build -o -name .dart_tool -o -name Pods \
       -o -name .symlinks -o -name ephemeral \) \
    -prune -exec rm -rf {} + 2>/dev/null || true
  echo "    packages/$package"
done

echo "==> the bridge template"
cp -R "$repo_root/tool/sdk/templates" "$stage/sdk/$version/templates"

echo "==> the archive"
archive="$out/$name.$extension"
if [ "$extension" = zip ]; then
  "$release_tar" -a -cf "$archive" -C "$stage" bin sdk
else
  "$release_tar" -czf "$archive" -C "$stage" bin sdk
fi
release_checksum "$archive"

# A assinatura do tarball, para o self-install/self-update verificarem contra
# a chave que o binário embute. Um release não assinado não existe: recusa
# antes de publicar. A privada fica em keys/sdk.key (gitignored), a pública
# em tool/sdk/sdk_release.pub (versionada, embutida pelo build_release.sh).
if [ ! -f "$repo_root/keys/sdk.key" ]; then
  echo "no SDK release key at keys/sdk.key" >&2
  echo "  Generate it once: minisign -G -W -p tool/sdk/sdk_release.pub -s keys/sdk.key" >&2
  exit 1
fi
minisign -S -x "$archive.minisig" -s "$repo_root/keys/sdk.key" \
  -m "$archive" -t "dovetail-sdk $version $os-$arch" >/dev/null

echo
echo "sdk      $archive"
echo "minisig  $archive.minisig"
echo "sha256   $(cat "$archive.sha256")"
if [ -z "$cross" ]; then
  echo "reports  $("$stage/bin/$binary" --version)"
fi
