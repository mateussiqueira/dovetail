# `dovetail.yaml`, chave por chave

Um arquivo, na raiz do projeto. `dovetail init` o escreve deduzindo o que
consegue, e a esteira inteira sai dele.

Este documento é conferido por teste: cada chave que o parser lê tem de
aparecer aqui, e uma chave documentada que o parser não conhece também falha.
Ver `toolkit/dovetail_cli/test/config_documented_test.dart`.

---

## O mínimo que roda

```yaml
identifier: com.example.demo
name: Demo
manufacturer: Example Ltda
targets:
  - darwin-aarch64
  - windows-x86_64
```

**Não existe chave de versão.** Ela mora no `pubspec.yaml` e é lida de lá, sem
o `+build`. Duplicá-la só criaria dois lugares para discordar.

**Nenhuma identidade é escrita aqui**, só o nome da variável de ambiente que a
carrega — e é por isso que este arquivo pode ser commitado.

---

## Identidade

### `identifier`

Nome em domínio reverso: `com.example.demo`. Não é decoração — a **instância
única** e o **deep link** se ancoram nele, e o polkit nomeia o arquivo de
política pelo namespace dele.

`init` o deduz do `AppInfo.xcconfig`, nunca do `RunnerTests` — que é o único
`PRODUCT_BUNDLE_IDENTIFIER` de um `project.pbxproj` recém-criado. Quando as
plataformas declaram identificadores diferentes, ele **delata os dois** em vez
de escolher em silêncio: divergir ali é um defeito.

### `name`

O nome que aparece para quem usa: título de janela, nome do volume do dmg,
entrada no menu. Deduzido do `pubspec.yaml`.

### `manufacturer`

Quem publica. Vai para o MSI (que exige um fabricante), para o campo
`Maintainer` do `.deb`, para o `Vendor` do `.rpm` e para o `vendor` do polkit
quando a seção de serviço não declara o seu.

### `targets`

A matriz de publicação, em pares `sistema-arquitetura`:

```yaml
targets: [darwin-aarch64, darwin-x86_64, windows-x86_64, linux-x86_64]
```

Validado contra **o mesmo vocabulário do manifesto de update**. Chave que o
cliente nunca pede é release que ninguém enxerga, e `darwin-arm64` é
exatamente esse erro: `arm64` é como Apple e WiX escrevem, `aarch64` é como o
protocolo escreve.

No macOS as duas arquiteturas viram **um** bundle universal, publicado sob
`darwin-universal` — a chave que o `releaseFor` resolve quando um cliente pede
`darwin-aarch64`. E alvos de outro sistema são deixados de lado: um host cuja
parte da matriz mora em outro lugar sai 0 sem fazer nada, porque é um runner
sem trabalho e não um erro.

---

## `update`

A seção que faz o `ship` assinar e escrever o manifesto. Sem ela, `ship` para
depois de empacotar.

```yaml
update:
  key: keys/update.key
  password-env: DOVETAIL_UPDATE_KEY_PASSWORD
  base-url: https://cdn.example.com/releases
  manifest: dist/latest.json
  endpoint: https://api.example.com/desktop-version/check/{{target}}
  public-key: |
    untrusted comment: minisign public key D18395BE8A6B994E
    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP
  unencrypted: false
```

### `key`

Caminho da chave privada minisign. `dovetail keygen` a cria e **recusa
sobrescrever um par existente**, porque perder a privada não é perder um
arquivo: é perder o caminho de atualização de toda instalação no campo, e a
recuperação é reinstalar em cada máquina.

Ele avisa quando o destino não está no `.gitignore`.

### `password-env`

O **nome** da variável de ambiente que carrega a senha da chave, nunca a senha.
Variável não exportada é recusa com o nome dela na mensagem — nunca senha vazia
assumida.

### `unencrypted`

`true` para par gerado com `-W`, sem senha. Chave sem senha é aceitável em
desenvolvimento e não em release, e chamar de sem-senha uma chave que tem senha
falha no `minisign` de verdade, alto.

### `base-url`

Onde os artefatos vão ficar. O `release` monta cada URL como
`<base-url>/<versão>/<arquivo>` — então `--artifact chave=caminho` basta, sem
repetir a URL em cada um.

O `ship` **recusa antes do build** quando a seção existe sem `base-url`: gastar
uma compilação inteira para falhar na última etapa é o desperdício que essa
recusa existe para evitar.

### `manifest`

Onde escrever o `latest.json`.

### `endpoint`

Onde o **app instalado** pergunta pelo manifesto — com os placeholders que o
updater resolve (`{{target}}`, `{{arch}}`, `{{current_version}}`). Tem de ser
https. Não é o `base-url`: este é de onde os artefatos são baixados; aquele é
quem responde o `latest.json`. Fica aqui para o `dovetail build` embuti-lo no
app junto com a chave: um build de staging aponta para um host de staging
trocando este arquivo, não o app.

### `public-key`

A pública correspondente, **a chave em si — não um caminho**. É obrigatória
quando há seção `update`. O `dovetail build` a embute no app como
`--dart-define=dovetail.update.public_key` (base64 de uma linha, a forma que o
`keygen` imprime), junto de `dovetail.update.endpoint`, `dovetail.update.base_url`,
`dovetail.identifier` e `dovetail.version` (do `pubspec.yaml`) — e diz o que
embutiu. Um só arquivo decide em quem o app confia, com o que o `release`
assina e o que o `probe` verifica.

Não é caminho de propósito: `keys/` é gitignored, então um caminho apontaria
para um arquivo que não existe num clone, e a checagem que mais importa
dependeria de quem clonou ter a chave. A pública é pública por definição; é a
secreta que fica de fora.

E é obrigatória porque, enquanto não era, ela era a checagem mais fácil de
desligar: bastava não escrever a linha. Foi assim que saiu um release assinado
com a chave de desenvolvimento (`D18395BE8A6B994E`) que o app — compilado para
confiar em outra — recusa. Chave de desenvolvimento com endereço de produção é
a combinação que produz artefato publicável e inútil.

São **duas linhas** — o comentário e a chave —, então no YAML ela vai num
bloco `|`, como no exemplo acima. A alternativa de uma linha só é o base64 que
o Tauri guarda no `tauri.conf.json`, que também é aceito; a chave sozinha, sem
o comentário, **não** é. Na linha de comando, `dovetail release
--public-key <arquivo ou chave>` faz o mesmo papel para quem não tem
`dovetail.yaml`.

---

## `sign`

```yaml
sign:
  macos:
    identity-env: DOVETAIL_MACOS_IDENTITY
    entitlements: macos/Runner/Release.entitlements
    notarize: false
  windows:
    certificate-env: DOVETAIL_WINDOWS_CERTIFICATE
    password-env: DOVETAIL_WINDOWS_CERTIFICATE_PASSWORD
    timestamp-url: http://timestamp.digicert.com
```

Sem credencial, o passo de assinar **diz que o artefato fica sem assinar** e
segue, em vez de fingir — exceto com `notarize: true`, que é declarar release
de verdade: aí o `ship` exige assinatura e notarização, e recusa **antes do
build** o que faltar.

### `sign.macos`

O bloco de assinatura da Apple: `identity-env`, `entitlements` e `notarize`.

#### `macos.identity-env`

Nome da variável com a Developer ID. O `sign` lê essa variável, ou
`APPLE_SIGNING_IDENTITY`, que vale sempre e vence quando as duas existem
(vazia conta como ausente — um secret que não existe no CI vira string vazia).
Sem nenhuma das duas o artefato sai sem assinatura, com o motivo dito em voz
alta.

#### `macos.entitlements`

Caminho do `.entitlements` do app, que o `ship` repassa ao passo de assinatura
do `.app` (nunca ao do `.dmg`: entitlements são do código, não da imagem).
Omitido, o `sign` aplica o plist que o projeto Xcode assina em Release — o
`CODE_SIGN_ENTITLEMENTS` de `macos/Runner.xcodeproj/project.pbxproj`, com
`macos/Runner/Release.entitlements` como reserva — e imprime qual. Isso não é
detalhe: `codesign --force` sem `--entitlements` substitui a assinatura do Xcode
e apaga os entitlements que o build tinha, inclusive o `app-sandbox`; e é o que
remove o `get-task-allow` que o Xcode deixa no Release e que a notarização
recusa. Um bundle com binário aninhado pode precisar de entitlements diferentes
por caminho relativo — para isso existe `sign --entitlements-for`.

#### `macos.notarize`

`true` é declarar release de verdade. O `ship` passa `--require-signature
--notarize` nos **dois** passos do macOS — o `.app` primeiro, para o ticket
ficar grampeado nele (quem arrasta o app da imagem abre um app com ticket,
mesmo offline), e o `.dmg` depois, porque é o que se baixa e o Gatekeeper
avalia ao montar. E recusa **antes do build**, no `--dry-run` inclusive, se a
identidade não está exportada ou nenhum grupo de credenciais está completo:
`APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`, ou `APPLE_API_KEY_ID` +
`APPLE_API_ISSUER` + `APPLE_API_KEY_PATH`. O `doctor` diz o mesmo, como
`missing signing`.

`false`, o que o `init` escreve, mantém o build local: sem credencial, o passo
diz que o artefato fica sem assinar e segue. Num `sign` avulso, `--notarize` sem
credenciais diz que nada foi submetido; com `--require-signature` junto, recusa.

### `sign.windows`

O bloco do Authenticode: `certificate-env`, `password-env` e `timestamp-url`.
As duas variáveis nomeadas alimentam `WINDOWS_CERTIFICATE_FILE` e
`WINDOWS_CERTIFICATE_PASSWORD`, que o signer lê, quando essas não estão
definidas; a `timestamp-url` do yaml vale quando `WINDOWS_TIMESTAMP_URL` não
está. O UpgradeCode do MSI não se configura: é derivado do `identifier` (UUID
v5), estável entre releases — mudar o identifier é mudar de produto, e para o
Windows Installer também.

#### `windows.certificate-env`

Nome da variável com o caminho do `.pfx`/`.p12`. Um certificado em arquivo é
assinado pelo `osslsigncode` em **qualquer** host, Windows inclusive; o
`signtool` só entra quando o certificado está no store da máquina, apontado
por `WINDOWS_CERTIFICATE_THUMBPRINT` sem arquivo nenhum — e essa variável não
tem chave no yaml. A `timestamp-url` do yaml só é aplicada quando há um
certificado para carimbar; sozinha, ela faria um build local sem certificado
ser recusado como meio configurado.

#### `windows.password-env`

Nome da variável com a senha do certificado.

#### `windows.timestamp-url`

Servidor RFC3161. **Não há padrão aqui, de propósito:** assinatura sem
timestamp deixa de valer no dia em que o certificado expira, e escolher um
servidor pelo usuário é escolher de quem ele depende.

---

## `service`

O helper privilegiado. Sem ele não há kill switch, e nenhum pacote o instalava:
a unit systemd, a política polkit e os scripts de manutenção existiam e o
comando que empacota não os alcançava.

```yaml
service:
  name: demo-helper.service
  description: Privileged helper for the tunnel
  exec-start: /usr/lib/demo/demo-helper
  capabilities: [CAP_NET_ADMIN]
  runtime-directory: demo
  state-directory: demo
  logs-directory: demo
  purge-paths: [/var/lib/demo]
  polkit:
    action: com.example.demo.manage
    vendor: Example Ltda
    description: Manage the connection
    message: Authentication is required to change the connection
```

Declarar esta seção **recusa o formato AppImage**: um AppImage não instala
nada, então não há unit, não há helper e não há kill switch — e o que sai não é
produto degradado, é uma janela que não conecta.

### `name`, `description`, `exec-start`

Nome do arquivo da unit, o que aparece no `systemctl status`, e o binário que
sobe.

### `capabilities`

Entram no `CapabilityBoundingSet` **e** no `AmbientCapabilities`. Uma ambiente
fora do bounding set é descartada em silêncio, e o helper sobe sem o privilégio
de que precisa — que é uma falha que só aparece na primeira conexão.

### `runtime-directory`, `state-directory`, `logs-directory`

Viram `RuntimeDirectory=`, `StateDirectory=` e `LogsDirectory=`. O systemd cria
e limpa cada uma com o dono certo, o que é menos código de instalação do que
criá-las à mão.

Cada uma aceita um nome, ou um nome com permissão:

```yaml
service:
  state-directory:
    name: demo
    mode: '0700'
```

O `mode` é `0750` quando não é dito. Caminho **absoluto** aqui é recusado: o
systemd lê estes nomes como relativos a `/run`, `/var/lib` e `/var/log`, então
um absoluto é um diretório que nada cria.

### `purge-paths`

O que o `postrm --purge` do `.deb` e o `%postun` do `.rpm` apagam. Desinstalar
sem purgar deixa o estado; purgar tem de apagar, e apagar caminho não declarado
é o que ninguém quer que um desinstalador faça.

### `service.polkit`

A política de autorização. Sem ela o helper existe e nada pode pedir que ele
aja — `action`, `vendor`, `description` e `message`.

#### `polkit.action`

A ação tem de estar **dentro do namespace do `identifier`**, porque o polkit
nomeia o arquivo pelo namespace e **ignora ação declarada fora dele** — o que
falha como "pediu senha e não fez nada".

#### `polkit.vendor`, `polkit.description`, `polkit.message`

Quem assina a política, o rótulo da ação, e a frase que o diálogo de
autenticação mostra. `message` é o texto que a pessoa lê antes de digitar a
senha de administrador; vale escrevê-lo.

---

## O que o `init` deduz, e o que ele não inventa

Ele lê os diretórios `macos/`, `windows/` e `linux/` que existem para montar
`targets`, o `AppInfo.xcconfig` para o `identifier`, e o `pubspec.yaml` para o
`name`. Não inventa `update`, `sign` nem `service`: as três dependem de decisão
— onde a chave mora, de quem é o certificado, se existe helper — e um valor
inventado ali é pior que um campo ausente.
