# dovetail_cli

Um ponto de entrada para o toolkit. O que existia lá fora eram peças soltas —
`window_manager`, `tray_manager`, `hotkey_manager`, `auto_updater`, Fastforge —
cada uma de um autor, cada uma com a sua configuração. O que o Tauri tem e o
Flutter não tinha é o **arquivo único** e o CLI que lê ele.

## `ship`: a esteira inteira, a partir da config

```bash
dovetail ship --dry-run
```

```
→ build macos
→ sign darwin-universal
→ bundle darwin-universal
→ sign dmg darwin-universal
→ archive darwin-universal
→ release 4.2.0
```

O plano é **dado**, não execução — é por isso que o `--dry-run` sai de graça e
o comando é testável sem tocar em toolchain nenhuma. Os testes do plano não
chamam o Flutter, o `wixl` nem o `codesign`. E o que o plano já sabe que o
último passo vai recusar — `update.public-key` ausente, `notarize: true` sem
identidade ou credenciais exportadas — ele recusa antes do build, no `--dry-run`
inclusive.

Três decisões que ele toma e vale conhecer. No macOS as arquiteturas declaradas
viram **um** bundle universal, publicado sob `darwin-universal` — a chave que o
`releaseFor` resolve quando um cliente pede `darwin-aarch64`. No Linux e no
Windows é um pacote por arquitetura, porque um `.deb` carrega uma só.

E no macOS são **duas assinaturas**: o `.app` antes de empacotar, porque um dmg
que embrulha um `.app` não assinado não fica assinado por assinar o dmg
depois; e o `.dmg` depois de montado, porque é ele que o usuário baixa e o
Gatekeeper avalia — e é ele que se notariza. No Windows e no Linux o que se
assina é o instalador, então o bundle vem primeiro.

O nome de cada artefato não é adivinhado: o plano pergunta ao bundler que vai
escrevê-lo. Enquanto ele adivinhava, o dmg saía
`app_1.0.0_universal.dmg` e o manifesto apontava para `app_1.0.0.dmg` — um
arquivo que não existia.

Alvos de outro sistema são deixados de lado. Um host cuja parte da matriz mora
em outro lugar sai 0 sem fazer nada, porque é um runner sem trabalho nesta
rodada e não um erro.

Escrever isso pegou cinco defeitos meus, e vale dizer como cada um apareceu.
Dois pelo `--dry-run`, antes de qualquer coisa rodar: o macOS empacotava duas
vezes para o mesmo arquivo de saída, e a arquitetura ia na grafia do fio
(`aarch64`) onde o `bundle` só aceita a da Apple (`arm64`). Três só rodando de
verdade no app deste repositório: o `app-dir` apontava para o diretório acima
do `.app`, a assinatura vinha depois do dmg, e o nome previsto não era o nome
que o bundler escrevia.

## Instalar nesta máquina

```bash
tool/build_release.sh --install
```

Compila e deixa o binário em `~/.local/bin`, avisando se o diretório não
estiver no `PATH`. Um caminho diferente vai como segundo argumento.

```bash
$ dovetail --version
dovetail 0.1.0 (macos-arm64, dart 3.12.2)
```

Nada disso pede notarização nem passa pelo Gatekeeper: um binário compilado
localmente não chega em quarentena. Isso só volta a importar quando o arquivo
vier pela rede.

## Distribuição: um binário, sem fonte

O CLI compila para um executável nativo autocontido. `tool/build_release.sh`
produz o binário, o tarball e o SHA256, e recusa publicar se o binário não
reportar a versão que o `pubspec.yaml` declara.

```bash
tool/build_release.sh dist
```

O que o binário carrega compilado: `dovetail_bundler`, `dovetail_signer`,
`dovetail_updater`, `dovetail_process_runner` e o próprio CLI — como código de máquina.
Não há fonte Dart recuperável dele. Literais de string ficam, como em qualquer
compilação AOT: nomes de ferramenta, mensagens de erro e os fragmentos de
template `.wxs` e `.nsi`. Esses fragmentos são a saída do comando de qualquer
jeito, então não são segredo que o binário guarde.

`tool/dovetail.rb` é a fórmula Homebrew. Ela existe porque metade do problema
de instalar não é o binário: é o `minisign`, o `msitools`, o `osslsigncode` e o
`rpm` que o CLI invoca. A fórmula os declara como dependência e o `caveats`
nomeia os dois que ela deliberadamente não instala — o `flutter`, que você já
tem, e o `makensis`, que só faz falta se você quiser o instalador NSIS além do
MSI.

**O que o binário não cobre.** Os pacotes de runtime —
`dovetail_platform_channel`, `dovetail_shortcut_channel`, `dovetail_updater` e o
guarda-chuva `dovetail` — são compilados *dentro* do app de quem consome. O
Dart não tem formato binário para dependência de pub: um pacote sem
`lib/*.dart` não pode ser importado. Quem usar a janela, a bandeja, o painel ou
o atalho precisa da fonte desses pacotes; quem usar só a esteira de build,
empacotamento, assinatura e publicação não precisa de nenhuma.

## O canal de release e o instalador

O runtime viaja num SDK versionado, servido por um canal:

```
<base>/latest                                           → a versão mais nova
<base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz
<base>/<versão>/dovetail-sdk-<versão>-<os>-<arch>.tar.gz.sha256
```

O caminho curl|sh é o `tool/sdk/install.sh`:

```bash
curl -fsSL https://<host>/install.sh | sh
```

E o mesmo trabalho existe de dentro do binário, para quem já o tem:

```bash
dovetail self-install --base-url https://<host>   # instala o SDK da versão do binário
dovetail self-update  --base-url https://<host>   # troca para o latest do canal
```

A base vem de `--base-url` ou de `DOVETAIL_INSTALL_URL`; sem os dois o comando
recusa nomeando os dois — um instalador que adivinha o host instala o que o
host decidir. O download passa por TLS (o fetcher do updater recusa http) e o
tarball é conferido contra o `.sha256` publicado **antes** de um byte tocar o
disco. O `self-update` instala a versão nova **ao lado** da antiga e troca o
binário: `sdk/<antiga>` fica no lugar, e um app cujo `pubspec_overrides.yaml`
aponta para ela continua resolvendo — é por isso que o SDK é versionado por
diretório e não sobrescrito. Um `latest` igual ou mais velho é saída 0 sem
tocar nada, nunca um downgrade. O `doctor` reporta o que vê: versão instalada,
e quando ela discorda da do binário, qual comando fecha a distância.

## dovetail.yaml

`dovetail init` lê o projeto e escreve o arquivo; ele não pergunta nada que
consiga descobrir sozinho.

```bash
dovetail init
```

Ele deduz os alvos dos diretórios `macos/`, `windows/` e `linux/` que existem,
o identificador do `AppInfo.xcconfig` (nunca do `RunnerTests`, que é o único
`PRODUCT_BUNDLE_IDENTIFIER` de um `project.pbxproj` recém-criado), e o nome do
`pubspec.yaml`. Quando as plataformas declaram identificadores diferentes ele
delata os dois em vez de escolher em silêncio — a instância única e o deep link
se ancoram nesse nome, então divergir ali é um defeito.

Se o `dovetail.yaml` já existe, o comando recusa; `--force` sobrescreve,
descartando o que foi configurado à mão — por isso não é o padrão.

```yaml
identifier: com.example.demo
name: Demo

targets:
  - darwin-aarch64
  - linux-x86_64

update:
  key: keys/update.key
  password-env: DOVETAIL_UPDATE_KEY_PASSWORD
  base-url: https://cdn.example.com/releases
  public-key: |
    untrusted comment: minisign public key D18395BE8A6B994E
    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP
  manifest: dist/latest.json

sign:
  macos:
    identity-env: DOVETAIL_MACOS_IDENTITY
    notarize: false
  windows:
    certificate-env: DOVETAIL_WINDOWS_CERTIFICATE
    timestamp-url: http://timestamp.digicert.com
```

**Não há campo de versão.** Ela mora no `pubspec.yaml` e é lida de lá, sem o
`+build`. Duplicá-la só criaria dois lugares para discordar.

**Nenhuma identidade é escrita aqui**, só o nome da variável que a carrega —
por isso o arquivo pode ser commitado.

Um `targets` é validado contra o mesmo vocabulário do manifesto de update. Uma
chave que o cliente nunca pede é um release que ninguém enxerga, e `darwin-arm64`
é exatamente esse erro: `arm64` é como Apple e WiX escrevem, `aarch64` é como o
protocolo escreve.

### O runtime pelo SDK instalado

Fora do monorepo o runtime não tem `path: ../` para onde apontar: ele vem de um
SDK instalado em `~/.dovetail/sdk/<versão>/packages` (ou `$DOVETAIL_HOME`,
quando definido).

```bash
dovetail init --sdk
```

A flag escreve um `pubspec_overrides.yaml` no app, cada pacote do runtime
apontado para a cópia do SDK — o mecanismo nativo do Dart para resolver fora
do pubspec, o mesmo que o Flutter SDK usa para entregar os pacotes dele. A
versão preferida é a do próprio binário; quando ela não está instalada, a mais
recente serve. Sem SDK instalado o comando recusa **antes de escrever nada**, e
a mensagem nomeia o instalador. Os caminhos são locais, então o arquivo de
overrides não é para versionar. O modelo completo — instalação, ciclo de
versão e o `bridge` — está em [docs/instalador.md](../../docs/instalador.md).

## `upgrade`: o ciclo de versão do consumidor

O `self-update` troca o SDK instalado sem mover os apps: cada app carrega um
`pubspec_overrides.yaml` cujos `path` apontam para `sdk/<versão>/packages`, e a
versão antiga fica no disco para quem ainda a usa. O `upgrade` é o comando que
re-aponta esse arquivo para o SDK preferido:

```bash
dovetail upgrade
```

Sem um `pubspec.yaml` no diretório ele recusa, porque o override pertence a um
projeto. O `doctor` reporta a discordância quando vê um app cujo override
aponta para uma versão mais velha que a instalada — e o `upgrade` é quem fecha
a distância.

## `update`: o ciclo de versão num comando só

O `self-update` troca o SDK e o `upgrade` re-aponta o app — dois comandos que
andam juntos em todo ciclo de versão. O `update` colapsa os dois: troca o SDK
para o latest do canal e, quando o app é dado, re-aponta o
`pubspec_overrides.yaml` dele:

```bash
dovetail update --base-url https://<host>                # só o SDK
dovetail update --base-url https://<host> --root app     # SDK + app
```

Sem `--root` só o SDK muda, e re-apontar o app fica para um `upgrade`
posterior. Com `--root` apontando para um diretório sem `pubspec.yaml` ele pula
o re-apontar com um aviso, em vez de quebrar — o override pertence a um
projeto. Já estar no latest é saída 0 sem tocar nada, nunca um downgrade, e sem
SDK nenhum no disco para onde o app possa apontar, ele recusa nomeando o
`self-install`.

## O serviço privilegiado

Um VPN não conecta sem o helper privilegiado, e nenhum pacote o instalava: a
unit systemd, a política polkit e os scripts de manutenção existiam e o comando
que empacota não os alcançava. Agora eles vêm da config.

```yaml
service:
  name: demo-helper.service
  description: Privileged helper for the tunnel
  exec-start: /usr/lib/demo/demo-helper
  capabilities: [CAP_NET_ADMIN]
  runtime-directory: demo
  purge-paths: [/var/lib/demo]
  polkit:
    action: com.example.demo.manage
    vendor: Example Ltda
    description: Manage the connection
    message: Authentication is required to change the connection
```

As capacidades entram no `CapabilityBoundingSet` **e** no
`AmbientCapabilities` — uma ambiente fora do bounding set é descartada em
silêncio, e o helper sobe sem o privilégio de que precisa. A ação polkit tem
que estar dentro do namespace do `identifier`, porque o polkit nomeia o arquivo
pelo namespace e ignora ação declarada fora dele.

## Com a config no lugar

```bash
dovetail doctor
dovetail release --artifact "darwin-aarch64=dist/Demo.dmg"
```

O `doctor` sem `--target` percorre **todos** os alvos declarados, um relatório
por alvo, e sai 1 se alguma ferramenta está presente mas quebrada — pior que
ausente, porque um build reporta sucesso que não ganhou.

O `release` tira do arquivo a versão, a chave, a variável de senha, o destino do
manifesto e a URL de cada artefato (`<base-url>/<versão>/<arquivo>`), e recusa
uma chave de plataforma que não esteja em `targets`. A forma longa
`platformKey=url=path` continua valendo para quando a URL não segue o padrão —
inclusive com query string, que a forma antiga truncava no primeiro `=`.

## Instalação

```yaml
dependencies:
  dovetail_cli:
    path: ../dovetail_cli
```

```bash
dart run bin/dovetail.dart --help
```

## A esteira, na ordem em que roda

```
init      lê o projeto e escreve o dovetail.yaml que os outros leem
new       cria o projeto do zero, já ligado ao dovetail
ship      a esteira inteira, a partir da config
doctor    esta máquina consegue construir para esse par de SO e arquitetura?
dev       a ponte nunca fica para trás — vigia e regenera
bridge    gera o plugin ffiPlugin que fala com o núcleo Rust do produto
build     compila o que este host pode compilar, e recusa alto o que não pode
icon      de um PNG saem .ico, .icns e os PNGs do tema do Linux
bundle    nsis | msi | dmg | deb | rpm — nunca assina nada
sign      codesign e notarização, ou Authenticode — nunca empacota nada
keygen    gera o par minisign e imprime a chave pública
release   assina cada artefato e escreve o manifesto que aponta para eles
inspect   o que o arquivo é, não o que o nome dele diz
manifest  o manifesto sozinho, quando a assinatura já existe
probe     pergunta ao endpoint se ele serve o que o cliente lê
self-install  instala o runtime do SDK ao lado do binário, do canal de release
self-update   troca o SDK para o latest do canal, mantendo a versão que os apps apontam
update        troca o SDK para o latest e re-aponta o app, num comando só
upgrade       re-aponta o pubspec_overrides.yaml do app para o SDK instalado
```

A separação entre `bundle` e `sign` não é organizacional: assinatura acontece
**depois** do build e nunca dentro dele. Um build que assina é um build que não
se pode reproduzir sem a chave.

## `doctor` pergunta se a ferramenta funciona

Não se ela está no `PATH`. Cada sonda entrega ao binário real uma entrada
trivial real e confere a saída real: o `makensis` compila um script de quatro
linhas e tem que produzir o `.exe`; o `ditto` copia um arquivo e tem que
produzir a cópia; o `codesign` lê o `/bin/ls`.

Sem `--target` ele percorre todos os alvos do `dovetail.yaml`. Com, ele
pergunta por um só:

```bash
dovetail doctor --target windows --arch arm64
```

```
target: windows/arm64
missing  aarch64-pc-windows-msvc  rustup target add aarch64-pc-windows-msvc
broken   makensis  libc++abi: terminating due to uncaught exception of type std::bad_alloc
missing  wix  compiles the MSI, when one is asked for
broken   signtool  You must specify a key with which to sign.
```

Uma ferramenta presente e quebrada sai como `broken`, com o texto de erro dela, e
o comando termina em 1 — porque um build que reporta sucesso que não mereceu é
pior do que um build que falha.

Isso não é hipotético: nesta máquina o `makensis` do Homebrew aborta com
`std::bad_alloc` num script de quatro linhas, e existe um `signtool` que não é o
do Windows no `PATH`. Uma sonda de presença chama os dois de prontos.

## `bundle` não precisa de Windows para empacotar Windows

O WiX faz P/Invoke em `msi.dll`, que é a biblioteca do Windows Installer —
por isso a documentação do Tauri diz que **um MSI só pode ser criado no
Windows**. Isso vale para o WiX, não para o formato: o `wixl`, do `msitools`,
escreve o banco MSI diretamente.

```bash
brew install msitools
dovetail bundle --target windows --arch x86_64 --windows-format msi \
  --upgrade-code 3F2504E0-4F89-11D3-9A0C-0305E82C3301 ...
```

`MsiBackend.forHost` escolhe: `wix` no Windows, `wixl` em qualquer outro lugar.
O dialeto muda junto — o `wixl` lê o esquema v3 (`<Product>`), e o WiX v4 lê o
seu próprio. Provado aqui: o MSI sai com o cabeçalho OLE2, o `msiinfo` lê nome,
fabricante e versão, e o `msiextract` tira do CAB embutido cada arquivo que foi
preparado.

## `doctor` relata o projeto antes das ferramentas

Sem `--target`, ele responde primeiro se o projeto está pronto — e distingue o
que **falta** do que só **não foi configurado**:

```
project
  ok       identifier  com.acme.client
  ok       name  Acme Client by Acme Ltda
  ok       version  1.2.0  (from pubspec)
  ok       targets  darwin-x86_64, darwin-aarch64 on this host of 4
  off      update  keys/update.key — no base-url, so every artefact needs its url spelled out
  ok       signing  DOVETAIL_MACOS_IDENTITY, not notarised
  off      service  no privileged helper is installed by the linux packages
```

A distinção é o ponto. Um host que não constrói nenhum dos alvos declarados sai
`off`, não `missing` — é um runner cuja parte da matriz mora em outro lugar, e
chamar isso de erro derrubaria um job de CI que está correto. O que sai
`missing` é o que impede publicar: config ausente, ou um `pubspec` sem versão.

## `sign` não precisa de Windows para assinar Windows

O `signtool` vem com o SDK do Windows e não existe em outro lugar — o que
responde por esse nome num Mac é o assinador de JAR do `nss`. O caminho
multiplataforma é o `osslsigncode`, e é o que o comando usa em qualquer host
que não seja Windows.

```bash
dovetail sign --target windows \
  --file dist/setup.exe \
  --certificate keys/publisher.pem \
  --private-key keys/publisher.key \
  --timestamp-url http://timestamp.digicert.com
```

As flags sobrepõem o ambiente; sem elas ele lê `WINDOWS_CERTIFICATE_FILE`,
`WINDOWS_PRIVATE_KEY_FILE` e `WINDOWS_TIMESTAMP_URL`. Um PKCS#12 entra pelo
`--certificate` sem `--private-key`, e aí a senha vem de
`WINDOWS_CERTIFICATE_PASSWORD` — vazia nunca é assumida, porque o
`osslsigncode` pergunta no terminal e uma pergunta numa esteira é um build que
trava em vez de falhar.

No Windows, com um `WINDOWS_CERTIFICATE_THUMBPRINT`, ele continua usando o
`signtool` de verdade contra o certificado que está na loja.

## `sign --entitlements-for` para o que está aninhado

Um helper privilegiado, uma Network Extension ou um login item dentro do bundle
precisam das próprias entitlements. Dar a do app é como um daemon acaba com o
sandbox do app.

```bash
dovetail sign --target macos --bundle build/Example.app \
  --entitlements macos/Release.entitlements \
  --entitlements-for "Contents/Helpers/daemon=macos/Daemon.entitlements"
```

## `build` conhece o teto

Assinar e empacotar podem ser centralizados numa máquina; **compilar não**. O
Flutter recusa na origem: `"build windows" only supported on Windows hosts`.
Nenhuma ferramenta nossa contorna isso, e o `build` recusa antes de invocar o
Flutter, dizendo qual passo precisa de outra máquina em vez de deixar o erro
aparecer no meio do build.

```bash
dovetail build
```

Sem `--target`, ele olha os alvos do `dovetail.yaml` e constrói o que este host
alcança. Um host cuja parte da matriz está em outro lugar sai 0 sem fazer nada
— não é erro, é um runner sem trabalho nesta rodada.

## `icon` nunca aumenta

De um PNG quadrado de 512px ou mais saem sete tamanhos no `.ico`, nove entradas
no `.icns` e oito PNGs no tema do Linux. Os dois contêineres são escritos em Dart
puro, sem ferramenta externa.

```bash
dovetail icon --source brand/icon.png --out build/icons --app-id io.exemplo.cliente
```

Quatro recusas, e cada uma existe porque a falha é silenciosa em vez de alta: um
arquivo que não é PNG, uma fonte não quadrada (as duas plataformas esticam em vez
de recusar), uma fonte abaixo de 512px (aumentar dá ícone borrado que nenhum
revisor rejeita e todo usuário vê), e pedir os ícones do tema sem `--app-id` —
sem ele os arquivos entram com um nome que o `.desktop` não aponta, e o launcher
não mostra ícone nenhum.

## `inspect` lê o arquivo, não o nome

```bash
dovetail inspect dist/*.dmg dist/*.exe dist/*.deb
```

Para um bundle macOS ou um Mach-O reporta as arquiteturas presentes, o estado da
assinatura e — o motivo do comando — se a arquitetura no **nome** concorda com o
**conteúdo**. Discordância sai com 1: um artefato cujo nome mente é pior do que
um que falha ao construir, porque ele sobe.

Um bundle onde parte dos binários é gorda e parte é magra sai como universal
**só em parte**, com o aviso de que não vai abrir em todo Mac onde instalar.
Para `.deb`, `.rpm`, `.msi` e `.exe` ele diz que **só leu o nome**, para que uma
linha que passou nunca seja confundida com uma linha verificada.

## `keygen` recusa sobrescrever

```bash
dovetail keygen --out keys/update.key
```

Gera o par minisign e imprime a chave pública **na forma que o manifesto
carrega**, para colar direto na config. Recusa quando já existe um par no
destino: perder a privada de update não é perder um arquivo, é perder o caminho
de atualização de toda instalação no campo, e a recuperação é reinstalar em cada
máquina. Avisa também quando o destino não está no `.gitignore`.

## `manifest` para quando a assinatura já existe

```bash
dovetail manifest --version 2.1.0 \
  --release darwin-universal=https://cdn/app.tar.gz=dist/app.tar.gz.minisig \
  --out dist/latest.json
```

O `release` assina e escreve o manifesto num passo só; o `manifest` é o passo de
escrever sozinho, para quando as assinaturas vieram de outro lugar — de um HSM,
ou de uma máquina que guarda a chave e não roda a esteira.

Ele embute o **conteúdo** do `.minisig`, nunca o caminho: um caminho ali seria
silenciosamente inverificável na máquina de quem baixa.

## `probe` pergunta ao endpoint se ele serve

```bash
dovetail probe --url https://api.exemplo.com/manifest/darwin \
  --public-key keys/update.pub --installed 1.0.0 --download
```

O formato do manifesto está em código, em teste e em prosa, e nada disso diz a
quem escreve o servidor se o que subiu funciona. Este comando diz — de fora,
pela rede, com o **mesmo** `ManifestParser`, a mesma `UpdatePolicy` e o mesmo
verificador minisign que o app carrega.

Ele decodifica base64 **antes** de parsear, sem alternativa, porque é o que um
cliente no campo faz: aceitar as duas formas é o que deixa uma release sair na
forma que ninguém lê. Com `--public-key` confere o key id, e recusa `--download`
sem chave, porque verificar um artefato contra a chave que o assinou só prova
que os dois vieram do mesmo lugar.

Sai 0 só quando todos os alvos passam. Sem `--target` ele pergunta pelos três
que o produto publica, então um endpoint que serve um e quinhentos os outros
dois diz isso sem ninguém precisar pedir.

## `new`: um projeto que já consome a biblioteca

```bash
dovetail new demo
cd demo && flutter pub get && flutter test && dovetail doctor
```

O `init` lê um projeto que já existe e escreve o `dovetail.yaml`. O `new` faz
o caminho inverso: cria o projeto do zero, já com a biblioteca dovetail
ligada. Ele escreve um `pubspec.yaml` com a dependência de caminho, um
`lib/main.dart`, um teste de widget e um `dovetail.yaml` com os padrões que o
`doctor` aceita — o mesmo `ConfigTemplate` que o `init` usa.

O que o `new` gera é o projeto desktop completo, montado a partir do template
do SDK (`tool/sdk/templates/app`), e não um `lib/main.dart` solto:

```
demo/
├── lib/               clean-arch (o refinamento do Manguinho que o time
│   ├── data/            mobile usa): data → domain → infra → presentation
│   ├── domain/          → main, com presenters em interface + impl
│   ├── infra/           change_notifier_*, DI e rotas pelo weave_di
│   ├── main/            (repo privado, pinado em v3.3.0)
│   ├── presentation/
│   └── shared/
├── core/              o núcleo Rust (crate <nome>_core, fachada CoreHandle)
├── core_bridge/       o plugin FFI que repassa o núcleo, do mesmo template
│                       que o `bridge init` usa — com um repasse de exemplo e
│                       o portão de cobertura que recusa núcleo crescido sem
│                       repasse
├── scripts/checks/    as duas suites de conformidade do time, adaptadas:
│   ├── flutter/         a do mobile (camadas, nomenclatura, Weave, tamanho),
│   └── rust/            a do desktop (comentários, inglês, tamanho, URLs)
├── .githooks/         pre-commit e pre-push rodando o gate
├── run_app.sh         gate das duas suites + flutter run -d macos
└── Makefile           quality, codegen, tests, run, hooks, build
```

O laço do dia a dia no projeto gerado: `make codegen` regenera a ponte quando
o núcleo cresce (o Dart gerado não é versionado), `make quality` roda as duas
suites, e `./run_app.sh` se recusa a subir o app se o gate reprovar.

O caminho para a biblioteca é calculado sozinho, nesta ordem: dentro do
repositório ele sobe até achar `toolkit/dovetail/lib/dovetail.dart` e grava o
caminho relativo a partir do projeto novo; fora dele — o caso do binário
compilado, que não tem repo — ele aponta para o SDK instalado, em caminho
absoluto. `--dovetail-path` sobrescreve qualquer um dos dois, e sem nenhuma
das três fontes o comando recusa nomeando-as, porque um scaffold cujo path
aponta para lugar nenhum mente no primeiro `flutter pub get`. O teste de
widget que o `new` escreve exercita de verdade o runtime do próprio dovetail —
um smoke que só renderiza o app provaria o Flutter, não o SDK que o scaffold
prometeu ligar.

O `weave_di` — DI e rotas do template — resolve pela mesma regra, e por um
motivo que vale escrever: ele era uma dependência `git` com a url
`git@weave-di.github.com:`, um **alias de SSH** que existe no `~/.ssh/config`
de uma máquina só. Todo projeto que este comando gerou herdava isso, então o
primeiro `flutter pub get` de qualquer outra pessoa morria num host que o DNS
não resolve. O repositório é privado, então a url https também não salvaria
quem está de fora: o caminho certo é o mesmo dos outros pacotes do runtime —
viajar dentro do SDK. A ordem é `--weave-path`, depois `$DOVETAIL_WEAVE_PATH`,
depois o SDK instalado; sem nenhuma das três o comando recusa **antes de
escrever qualquer byte**, porque scaffold pela metade é pior do que nenhum. Um
caminho que existe mas não tem `pubspec.yaml` conta como ausente, e uma
variável exportada vazia também — as duas produziriam um `path:` que só falha
lá na frente.

Nenhum `pubspec.yaml` que este comando escreve carrega `git:` — há teste
prendendo isso.

O template do app resolve como o do bridge: `--template` explícito, depois o
SDK instalado (`sdk/<versão>/templates/app`), depois o repo. Sem nenhum, o
comando recusa nomeando as fontes — e o bridge vem do mesmo lugar, porque
template e `dovetail_rust_core` têm que casar.

O nome vem do diretório, ou de `--name`, e precisa começar com letra e conter
só letras, dígitos e sublinhados. O identificador padrão é
`com.example.<nome>`, trocável com `--identifier`. Um diretório que já existe
faz o comando recusar em vez de sobrescrever.

O `dovetail new --sdk` resolve o runtime do SDK instalado via
`pubspec_overrides.yaml`, em vez de um `path` no pubspec.

## Desenvolvimento

```bash
dart test
```

```bash
dart analyze
```

## `bridge`: o plugin que fala com o núcleo

```bash
dovetail bridge init --core <crate> --name <nome> [--out dir] [--template dir]
```

Gera o plugin `ffiPlugin` (Windows/macOS/Linux) que repassa o núcleo Rust de
um produto para o Flutter — o mecanismo do qual o `product/desktop_core_bridge`
é o fixture, reproduzido pelo template do SDK. O `--core` é o diretório do
crate (o que segura o `Cargo.toml` dele), e o comando lê o nome real do crate
do manifesto em vez de adivinhar. O `dovetail_rust_core` entra do SDK instalado — o
template e o runtime vêm do mesmo lugar, senão o gerado aponta para um e
resolve outro.

O template entrega a mecânica, não o conteúdo: `rust/src/api/` sai vazio (os
repasses são do produto), `lib/src/rust/` é gerado pelo codegen, e o
`example/` não existe. O laço do gerado é o mesmo do fixture:

```bash
flutter_rust_bridge_codegen generate
cd rust && cargo check
flutter test test/core_coverage_test.dart
```

O último é o portão de forma que o template carrega: lê o `handle.rs` do crate
e as chamadas em `rust/src/api/`, e recusa quando o núcleo cresceu um método
que nenhum repasse expõe. Sem template nenhum — nem `--template`, nem SDK
instalado — o comando recusa nomeando o instalador.

## `dev`: a ponte nunca fica para trás

A armadilha está em dois documentos deste repo: você escreve um método em
Rust, tudo compila, e ele **não existe do lado Dart** — sem erro em lugar
nenhum, até o `verify frb` gritar. O `dev` faz a ponte falar antes:

```bash
dovetail dev            # recusa se o Dart está atrás (nomeando o método); senão vigia e regenera
dovetail dev --check    # só o veredito, sem vigiar
dovetail dev --once     # regenera agora e diz o que entrou
```

Ele roda dentro de um package que tem `flutter_rust_bridge.yaml` (ou com
`--root` apontando para ele). O check gera num diretório temporário com o
codegen real e compara os `debugName` — nunca parseia Rust na mão — então a
recusa nomeia exatamente o método que o Dart não tem, e a árvore fica
intocada.

## O que não dá para provar nesta máquina

O `bundle --target windows` e o `--windows-format msi` nunca rodaram: o
`makensis` local está quebrado e o `wix` não está instalado. O `sign --target
windows` nunca assinou nada, porque não há certificado nem `signtool` de
verdade aqui.

O que está provado é a composição: o manifesto que o `release` escreve é lido de
volta e verificado pelo `dovetail_updater`, e o `doctor` reporta os seis alvos
desta máquina com o resultado real de cada sonda.
