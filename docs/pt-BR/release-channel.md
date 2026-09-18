[English](../release-channel.md) · **Português**

# O canal de release, de ponta a ponta

Este documento responde a uma pergunta: **o que tem de ser verdade antes de o
`dovetail ship` poder entregar um artefato a alguém que não é da equipe.** Ele
foi escrito a partir do que foi medido nesta árvore, não do que os comandos
prometem.

O canal interno é a outra metade — um build de debug, assinado ad-hoc, sem
manifesto, com o instalador que consegue pôr o componente privilegiado
declarado no lugar. Tudo abaixo é sobre `--channel release`, o padrão.

## O que o canal exige

| exigência | onde mora | o que compra |
|---|---|---|
| uma identidade Developer ID | `sign.macos.identity-env` (padrão `DOVETAIL_MACOS_IDENTITY`), ou `APPLE_SIGNING_IDENTITY` | uma assinatura que o Gatekeeper avalia, e o Team ID que o `SMAppService` exige |
| credenciais de notarização | `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`, ou `APPLE_API_KEY_ID` + `APPLE_API_ISSUER` + `APPLE_API_KEY_PATH` | um ticket que a máquina que nunca viu o build consegue grampear e confiar |
| um certificado de assinatura Windows | `sign.windows.certificate-env` (padrão `DOVETAIL_WINDOWS_CERTIFICATE`), ou `WINDOWS_CERTIFICATE_FILE` / `WINDOWS_CERTIFICATE_THUMBPRINT` | um instalador, e o payload dentro dele, que o SmartScreen não assusta quem usa |
| um servidor de carimbo | `sign.windows.timestamp-url` ou `WINDOWS_TIMESTAMP_URL` | uma assinatura que sobrevive ao dia em que o certificado expira |
| a chave minisign **secreta** | `update.key`, na máquina de release | um manifesto que os clientes instalados aceitam |
| a chave minisign **pública** | `update.public-key` | a conferência de que a chave secreta é a que o app já embarcado confia |
| um host https | `update.base-url` / `update.endpoint` | um transporte que o updater fala |
| uma versão | `version:` no `pubspec.yaml` | monotonicidade, e o passo `release` |

Nenhuma delas é código. Cada uma é um valor na máquina de release — e todo
valor que o toolkit não consegue ver é um valor que ele tem de recusar inventar.

## Os passos na ordem, como o `ship` monta

`dovetail ship` é um planejador: lê o `dovetail.yaml`, imprime os passos e
redespacha cada um pelo próprio CLI. A ordem é o contrato.

macOS (release):

```
build macos          flutter build --release, com o endpoint e a chave pública embutidos
sign darwin-universal  codesign do .app de dentro para fora (--require-signature --notarize quando notarize: true)
bundle darwin-universal  o .dmg que o usuário baixa
sign dmg darwin-universal  codesign do .dmg como arquivo plano, depois notariza e grampeia
archive darwin-universal   o .app.tar.gz que o updater instala
release <version>          assina cada artefato com minisign, escreve dist/latest.json
```

Windows (release): `build` → `sign payload` (todo `.exe`/`.dll` sob a saída) →
`bundle` → `sign` (o instalador). O payload é assinado antes de o instalador
embrulhá-lo: um instalador que passa pelo SmartScreen e então deposita
executáveis sem assinatura é pior que nenhum, porque parece certo.

Linux: `bundle` → `sign`, que escreve um `SHA256SUMS` — sem identidade.

## O que é recusado antes do build, e por quê

O build é a metade lenta: `flutter build --release`, o `codesign` sobre o
bundle, o `hdiutil`. Cada conferência abaixo roda a partir da configuração e do
ambiente em milissegundos, no `--dry-run` também. Um dry-run verde sobre um
plano cujo último passo recusa é a mentira mais cara que o comando poderia
contar.

```
$ dovetail ship --dry-run
→ build macos
→ sign darwin-universal
→ bundle darwin-universal
→ sign dmg darwin-universal
→ archive darwin-universal
→ release 1.0.0

ship: sign.macos.notarize is true, and neither DOVETAIL_MACOS_IDENTITY nor APPLE_SIGNING_IDENTITY is exported — the sign step would refuse after the build. ...
ship: sign.macos.notarize is true, and no notarisation credential group is complete: APPLE_ID + APPLE_PASSWORD + APPLE_TEAM_ID, or APPLE_API_KEY_ID + APPLE_API_ISSUER + APPLE_API_KEY_PATH. ...
Nothing ran. These are checked from the config, before the build, because the build is the slow half.
$ echo $?
1
```

Isso já valia para a notarização. Mais três conferências entraram para que a
pergunta "este projeto consegue fazer release?" seja respondida honestamente, e
para que o mesmo veredito venha do `ship` e do `doctor`:

| o quê | antes | agora |
|---|---|---|
| a chave **secreta** do update não está no disco | o `ship --dry-run` planejava todos os passos, exit 0; o passo `release` morria no fim, depois do build inteiro | recusado antes do build, nomeando o caminho resolvido |
| a chave do update tem senha, e `update.password-env` não está exportada | a mesma morte tardia | recusado antes do build, nomeando a variável |
| `sign.windows` está declarado e nenhum certificado está presente | o `sign` imprimia "the artefact stays unsigned" e saía 0 | o canal de release recusa antes do build, e os passos de assinatura Windows carregam `--require-signature` como segunda linha de defesa |
| `sign.windows` declarado, certificado presente, sem carimbo | o `sign` recusaria "half configured" depois do build | recusado antes do build |

A chave secreta é a mais afiada das quatro: é a metade do par que assina.
Perdê-la significa que nenhum cliente instalado aceita atualização de novo, e
ela não pode ser reemitida sem entregar um instalador novo em cada máquina.

## O que o toolkit faz com uma credencial que não tem

Ele para, e diz exatamente o que falta. Ele **não** cai para uma assinatura
ad-hoc, um certificado autoassinado, um marcador, ou um manifesto com assinatura
vazia. O `--ad-hoc` existe, mas só o canal interno o passa, e ele diz em voz
alta que não há Team ID — e é por isso que o canal interno não consegue
registrar um daemon `SMAppService` embarcado.

Concretamente, sem Developer ID:

- `dovetail ship --dry-run` sai 1 com as duas linhas de macOS acima, antes do
  build;
- `dovetail doctor --channel release` imprime `missing signing` e sai 2;
- `dovetail sign` sem identidade imprime, literalmente, `Developer ID signing
  identity: no credentials, so the artefact stays unsigned. Missing
  APPLE_SIGNING_IDENTITY.` no macOS e `Authenticode signing without a Windows
  machine: no credentials, so the artefact stays unsigned. Missing
  WINDOWS_CERTIFICATE_FILE, WINDOWS_TIMESTAMP_URL.` no caminho Windows
  cross-host, e sai 0 — que é exatamente o que torna a recusa pré-build do
  `ship` necessária em vez de decorativa: sozinho, um release sairia verde
  sobre um artefato sem assinatura.

## O que o updater faz, e o que ele recusa

O updater é o consumidor de tudo o que o `release` produz. O caminho dele é
`check` → `download` → `install`, e a fronteira de confiança fica entre o
segundo e o terceiro.

- **Download.** O `HttpArtifactFetcher` recusa qualquer esquema que não seja
  `https`, segue redirecionamento à mão (para um https→http ser recusado, e não
  aceito em silêncio) e impõe um teto de 512 MiB a partir do tamanho declarado e
  no meio do fluxo.
- **Verificação.** O `MinisignVerifier` é Ed25519, com pré-hash BLAKE2b-512 para
  o algoritmo `ED`. Ele confere três coisas, em ordem: o id da chave é o que o
  app confia; a assinatura cobre os bytes; e o trusted comment está amarrado à
  assinatura. Só então existe um `VerifiedArtifact`.
- **Instalação.** Por host: macOS extrai o `.app.tar.gz` e troca o bundle;
  Windows roda `msiexec /i` (ou um NSIS `.exe` destacado); Linux troca o
  AppImage ou roda `pkexec dpkg`/`rpm`.

**Não existe campo SHA256** no manifesto, e o manifesto **não é assinado** —
só cada artefato é. A integridade do manifesto é o transporte HTTPS; a do
artefato é a assinatura. Essa forma é deliberada, não um descuido, mas é o que
faz da decisão de host uma decisão de segurança, e não de hospedagem.

O que acontece quando falha é medido, não descrito. Montando um par
descartável, assinando um artefato, servindo por uma CA privada e perguntando ao
`probe` (o mesmo parser e o mesmo verificador que o app usa):

```
# o caso válido
ok     darwin-universal  the artefact downloads — 38 bytes
ok     darwin-universal  the artefact verifies — the bytes served are the bytes signed
probe: ok — this endpoint serves what the client reads

# um byte trocado no artefato
FAILED darwin-universal  the artefact verifies — the signature does not cover what the url serves: the artefact does not match its signature.
Nothing is installed. The download was altered or truncated.. Every install would refuse it.

# a url do manifesto reescrita para http
Only https carries an update.

# o campo signature do manifesto trocado por lixo
FAILED darwin-universal  the signature field decodes — it is not base64. ...
```

Em toda falha o instalador nunca roda. O tipo da falha é `UpdateFailure`
(mensagem + remédio) ou `DowngradeRefused`; nada chega ao disco.

## O `doctor` responde à mesma pergunta antes do build

`dovetail doctor --channel release` lê o `dovetail.yaml`, o ambiente e o disco,
e devolve exit 2 quando algo que ele consegue ver faria o passo de release
recusar:

```
$ dovetail doctor
project
  ok       identifier  com.example.demo
  ok       name  Demo by Demo Inc
  ok       version  1.0.0  (from pubspec)
  ok       targets  darwin-aarch64, darwin-x86_64 on this host of 2
  missing  update  the signing key keys/missing.key is not on disk (...), and the release step signs the artefacts with it at the end of the run — ...
  ok       signing  DOVETAIL_MACOS_IDENTITY, not notarised
  off      service  no privileged component is declared, on any platform
$ echo $?
2
```

`doctor` e `ship` nunca podem discordar sobre o que pode sair; cada conferência
nova num é espelhada no outro, e um teste fixa as duas. `doctor --channel
internal` responde à pergunta do canal interno, incluindo a combinação que o
`ship` recusa de saída: um build interno de um projeto que declara `update:`.

## A prova, e os limites dela

Rodado nesta máquina:

- `bash tool/ci/prove_update.sh --host macos` — o laço de release inteiro com
  substitutos para as três coisas que não existem aqui (par descartável, host
  https em loopback com CA privada, identidade ad-hoc). Ele exige um `.app` de
  Release já construído num produto, então não roda neste repositório, que só
  carrega o toolkit.
- `dart test` em `toolkit/dovetail_cli` (548 passaram, 11 pulados) e em
  `toolkit/dovetail_updater` (167 passaram).
- O transcript do `probe` acima.

O que ela **não** prova, e só a conta real prova:

- o Gatekeeper aceitar o download (`spctl -a -t open` numa máquina que nunca viu
  o build) — precisa do Developer ID e da notarização reais, não de um
  substituto;
- o parque instalado aceitar a atualização — o manifesto é assinado com a chave
  de produção, e essa chave é uma decisão de custódia, não de código;
- comportamento de DNS e CDN;
- qualquer coisa compilada com MSVC, e qualquer corrida de CI hospedada — a
  conta dona deste repositório nunca executou workflow nenhum.

## O dia do release real: trocar valores, não código

| o quê | onde |
|---|---|
| chave minisign de produção | `update.key` e `update.public-key` (tire o par de staging do caminho antes; o `keygen` recusa sobrescrever) |
| host | `update.base-url`, `update.endpoint` |
| Developer ID | `APPLE_SIGNING_IDENTITY` (ou a variável que `sign.macos.identity-env` nomeia) e `sign.macos.notarize: true` |
| notarização | o grupo `APPLE_*` |
| certificado Windows | a variável que `sign.windows.certificate-env` nomeia, mais `WINDOWS_TIMESTAMP_URL` |

Com `notarize: true` e sem credenciais, tanto o `ship --dry-run` quanto o
`doctor` recusam antes do build, nomeando exatamente as variáveis acima — e é
essa a lista que eles nomeiam.

## Lacunas conhecidas no próprio canal

Registradas para ninguém precisar redescobri-las:

- o manifesto não é assinado (a integridade dele é o HTTPS);
- o manifesto não carrega tamanho nem hash, então não há conferência
  declarado-versus-real;
- o updater não confere o nome do arquivo contra a chave de plataforma pedida —
  um artefato errado, mas assinado, verifica e falha mais tarde, no instalador;
- a extração no macOS depende do `tar` do sistema e não é endurecida contra
  path traversal;
- não há um opt-in de notarização para o Windows: o canal de release agora exige
  certificado sempre que `sign.windows` é declarado, e o canal interno é a saída
  para um build de testador sem assinatura.
