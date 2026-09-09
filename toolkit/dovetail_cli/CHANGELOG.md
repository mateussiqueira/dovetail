# Changelog

## 0.1.1 — 2026-09-09

Nada no código mudou. A 0.1.0 foi publicada com o README em português e com
avisos que deixaram de ser verdade no momento em que o pacote saiu — "parte do
dovetail, versionado só localmente" era um deles. A página do pub.dev é
congelada na versão publicada, então esta versão existe para substituir o que
ela mostra.

O que muda: README em inglês no caminho canônico, com o português ao lado em
`README.pt-BR.md` e um seletor de idioma no topo dos dois. A instalação passa a
mostrar a dependência publicada em vez de um caminho para dentro do monorepo.

---

## 0.1.0 — 2026-09-08

A porta única do toolkit, distribuída como binário: `init`, `doctor`, `dev`,
`build`, `ship`, `bundle`, `sign`, `icon`, `inspect`, `keygen`, `manifest`,
`probe`, `new` e `release`.

- `new` cria um projeto Flutter mínimo já consumindo a biblioteca dovetail:
  `pubspec.yaml` com dependência de caminho, `main.dart`, um teste de widget
  e um `dovetail.yaml` que `dovetail doctor` aceita. O caminho para a
  biblioteca é calculado a partir do repositório quando o CLI roda dentro
  dele, e pode ser sobrescrito com `--dovetail-path`.
- `dev` vigia um crate de `flutter_rust_bridge` e recusa iniciar quando o
  Dart gerado está atrás do Rust, nomeando cada método que falta — a
  armadilha em que tudo compila e o método não existe do lado Dart. `--check`
  só reporta, `--once` regenera e diz o que entrou.
- `ship` percorre a esteira inteira a partir do `dovetail.yaml`, com o plano
  como dado — `--dry-run` imprime os passos sem rodar nenhum.
- `doctor` sem `--target` relata o projeto antes das ferramentas, e distingue
  o que falta do que só não foi configurado.
- `bundle --target windows` produz MSI pelo `wixl` e NSIS pelo `makensis` em
  qualquer host; `sign --target windows` usa `osslsigncode` fora do Windows.
- `--version` informa versão, alvo, o Dart que construiu o binário e o commit
  de que ele saiu (`commit source` quando roda por `dart run`). O semver está
  parado em 0.1.0, e sem o commit um binário de três semanas e a árvore de
  hoje respondiam a mesma linha.
- `ship` no macOS ganha o passo `archive`: o `.app` assinado vira
  `<binário>_<versão>_universal.app.tar.gz`, e é ESSE arquivo que o manifesto
  publica — o updater extrai tar.gz com um `.app` dentro e não monta dmg.
  Publicar o dmg no manifesto fazia a primeira atualização automática morrer
  em "could not extract the update archive" depois de baixar e verificar 33
  MB. O dmg continua saindo, assinado e notarizado, como download de
  instalação inicial; o `ship` imprime os dois no fim, separados.
  `bundle --macos-format tar` produz o arquivo avulso.
- `sign --target macos --file <dmg>`: o `ship` planejava o passo `sign dmg` e
  o comando o recusava com "macos needs --bundle" — a esteira morria no quarto
  de cinco passos. O `.dmg` é assinado como arquivo plano e, com `--notarize`,
  notarizado e grampeado ele mesmo.
- `sign --bundle` aplica por padrão o plist que o projeto Xcode assina em
  Release (`CODE_SIGN_ENTITLEMENTS` do `macos/Runner.xcodeproj/project.pbxproj`,
  resolvido contra a raiz do projeto; `macos/Runner/Release.entitlements` como
  reserva) e diz qual aplicou: `codesign --force` sem `--entitlements` substitui
  a assinatura do Xcode e deixa cair os entitlements que o build tinha — o
  `app-sandbox` — e é também o que remove o `get-task-allow` que o Xcode deixa
  no Release e que a notarização recusa. O `ship` repassa
  `sign.macos.entitlements` quando declarado.
- `ship` com `sign.macos.notarize: true` passa `--require-signature` e
  `--notarize` nos dois passos de assinatura do macOS — o `.app` antes do dmg,
  para o ticket ficar grampeado nos dois — e recusa ANTES do build, no
  `--dry-run` inclusive, quando a identidade não está exportada ou nenhum grupo
  de credenciais de notarização está completo. Com `notarize: false`, que é o
  que o `init` escreve, o build local sem Developer ID segue sem assinar e diz
  isso, como sempre. `sign --notarize --require-signature` sem credenciais de
  notarização recusa nomeando os dois grupos, em vez de sair 0 dizendo
  "nothing was submitted".
- `sign.macos.identity-env` passa a valer: a variável que a config nomeia é
  lida e alimenta a identidade que a política conhece, quando
  `APPLE_SIGNING_IDENTITY` não está definida ou está vazia (um secret ausente
  no CI vira string vazia). Estava documentada, escrita pelo `init`, impressa
  pelo `doctor` — e nunca lida. O `sign` só consulta o `dovetail.yaml` nos
  alvos macOS e Windows (o Linux nunca o lê), e um yaml inválido vira nota, não
  recusa; `--file` recusa diretório.
- `doctor` diz `missing update` quando `update.public-key` não está declarada,
  e `missing signing` quando `notarize: true` não tem identidade ou credenciais
  exportadas — em vez de `ok` para o mesmo yaml que o `ship` recusa.
- `build` embute no app o que o `dovetail.yaml` decide, como `--dart-define`:
  `dovetail.update.public_key` (base64 de uma linha), `dovetail.update.endpoint`,
  `dovetail.update.base_url`, `dovetail.identifier` e `dovetail.version` (do
  `pubspec.yaml`) — e diz o que embutiu. Um só arquivo decide em quem o app
  confia, com o que o `release` assina e o que o `probe` verifica; um build de
  staging aponta para um host de staging trocando o yaml, não o app.
- `update.endpoint` no `dovetail.yaml`: onde o app instalado pergunta pelo
  manifesto (https, com os placeholders do updater). Não é o `base-url`.
- `probe --ca <pem>`: uma raiz A MAIS para esta corrida, nunca um jeito de
  pular o TLS — cadeia e hostname continuam verificados. É o que permite provar
  transporte e assinatura contra um host local com CA privada
  (`tool/serve_dist.dart`, `tool/ci/prove_update.sh`). Um PEM inválido é erro
  de uso, não defeito. Sem `--public-key`, o `probe` verifica com a
  `update.public-key` do `dovetail.yaml` ao lado, e diz isso.
- `HttpArtifactFetcher` recusa um redirecionamento que saia do https: o
  `HttpClient` segue redirecionamentos por padrão, e um CDN respondendo 302
  para um espelho http entregaria o manifesto em texto claro com a cara de
  https. Saltar é permitido; sair do https não.
- `release --public-key` vence `update.public-key`, como `--version`, `--key` e
  `--out` já venciam, e diz quando vence (os dois key ids). Era o contrário, e
  no dia em que o yaml de produção declara a chave do parque nenhum release de
  staging com par descartável seria possível sem editar o yaml de produção.
  `--public-key` e `--out` relativos resolvem contra `--root`, como
  `--artifact` e `update.key` — da raiz do repo, `--public-key keys/update.pub`
  não achava o arquivo e tratava o texto do caminho como a chave.
- Windows tinha os dois defeitos que o macOS tinha: `sign.windows.*` era lido
  do yaml e ignorado pelo signer (passa a alimentar `WINDOWS_CERTIFICATE_FILE`,
  `WINDOWS_CERTIFICATE_PASSWORD` e `WINDOWS_TIMESTAMP_URL` quando essas não
  estão definidas), e o `ship` pedia `--windows-format msi` sem o
  `--upgrade-code` que o `bundle` exige — um ship Windows morria no passo de
  bundle. O UpgradeCode passa a ser derivado do `identifier` (UUID v5, estável
  entre releases; dois produtos nunca compartilham um).
- `self-install`, `self-update` e `update` ganham limite de tempo, 30 s entre
  dois pedaços do download (o `probe` e o `doctor` usam 15 s, por serem
  sondas): um host que parou de responder não deixa mais o comando mudo.
- `probe --timeout <s>` (padrão 15) limita conexão, resposta e intervalo entre
  pedaços; um endpoint morto vira `FAILED — did not answer within 15s` em vez
  de minutos de silêncio. Zero devolve a espera do SO. O `doctor
  --check-updates` usa o mesmo limite.
- `build` mostra a saída do `flutter build` conforme ela sai, não no fim: um
  comando que só fala ao terminar não se distingue de um travado. O
  `sign --notarize` faz o mesmo com o `notarytool submit --wait`.
- `new` localiza as quatro coisas que o scaffold aponta — barril, `weave_di`,
  template do app e template do bridge — antes de escrever qualquer byte, e
  recusa **junto**: uma corrida lista tudo o que falta com a sua saída, em vez
  de mostrar uma falta por corrida. Com uma só, a mensagem é a de sempre.
- `doctor` ganha a seção `binary`: compara o `dovetail` que responde no PATH
  com o processo atual, por commit e por conjunto de comandos, e nomeia os
  comandos que o instalado não tem — o sinal que antes só aparecia na hora de
  usar um comando que não existia.

- `doctor`: sonda se a ferramenta **funciona**, não se está no PATH, e reporta
  se o alvo Rust do par SO/arquitetura está instalado.
- `icon`: de um PNG saem `.ico`, `.icns` e os PNGs do tema do Linux.
- `bundle`: nsis, msi, dmg, deb, rpm. Nunca assina.
- `sign`: codesign com notarização, ou Authenticode. Nunca empacota.
- `release`: assina cada artefato e escreve o manifesto com o conteúdo da
  assinatura, não com um caminho.
- `inspect`: lê o artefato e recusa quando a arquitetura no nome discorda do
  conteúdo.
- `manifest`: o manifesto sozinho, quando a assinatura já existe.
- `keygen`: gera o par minisign e recusa sobrescrever — a recuperação de uma
  privada perdida é reinstalar em todas as máquinas.
- `probe`: pergunta a um endpoint, de fora e pela rede, se ele serve o que o
  cliente lê, com o mesmo parser e o mesmo verificador que o app carrega.
- `ship` no Windows assina o payload **antes** de empacotar e o instalador
  depois: assinar só o instalador passa pelo SmartScreen e deposita
  executáveis sem assinatura no disco de quem instalou.
- `bundle` recusa AppImage quando a config declara serviço — o formato não
  instala nada, então não há unit, não há helper e não há kill switch.
