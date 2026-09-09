**Português** · [English](../problemas.md)

# Quando algo dá errado

Cada item aqui aconteceu de verdade neste projeto, e está escrito pela
**mensagem que você vai ver** — não pela causa, que é o que você ainda não
sabe.

---

## Escrevi um método em Rust e ele não existe no Dart

Nenhuma mensagem. `cargo check` passa, o app compila, os testes passam, e
`core.novaCoisa()` simplesmente não existe.

O Dart em `core_bridge/lib/src/rust/` é **gerado**, e nada avisa quando ele
ficou atrás.

```bash
make codegen          # regenera a ponte a partir do Rust
```

Para não cair de novo, deixe o vigia rodando enquanto mexe em Rust:

```bash
dovetail dev          # regenera a cada .rs salvo; --check só confere e sai
```

E a rede que pega isso sem ninguém lembrar: `make tests` roda também o
`core_bridge/test/core_coverage_test.dart`, que compara os métodos públicos do
núcleo com os que chegaram ao Dart e falha nomeando o que falta.

---

## Erro sobre hash de conteúdo, ou a ponte que funcionava e parou

Se a mensagem fala de *content hash* ou de versão do codegen, o CLI que gerou o
código e a runtime que o executa são versões diferentes. O CLI é global, a
runtime é pinada no `Cargo.toml`, e nada os mantinha juntos.

```bash
flutter_rust_bridge_codegen --version              # o CLI que gera
grep flutter_rust_bridge core_bridge/rust/Cargo.toml   # a runtime pinada
cargo install flutter_rust_bridge_codegen --version <a do Cargo.toml>
```

*(No monorepo do dovetail, `dart tool/verify.dart frb` faz essa comparação e
diz qual está fora — mas esse comando só existe lá.)*

Conserte a ferramenta, **não o pin**. E se você regenerou com o CLI errado e
commitou, o código quebra na máquina de todos os outros — não na sua.

---

## `Failed to load dynamic library` com dez caminhos listados

```
Invalid argument(s): Failed to lookup symbol ...
dlopen(desktop_core_bridge.framework/desktop_core_bridge, 0x0001): tried: ...
```

O carregador procura o framework pelo **stem do nome do crate**. Um crate
chamado diferente do plugin produz um carregador procurando um framework que
não existe: os símbolos ficam linkados e **inalcançáveis**, e é por isso que a
lista de caminhos parece toda errada.

O nome do crate em `core_bridge/rust/Cargo.toml` tem de ser o nome do plugin
— `dovetail new` já os deixa iguais, e é renomeando um dos dois à mão que se
cai aqui. A regra e o porquê estão no README do bridge gerado.

---

## `MissingPluginException` ao subir o canal de plataforma

```
MissingPluginException(No implementation found for method ensureInitialized
on channel window_manager)
```

Dois casos, com a mesma cara.

**Em `flutter test`, em qualquer sistema.** Não há lado nativo num teste de
widget, então a primeira chamada de `DesktopPlatformChannel.ensureInitialized`
— que vai ao `window_manager` — não encontra ninguém. Não é defeito: é um teste
que quer a janela de verdade. Quem testa código que depende do canal injeta o
dublê (o `DesktopPlatform` é uma interface) em vez de chamar
`ensureInitialized`; e o dovetail agora relança esse erro nomeando o canal e
dizendo isto, em vez de deixar o texto cru do `window_manager` chegar a quem
não sabe o que ele é.

**Rodando o app, num sistema só.** Aí um plugin da árvore de dependências não
tem implementação para aquele desktop. O dovetail em si só depende de plugins
com os três; o que costuma trazer um sem é uma dependência do **seu** app — um
pacote de UI que exporta um widget de câmera, por exemplo. O caminho é o
`pubspec.lock`: procure o plugin que a mensagem nomeia e veja quem o trouxe. A
correção não é no dovetail.

*(No monorepo do dovetail, `dart tool/verify.dart cross` lista todo plugin sem
implementação em algum dos três desktops — mas esse comando só existe lá.)*

---

## O app abre num Mac antigo e morre sem dizer nada

Sintoma: a janela pisca, ou o app fecha, ou reclama de um símbolo ausente.

`LSMinimumSystemVersion` é a única coisa que impede o sistema de abrir um
binário que ele não roda. Sem a chave, o macOS tenta.

O `dovetail bundle` recusa um `.app` que não a declare, recusa uma que ficou
`$(MACOSX_DEPLOYMENT_TARGET)` **sem expandir** (que o macOS lê como versão
nenhuma), e recusa uma que discorde do que a release declara.

**Vindo do Tauri, confira o número.** O template do Flutter escreve `10.15` e
ninguém o escolheu; o `tauri.conf.json` pode declarar outro, escolhido de
propósito — neste produto, `13.0`, porque o caminho de instalação do helper no
macOS passa por `SMAppService`, que existe a partir do 13.

---

## `signtool` assinou o instalador e o Windows reclama dos binários

O instalador passa, e os executáveis que ele deposita não têm assinatura.

Isso era defeito da esteira e foi corrigido: no Windows, `ship` faz **duas**
assinaturas — `sign --directory` sobre o payload **antes** do `bundle`, e
`sign --file` sobre o instalador depois. Assinando à mão, a ordem é sua:

```bash
dovetail sign --target windows --directory build/windows/x64/runner/Release
dovetail bundle --target windows ...
dovetail sign --target windows --file dist/app_1.0.0_x64_setup.exe
```

---

## `pkexec` saiu com 126 ou 127

126 é o diálogo de autorização **dispensado**. 127 é o diálogo que **não pôde
ser mostrado** — o que acontece por ssh sem barramento de sessão.

Nos dois casos nada foi substituído, e a mensagem do `LinuxInstaller` diz qual
dos dois foi.

---

## `dovetail bundle --linux-format appimage` foi recusado

```
this project declares a service (demo-helper.service), and an AppImage
cannot install one.
```

Um AppImage roda de um arquivo em vez de instalar: sem unit systemd, sem helper
privilegiado, sem kill switch. As três rotas para privilégio estão **fechadas,
não difíceis** — `fusermount` força `nosuid` na montagem,
`--appimage-extract-and-run` não pode `chown` para root, e pedir senha em
runtime é recusado pelo próprio produto.

Construa `.deb` e `.rpm`, cujos `postinst` e `%post` instalam a unit e a
política. Se este produto realmente não tem serviço privilegiado, tire a seção
`service` do `dovetail.yaml`.

---

## `makensis` aborta com `std::bad_alloc`

```
libc++abi: terminating due to uncaught exception of type std::bad_alloc
```

Nesta máquina, a build do Homebrew para arm64 aborta **até num script de quatro
linhas**. Não é o script gerado. Essa prova é de runner Windows, e o teste que
depende dela pula com esse motivo escrito.

---

## O cliente recusa a release, e a assinatura está certa

O campo `signature` do manifesto carrega **base64 por cima do texto minisign**,
nunca o texto cru. Um cliente no campo decodifica antes de parsear e não tem
alternativa — então a forma crua decodifica para nada, e ele descobre isso numa
máquina que você não vê.

O `ManifestWriter` é quem decide essa codificação, e ele aceita as duas formas
na entrada justamente para que quem chama não precise saber. Para conferir de
fora:

```bash
dovetail probe --url <manifesto> --public-key keys/update.pub
```

Ele decodifica base64 **primeiro, sem alternativa**, como o cliente faz.

---

## O endpoint devolve 500 para `darwin` e 200 para `macos`

Duas palavras para a mesma coisa. O app pede a plataforma pelo nome que o Rust
usa — `darwin` — e a tabela do backend guarda a linha sob `macos`; o valor cru
chega ao Postgres, que recusa fora do enum.

É desacordo de vocabulário, não funcionalidade faltando, e a correção é no
servidor: aceitar as duas grafias e responder **404** para o que não conhece,
que é a resposta honesta para uma plataforma que não existe.

---

## `Wrong password` do minisign, e a senha está certa

Confira se a chave é mesmo protegida por senha. Chamar de `--unencrypted-key`
uma chave que tem senha falha no `minisign` de verdade, alto — e o contrário
também.

Variável de senha não exportada é **recusa com o nome dela na mensagem**, nunca
senha vazia assumida.

---

## O atalho global reporta sucesso e nunca dispara

Você está em Wayland. Um compositor Wayland só concede atalho de sistema pelo
portal `org.freedesktop.GlobalShortcuts`, onde **o compositor é dono do
acorde** — e sob XWayland existe um `DISPLAY`, então uma sonda ingênua lê a
sessão como X11 e chama `XGrabKey`, que **tem sucesso e nunca dispara**.

O `dovetail_shortcut_channel` recusa por isso, reportando
`ShortcutBackend.waylandPortal` com `available: false` e **nomeando a sessão**.
`XDG_SESSION_TYPE` vence um `DISPLAY` presente, e a sonda lê o ambiente
injetado para que essa regra seja testável em vez de afirmada.

---

## `flutter --version` diz `0.0.0-unknown`

O `bin/cache/flutter.version.json` do SDK aponta para uma revisão que não está
no histórico git dele. Aconteceu nesta máquina.

Apague o cache e deixe o Flutter regenerar:

```bash
mv "$(dirname "$(which flutter)")/cache/flutter.version.json" /tmp/
flutter --version
```

---

## O portão diz `UNTRACKED` num arquivo de teste

*(Monorepo do dovetail: o portão é `dart tool/verify.dart`, que um projeto
gerado não tem.)*

```
UNTRACKED toolkit/algum_pacote/test/algo_test.dart — it counts here
and exists nowhere else. git add it, or delete it.
```

A suíte conta na corrida e não existe no git, então a contagem local não
corresponde a nenhum clone. É `git add` ou `git rm` — e isso já pegou um caso
de `.gitignore` engolindo um arquivo de teste de verdade, por um padrão
(`**/probe_test.dart`) que existia para sondagem temporária.

---

## `Developer ID signing identity has no credentials and a signature was required`

O `dovetail.yaml` tem `sign.macos.notarize: true` e nenhuma identidade está
exportada — nem a variável de `identity-env`, nem `APPLE_SIGNING_IDENTITY`.
`notarize: true` é declarar release de verdade, e aí ficar sem assinar é erro.
O `ship --dry-run` e o `doctor` dizem isso **antes** do build; se você chegou
a esta mensagem depois de um build, rodou o `sign` à mão.

Exporte a identidade (`Developer ID Application: …`) na variável que a config
nomeia, ou ponha `notarize: false` para um build local sem assinatura. O
remédio que a mensagem sugere, tirar `--require-signature`, vale para o `sign`
avulso; no `ship` a flag vem do `notarize`.

---

## `macos signs --bundle or --file in one call, not both`

São dois selos, em dois passos: o `.app` com `--bundle` (de dentro para fora,
com hardened runtime e entitlements) e o `.dmg` com `--file` (arquivo plano,
assinado depois de montado, e é ele que se notariza). O `ship` roda os dois
nessa ordem; à mão, são duas chamadas.

---

## `missing  update  update.public-key is not declared`

O `doctor` diz o que o `ship` vai recusar no último passo: a chave pública que
o app embute não está no `dovetail.yaml`, e sem ela um release assinado por
qualquer outra chave seria publicado sem que nada reclamasse. `dovetail keygen`
imprime a linha pronta; se o par já existe, é o conteúdo do `.pub`, em bloco:

```yaml
update:
  public-key: |
    untrusted comment: minisign public key 1234567890ABCDEF
    RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
```

---

## O app fechava sozinho, sem log

Isto era um defeito e está corrigido, mas vale conhecer a forma: um `Mutex`
envenenado em `PumpTable` fazia `.expect(...)`, e essa tabela é alcançada pelos
métodos **síncronos** da ponte, que não passam pelo runtime que captura pânico.
Um pânico ali atravessa o FFI e **aborta o processo** — sem mensagem, sem log,
sem tela de erro.

Se você escrever código novo alcançado por método `#[frb(sync)]`, esta é a
regra: **nada de `unwrap`, `expect`, `panic!` ou indexação**. O assíncrono está
coberto por `support::run`; o síncrono não está coberto por nada.
