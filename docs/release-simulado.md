# Release simulado: a esteira inteira sem as três coisas que ainda não existem

> **Contexto para quem chega pelo repositório público.** Este documento cita
> `product/`, que é o app privado onde o toolkit é exercitado, e não existe
> neste repositório. O mecanismo descrito é do toolkit e vale para qualquer
> app; só o caminho do exemplo é de outra árvore.

Uma release de produção precisa de três coisas que este repositório não tem: a
chave minisign de produção, um host https e um Developer ID com credenciais de
notarização. Nenhuma delas é código. O que este documento descreve é como rodar
a esteira **inteira** nesta máquina com substitutos que seguem o **mesmo
contrato**, para que o dia da release real seja trocar valores no
`dovetail.yaml` e no ambiente — e nada mais.

| falta | substituto | onde entra | o que prova |
|---|---|---|---|
| chave de produção | par minisign descartável (`dovetail keygen --out`) | `update.key`, `update.public-key` | assinatura sobre os bytes, recusa de chave estranha |
| host https | `tool/serve_dist.dart` em loopback com CA privada | `update.base-url`, `update.endpoint`, `probe --ca` | transporte, formato do manifesto, o `.app.tar.gz` que o updater instala |
| Developer ID | identidade ad hoc `-` | `APPLE_SIGNING_IDENTITY=-` | ordem dos selos, entitlements, `codesign --verify` no `.app` e no `.dmg` |

O que **não** se prova assim, e só o real prova: Gatekeeper e notarização
(`spctl` dizendo `Notarized Developer ID`), DNS e CDN, e o parque Tauri
aceitando o update — o app novo é outro binário, com outra chave, e o plugin
do updater do parque nunca é chamado; a compatibilidade a honrar é a do
`example-rust` novo consigo mesmo.

## Um comando

```bash
tool/ci/prove_update.sh --host macos
```

Ele exige o `.app` de Release já construído no produto (`dovetail build` em
`product/vpn_desktop`), `openssl`, `minisign`, `dart`, `python3` e as
ferramentas de linha de comando do Xcode (`codesign`, `hdiutil`), e roda
**sempre** o CLI da árvore, nunca o instalado no PATH — o instalado pode estar
comandos atrás, e o `doctor` diz quando está.

O que acontece, na ordem:

1. Uma **raiz de staging** em `$TMPDIR/dovetail-update-stage` com um
   `dovetail.yaml` próprio: a identidade do produto, `base-url` e `endpoint`
   apontando para `https://localhost:8443`, `notarize: false`, e um par
   descartável em `keys/staging.key`. O `dovetail.yaml` do produto não é
   tocado.
2. `ship --no-build` com `APPLE_SIGNING_IDENTITY=-`: o `.app` copiado com
   `ditto` é reassinado de dentro para fora com os entitlements de Release (o
   que remove o `get-task-allow` que o Xcode deixa e a notarização recusa), o
   `.dmg` é montado e assinado como arquivo plano, o `.app.tar.gz` é gerado
   para o updater, e o `release` escreve `dist/latest.json` apontando para o
   tar.gz — não para o dmg, que o `MacosInstaller` não abre.
3. `codesign --verify --deep --strict` no `.app` e `--strict` no `.dmg`.
4. Uma CA privada e uma folha para `localhost` saem do `openssl` — a folha com
   `extendedKeyUsage = serverAuth`, porque no macOS o Dart delega a confiança
   ao Security framework da Apple, que exige isso de todo certificado de
   servidor TLS (o `curl` aceita sem; o cliente Dart recusa com "application
   verification failure"). `tool/serve_dist.dart` serve `dist/` por https,
   respondendo também `/desktop-version/check/<os>` — a forma do endpoint que
   o app consulta.
5. `probe` **sem** `--ca` tem de falhar pelo handshake (o cliente não aceita
   certificado que não conhece); com `--ca tls/ca.crt --public-key
   keys/staging.pub --target darwin-universal --installed 0.9.0 --download`,
   tem de oferecer a versão e verificar os bytes do tar.gz com a chave
   descartável; e com `--installed` igual à versão servida, tem de dizer
   `upToDate` e não oferecer nada.

## Fechar o laço com o app

O `probe` é o mesmo parser e verificador do app, mas não é o app. Para ver o
app instalado aceitar um update do host local:

- A raiz de staging **não é um projeto Flutter**: só carrega o `.app` copiado,
  o yaml, as chaves e o TLS. O build que embute os valores de staging é feito
  no produto: o `dovetail.yaml` de `product/vpn_desktop` já carrega a chave de
  staging e o endpoint em `localhost:8443`, então `dovetail build` lá embute
  os dois via `--dart-define`, e o app os lê com `String.fromEnvironment`. Para
  que esse app aceite o manifesto do stage, o stage tem de assinar com a
  **mesma** chave (aponte `update.key` e `update.public-key` do yaml de stage
  para `keys/update.key` do produto, em vez do par descartável).
- A CA privada precisa ser confiada pelo app. O `HttpClient` do Dart não lê o
  keychain para raízes extras, então a costura é a mesma do `probe`: um
  `HttpArtifactFetcher(client: ProbeCommand.clientTrusting(caPath))` ou o
  equivalente no `makeUpdateWatch(fetcher: ...)` — código do app, e portanto
  seu.
- A versão do artefato servido tem de ser **maior** que a do app que roda:
  suba `version:` no `pubspec.yaml` antes do segundo `dovetail build` (é dali
  que o build tira `dovetail.version`; não há flag para isso) e publique com
  `dovetail release --version` igual, senão o veredito é `up to date`.
- O app em sandbox precisa de `com.apple.security.network.client` para sair
  para a rede; os dois `.entitlements` do produto agora o carregam, e um teste
  do produto prende isso.

## O dia da release real

Troque valores, não código:

| o quê | onde |
|---|---|
| chave de produção | mova o par de staging (`keys/update.key`, `keys/update.pub`) para fora — o `keygen` recusa sobrescrever de propósito —, então `dovetail keygen --out keys/update.key` (com senha, `unencrypted: false`), e as duas linhas de `update.public-key` no `dovetail.yaml` |
| host | `update.base-url` e `update.endpoint` |
| Developer ID | `APPLE_SIGNING_IDENTITY` (ou a variável de `identity-env`) e `sign.macos.notarize: true` |
| notarização | `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`, ou a trinca `APPLE_API_*` |

Com `notarize: true`, o `ship --dry-run` e o `doctor` recusam **antes do
build** o que faltar disso — a lista acima é exatamente o que eles nomeiam.
