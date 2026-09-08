#!/usr/bin/env bash
# Prova ponta a ponta, NESTA maquina, do laco de release do produto sem as tres
# coisas que ainda nao existem: a chave de producao, o host e o Developer ID.
# Cada uma entra por um substituto que segue o MESMO contrato, para que o real
# seja trocar valores e nao codigo:
#
#   chave de producao  -> par minisign descartavel   (dovetail keygen --out)
#   host https         -> loopback com CA privada    (tool/serve_dist.dart)
#   Developer ID       -> identidade ad hoc `-`      (APPLE_SIGNING_IDENTITY=-)
#
# O que isto PROVA: a ordem da esteira (sign .app -> bundle -> sign dmg ->
# archive -> release), o selo e os entitlements do .app e do .dmg, o formato do
# manifesto, que o artefato publicado e o que o updater instala (.app.tar.gz),
# transporte https, e a assinatura minisign sobre os bytes servidos — com o
# `probe`, que e o mesmo parser e o mesmo verificador do app.
#
# O que isto NAO prova: distribuibilidade (Gatekeeper, notarizacao — precisa
# de Developer ID e de credenciais Apple), DNS e CDN reais, e o app instalado
# aceitando o update (o binario embute a chave que confia; ver o runbook em
# docs/release-simulado.md para o passo com o app).
#
# Uso: tool/ci/prove_update.sh --host macos
#      PRODUCT=/caminho/do/produto tool/ci/prove_update.sh --host macos
# Requisitos: o .app de Release ja construido no produto (`dovetail build`),
# openssl, minisign, dart. Roda SEMPRE o CLI da arvore, nunca o instalado.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
product="${PRODUCT:-$repo/product/vpn_desktop}"
stage="${DOVETAIL_UPDATE_STAGE:-${TMPDIR:-/tmp}/dovetail-update-stage}"
port="${DOVETAIL_UPDATE_PORT:-8443}"
cli=(dart "$repo/toolkit/dovetail_cli/bin/dovetail.dart")

host=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host) host="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
if [ "$host" != "macos" ]; then
  echo "usage: tool/ci/prove_update.sh --host macos   (the only host proven so far)" >&2
  exit 64
fi
if [ "$(uname -s)" != "Darwin" ]; then
  echo "--host macos runs on a Mac; this is $(uname -s)" >&2
  exit 1
fi
for tool in openssl minisign dart codesign hdiutil curl python3; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

say() { printf '\n== %s\n' "$*"; }
fail() { echo "FAILED: $*" >&2; exit 1; }

# ---- what the product declares, read once ---------------------------------
[ -f "$product/dovetail.yaml" ] || fail "no dovetail.yaml at $product"
[ -f "$product/pubspec.yaml" ] || fail "no pubspec.yaml at $product"
binary="$(awk '/^name:/{print $2; exit}' "$product/pubspec.yaml")"
version="$(awk '/^version:/{print $2; exit}' "$product/pubspec.yaml" | cut -d+ -f1)"
built="$product/build/macos/Build/Products/Release/$binary.app"
[ -d "$built" ] || fail "no Release .app at $built — run 'dovetail build' in $product first"

scalar() { awk -v k="$1:" '$1==k{ $1=""; sub(/^ /,""); print; exit }' "$product/dovetail.yaml"; }
identifier="$(scalar identifier)"; name="$(scalar name)"; manufacturer="$(scalar manufacturer)"
targets_line="$(grep -m1 '^targets:' "$product/dovetail.yaml")"
[ -n "$identifier" ] && [ -n "$name" ] && [ -n "$manufacturer" ] && [ -n "$targets_line" ] \
  || fail "identifier/name/manufacturer/targets not all found in $product/dovetail.yaml"

# ---- a staging root, so nothing in the product is edited ------------------
say "staging root: $stage"
if [ -e "$stage" ]; then
  [ -f "$stage/.dovetail-stage" ] || fail "$stage exists and is not a previous stage (no .dovetail-stage marker); refusing to remove it"
  rm -rf "$stage"
fi
mkdir -p "$stage/build/macos/Build/Products/Release" "$stage/macos/Runner" "$stage/keys" "$stage/tls"
touch "$stage/.dovetail-stage"
cp "$product/pubspec.yaml" "$stage/pubspec.yaml"
cp "$product/macos/Runner/Release.entitlements" "$stage/macos/Runner/Release.entitlements"
# ditto preserva a assinatura que o Xcode deixou; o ship a substitui de proposito.
ditto "$built" "$stage/build/macos/Build/Products/Release/$binary.app"
cd "$stage"

say "throwaway minisign pair (never the production key)"
# Caminho absoluto: sem ele, o keygen procura um dovetail.yaml subindo ate 12
# pastas e resolve o --out contra ELE — e o stage ainda nao tem yaml aqui.
"${cli[@]}" keygen --out "$stage/keys/staging.key" --unencrypted | sed -n '1,2p'
[ -f keys/staging.pub ] || fail "keygen did not write keys/staging.pub"

{
  echo "identifier: $identifier"
  echo "name: $name"
  echo "manufacturer: $manufacturer"
  echo "$targets_line"
  echo "update:"
  echo "  key: keys/staging.key"
  echo "  unencrypted: true"
  echo "  base-url: https://localhost:$port/releases"
  echo "  manifest: dist/latest.json"
  echo "  endpoint: https://localhost:$port/desktop-version/check/{{target}}"
  echo "  public-key: |"
  sed 's/^/    /' keys/staging.pub
  echo "sign:"
  echo "  macos:"
  echo "    entitlements: macos/Runner/Release.entitlements"
  echo "    notarize: false"
} > dovetail.yaml
echo "wrote $stage/dovetail.yaml (staging values; the product's file is untouched)"

say "ship --no-build with the ad hoc identity"
APPLE_SIGNING_IDENTITY=- "${cli[@]}" ship --no-build

say "what ship left in dist/"
ls -la dist/
dmg="dist/${binary}_${version}_universal.dmg"
archive="dist/${binary}_${version}_universal.app.tar.gz"
[ -f "$dmg" ] || fail "no dmg at $dmg"
[ -f "$archive" ] || fail "no updater archive at $archive (the archive step)"
[ -f "$archive.minisig" ] || fail "no minisign signature beside $archive"
[ -f dist/latest.json ] || fail "no manifest at dist/latest.json"

# O layout que um CDN teria: <base-url>/<versao>/<arquivo>. O `release` escreve
# o dist/ plano, e servir o arquivo por qualquer caminho esconderia um manifesto
# que aponta para a versao errada — num host real, 404.
say "laying dist/ out the way the manifest's urls read"
mkdir -p "dist/releases/$version"
cp "$archive" "$archive.minisig" "$dmg" "dist/releases/$version/"
find "dist/releases/$version" -type f -exec basename {} \; | sort | sed 's/^/  /'

say "the manifest points the updater at the archive, not the dmg"
python3 - "$archive" <<'EOF'
import json, sys
manifest = json.load(open('dist/latest.json'))
url = manifest['platforms']['darwin-universal']['url']
print('  darwin-universal ->', url)
assert url.endswith('.app.tar.gz'), f'the manifest publishes {url}, which MacosInstaller cannot extract'
assert 'https://localhost' in url, url
EOF

say "the seals: .app inside out with the Release entitlements, dmg as a flat file"
codesign --verify --deep --strict "build/macos/Build/Products/Release/$binary.app" && echo "  .app: valid"
codesign -d --entitlements - --xml "build/macos/Build/Products/Release/$binary.app" 2>/dev/null | plutil -p - | sed 's/^/  /'
# Capturado antes do grep: sob pipefail, um `grep -q` que sai no primeiro
# acerto pode deixar o codesign morrer de SIGPIPE e o `if` ler o 141 dele.
entitlements="$(codesign -d --entitlements - --xml "build/macos/Build/Products/Release/$binary.app" 2>/dev/null)"
if grep -q get-task-allow <<<"$entitlements"; then
  fail "get-task-allow survived the re-sign; notarization would refuse it"
fi
codesign --verify --strict "$dmg" && echo "  .dmg: valid ($(codesign -dv "$dmg" 2>&1 | grep -o 'Signature=[a-z]*'))"

say "private CA + leaf for localhost (the real host has a public CA; the contract is the same)"
openssl req -x509 -newkey rsa:2048 -nodes -keyout tls/ca.key -out tls/ca.crt \
  -days 2 -subj "/CN=dovetail update proof CA" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout tls/srv.key -out tls/srv.csr \
  -subj "/CN=localhost" >/dev/null 2>&1
# EKU serverAuth nao e enfeite: no macOS o Dart delega a avaliacao de confianca
# ao Security framework da Apple, que exige extendedKeyUsage=serverAuth em todo
# certificado de servidor TLS (regra de 2019). Sem ele o `curl --cacert` aceita
# e o cliente Dart recusa com "application verification failure".
printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n' > tls/san.cnf
openssl x509 -req -in tls/srv.csr -CA tls/ca.crt -CAkey tls/ca.key -CAcreateserial \
  -out tls/srv.crt -days 2 -extfile tls/san.cnf >/dev/null 2>&1

say "serving dist/ at https://localhost:$port"
dart "$repo/tool/serve_dist.dart" --root dist --cert tls/srv.crt --key tls/srv.key --port "$port" > tls/server.log 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  curl -s --cacert tls/ca.crt "https://localhost:$port/latest.json" -o /dev/null && break
  sleep 0.2
done
curl -s --cacert tls/ca.crt "https://localhost:$port/latest.json" -o /dev/null || fail "the local host did not come up (see $stage/tls/server.log)"
code="$(curl -s --cacert tls/ca.crt -o /dev/null -w '%{http_code}' "https://localhost:$port/desktop-version/check/darwin")"
[ "$code" = "200" ] || fail "the app's endpoint shape (/desktop-version/check/darwin) answered $code"
echo "  /latest.json and /desktop-version/check/darwin answer 200"

say "probe: without --ca the client must REFUSE the private CA"
if untrusted="$("${cli[@]}" probe --url "https://localhost:$port/latest.json" --target darwin-universal --timeout 5 2>&1)"; then
  fail "probe accepted a certificate nobody trusts"
fi
# Recusado PELO certificado, nao por qualquer outro motivo: a mensagem tem de
# ser a do handshake.
echo "$untrusted" | grep -Eq 'HandshakeException|CERTIFICATE_VERIFY_FAILED|verification failure' \
  || { echo "$untrusted"; fail "the probe failed, but not because it refused the certificate"; }
echo "  refused, as a shipped client would"

say "probe: with --ca, an older client should be offered $version and verify the bytes"
"${cli[@]}" probe --url "https://localhost:$port/latest.json" --ca tls/ca.crt \
  --public-key keys/staging.pub --target darwin-universal --installed 0.9.0 --download

say "probe: the same version installed should NOT be offered anything"
# O probe trata "nao ofereceria" como FAILED de proposito — quem pergunta com
# --installed quer saber se o endpoint oferece algo a esse cliente. Aqui a
# resposta certa e nao, e o que se confere e o motivo: upToDate.
if same="$("${cli[@]}" probe --url "https://localhost:$port/latest.json" --ca tls/ca.crt \
  --public-key keys/staging.pub --target darwin-universal --installed "$version" 2>&1)"; then
  fail "the probe offered $version to a client already on $version"
fi
echo "$same" | grep -q "upToDate" || { echo "$same"; fail "expected the policy to say upToDate"; }
echo "  up to date for $version, as it should be"

kill $server 2>/dev/null || true
wait $server 2>/dev/null || true
trap - EXIT

cat <<EOF

prove_update: ok
  stage      $stage
  manifest   $stage/dist/latest.json
  updater    $archive  (+ .minisig)
  download   $dmg  (ad hoc; a real release signs with Developer ID and notarizes)
  key        keys/staging.pub  (throwaway; the production pair is a human decision)

To make it real, swap values, not code: update.public-key and keys/ in the
product's dovetail.yaml, update.base-url to the CDN, APPLE_SIGNING_IDENTITY to
the Developer ID, and sign.macos.notarize: true with the APPLE_* credentials.
EOF
