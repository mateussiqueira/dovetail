#!/usr/bin/env bash
set -euo pipefail

# A orquestração do release: os dois builds na ordem certa, e só termina
# com os canários verdes — nenhuma versão sai sem a prova do consumidor.
#
#   tool/release.sh
#
# Passos:
#   1. tool/build_xcframework.sh            o XCFramework do SPM (macOS)
#   2. tool/build_sdk.sh                    o tarball do host
#   3. tool/build_sdk.sh --target linux-x64 o tarball cross
#   4. tool/ci/prove_sdk.sh                 canário: container limpo instala
#   5. tool/ci/prove_bridge.sh              canário: o bridge gerado builda
#   6. tool/ci/prove_service.sh             canário: o daemon chega ao bundle
#
# Cada passo recusa alto com o nome do script que falhou; a ordem importa —
# o tarball macOS leva o XCFramework do passo 1, e o canário do passo 4 leva
# o tarball linux do passo 3.
#
# O passo 6 constrói um app do zero (`flutter create` + `dovetail build`), então
# exige `flutter` na máquina de release, além de `clang`, `plutil` e `codesign`.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

step() {
  echo
  echo "==> $1"
  shift
  "$@"
}

step "build_xcframework.sh (SPM, macOS)" bash tool/build_xcframework.sh
step "build_sdk.sh (host)" bash tool/build_sdk.sh
step "build_sdk.sh --target linux-x64" bash tool/build_sdk.sh --target linux-x64
step "prove_sdk.sh (canário do container)" bash tool/ci/prove_sdk.sh

# O canário do bridge gera um plugin contra o núcleo do PRODUTO e builda um app
# consumidor: ele precisa do checkout irmão, que é privado. Numa máquina de
# release que não o tem, exigi-lo tornaria impossível cortar um release do
# framework — e o que ele prova é o gerador do bridge, não o SDK.
#
# Então ele pula com o motivo escrito, e o resumo final diz o que NÃO foi
# provado. Um release que pula um canário em silêncio é pior do que um que
# recusa: quem lê "todos os canários verdes" acredita.
core="${DOVETAIL_CORE_PATH:-$repo_root/../example-rust/crates/core}"
weave="${DOVETAIL_WEAVE_PATH:-$repo_root/../../projects/weave}"
bridge_proof="verde"
if [ -f "$core/Cargo.toml" ] && [ -f "$weave/pubspec.yaml" ]; then
  step "prove_bridge.sh (canário do bridge)" bash tool/ci/prove_bridge.sh
else
  bridge_proof="PULADO"
  echo
  echo "==> prove_bridge.sh PULADO"
  [ -f "$core/Cargo.toml" ] || echo "    sem o núcleo do produto em $core"
  [ -f "$weave/pubspec.yaml" ] || echo "    sem o checkout do weave_di em $weave"
  echo "    aponte com \$DOVETAIL_CORE_PATH / \$DOVETAIL_WEAVE_PATH para prová-lo"
fi

# O canário do daemon responde a pergunta que nenhuma unidade respondeu: as seis
# peças que o `SMAppService` exige produzem um bundle junto? Ele roda o CLI daqui
# direto, sem ler tarball nenhum, e fica por último por ser o único passo que
# paga um build de app inteiro — quem corta release paga esse preço depois de o
# que é publicado já estar verde.
step "prove_service.sh (canário do daemon embarcado)" bash tool/ci/prove_service.sh

echo
if [ "$bridge_proof" = "verde" ]; then
  echo "release pronto: todos os passos e os três canários verdes"
else
  echo "release pronto: os passos e os canários do SDK e do serviço verdes"
  echo "  o canário do bridge NÃO rodou — o gerador do bridge segue não provado"
fi
find dist -maxdepth 1 -name 'dovetail-sdk-*.tar.gz' -exec echo "  {}" \; 2>/dev/null
