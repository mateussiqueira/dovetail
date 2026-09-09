# Quickstart: do dovetail instalado ao primeiro ship

O caminho de cinco minutos para quem nunca tocou no monorepo. Tudo aqui sai do
binário `dovetail` instalado, mais o SDK que ele baixa, sem clonar repositório
nenhum. Pré-requisito: Flutter com o target desktop do seu sistema.

> **Sobre o canal de instalação.** O dovetail é MIT e os pacotes estão no
> pub.dev, então a rota normal é declarar a dependência e pronto. O que este
> guia descreve — `install.sh` e `self-install` — é o canal de binário
> assinado, e o `<host>` dele **ainda não existe**: o mecanismo é testado, o
> servidor é que falta. Ver **Existe de onde baixar** em [roadmap.md](roadmap.md).

## 1. Instalar

O canal de release **ainda não está no ar**. Não há host, nenhum comando da
esteira publica, e o `install.sh` recusa sem `--base-url`/`$DOVETAIL_INSTALL_URL`
em vez de adivinhar. Até que exista, o caminho real é o monorepo; o que segue
descreve o mecanismo, que é testado, contra um host que ainda falta.

```bash
curl -fsSL https://<host>/install.sh | sh
```

Ou, para quem já tem o binário:

```bash
dovetail self-install --base-url https://<host>
```

Os dois fazem o mesmo trabalho e respeitam `DOVETAIL_HOME` quando definido. A
base vem de `--base-url` ou de `DOVETAIL_INSTALL_URL`; sem os dois o comando
recusa nomeando os dois, nunca adivinha o host. O que aterrissa no disco:

```
~/.dovetail/
  bin/dovetail                     a esteira, AOT, autocontida
  sdk/<versão>/packages            o runtime que o app importa, versionado por diretório
  sdk/<versão>/templates/bridge    o template que gera o bridge do produto
~/.local/bin/dovetail              symlink para o binário
```

Confira que a máquina está pronta:

```bash
dovetail doctor
```

## 2. App novo

```bash
dovetail new --sdk demo
cd demo
flutter test
```

O `new` cria o projeto do zero, já ligado ao dovetail: um `pubspec.yaml`, um
`pubspec_overrides.yaml` apontando para o SDK instalado, um `dovetail.yaml` com
os padrões que o `doctor` aceita, e os diretórios de plataforma (`macos/`,
`windows/`, `linux/`) preenchidos pelo `flutter create` que ele mesmo roda. A
flag `--sdk` resolve o runtime via `pubspec_overrides.yaml` em vez de um `path`
no pubspec, então nada aponta para dentro do monorepo.

## 3. A ponte

Se o app fala com um núcleo Rust, gere o plugin FFI:

```bash
dovetail bridge init --core <seu-crate> --name meu_bridge
```

`--core` é o diretório do crate (o que segura o `Cargo.toml` dele), e o nome
real do crate é lido de lá, nunca adivinhado. O gerado é o `ffiPlugin` dos três
sistemas. Daqui para frente o laço é:

1. escrever os repasses em `rust/src/api/`
2. `flutter_rust_bridge_codegen generate`
3. `tool/build_xcframework.sh`
4. `cd rust && cargo check`
5. `flutter test test/core_coverage_test.dart`

O último passo é o portão de forma: lê o `handle.rs` do crate e as chamadas em
`rust/src/api/`, e recusa quando o núcleo cresceu um método que nenhum repasse
expõe.

## 4. A config

O `dovetail.yaml` já vem com os padrões do `new`. O essencial:

```yaml
identifier: com.example.demo
targets:
  - darwin-aarch64
  - linux-x86_64
update:
  key: keys/update.key
  base-url: https://cdn.example.com/releases
  manifest: dist/latest.json
  public-key: |
    untrusted comment: minisign public key D18395BE8A6B994E
    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP
sign:
  macos:
    identity-env: DOVETAIL_MACOS_IDENTITY
```

O par de chaves sai de `dovetail keygen`, que imprime a linha `public-key`
pronta para colar; sem ela o `doctor` diz `missing update` e o `ship` recusa
antes do build, porque um release assinado por uma chave que o app não confia
é um release que só quem reinstalar consegue usar. Não há campo de versão:
ela mora no `pubspec.yaml`. Nenhuma identidade é escrita aqui, só o nome da
variável que a carrega, então o arquivo pode ser commitado. O mapa completo
de chaves está em [configuracao.md](configuracao.md).

## 5. Publicar

```bash
dovetail doctor
dovetail ship --dry-run
dovetail ship
```

O `doctor` confere o host, o projeto, o SDK e o `.xcframework`. O
`ship --dry-run` imprime o plano sem rodar nada — no macOS, build, sign,
bundle, sign dmg, archive e release; nos outros, build, bundle, sign e
release — e recusa antes do build o que o último passo recusaria; sem a flag,
ele percorre a esteira inteira e escreve o manifesto.

## 6. Atualizar

```bash
dovetail self-update   # troca o SDK para o latest do canal
dovetail upgrade       # re-aponta o pubspec_overrides.yaml do app para o SDK preferido
```

O `self-update` instala a versão nova ao lado da antiga e troca o binário, então
um app apontado para a anterior continua resolvendo. O `upgrade` fecha a
distância que o `doctor` reporta quando vê um app atrás da versão instalada. As
seções do `doctor` são `project`, `sdk`, `binary`, `app` e `spm`, cada uma com
o seu veredito — `binary` compara o `dovetail` que responde no `PATH` com o que
está rodando, por commit e por comandos, e nomeia os que o instalado não tem.

## 7. Depois dos cinco minutos

- [ESCREVER_O_APP.md](../ESCREVER_O_APP.md): a fronteira entre o que o framework
  decide e o que o app decide, a ordem do boot, texto, formulário, atalho,
  atualização e publicação.
- [migrar-do-tauri.md](migrar-do-tauri.md): o mapa do `tauri.conf.json` chave
  por chave, para quem sai do Tauri.
