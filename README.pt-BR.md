<!-- Português. English version: [README.md](README.md) -->

**Português** · [English](README.md)

# dovetail

> A junta entre Flutter e Rust no desktop. No lugar do Tauri.

Uma junta *dovetail* encaixa duas peças de material diferente e fica mais firme
sob carga, sem cola nem parafuso. É o que este projeto é: a junta entre uma UI
Flutter e um núcleo Rust, mais as ferramentas de construir, assinar e
distribuir isso no Windows, no macOS e no Linux.

## O estado, sem maquiagem

**Beta.** Não porque um número de versão mudou, mas porque a coisa finalmente
aconteceu: um produto de verdade saiu em cima deste toolkit, chegou a cerca de
cem pessoas, e voltou com elogio em vez de lista de defeito.

Esse produto é um cliente de VPN comercial — Flutter sobre um núcleo Rust, com
um daemon privilegiado que precisa se instalar sozinho e sobreviver a reinício.
É a forma mais difícil que este toolkit diz suportar, e o canal de distribuição
interna a carregou: `dovetail ship --channel internal` produziu um `.pkg` que
instala o daemon declarado, embrulhado num `.dmg` que um testador sabe abrir,
universal entre Intel e Apple Silicon. Instalou, rodou, sobreviveu a reinício,
desinstalou sem sobra. Foi isso que tirou o projeto do alfa.

O que está provado, e medido em vez de lembrado:
**1513 testes Dart declarados, 45 pulados**, mais as crates Rust. O
`dart tool/verify.dart` compara essa frase com o que as suítes acabaram de
reportar e falha quando discordam — então um README que exagera a própria
cobertura não consegue ser commitado. Os pulados estão nomeados em
`tool/skip_baseline.json`, com a razão.

O que **não** está provado, e preferimos dizer a deixar você descobrir:

- **Quase tudo rodou numa máquina macOS arm64 só.** O workflow de CI tem pernas
  para `macos-14`, `ubuntu-24.04` e `windows-2022`, e nenhuma jamais executou —
  a conta que publica isto não tem minutos de Actions. **Num fork ele roda**,
  porque Actions é grátis em repositório público. Se você bifurcar isto e a
  matriz passar no Windows ou no Linux — ou falhar —, isso continua sendo a
  coisa mais útil que este projeto pode receber.
- **Nada foi compilado com MSVC.** O código de Windows passa na checagem de
  tipos para `x86_64-pc-windows-msvc` e nunca encontrou um Windows de verdade.
- **O canal de release nunca viu um Developer ID real.** A assinatura foi
  exercitada com certificado autoassinado; notarização nunca passou por aqui. O
  canal interno, que não precisa de nenhum dos dois, é o que tem quilometragem.

Se algo quebrar na sua máquina, não é surpresa — é a informação que falta.
Abra uma issue com o seu sistema operacional e a saída.

## Os pacotes

| pacote | o que faz |
| --- | --- |
| `dovetail` | o guarda-chuva: junta o runtime numa dependência só |
| `dovetail_cli` | a esteira: `init`, `doctor`, `build`, `sign`, `ship`, `release` |
| `dovetail_rust_core` | a ponte com o núcleo Rust, sobre flutter_rust_bridge |
| `dovetail_bundler` | empacota: `.app`, `.dmg`, `.msi`, `.deb`, `.rpm`, AppImage |
| `dovetail_signer` | assina e notariza, e recusa quando não pode provar |
| `dovetail_updater` | verifica manifesto assinado com minisign e atualiza |
| `dovetail_platform_channel` | instância única e integração de janela |
| `dovetail_privileged_helper` | o daemon, serviço ou unit que um app em sandbox não pode ser |
| `dovetail_privileged_channel` | o fio até esse daemon: socket ou pipe, e quem tem direito de falar |
| `dovetail_privileged_daemon` | o esqueleto do próprio daemon: instalar, aceitar, validar, registrar |
| `dovetail_http_client` | um cliente HTTP tipado, e o cofre do sistema onde o token mora |
| `dovetail_shortcut_channel` | atalho global, com ou sem foco de janela |
| `dovetail_process_runner` | processo externo com timeout e desfecho tipado |
| `dovetail_form_validation` | validação de formulário sem depender de widget |
| `dovetail_screenshots` | o harness que fotografa as telas do app, com as fontes carregadas |

## Começar

```bash
git clone https://github.com/mateussiqueira/dovetail
cd dovetail/toolkit/dovetail_cli
dart pub get
dart run bin/dovetail.dart --help
```

O repositório é um monorepo de pacotes em `toolkit/`. Cada um publica sozinho e
declara os outros por versão; o `pubspec_overrides.yaml` de cada pacote aponta
para o vizinho local, então `dart pub get` resolve sem passar pelo pub.dev.

Para instalar o binário e chamá-lo de qualquer diretório:

```bash
cd toolkit/dovetail_cli && tool/build_release.sh --install
```

## Os comandos

A esteira inteira é um binário. Nada do que ela faz precisa da fonte dela.

| comando | o que faz |
| --- | --- |
| `dovetail init` | lê o projeto e escreve o `dovetail.yaml` |
| `dovetail doctor` | este host consegue construir o que foi declarado? |
| `dovetail new` | gera um projeto novo, já ligado ao runtime |
| `dovetail bridge` | gera o plugin FFI que fala com o núcleo Rust |
| `dovetail build` | compila o app Flutter com os defines da config |
| `dovetail bundle` | empacota: `.app`, `.dmg`, `.msi`, `.deb`, `.rpm`, AppImage |
| `dovetail sign` | assina e, no macOS, notariza |
| `dovetail icon` | deriva os ícones de cada plataforma de uma imagem só |
| `dovetail inspect` | diz o que um artefato é, lendo o cabeçalho dele |
| `dovetail keygen` | cria o par de chaves minisign do canal de update |
| `dovetail manifest` | escreve e assina o manifesto que o app vai ler |
| `dovetail ship` | a esteira inteira, a partir da config |

### Dois canais, e o que tem quilometragem

O `dovetail ship` tem dois: `release`, que quer um Developer ID e produz algo
que um estranho consegue instalar, e `internal`, que não quer nada e produz algo
que a sua equipe instala hoje à tarde.

O canal interno existe porque todo projeto precisa entregar build para testador
muito antes de ter identidade de assinatura — e a resposta de sempre, "compila e
passa a pasta adiante", desmonta no instante em que o app tem um componente
privilegiado. Então `--channel internal` preserva os símbolos de depuração,
assina ad-hoc, **recusa** escrever manifesto de updater (artefato interno não
pode chegar ao canal que os seus usuários publicados acompanham) e escolhe o
formato de instalador que de fato instala o que o projeto declarou.

No macOS isso quer dizer `.pkg`, porque é o único formato de lá que roda
pós-instalação como root — e o `.pkg` viaja dentro de um `.dmg`, porque é o que
uma pessoa sabe abrir. Familiar por fora, correto por dentro.

É esse o caminho que levou um produto real a cem testadores. É a coisa mais
exercitada deste repositório.
| `dovetail release` | publica a versão e move o canal |
| `dovetail probe` | verifica um manifesto publicado como o app verificaria |
| `dovetail update` | aplica uma atualização, como o app faria |
| `dovetail dev` | roda o app com o núcleo Rust em modo de desenvolvimento |
| `dovetail upgrade` | atualiza os pacotes que o projeto usa |
| `dovetail self-install` | instala este binário no `PATH` |
| `dovetail self-update` | atualiza este binário pelo canal assinado |

## Contribuir

Leia [CONTRIBUTING.md](CONTRIBUTING.md). O resumo: rode os testes do pacote que
tocou, e diga na descrição do PR **em que sistema operacional** você mediu. Este
projeto tem uma dívida específica — quase tudo foi verificado num só lugar — e
um PR que diga "testei no Windows 11, isto falhou assim" vale mais aqui do que
uma feature nova.

## Licença

MIT. Veja [LICENSE](LICENSE).
