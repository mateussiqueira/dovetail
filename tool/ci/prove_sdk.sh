#!/usr/bin/env bash
set -euo pipefail

# O canário do release: a prova fim-a-fim da Fase 5 de docs/instalador.md,
# versionada para qualquer máquina reproduzir — um container limpo instala o
# SDK do canal https, cria o app mínimo e roda doctor + test + build sem
# clonar o monorepo.
#
#   tool/ci/prove_sdk.sh               # usa o primeiro tarball linux-x64 de dist/
#   tool/ci/prove_sdk.sh --image img   # outra imagem (default: dovetail-gate-linux)
#
# O tarball entra por volume; a imagem precisa do ambiente do gate-linux
# (Flutter + Rust + toolchain linux) — o tool/ci/gate-linux.Dockerfile a
# constrói. Sem o tarball em dist/, o script recusa e diz como construí-lo:
#   bash tool/build_sdk.sh --target linux-x64

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

image="dovetail-gate-linux"
while [ $# -gt 0 ]; do
  case "$1" in
    --image) image="${2:?--image takes a name}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

tarball="$(ls -1 "$repo_root"/dist/dovetail-sdk-*-linux-x64.tar.gz 2>/dev/null | head -1)"
if [ -z "$tarball" ]; then
  echo "no linux-x64 SDK tarball in dist/. Run: bash tool/build_sdk.sh --target linux-x64" >&2
  exit 1
fi
version="$(basename "$tarball" | sed 's/^dovetail-sdk-\(.*\)-linux-x64.tar.gz$/\1/')"

# O volume precisa morar sob o home do usuário — o Colima não compartilha
# /Volumes com a VM.
stage="$HOME/dovetail-prove-stage"
rm -rf "$stage"
mkdir -p "$stage/channel/$version"
cp "$tarball" "$stage/channel/$version/"
cp "$tarball.sha256" "$stage/channel/$version/" 2>/dev/null || true
cp "$repo_root/tool/sdk/install.sh" "$stage/channel/"
printf '%s\n' "$version" > "$stage/channel/latest"

# O que o container executa: o mesmo fluxo que a Fase 5 provou, num script
# só, para o canário não depender de nada além do tarball.
cat > "$stage/run.sh" <<'RUN'
set -euo pipefail

apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends \
  python3 openssl ca-certificates libayatana-appindicator3-dev >/dev/null

mkdir -p /tmp/ca && cd /tmp/ca
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
  -days 2 -subj "/CN=dovetail proof CA" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -keyout chan.key -out chan.csr \
  -subj "/CN=127.0.0.1" >/dev/null 2>&1
printf 'subjectAltName=IP:127.0.0.1\n' > san.cnf
openssl x509 -req -in chan.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out chan.crt -days 2 -extfile san.cnf >/dev/null 2>&1
cp ca.crt /usr/local/share/ca-certificates/dovetail-proof.crt
update-ca-certificates >/dev/null

cat > /tmp/ca/serve.py <<'PY'
import http.server, ssl, os
os.chdir('/srv/channel')
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8443), http.server.SimpleHTTPRequestHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('/tmp/ca/chan.crt', '/tmp/ca/chan.key')
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PY
python3 /tmp/ca/serve.py >/tmp/ca/server.log 2>&1 &
sleep 1

export DOVETAIL_INSTALL_URL=https://127.0.0.1:8443
export DOVETAIL_HOME=/srv/home
export DOVETAIL_BIN_DIR=/srv/bin

echo "── install.sh ──"
sh /srv/channel/install.sh 2>/dev/null

echo "── dovetail new --sdk demo ──"
mkdir -p /srv/work && cd /srv/work
/srv/home/bin/dovetail new --sdk demo >/dev/null
cd demo

echo "── flutter create --platforms=linux . ──"
flutter create --platforms=linux . >/dev/null 2>&1

echo "── flutter pub get ──"
flutter pub get >/dev/null 2>&1

echo "── flutter test ──"
flutter test 2>&1 | tail -1

echo "── flutter build linux --debug ──"
flutter build linux --debug 2>&1 | tail -1

echo "── dovetail doctor ──"
/srv/home/bin/dovetail doctor 2>&1 | sed -n '/^sdk$/,/^$/p'
RUN

echo "==> provando $version contra a imagem $image"
docker run --rm --platform linux/amd64 -v "$stage:/srv" "$image" bash /srv/run.sh
echo "==> canário verde: o SDK $version instala e sustenta o app mínimo"
