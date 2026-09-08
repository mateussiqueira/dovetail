# Migrar do Tauri para o dovetail

Escrito enquanto a migração do `example-rust` acontecia, então cada
afirmação aqui vem de uma medição num produto de verdade, não de leitura de
documentação.

O resumo: **o núcleo Rust não se move.** O que sai é a casca — o webview, os
`#[tauri::command]` e o `tauri.conf.json`. O que entra é Flutter falando com o
mesmo Rust por FFI, e um CLI que faz o que a esteira do Tauri fazia.

---

## O que muda de verdade, e o que só muda de lugar

| no Tauri | no dovetail | é o mesmo? |
|---|---|---|
| `#[tauri::command]` + `invoke()` no JS | método Rust + método Dart gerado | **não**: deixa de ser JSON de ida e volta e passa a ser chamada de função |
| webview + SPA | Flutter compilado | **não**: as telas se recriam, não se portam |
| `tauri.conf.json` | `dovetail.yaml` | quase — ver o mapa abaixo |
| `tauri build` | `dovetail ship` | sim, e o plano é imprimível antes de rodar |
| `installer/hooks.nsh` | o mesmo arquivo, intacto | sim, de propósito |
| `tauri_plugin_updater` | `dovetail_updater` | **não**: ver a seção sobre o updater |
| `app.security.csp` | nada | o webview foi embora, e a CSP com ele |

O núcleo, o `api-client`, o `wg-engine`, o `ipc-proto` e o helper privilegiado
**não são tocados**. Foram 61 comandos Tauri cobrindo o que hoje são 51 métodos
públicos do `CoreHandle`, e 50 deles atravessam para o Dart — o único de fora é
o construtor, porque a ponte é dona do ciclo de vida.

---

## O mapa do `tauri.conf.json`

Este é o arquivo real do produto, chave por chave.

### Vai direto

| `tauri.conf.json` | `dovetail.yaml` |
|---|---|
| `productName` | `name` |
| `identifier` | `identifier` |
| `version` | **não existe** — sai do `pubspec.yaml` |
| `bundle.targets` | `targets`, em pares sistema-arquitetura |
| `bundle.macOS.entitlements` | `sign.macos.entitlements` |
| `bundle.macOS.minimumSystemVersion` | `MACOSX_DEPLOYMENT_TARGET`, no projeto Xcode |
| `bundle.windows.nsis.installMode` | `InstallMode`, no `bundle` |
| `bundle.windows.nsis.installerHooks` | `--installer-hooks` |
| `bundle.windows.nsis.languages` | `--installer-language`, repetível |
| `plugins.updater.endpoints` | `update.endpoint` — onde o app pergunta pelo manifesto |
| *(sem equivalente no Tauri)* | `update.base-url` — a raiz de onde os artefatos são baixados |
| `plugins.updater.pubkey` | `update.public-key` |

### Muda de forma

**`bundle.targets` deixa de ser lista de formato e passa a ser lista de alvo.**
No Tauri, `["nsis","dmg","deb","rpm","appimage"]` diz *o que empacotar*; no
dovetail, `targets` diz *para quem publicar* — `darwin-aarch64`,
`windows-x86_64` — e o formato vem de `bundle --linux-format` e
`--windows-format`. A razão é o updater: a chave do manifesto é
`sistema-arquitetura`, e um formato que não vira chave é release que nenhum
cliente pede.

**`appimage` provavelmente sai da lista.** O `dovetail bundle` **recusa**
AppImage quando o `dovetail.yaml` declara serviço, e este produto declara: um
AppImage não instala nada, então não há unit systemd, não há helper
privilegiado e não há kill switch. O Tauri construía o arquivo de todo jeito, e
o que saía não era produto degradado — era uma janela que não conecta.

**`signingIdentity: "-"` vira `APPLE_SIGNING_IDENTITY=-`** (ou a variável de
`identity-env`): o `-` é assinatura ad hoc e o `sign` a passa ao `codesign`
como está — é o que `tool/ci/prove_update.sh` usa para simular a esteira. Sem
identidade nenhuma exportada, e com `notarize: false`, o passo de assinar **diz
que o artefato fica sem assinar** e segue; com `notarize: true`, a identidade
ausente é recusada antes do build.

**`build.beforeBuildCommand` desaparece.** Aquele script compilava o helper e o
frontend. O frontend deixa de existir, e o build do helper é passo do produto —
não do bundler.

### Não tem para onde ir

- `build.frontendDist`, `build.devUrl`, `build.beforeDevCommand` — não há
  frontend web.
- `app.security.csp` — a CSP era a defesa do webview contra o próprio HTML que
  ele renderizava. Sem webview, a classe inteira de preocupação vai embora.
- `app.windows[]` — tamanho, título e decoração de janela passam a ser
  `WindowSpec`, em código, porque no white-label eles são decisão de revenda e
  não de build.

---

## A armadilha que vale mais que todo este documento

O `tauri.conf.json` deste produto declara:

```json
"bundle": { "macOS": { "minimumSystemVersion": "13.0" } }
```

E o projeto Flutter recém-criado declara:

```
MACOSX_DEPLOYMENT_TARGET = 10.15;
```

**Isso não é detalhe de build.** O `10.15` é o padrão do template do Flutter, e
ninguém o escolheu. O `13.0` foi escolhido: o caminho de instalação do helper
no macOS passa por `SMAppService`, que **existe a partir do macOS 13** — está
escrito no núcleo, em `crates/core/src/installer.rs:184`, como o plano da fase.

Deixar `10.15` significa que o app **abre** num Mac com macOS 11 e o helper
**nunca pode ser instalado ali**. O usuário vê uma janela que não conecta, e
nada explica por quê — o sistema não recusou porque o app disse que servia.

O `dovetail bundle` recusa um `.app` que não declara mínimo nenhum, e recusa um
que discorde do que a release declara. Ele **não** sabe qual número está certo:
esse é o número que a migração tem de trazer à mão.

> Ao migrar, copie o `minimumSystemVersion` do `tauri.conf.json` para o
> `MACOSX_DEPLOYMENT_TARGET` do projeto Xcode, **antes** do primeiro release.

---

## O updater: leia isto antes de planejar compatibilidade

A suposição natural é que existem instalações no campo confiando na chave
minisign cravada no `tauri.conf.json`, e que a nova esteira precisa falar
exatamente a mesma língua. **Nesse produto, medido contra produção, não era o
caso** — e verificar isso custou três `curl` e dois `grep`:

- `tauri_plugin_updater` estava registrado em `main.rs:51` e **invocado em
  lugar nenhum**: zero chamadas em Rust, e o pacote JS nem estava no
  `package.json` do frontend.
- O que a tela recebia era um aviso com link. O `sha256` que o endpoint
  devolvia não era consumido por nada, e `mandatory` era fixo `false`.
- **Não havia verificação de assinatura nem de hash no caminho vivo.**

Então **confira antes de assumir**. Se o plugin do seu projeto é chamado de
verdade, a compatibilidade é obrigação; se não é, ela é escolha — e você ganha a
liberdade de desenhar o manifesto, mais o item mais arriscado do plano sai da
lista.

O `dovetail_updater` mantém a dupla camada de base64 do Tauri porque custa nada
e preserva a opção. E faz três coisas que o cliente do Tauri não faz: confere o
comentário confiável (que carrega nome de arquivo e timestamp, e é assinado),
recusa downgrade como erro em vez de escolha do cliente, e nomeia qual bloco de
plataforma está quebrado.

Antes de confiar num endpoint, pergunte a ele:

```bash
dovetail probe --url https://api.exemplo.com/manifest/darwin \
  --public-key keys/update.pub --installed 1.0.0 --download
```

---

## Os 280 ganchos NSIS entram intactos

O `installer/hooks.nsh` do produto tem 280 linhas que instalam e registram o
serviço privilegiado. O gerador do dovetail expõe **os quatro ganchos com o
mesmo nome e a mesma posição** do template do Tauri, guardados por
`!ifmacrodef` — então o arquivo entra sem alteração.

*Deveria*: o `makensis` nunca compilou o script gerado com esse arquivo
incluído, em host nenhum. Nesta máquina ele aborta com `std::bad_alloc` até num
script de quatro linhas, então essa prova é de runner Windows. É lacuna
conhecida, não suposição escondida.

---

## A ordem em que vale fazer

Fazer B antes de A custa retrabalho de semanas, e a razão não é gosto: tela
desenhada contra caso de uso inexistente nasce ligada a nada.

1. **A ponte, e só ela.** Um método Rust chegando ao Dart, com um teste
   provando que atravessa. Enquanto isso não passa, nada acima existe.
2. **O catálogo de texto.** É a única coisa do front antigo que sobrevive
   inteira. Toda tela escrita antes dele nasce com string literal dentro, e
   reescrever depois é mais caro que portar agora. No `example-rust` foram
   819 chaves × 3 idiomas, e o importador em `tool/import_locales.dart` recusa
   em vez de adivinhar.
3. **As regras de validação.** O outro pedaço que sobrevive: regra de negócio,
   não visual. Sete regras, em `toolkit/dovetail_form_validation`.
4. **Sessão e autenticação.** É o que decide se a tela abre, então tudo em cima
   depende.
5. **O domínio de cada área**, sobre uma ponte que já responde.
6. **O shell de navegação**, depois de existir o que navegar.
7. **As telas.** Elas não se portam, se recriam.

Do front antigo sobrevivem o catálogo de texto e as regras de validação. Os
outros 92% são visual, e o visual é redesenhado.

---

## O que a migração ganha, além de sair do webview

- **Hot reload sobre o núcleo Rust**: 48 ms, restart em 352 ms, medido.
- **Erro tipado na fronteira.** `CoreFailure` chega com `kind`, e a tela dá
  `switch` nele. Não há prefixo de texto para procurar.
- **Um teste que prova que a ponte cobre o núcleo.** O compilador pega ponte
  chamando método inexistente; o sentido que ninguém pega é o núcleo crescer e
  a ponte calar, e há teste para isso.
- **A esteira imprimível.** `dovetail ship --dry-run` mostra os passos como
  dado antes de rodar nenhum.

E o que ela custa, dito sem maquiar: **as telas se recriam.** Se o valor do
projeto está no HTML, esta migração é caríssima. Se está no núcleo Rust — como
estava aqui —, o webview era só a casca.

---

## O que morde no caminho

Está tudo em [problemas.md](problemas.md), com a mensagem de erro de cada um.
Os três que mais custam tempo:

1. **Método Rust invisível do Dart.** Você escreve, tudo compila, e ele não
   existe do outro lado. Falta rodar o codegen, e nada diz isso.
2. **`dlopen` listando dez caminhos.** O nome do crate tem de bater com o nome
   do plugin, ou os símbolos ficam linkados e inalcançáveis.
3. **`MissingPluginException` só em Windows.** Uma dependência que existe no
   macOS e não nos outros dois, arrastada por um barril.
