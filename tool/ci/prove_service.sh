#!/usr/bin/env bash
set -euo pipefail

# Prova que o daemon privilegiado chega ao `.app` como o `SMAppService` exige:
# o plist no lugar em que ele procura, o `Label` igual ao nome do arquivo, o
# `BundleProgram` relativo, o binario em `Contents/MacOS/`, o bundle assinado
# inteiro e — o defeito que o `ddb337c` fechou — o daemon com os entitlements
# DELE, sem o `app-sandbox` do aplicativo. Cada peca tinha teste de unidade
# com runner de gravacao; nada provava que elas produziam um bundle junto.
#
# O que ele NAO prova: registro de verdade. Com a identidade ad-hoc (`-`) o
# `codesign -dv` reporta `TeamIdentifier=not set` dos dois lados, entao a
# checagem de Team ID do `sign` roda e nao recusa — a recusa por divergencia
# segue sem prova fim-a-fim, e o registro real no `SMAppService` continua
# esperando um Developer ID. Ver docs/release-simulado.md.
#
# Constroi o app do zero (`flutter create` + `dovetail build`), que e a parte
# cara. Roda no host macOS e precisa de `clang`, `plutil` e `codesign`.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cli="$repo_root/toolkit/dovetail_cli/bin/dovetail.dart"

stage="$(mktemp -d /tmp/dovetail-prove-service.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

fail() {
  echo "prove_service: $1" >&2
  exit 1
}

# O app e minimo de proposito: o que se prova e o bundle, nao o produto. Sem
# `dovetail new` aqui — ele pede o SDK e o weave, e nada disso e lido pelas
# assercoes abaixo.
app="$stage/probe_service"
echo "── flutter create --platforms=macos ──"
flutter create --platforms=macos --project-name probe_service "$app" >/dev/null

identifier="com.example.probe"
label="$identifier.helper"
program="probe-helper"
binary_rel="target/release/$program"
entitlements_rel="helper.entitlements"

# O daemon de verdade: um Mach-O, nao um script. O `codesign` so carrega
# entitlements num binario; um shell script assinaria sem eles.
mkdir -p "$app/target/release"
printf 'int main(void) { return 0; }\n' > "$stage/helper.c"
clang -o "$app/$binary_rel" "$stage/helper.c"

# Os entitlements do DAEMON. O que importa nao e a chave de dentro e sim o que
# NAO esta nela: nenhum `app-sandbox`. E a assercao 6.
cat > "$app/$entitlements_rel" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$app/dovetail.yaml" <<YAML
identifier: $identifier
name: Probe Service
manufacturer: Example Ltda
targets: [darwin-aarch64]
service:
  macos:
    label: $label
    program: $program
    binary: $binary_rel
    entitlements: $entitlements_rel
YAML

# O embed mora no `build` e exige o binario ja compilado; e a assinatura e um
# passo SEPARADO, o unico que aplica os entitlements do daemon.
echo "── dovetail build --target macos --no-release ──"
APPLE_SIGNING_IDENTITY=- dart run "$cli" build --root "$app" --target macos \
  --no-release >"$stage/build.log" 2>&1 ||
  {
    tail -30 "$stage/build.log" >&2
    fail "dovetail build failed"
  }
grep -E '^(building|define|daemon|output) ' "$stage/build.log" || true

bundle="$app/build/macos/Build/Products/Debug/probe_service.app"
plist="$bundle/Contents/Library/LaunchDaemons/$label.plist"
daemon="$bundle/Contents/MacOS/$program"

echo "── dovetail sign --target macos --bundle ──"
# Do diretorio do projeto de proposito: o `sign` acha o `dovetail.yaml` pelo
# cwd, e sem ele nao le `service.macos.entitlements` — o daemon sairia com os
# entitlements do app, que e exatamente o defeito que esta prova cobre.
(cd "$app" && APPLE_SIGNING_IDENTITY=- dart run "$cli" sign --target macos \
  --bundle "$bundle") || fail "dovetail sign failed"

echo "── 1. o plist existe e o plutil o aceita ──"
[ -f "$plist" ] || fail "no plist at $plist"
plutil -lint "$plist" >/dev/null || fail "plutil rejects $plist"

echo "── 2. o Label e o nome do arquivo sem .plist ──"
declared_label="$(plutil -extract Label raw -o - "$plist")"
[ "$declared_label" = "$(basename "$plist" .plist)" ] ||
  fail "Label is '$declared_label', file is '$(basename "$plist")'"

echo "── 3. BundleProgram relativo, em Contents/MacOS/$program ──"
bundle_program="$(plutil -extract BundleProgram raw -o - "$plist")"
[ "$bundle_program" = "Contents/MacOS/$program" ] ||
  fail "BundleProgram is '$bundle_program'"
case "$bundle_program" in
  /*) fail "BundleProgram is absolute: $bundle_program" ;;
esac

echo "── 4. o binario existe e e executavel ──"
[ -x "$daemon" ] || fail "no executable at $daemon"

echo "── 5. codesign --verify --deep --strict ──"
codesign --verify --deep --strict "$bundle" || fail "codesign --verify failed"

echo "── 6. os entitlements do daemon, e nenhum app-sandbox ──"
codesign -d --entitlements :- "$daemon" 2>/dev/null >"$stage/daemon.plist" ||
  fail "codesign could not read entitlements from $daemon"
[ -s "$stage/daemon.plist" ] || fail "$daemon carries no entitlements at all"
codesign -d --entitlements :- "$bundle" 2>/dev/null >"$stage/app.plist" || true

# Comparadas como CONJUNTO de chaves, e nao como texto: o `codesign` reescreve
# o plist que guardou, e comparar bytes acusaria uma diferenca que nao existe.
keys() {
  plutil -convert json -o - "$1" |
    python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))'
}
declared_keys="$(keys "$app/$entitlements_rel")"
embedded_keys="$(keys "$stage/daemon.plist")"
[ "$embedded_keys" = "$declared_keys" ] ||
  fail "the daemon carries '$embedded_keys', and '$declared_keys' was declared"
if printf '%s' "$embedded_keys" | grep -qx 'com.apple.security.app-sandbox'; then
  fail "the daemon inherited app-sandbox from the application"
fi

# A PREMISSA da assercao acima: o app precisa carregar o `app-sandbox`, senao
# "o daemon nao herdou" passa por vacuidade — um template que deixe de po-lo
# tornaria esta prova verde sem provar nada, que e o defeito que o verify.dart
# existe para nao deixar passar.
app_keys="$([ -s "$stage/app.plist" ] && keys "$stage/app.plist" || true)"
printf '%s' "$app_keys" | grep -qx 'com.apple.security.app-sandbox' ||
  fail "the application carries no app-sandbox, so assertion 6 proved nothing"

echo "==> daemon embarcado: plist, Label, BundleProgram, binario e entitlements proprios verdes"
