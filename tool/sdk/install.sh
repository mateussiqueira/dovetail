#!/bin/sh
# Instala o dovetail: o binário da esteira + o runtime do SDK, do canal de
# release. É o caminho curl|sh do plano em docs/instalador.md:
#
#   curl -fsSL https://<host>/install.sh | sh
#
# Env:
#   DOVETAIL_INSTALL_URL  base do canal (obrigatória): serve latest/,
#                         install.sh e os tarballs por versão
#   DOVETAIL_HOME         destino (padrão ~/.dovetail)
#   DOVETAIL_BIN_DIR      onde fica o symlink (padrão ~/.local/bin)
#   DOVETAIL_VERSION      pin de versão (padrão: o /latest do canal)
#
# Idempotente: rodar de novo re-extrai a mesma versão e re-aponta o symlink.
# Instalar uma versão nova mantém as anteriores em sdk/<versão> — é o que
# deixa apps apontados para a anterior continuarem resolvendo.
set -eu

base="${DOVETAIL_INSTALL_URL:-}"
if [ -z "$base" ]; then
  echo "install: set DOVETAIL_INSTALL_URL to the channel root (e.g. https://releases.example.com)" >&2
  exit 1
fi
base="${base%/}"

if ! command -v curl >/dev/null 2>&1; then
  echo "install: curl is required" >&2
  exit 1
fi

home="${DOVETAIL_HOME:-$HOME/.dovetail}"
mkdir -p "$home"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  darwin) os=macos ;;
  linux) os=linux ;;
  *) echo "install: dovetail builds on macOS or Linux, not $os" >&2; exit 1 ;;
esac

arch="$(uname -m)"
case "$arch" in
  arm64|aarch64) arch=arm64 ;;
  x86_64) arch=x64 ;;
  *) echo "install: no dovetail build for $arch" >&2; exit 1 ;;
esac

version="${DOVETAIL_VERSION:-}"
if [ -z "$version" ]; then
  version="$(curl -fsSL "$base/latest" | tr -d '[:space:]')"
  if [ -z "$version" ]; then
    echo "install: $base/latest served no version" >&2
    exit 1
  fi
fi

name="dovetail-sdk-$version-$os-$arch"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

curl -fsSL "$base/$version/$name.tar.gz" -o "$stage/$name.tar.gz"

if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
  curl -fsSL "$base/$version/$name.tar.gz.sha256" -o "$stage/expected"
  if command -v shasum >/dev/null 2>&1; then
    (cd "$stage" && shasum -a 256 "$name.tar.gz" | awk '{print $1}') > "$stage/actual"
  else
    (cd "$stage" && sha256sum "$name.tar.gz" | awk '{print $1}') > "$stage/actual"
  fi
  if ! cmp -s "$stage/expected" "$stage/actual"; then
    echo "install: sha256 mismatch on $name.tar.gz — refusing to unpack" >&2
    exit 1
  fi
fi

tar -xzf "$stage/$name.tar.gz" -C "$home"

bin_dir="${DOVETAIL_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$bin_dir"
ln -sf "$home/bin/dovetail" "$bin_dir/dovetail"

"$home/bin/dovetail" --version
echo "installed dovetail $version at $home"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "  note: $bin_dir is not in PATH" >&2 ;;
esac
