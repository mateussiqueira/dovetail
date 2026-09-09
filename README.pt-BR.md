<!-- Português. English version: [README.md](README.md) -->

**Português** · [English](README.md)

# dovetail

> A junta entre Flutter e Rust no desktop. No lugar do Tauri.

Uma junta *dovetail* encaixa duas peças de material diferente e fica mais firme
sob carga, sem cola nem parafuso. É o que este projeto é: a junta entre uma UI
Flutter e um núcleo Rust, mais as ferramentas de construir, assinar e
distribuir isso no Windows, no macOS e no Linux.

## O estado, sem maquiagem

Isto é aberto **porque ainda não está pronto**, e a lista abaixo é o convite.

O que está provado nesta máquina: os dez pacotes passam nos próprios testes, o
CLI constrói, empacota, assina e verifica um release de ponta a ponta contra um
host local com CA privada, e o updater recusa manifesto sem assinatura válida.

O que **não** está provado:

- **Nada rodou fora de um macOS arm64.** O workflow existe, com pernas para
  `macos-14`, `ubuntu-24.04` e `windows-2022`, e nenhuma delas jamais
  executou: a conta que publica este repositório não tem GitHub Actions
  disponível. **Num fork, ele roda** — o Actions é gratuito em repositório
  público. Se você forkar e a matriz passar (ou falhar) em Windows ou Linux,
  essa é a informação mais valiosa que este projeto pode receber hoje.
- **Nada foi compilado com MSVC.** A perna Windows é código escrito às cegas.
- **Nenhum pacote tinha sido publicado** até esta primeira leva.
- A assinatura macOS foi exercitada com certificado autoassinado. Developer ID
  e notarização de verdade nunca passaram por aqui.

Se algo aqui não funcionar na tua máquina, isso não é surpresa — é a
informação que falta. Abre uma issue com o sistema operacional e a saída.

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
| `dovetail_shortcut_channel` | atalho global, com ou sem foco de janela |
| `dovetail_process_runner` | processo externo com timeout e desfecho tipado |
| `dovetail_form_validation` | validação de formulário sem depender de widget |

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
