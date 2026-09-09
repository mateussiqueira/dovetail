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

## O que o PR precisa dizer

- **Em que sistema operacional você mediu.** Sem isso a informação mais
  importante do PR está faltando.
- O que você viu, não o que deveria acontecer. "Rodei X, saiu Y" em vez de
  "corrige o comportamento de X".

## Estilo

- `dart format` antes de commitar. O formatador é o árbitro, sem discussão.
- Comentário explica **por que**, não o que o código já diz. Um comentário que
  narra a linha abaixo dele é ruído; um que registra a decisão que a linha
  esconde, ou o defeito que ela evita, é o mais valioso do arquivo.
- Teste que descreve o defeito que evita vale mais que teste que descreve a
  função.
- Nome de identificador em inglês. Comentário e documentação podem estar em
  português — o projeto é bilíngue nisso, e não vamos traduzir o que já existe.

## Licença

Contribuição entra sob a MIT, a mesma do projeto.
