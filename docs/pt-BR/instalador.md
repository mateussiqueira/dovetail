**Português** · [English](../instalador.md)

# Instalar o dovetail: o SDK fora do monorepo

> **Contexto para quem chega pelo repositório público.** Este documento cita
> `product/`, que é o app privado onde o toolkit é exercitado, e não existe
> neste repositório. O mecanismo descrito é do toolkit e vale para qualquer
> app; só o caminho do exemplo é de outra árvore.

O objetivo: um app desktop, em qualquer máquina, ganha a esteira, o runtime e
o mecanismo de bridge com um `curl` e um comando — sem clonar o monorepo e sem
`path: ../../`.

## O modelo

O mesmo do rustup e do Flutter SDK: um binário único (a esteira) que instala,
atualiza e controla o resto.

```
curl -fsSL https://<host>/install.sh | sh
  → ~/.dovetail/
      bin/dovetail          ← a esteira (AOT, já existe)
      sdk/<versão>/packages ← o runtime que o app importa, versionado
      sdk/<versão>/templates/bridge ← o template que gera o bridge do produto
  → ln -s ~/.dovetail/bin/dovetail ~/.local/bin/dovetail
```

Como os pacotes estão no pub.dev, existe agora uma segunda rota, mais simples
para a maioria: declarar `dovetail: ^0.1.0` e ativar o `dovetail_cli`. O canal
assinado descrito aqui é o que entrega um binário AOT autocontido e um SDK
versionado no disco, que é o que uma máquina de release quer.

O `dovetail init` escreve um `pubspec_overrides.yaml` no app apontando para o
SDK instalado — o mecanismo nativo do Dart para resolver fora do pubspec, o
mesmo que o Flutter SDK usa para entregar os packages dele. O app ganha o
framework com uma linha e um comando.

## O que entra no SDK, e o que não

| entra | fica de fora |
|---|---|
| `dovetail_platform_channel`, `dovetail_shortcut_channel`, `dovetail_updater`, `dovetail_form_validation`, `dovetail_process_runner` — o runtime do barril | `dovetail_bundler`, `dovetail_signer`, `dovetail_cli` — vivem **só dentro do binário** (decisão do [barril](../../toolkit/dovetail/README.md)) |
| `dovetail_rust_core` — a junta Dart↔Rust é do framework, não do monorepo | o `product/` — o SDK não conhece produto nenhum |

O `product/desktop_core_bridge` é o **fixture** do mecanismo de bridge: o
template do SDK reproduz o que ele é, e o critério de aceite da Fase 4 é o
`bridge init` gerar algo que passa no `core_coverage_test` contra o mesmo
crate.

## As fases

Cada fase tem critério de aceite executável e só entra depois que a anterior
prova. Dá para parar em qualquer uma com valor.

1. **O layout e o build do release.** `tool/build_sdk.sh` produz
   `dovetail-sdk-<versão>-<os>-<arch>.tar.gz` (macOS/Linux/Windows × arm64/x64)
   com `bin/`, `sdk/<versão>/packages/` e `sdk/<versão>/templates/bridge/`.
   Aceite: o tarball extraído roda `dovetail doctor` sem o monorepo presente.
2. **`init` resolve o runtime do SDK.** O `pubspec_overrides.yaml` aponta para
   o SDK. Aceite: app novo em outra máquina faz `flutter pub get` e
   `flutter test` verdes só com o SDK.
3. **O instalador e o ciclo de versão.** `install.sh` (curl | sh),
   `dovetail self-install`, `self-update`; o doctor checa SDK presente e
   versão. Aceite: container limpo instala, doctor verde, self-update troca a
   versão sem quebrar apps apontados para a anterior (SDK versionado por
   diretório).
4. **`dovetail bridge`.** `bridge init --core <crate> --name <nome>` gera o
   plugin `ffiPlugin` (3 SOs) com o crate por path configurável e o
   `dovetail_rust_core` do SDK. Aceite: gerado contra o `example-rust` passa no
   `core_coverage_test` — o `desktop_core_bridge` reproduzido bate com o
   versionado.
5. **Prova fim-a-fim.** O [gate-linux Dockerfile](ci.md) vira o palco: um
   container limpo instala, inicia um app mínimo e roda doctor + test + build
   sem clone nenhum.

## O canal de release

O host que serve a instalação fala um layout fixo:

```
<base>/latest                                            → "0.2.0"
<base>/install.sh                                        → o instalador curl|sh
<base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz
<base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz.sha256
```

Dois caminhos fazem o mesmo trabalho, e os dois respeitam `DOVETAIL_HOME`:

```bash
curl -fsSL https://<host>/install.sh | sh   # o caminho de uma linha
dovetail self-install --base-url https://<host>
dovetail self-update  --base-url https://<host>
```

A base vem de `--base-url` ou de `DOVETAIL_INSTALL_URL`, e sem os dois a
recusa nomeia os dois. O download é TLS-only (o fetcher do updater recusa
http) e o tarball é conferido contra o `.sha256` do canal antes de um byte
tocar o disco. O `self-update` extrai a versão nova **ao lado** da antiga e
troca o binário — `sdk/<antiga>` permanece, que é o que mantém um app apontado
para ela resolvendo, e o symlink nem precisa ser re-apontado. Um `latest`
igual ou mais velho é saída 0 sem tocar nada. O `doctor` reporta o SDK numa
seção própria: a versão instalada, e quando ela discorda da do binário, qual
comando fecha a distância — `off`, nunca `missing`, porque dentro do monorepo
o SDK é opcional e um dev que resolve por path não deve ser bloqueado.

## O bridge

O SDK carrega o template do bridge — `sdk/<versão>/templates/bridge` — e o
comando o copia e parametriza:

```bash
dovetail bridge init --core <crate> --name <nome>
```

O `--core` é o diretório do crate do produto; o nome do crate é lido do
`Cargo.toml` dele, nunca adivinhado. O gerado é o plugin `ffiPlugin` dos três
SOs, com o `dovetail_rust_core` do SDK nos dois lados — o Dart no pubspec, o crate no
`Cargo.toml`. O template reproduz a mecânica do fixture
(`product/desktop_core_bridge`) e deixa de fora, de propósito, o que é do
produto: os repasses em `rust/src/api/`, o Dart gerado e o `example/`.

O portão de forma vem junto: o `core_coverage_test` do gerado lê o `handle.rs`
do crate e as chamadas em `rust/src/api/`, e recusa quando o núcleo cresceu um
método que nenhum repasse expõe. O critério de aceite da Fase 4 é exatamente
esse: o gerado contra o `example-rust`, alimentado com o mesmo `api/` do
versionado, passa no mesmo portão.

## A prova fim-a-fim

A Fase 5 roda no container do gate-linux: um ubuntu limpo instala o SDK do
canal https, cria o app mínimo com `dovetail new --sdk`, e roda doctor + test +
build sem clonar o monorepo:

```
install.sh               → dovetail 0.1.0 (linux-x64)
dovetail new --sdk demo
flutter create --platforms=linux .
flutter pub get          → resolve do SDK, sem repo
flutter test             → o runtime do SDK responde no teste
flutter build linux      → ✓ Built build/linux/x64/debug/bundle/demo
dovetail doctor          → sdk ok + project ok
```

O que a prova expôs, e o build do SDK corrigiu: os platform dirs dos plugins
nativos e o cargokit vendored do ffiPlugin têm que ir no tarball — o
`flutter build` faz `add_subdirectory` neles — e os artifacts de build
(`target/`, `build/`) ficam de fora, senão o tarball carrega centenas de MB
que o consumidor não precisa. O gate-linux ganhou o `appindicator` que o
`tray_manager` exige no Linux.

A prova é versionada: `tool/ci/prove_sdk.sh` roda o fluxo acima num container
limpo a partir do tarball em `dist/`, e `tool/ci/prove_bridge.sh` prova o
outro caminho do consumidor — o `bridge init` gerado, com o codegen, o
XCFramework do SPM e um app que o importa, buildando no macOS. Os dois são o
canário do release: nenhuma versão sai sem eles verdes. O que fica em
aberto e em ordem está no [roadmap](roadmap.md).

## Fora de escopo

Distribuir o app de produto, e mudar a divisão toolkit/product.

Publicar no pub.dev **estava** fora de escopo e não está mais: os dez pacotes
estão publicados, e essa passou a ser a rota comum de um consumidor. O canal
assinado continua, para a máquina de release que quer binário AOT e SDK
versionado.
