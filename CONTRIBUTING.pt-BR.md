**Português** · [English](CONTRIBUTING.md)

# Contribuir

## O que ajuda mais

Este projeto foi verificado quase inteiro numa única máquina — um macOS arm64.
A dívida mais cara não é falta de feature: é falta de gente que rodou isso em
outro lugar. Então, em ordem de utilidade:

1. **Rodar em outro sistema operacional e relatar.** Windows com MSVC e Linux
   são território não testado. Uma issue dizendo "no Windows 11, `dovetail
   doctor` falhou assim" é mais valiosa que uma feature.
2. **Rodar a matriz num fork.** As três pernas existem no workflow e nunca
   executaram, porque a conta que publica este repositório não tem Actions.
   Em repositório público o Actions é gratuito: forkar e deixar a matriz
   rodar já produz a informação que falta, mesmo que você não mude uma linha
   de código.
3. **Feature ou correção.** Bem-vindas, com teste.

## Como rodar

Cada pacote em `toolkit/` é independente:

```bash
cd toolkit/<pacote>
dart pub get        # ou flutter pub get, nos pacotes que dependem de Flutter
dart test           # ou flutter test
```

O `pubspec_overrides.yaml` de cada pacote aponta para os vizinhos locais, então
nada precisa vir do pub.dev para desenvolver.

Alguns testes precisam de um artefato construído ou de uma ferramenta do
sistema (`codesign`, `minisign`, `msitools`). Eles **pulam com o motivo
escrito** quando ela falta — um pulo explicado não é uma falha, mas também não
é uma prova. Se um deles pular na tua máquina e você tiver a ferramenta, isso é
um bug: relate.

## Hooks e portões

Nada roda num servidor ainda, então os hooks são o portão. Instale uma vez
por clone:

```bash
dart tool/verify.dart hooks
```

Ele aponta o `core.hooksPath` para o `.githooks` deste clone, como `git
config core.hooksPath "$PWD/.githooks"`, e não sobrescreve um que aponte
para outro lugar. O `.githooks/pre-push` confere cada branch que você
publica, numa worktree do commit enviado:

- `scripts/pr/check_open_pr_limit.sh`: no máximo três PRs abertos;
- `scripts/checks/check_pr_rules.sh`: até 250 linhas alteradas e 7
  arquivos, Conventional Commits, branch no formato `feat/...`. Uma
  varredura mecânica diz o motivo com `PR_SIZE_EXEMPT='<motivo>'`; uma
  branch empilhada é medida contra a mãe com `PR_BASE=<mãe>`;
- `scripts/checks/check_no_comments.sh`: nenhum comentário em linha nova de
  Dart, Rust ou shell;
- todo `*_selftest.sh` em `scripts/checks` e `scripts/pr`, `cargo fmt
  --check` nos crates que a branch tocou e `dart tool/verify.dart`, que
  `DOVETAIL_VERIFY_SKIP='<motivo>'` pula.

## O que o PR precisa dizer

- **Em que sistema operacional você mediu.** Sem isso a informação mais
  importante do PR está faltando.
- O que você viu, não o que deveria acontecer. "Rodei X, saiu Y" em vez de
  "corrige o comportamento de X".

## Estilo

- `dart format` antes de commitar. O formatador é o árbitro, sem discussão.
- Nenhum comentário em código novo (Dart, Rust e shell), como nos repositórios
  irmãos: o `scripts/checks/check_no_comments.sh` recusa no pre-push. O porquê,
  a decisão que a linha esconde ou o defeito que ela evita, vai no corpo do
  commit e do PR, e um teste que descreve o defeito o mantém vivo. Os
  comentários que já existem ficam até o código em volta mudar.
- Teste que descreve o defeito que evita vale mais que teste que descreve a
  função.
- Nome de identificador em inglês. Documentação pode estar em português — o
  projeto é bilíngue nisso, e não vamos traduzir o que já existe.

## Licença

Contribuição entra sob a MIT, a mesma do projeto.
