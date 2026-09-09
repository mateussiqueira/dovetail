# Roadmap final — dovetail para produção

> **Contexto para quem chega pelo repositório público.** Este documento nasceu
> no monorepo onde o toolkit é desenvolvido, e cita caminhos que **não existem
> aqui** — `product/vpn_desktop` é o app privado que consome o toolkit, e
> `example-rust` é o repositório de crates que ele usa por path. Nada disso é
> necessário para usar ou contribuir com os dez pacotes: cada um roda e testa
> sozinho. O documento fica porque é o inventário honesto do que falta, e é
> por ele que dá para escolher no que ajudar.

> **Levantado em 2026-09-05 contra `31f5a7d`.** Seis frentes varridas em paralelo,
> cada uma revisada por um segundo passe adversarial que adicionou 48 tarefas,
> corrigiu 68 estimativas/critérios e descartou 15 itens como não-bloqueantes.
> Total: 118 tarefas levantadas, 166 depois da crítica.
>
> Os achados foram revalidados contra `31f5a7d` depois que o HEAD avançou 14
> commits durante a análise (SPM, `dovetail bridge`, prova e2e do SDK em
> container, `install.sh`/`self-install`/`self-update`, quickstart). Os seis
> defeitos estruturais abaixo continuam presentes nessa árvore.
>
> Todo critério de aceite é um comando ou um artefato verificável. Onde um
> número aparece, ele foi medido nesta máquina, não estimado.

> **Atualização 2026-09-06, `31f5a7d..74d2cb0` (17 commits, branch
> `roadmap/m0-sai-desta-maquina`).** Dos seis defeitos estruturais da seção 1,
> três se moveram: o baseline agora é gravado **frio** de verdade
> (`tool/rebless_cold.sh`, 1404 declarados, 44 pulados); o `dovetail new` não
> emite mais o alias de SSH e localiza barril, `weave_di` e os dois templates
> antes de escrever, recusando junto o que faltar; e o `weave_di` passa a
> viajar dentro do SDK como os outros pacotes do runtime. Os outros três não
> são código: CI sem job (billing da conta), nada compilado com MSVC, e
> nenhum certificado nem host. O que mais entrou está no `git log` e nos
> CHANGELOGs; os números desta página continuam os de 05/09 onde não foram
> refeitos.
>
> **Mesmo dia, mais tarde — Marco 4.** `m4-signer-dmg` e `m4-ship-macos-ordem`
> feitos: `sign --target macos --file <dmg>` existe, o dmg é notarizado direto
> e a esteira macOS completa os cinco passos. `m4-require-signature` feito com
> gatilho em `notarize: true` (não em "seção declarada", porque o `init`
> escreve `sign.macos` em todo projeto), e a recusa acontece antes do build, no
> `--dry-run` e no `doctor`. `m4-config-chega` feito: `identity-env`,
> `entitlements` e as três chaves `sign.windows.*` chegam ao signer.
>
> **Marco 5, no mesmo dia.** `m5-ship-tarball` feito (o `archive` gera o
> `.app.tar.gz` e o manifesto aponta para ele; o dmg fica fora do manifesto).
> `m5-e2e-macos` feito como `tool/ci/prove_update.sh --host macos`, que
> passou nesta máquina de ponta a ponta com substitutos de mesmo contrato:
> par descartável, host https em loopback com CA privada, identidade ad hoc.
> `m5-public-key` ligado ao app: o `build` embute a chave e o endpoint do
> yaml via `--dart-define`, e o `app_release.dart` os lê. O que resta do
> marco é o que só o real prova: notarização, DNS, o parque aceitando.
>
> **Fim do dia, `74d2cb0..baf1265` (6 commits mais).** Por id, o que mudou de
> estado e o que ficou pela metade:
>
> - `m4-upgrade-code` **feito**, sem chave nova no vocabulário: o UpgradeCode é
>   derivado do `identifier` (UUID v5 sobre o namespace URL), estável entre
>   releases e distinto entre produtos, com o vetor preso em teste. Um ship
>   Windows morria no passo de bundle e não morre mais.
> - `m5-chave-uma-fonte` **feito**: `update.endpoint` entrou no `UpdateConfig`,
>   e `dovetail build` embute chave, endpoint, base-url, identifier e versão
>   como `--dart-define`. A varredura da saída de build entre sign e bundle,
>   que o item também pedia, **não** foi feita.
> - `m5-fetch-redirect` **feito**, e por duas vezes: o primeiro conserto
>   comparava o esquema do `Location` e teria recusado todo salto relativo —
>   quebrando o updater contra qualquer CDN. Agora os saltos são seguidos à
>   mão, resolvidos contra a url atual, recusados antes do pedido seguinte. O
>   O `Accept` também foi corrigido para `application/json, */*`, a segunda
>   metade do item: pedir só json para um tarball autoriza um 406 no download.
> - `m5-fetch-timeout` **feito no fetcher** (limite de conexão, cabeçalhos e
>   entre pedaços; `probe --timeout`, 30 s nos três comandos que baixam). O
>   `update_flow.dart` que só avança para o próximo endpoint quando o fetch
>   **lança** continua como está.
> - `m4-preflight` **parcial**: as recusas de notarização e de
>   `update.public-key` acontecem antes do build; `minisign` ausente e variável
>   de senha vazia ainda são descobertos no último passo.
> - `m4-windows-signer-select` **não feito**, e agora está escrito como é: um
>   certificado em arquivo vai para o `osslsigncode` em qualquer host, e o
>   `signtool` só é alcançado por thumbprint — que não tem chave no yaml.
> - `m4-docs-assinatura` **feito** para as afirmações que existiam, mas o dia
>   criou e corrigiu outras: uma revisão de seis lentes achou 49 pontos, e onze
>   eram doc contradizendo o código, incluindo um `dovetail.yaml` de quickstart
>   que os próprios comandos recusavam.
>
> E entrou uma prova que o levantamento não pedia: `dart tool/verify.dart
> release` roda a esteira macOS inteira contra um host local dentro do portão,
> pulando com a razão escrita quando não há build. Fora do portão, medido no
> mesmo dia: `tool/soak.sh 5` deu `5/5 green` duas vezes,
> `tool/prove_on_linux.sh` deu `both suites passed`.


## 1. Onde está

O framework é um monorepo que só funciona nesta máquina: doze pacotes cujo portão não resolve sem dois repositórios privados, um baseline gravado quente e vendido como frio (`docs/ci.md:34` vs `tool/skip_baseline.json`), 29 corridas de CI que nunca criaram um job, nada jamais compilado com MSVC, nenhum comando que publique, nenhum certificado, nenhum host — e um `dovetail new` que gera um `pubspec.yaml` apontando para `git@weave-di.github.com:` (`new_command.dart:328`), um alias de SSH que existe só no `~/.ssh/config` do autor. O que separa isso de produção não é uma lista de features: é que **nenhuma afirmação do repositório foi verificada por alguém que não seja você, numa máquina que não seja esta.**

---

## 2. Os marcos

Convenção de tamanho usada em toda a tabela e no caminho crítico: **XS ≤ 0,5 dia · S = 1 dia · M = 2,5 dias · L = 5 dias · XL = 12 dias** (uma pessoa, dia útil).

---

### Marco 0 — Sai desta máquina

**Condição de saída:** `git clone <repo> /tmp/solo && cd /tmp/solo && dart tool/verify.dart all --only toolkit && dovetail new demo && cd demo && flutter pub get` sai 0 numa máquina sem `example-rust`, sem `example-design-system` e sem o `~/.ssh/config` do autor.

Este marco existe porque **todo critério de aceite de todos os outros marcos é inexecutável sem ele.** Hoje `case 'fast'` (`tool/verify.dart:83-84`) despacha `_fast()` sem `--only`, `_fast()` analisa os doze pacotes de `tool/verify.dart:31-44`, e `_cross` chama `_pluginCoverage()` incondicionalmente em `tool/verify.dart:476` — que roda `flutter pub get --enforce-lockfile` contra `product/vpn_desktop`. Então `cross --only toolkit` (`ci.yml:183`, `:259`) também não é toolkit-only, e `tool/githooks/pre-commit` executa `verify fast`: o primeiro `git commit` de um segundo engenheiro falha.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m0-toolkit-only` | `--only toolkit` real para `fast`, `cross` e `all`; job de CI com `SIBLINGS_TOKEN` deliberadamente vazio | M | — | — |
| `m0-weave-di` | Remover a dependência por alias SSH que todo app gerado herda (`new_command.dart:326-329`) | M | — | ✔ decidir: publicar no pub.dev ou URL https legível |
| `m0-app-clone` | `pubspec_overrides.yaml` entra no `.gitignore` do template (`tool/sdk/templates/app/.gitignore`, hoje 0 ocorrências) e o `pub get` de um clone erra citando `dovetail upgrade` | S | `m0-weave-di` | — |
| `m0-scripts-portateis` | `grep -rn '/Volumes/BACKUP' tool/` = 0 (hoje 2: `prove_bridge.sh:15,35`); `sed -i ''` some; `tool/ci/build_gate_image.sh` constrói a imagem que hoje exige um `flutter_linux.tar.xz` baixado à mão | M | — | — |
| `m0-release-portavel` | `tool/release.sh` roda de um clone limpo: `prove_bridge.sh` recebe `--core` e pula com motivo quando o sibling falta | S | `m0-scripts-portateis` | ✔ decidir se o canário da ponte continua sendo portão de release |
| ~~`m0-licenca`~~ **FEITO** | MIT na raiz, nos dez pacotes e nos dois `Cargo.toml`, com o copyright de Mateus Siqueira. Era o caso em que a doc convidava a consumir e a licença proibia | XS | — | — |
| `m0-repo-state` | `git check-ignore -q toolkit/dovetail_form_validation/build` passa (hoje sai 1: `.gitignore:11` é `/build/`, ancorado na raiz — 8,1 MB prestes a entrar na história) | XS | — | — |

---

### Marco 1 — Verde quer dizer verde

**Condição de saída:** `bash tool/soak.sh 10` imprime `10/10 green`, e `bash tool/ci/prove_baseline_is_cold.sh` (que estaciona os artefatos, aplica um PATH mínimo, roda `test` e `bless`) deixa `git diff --exit-code tool/skip_baseline.json` limpo — duas vezes seguidas.

O portão hoje é 1 vermelho em 2 corridas (`tool/verify.dart:523` roda 3 pacotes por lane; os seis últimos de `_packages` são todos `flutter`, então a lane 4 são três `flutter test` concorrentes sobre um cache só). E quando fica vermelho não diz por quê: `tool/verify.dart:600-605` captura o stderr e `:621-626` imprime só `parsed.failures` — que está vazia quando o runner morre antes do primeiro JSON. Foi exatamente isso que produziu `FAILED product/vpn_desktop` com zero testes.

**Decisão sobre concorrência:** isolamento por runner, não serialização geral e **não retry-com-quarentena** — retry torna verde compatível com "não provado", que é a única patologia que `tool/verify.dart:1-16` existe para impedir. Um flake genuinamente insolúvel vira skip nomeado no baseline, visível.

**Decisão sobre o baseline:** não construir o app em CI. Construir puxa quatro crates privadas por path (`product/desktop_core_bridge/rust/Cargo.toml:17-21`), então um vermelho nasceria noutro repositório, e minuto de macOS custa 10x. O baseline é gravado no **piso** dos ambientes prováveis e ganha uma dimensão de capacidades, para que "skip novo explicado por uma ferramenta ausente" seja notícia e "skip novo inexplicado" continue fatal.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m1-stderr` | Um pacote FAILED imprime exit code e a cauda do stderr; suíte que falha ao **carregar** vira `LOAD FAILED`, não `declared: 0` | S | — | — |
| `m1-lanes` | Seis pacotes `dart` 3-wide, seis `flutter` um de cada vez, `--concurrency`/`-j` explícito por invocação, `DOVETAIL_LANES` como override; `tool/soak.sh` versionado | M | `m1-stderr` | — |
| `m1-bless-recusa` | `bless` recusa run file parcial (`--only`), vermelho, ou de outro sha. Hoje `dist/verify-run.json` tem **82 bytes** — um pacote, `suites` vazio — e `_bless` (`:852-864`) é um `cp` cego | S | `m1-stderr` | — |
| `m1-fingerprint` | `verify-run.json` e `skip_baseline.json` carregam um bloco `environment` (ferramentas + artefatos); `_compare` rebaixa `SKIP NEW` a notícia só quando o motivo nomeia uma capacidade que o baseline tinha e esta corrida não | M | `m1-guards-tabela` | — |
| `m1-baseline-frio` | Regravar o baseline no piso, e corrigir `docs/ci.md:34` e `:81` (a frase "forma fria" é falsa) | M | `m1-fingerprint`, `m1-bless-recusa` | — |
| `m1-readme-total` | `README.md:90` ("1371 declarados, 2 pulados") acompanha o baseline novo — commit obrigatório, o número só é conhecido depois da corrida | XS | `m1-baseline-frio` | — |
| `m1-suite-nova` | `_compare` reporta `SUITE NEW` — hoje itera só `recorded.entries`, então um arquivo de teste novo com dez skips não é problema nem notícia | XS | — | — |
| `m1-guards-tabela` | `_toolsBehindSkips` (`:49-58`) gerado a partir dos executáveis que os testes de fato invocam (23 nomes reais; a lista atual cita `rpmbuild` e `wixl`, que nenhum teste chama, e omite `rustup`, `codesign`, `python3`, `osslsigncode`, `makensis`) | S | — | — |
| `m1-skips-gerado` | `dart tool/verify.dart skips --check` gera `docs/skips.md`, uma linha por guarda, e falha quando as linhas ≠ nº de `markTestSkipped` na árvore (137 hoje) | M | `m1-fingerprint` | — |
| `m1-cwd` | `Directory.current` some de doze call-sites de teste em cinco pacotes; `test/support/repo_root.dart:6-11` explica por que é perigoso e três pacotes já têm o helper | M | — | — |
| `m1-docs-index-varredura` | `docs_index_test.dart:75` compara **caminho**, não basename (19 dos 31 documentos são `README.md`, então uma menção cobre todos), e varre `git ls-files`, não o filesystem com `dist/` dentro | S | — | — |

---

### Marco 2 — O portão roda em CI e barra um merge

**Condição de saída:** um PR com o gate vermelho recusa `gh pr merge`, nomeando o check; `gh api repos/.../branches/main/protection --jq '.required_status_checks.contexts|length'` = 3.

Nada aqui é código difícil; é uma conta e três bugs de YAML que só aparecem num runner. O maior deles: `ci.yml:65-67` define `working-directory: dovetail` como default do job, e esse default vale para o **primeiro** passo — a guarda de `SIBLINGS_TOKEN` em `:69-76` — que roda **antes** do `checkout with: path: dovetail` em `:77-79`. No runner o workspace está vazio ali, então nenhuma das quatro linhas `::error::` chega ao log. É a única mensagem do arquivo que nunca pode ser vista, e é a mensagem escrita para quem bate nela primeiro.

Segundo: `ci.yml:177-184` e `:253-260` põem seis comandos num único `run:`, que roda sob `bash -e`. O primeiro não-zero encerra o passo e os cinco restantes não executam — jogando fora exatamente a propriedade que `_all()` foi escrito para ter (`tool/verify.dart:110-113`), nas duas pernas que nunca rodaram uma vez.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m2-billing` | Destravar Actions na conta. 29/29 `startup_failure` em 0s; todo repo privado do dono falha idêntico, todo público roda. `branches/main/protection` devolve 403 "Upgrade to GitHub Pro" — a mesma decisão | XS | — | ✔ **comprar plano / tornar público / mover para org** |
| `m2-primeiro-passo` | Passo 1 de cada job ganha `working-directory: .` (ou o default sai); prova: com o secret removido, `gh run view --log \| grep -c 'SIBLINGS_TOKEN is not set'` = 3 | XS | `m2-billing` | — |
| `m2-tudo-depois-decide` | Pernas Linux/Windows viram um passo por alvo, ou `verify all`; numa corrida vermelha o log mostra ≥ 6 cabeçalhos `── ` | S | `m2-billing` | — |
| `m2-pr-trigger` | `pull_request` + `merge_group`; `cancel-in-progress: ${{ github.event_name != 'merge_group' }}` e nunca em push para `main` (hoje `:37-39` descarta o veredito de um commit já mergeado) | XS | `m2-billing` | — |
| `m2-branch-protection` | Três contextos obrigatórios; atenção aos nomes com **·** não-ASCII (`ci.yml:62`, `:131`, `:211`) — renomear para ASCII ou citar exato | S | `m2-pr-trigger` | ✔ mesma decisão de plano |
| `m2-cache` | `cargo-binstall` no lugar do `cargo install flutter_rust_bridge_codegen --locked` (`:106`, compila do fonte toda corrida), cache de Rust e de `~/.pub-cache` | S | `m2-billing` | — |
| `m2-rede` | Digest-pin nos três `docker pull` anônimos (`prove_on_linux.sh:14-15`, `prove_guard_on_wine.sh:18`), retry, e um vermelho de rede distinguível de um vermelho de código | M | `m2-billing` | — |
| `m2-ffi-decisao` | Decidir o alvo `ffi` na perna macOS: `_ffiCrosses` (`:915-963`) **abre uma janela** por documentação própria (`:912-913`), é o maior build da perna 10x, e puxa as crates privadas. Manter com pré-condição de window server e falha nomeada, ou tirar do `all` do runner | M | `m2-billing` | — |
| `m2-toolchain-pin` | Um arquivo versionado é a fonte de `FLUTTER_VERSION`/`RUST_VERSION`; `doctor` checa **versão**, não presença (`tool/verify.dart:164-210` só faz `_which`) | S | — | — |
| `m2-runner-json` | `dist/runner.json` (imagem, arch, cpus) dentro da primeira corrida verde; pins explícitos mantidos, sem workflow canário | XS | `m2-billing` | — |
| `m2-politica-gatilho` | Linux em todo push e PR; macOS e Windows em `pull_request`, `merge_group` e nightly. Orçamento executável: `gh api .../timing --jq` × 10 (macOS) + × 2 (Windows), comparado com um teto escrito | S | `m2-branch-protection`, `m2-cache` | ✔ o teto mensal é decisão de gasto |

---

### Marco 3 — O nativo compila, linka e roda nos três

**Condição de saída:** `gate-windows` e `gate-linux` terminam verdes com `dart tool/verify.dart baseline` rodando neles, e o `.dll`/`.so` que um app de consumidor embarca foi produzido pelo toolchain daquele SO — não por `cargo check`.

`cargo check` produz `.rmeta` e para antes do codegen. Medido: `x86_64-pc-windows-msvc/debug/deps` tem 17 arquivos, todos `.rmeta`, zero `.lib`/`.o`. `tool/verify.dart:386-387` passa `-c` ao mingw, então o guarda do Windows compila para objetos e nunca linka. E `tool/verify.dart:376-378` e `:451-454` imprimem `absent` e seguem **sem incrementar `failed`** — então a perna `cross` sai 0 tendo checado nada, inclusive no runner Windows, que recebe só `targets: x86_64-unknown-linux-gnu` (`ci.yml:250-251`).

O fixture certo para o build é `dovetail new`, não `product/vpn_desktop`: é código do framework, não puxa as crates privadas, e é literalmente o que o usuário do framework recebe.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m3-cross-absent-vermelho` | `verify cross` sai não-zero quando falta triple ou mingw, salvo `--allow-absent` explícito | S | — | — |
| `m3-link-mingw` | `cargo build --target x86_64-pc-windows-gnu` produz `.dll`; a saída diz "links for … (mingw ABI; MSVC unproven)" — não retira o risco de linker MSVC | M | `m3-cross-absent-vermelho` | — |
| `m3-guard-dll` | O guarda vira DLL linkada no lane `cross` (o `build_guard_probe.sh:24-38` já faz isso e não está ligado a nada); apagar um `DOVETAIL_EXPORT` põe vermelho | S | `m3-cross-absent-vermelho` | — |
| `m3-win-suite-carrega` | A suíte Dart carrega e passa no Windows: `doctor_test.dart:17` escreve um `#!/bin/sh` e o executa, `rust_target_probe_test.dart:61,88,107` idem, `deb_directory_test.dart:95` cria `Link` relativo | M | `m2-billing`, `m1-lanes` | — |
| `m3-win-tools` | A perna Windows instala ferramenta alguma hoje (`ci.yml:249-260`); choco/scoop para minisign, makensis, osslsigncode, openssl, xmllint, python3 | S | `m3-win-suite-carrega` | — |
| `m3-msvc-cpp` | `ilammy/msvc-dev-cmd` + `cl /std:c++17 /LD` + `dumpbin /exports` com os quatro símbolos; ensinado ao `_cross`, não um passo avulso | M | `m3-win-suite-carrega` | — |
| `m3-guard-nativo` | O handshake de duas processos roda no Windows de verdade (`prove_guard_on_wine.sh:13` já diz que wine é segunda opinião) | S | `m3-msvc-cpp` | — |
| `m3-flutter-build-fixture` | `dovetail new` + `flutter build <host>` nas **três** pernas. Nenhuma perna roda `flutter build` hoje; `new_command_test.dart:249-266` só confere que o `CMakeLists.txt` foi preenchido | L | `m3-msvc-cpp`, `m3-win-tools` | — |
| `m3-nsis-real` | O único skip de ferramenta do baseline vira passo: makensis real sobre o `.nsi` gerado, no runner. Em paralelo, `bundle_command.dart:81` passa a default `msi`, alinhado com `ship_command.dart:22-27`, e o help diz que NSIS é não-provado | M | `m3-win-tools` | — |
| `m3-baseline-por-so` | `skip_baseline.{linux,windows}.json`; `_compare` escolhe por `Platform.operatingSystem`; as duas pernas passam a rodar `baseline` | M | `m1-fingerprint`, `m3-win-suite-carrega` | — |
| `m3-linux-arch` | Uma linha: a perna Linux afirma `test "$(uname -m)" = x86_64` e grava a arch no artefato — o resto (`prove_on_linux.sh:17-28`, `prove_guard_on_wine.sh:39-43`) já existe | XS | `m2-billing` | — |
| `m3-registry-nativo` | Os 17 testes de registro real rodam no Windows (Win32 `RegisterHotKey`) e no Linux sob `xvfb-run` (X11 `XGrabKey`); hoje só o backend Carbon jamais executou | M | `m3-baseline-por-so`, `m3-flutter-build-fixture` | — |
| `m3-ffi-crossing` | `verify ffi` sai não-zero onde não cruzou (hoje `:918-924` imprime "skipped" e devolve 0); o cruzamento Dart↔Rust é observado nos três SOs | L | `m3-flutter-build-fixture` | — |
| `m3-si-race` | `claim()` atômico: medido 10/10, duas chamadas simultâneas lançam `SocketException` de dentro de `_takeOver` e escapam do `main()` antes do `runApp` (`socket_single_instance.dart:78-82`) | M | — | — |
| `m3-si-peer-unix` | Autenticar o par: hoje um processo local que faz bind primeiro recebe o payload inteiro com o deep link, e o app real sai (`single_instance_verdict.dart:6`). `/tmp` é 1777 no Linux — é cross-user lá | M | `m3-si-race` | — |
| `m3-si-peer-win` | Idem no Windows: `FindWindowExW(nullptr,nullptr,…)` (`single_instance_guard.cpp:41-42`) casa qualquer janela, `dwData` é 0 sem magic nem versão, e `AllowSetForegroundWindow` é dado ao invasor primeiro | M | `m3-guard-dll` | — |
| `m3-copydata-bounds` | `guard_window.cpp:30-31` monta `std::wstring` a partir de `cbData` sem teto, sem paridade e sem NUL exigido; papel `hostile` no `guard_probe.cpp`, rodado na perna Linux via wine | M | `m3-guard-dll` | — |
| `m3-deeplink-schemes` | `DesktopAppSpec` ganha allow-list e `dovetail_platform_channel.dart:140` para de construir `JoinedDeepLinkInbox` sem `schemes:` (conjunto vazio = filtro desligado, `launch_arguments.dart:16`). Recusa em runtime, não `assert` — o build que importa é release | S | — | — |
| `m3-deeplink-ordem` | `ensureInitialized` antes de `claimSingleInstance` derruba todo link encaminhado em silêncio (`:135-142` lê `_guard` estático, setado só em `:64-68`) | S | — | — |
| `m3-ffi-panic` | Nove `.expect("lock poisoned")` atravessam `extern "C"` e abortam o app do consumidor; `dovetail_rust_core/rust/src/data/pump_table.rs` já decidiu o contrário e escreveu por quê (o caminho ganhou a camada em 2026-09-07) | M | — | — |
| `m3-pump-panic` | Um pump que entra em pânico hoje some: o `JoinHandle` é descartado (`task.rs:12-19`), a entrada morta não é colhida, e o stream Dart congela no último valor | M | — | — |
| `m3-runtime-blocking` | Runtime tokio sem `worker_threads`/`max_blocking_threads` e sem `spawn_blocking` exposto: medido, 11 pumps bloqueantes entregam 0 de 50 eventos concorrentes e `abort()` não ajuda | M | — | — |
| `m3-pump-lag` | 100k eventos num canal de 16 entregaram 65.809 — 34% perdidos, reportados só por um `tracing::warn!` sem subscriber | S | — | — |
| `m3-spm-install-name` | Medido: o dylib do XCFramework carrega `/Volumes/BACKUP/...` como install name nas duas fatias; `build_xcframework.sh:52-66` nunca passa `-install_name` | S | — | — |
| `m3-spm-portao` | `verify spm` que realmente constrói com SPM ligado (o `README.md:365-372` afirma provado; `flutter config` diz `false` e nenhum alvo liga a flag) | M | `m3-spm-install-name` | — |
| `m3-spm-loader` | `library_loader.dart:35-37` procura um nome que a rota SPM não entrega | M | `m3-spm-portao`, `m3-spm-install-name` | — |
| `m3-xcframework-stale` | `spm_report.dart:57-73` diz `ready` só por o diretório existir; digest de `rust/src` + `Cargo.{toml,lock}` ao lado, e `stale` quando difere | S | `m3-spm-portao` | — |
| `m3-capabilities` | `README.md:94` diz instância única `✗` no Windows; `platform_capabilities.dart:24-28` e o teste dizem `true`. Teste que lê a tabela do README e a confronta, 12 capacidades × 3 hosts | S | — | — |
| `m3-tray-icon` | `TrayIconAsset` é um path cru entregue ao `tray_manager` (`tray_manager_surface.dart:43`); Windows quer `.ico`, macOS quer template PNG — recusa nomeada por host | S | `m3-capabilities` | — |
| `m3-wayland-ci` | `prove_wayland_session.sh` entra na perna Linux (não depende de build Flutter nenhum) | S | — | — |

---

### Marco 4 — O download abre sem aviso

**Condição de saída:** para o `.dmg`, `codesign --verify --strict` + `xcrun stapler validate` + `spctl -a -t open --context context:primary-signature` dizendo `source=Notarized Developer ID`; para o instalador Windows, `osslsigncode verify` no container **e** em cada `.exe`/`.dll` do payload; e um pipeline sem credenciais sai **não-zero**, nunca 0 com um artefato sem assinatura.

O bug estrutural é `ship_plan.dart:144`: `'macos' => [signing, bundling]`. O Windows é `[signingPayload, bundling, signing]` e está certo. No macOS não há assinatura depois do bundle, então o `.dmg` que o usuário baixa sai sem assinatura — o `.app` dentro fica assinado, e o macOS avalia a imagem no mount.

O segundo é que `--require-signature` existe em dois lugares não-teste (`sign_command.dart:23,52` e `dovetail_signer/bin/dovetail_signer.dart:17,37`) e o `ShipPlan` emite em **zero** das doze invocações. Sem ele, `signing_policy.dart:50-55` devolve `skip` e `sign_command.dart:84-86`, `:138-140`, `:225-227` cada um faz `return 0`. Os READMEs dizem que a flag é "a que só a esteira passa" — a esteira é o único chamador que nunca passa.

E há dois caminhos independentes de reportar sucesso sobre um artefato que o Gatekeeper recusa: `APPLE_SIGNING_IDENTITY=-` passa a política (ela só checa não-vazio) e `codesign --verify` aceita ad-hoc — que é por que `real_codesign_test.dart:67` fica verde assinando com `-`.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m4-ferramenta-ausente` | Ferramenta faltando nomeia a si mesma. Medido: `--osslsigncode /nonexistent` imprime "This is a defect in dovetail" + 14 frames. `SystemProcessRunner.run:24` chama `Process.start` sem nada em volta, e `bin/dovetail.dart:61` só pega `ProcessException` pelo braço `Object` | S | — | — |
| `m4-recusa-adhoc` | Identidade `-` é recusada antes do `codesign`; após assinar, o signer exige uma linha `Authority=` e ausência de `adhoc` nas flags | S | — | — |
| `m4-fixture-sem-credencial` | CA + PKCS#12 gerados em runtime (o padrão já existe em `prove_sdk.sh:53-62`) e keychain descartável no macOS, para que todo aceite negativo ("virar um byte") rode numa máquina sem certificado | M | — | — |
| `m4-require-signature` | `ShipPlan` emite a flag; ela passa a valer também para os grupos de notarização quando `--notarize` está presente (hoje `sign … --notarize --require-signature` sem `APPLE_ID` sai **0** dizendo "nothing was submitted"); a perna Linux diz o que exige ou que a flag é inerte lá | M | `m4-ferramenta-ausente` | — |
| `m4-config-chega` | `sign.macos.entitlements` e `identity-env`, `sign.windows.certificate-env`/`timestamp-url` chegam ao signer. Hoje `config_template.dart:43-56` escreve `DOVETAIL_MACOS_IDENTITY` e o signer lê `APPLE_SIGNING_IDENTITY` — os três defaults do `init` são mortos, e `project_report.dart:126-133` faz o `doctor` dizer `ready` para eles. `--force` sem `--entitlements` derruba o `app-sandbox` que o Xcode aplicou | L | `m4-require-signature` | — |
| `m4-upgrade-code` | `ship` default é `msi` (`ship_command.dart:22-27`), `ShipPlan` nunca emite `--upgrade-code`, e `bundle_command.dart:186-196` lança. Chave nova no vocabulário do config (com `docs/configuracao.md`, senão `config_documented_test` quebra) e GUID gerado pelo `init` | M | — | — |
| `m4-signer-dmg` | O signer aceita `--file` no macOS e o `Notarizer` pula o `ditto` para arquivo plano; `notarization_step.dart:26` para de anexar `.zip` | M | — | ✔ Developer ID + credencial de notarytool |
| `m4-ship-macos-ordem` | Plano macOS vira `[build, sign .app, bundle, sign+notarize+staple dmg]`; atualizar `ship_plan_test.dart:86-102` (preservando a metade Linux), `:104-116` e `:118-124` | S | `m4-signer-dmg` | — |
| `m4-windows-signer-select` | Seletor explícito de signer: `sign_command.dart:123-131` roteia para o caminho de arquivo sempre que `WINDOWS_CERTIFICATE_FILE` existe, tornando o caminho `signtool /sha1` (o único compatível com HSM/nuvem) inalcançável | S | — | — |
| `m4-windows-verify` | As duas assinaturas são exigidas e conferidas; teste negativo deixa uma DLL do payload sem assinar e espera não-zero nomeando-a | M | `m4-require-signature`, `m4-upgrade-code`, `m4-windows-signer-select` | ✔ certificado OV/EV |
| `m4-verify-command` | `VerifyCommand` de topo (registrado em `bin/dovetail.dart:20-40`, logo `readme_covers_commands_test` cobra), verificando os caminhos exatos de `ShipPlan.artifacts` — não `dist/*` | L | `m4-ship-macos-ordem`, `m4-windows-verify`, `m4-fixture-sem-credencial`, `m5-linux-sums` | — |
| `m4-argv-senha` | `osslsigncode_request.dart:57` põe a senha do PKCS#12 no argv, legível por `ps`/`/proc`. `-readpass` num arquivo 0600 sob `RUNNER_TEMP`; `update_signer.dart:63-76` já é o precedente correto | XS | — | — |
| `m4-notarytool-retomavel` | O id da submissão é impresso antes do wait e a expiração dos 30 min fixos (`notarizer.dart:12`) diz `xcrun notarytool wait <id>` em vez de "defect in dovetail" | S | `m4-ferramenta-ausente` | — |
| `m4-preflight` | Recusar antes do build: minisign ausente, `update.key` ausente, variável de senha vazia, `update.base-url` ausente. Hoje a etapa de release é a **última** do plano (`ship_plan.dart:150-167`) e o primeiro `ship` de um estranho gasta o build inteiro para morrer nela | S | — | — |
| `m4-dry-run-quote` | `ShipStep.toString()` é `invocation.join(' ')` (`ship_step.dart:15`): todo nome de produto com espaço torna o `--dry-run` não colável | XS | — | — |
| `m4-inspect` | `dovetail inspect app.dmg` não diz nada — `diskImage` cai no braço `_ =>` de `artifact_inspector.dart:17-25`, embora `codesign --verify` funcione em imagem | S | `m4-ferramenta-ausente` | — |
| `m4-ci-secrets` | `release.yml` que importa Developer ID num keychain só do runner e apaga em `if: always()`; alvo é `tool/release.sh` + assinatura do binário, e o `ship` end-to-end roda num fixture criado por `dovetail new` — **não** em `product/` (não há `dovetail.yaml` na raiz) | L | `m2-billing`, `m4-require-signature`, `m6-key-custody` | ✔ comprar/baixar .p12, criar chave App Store Connect, gravar secrets |
| `m4-cli-notarizado` | Medido: `dart compile exe` dá `Signature=adhoc`, `spctl --assess` = `rejected`, e `build_release.sh:71-87` vai de `compile` a `tar` sem passar por `codesign`. Regressão: `xattr -w com.apple.quarantine … && ./dovetail --version` sai 0 | M | `m4-ci-secrets` | ✔ mesmo certificado |
| `m4-ev-decisao` | Decisão escrita: Azure Trusted Signing/DigiCert KeyLocker (chave EV não é exportável desde a baseline de 2023) ou OV+HSM aceitando a rampa de reputação do SmartScreen | S | `m4-windows-signer-select` | ✔ **compra + validação de organização: dias a semanas** |
| `m4-docs-assinatura` | As quatro afirmações que o código contradiz (`dovetail_signer/README.md:27`, `dovetail_bundler/README.md:96`, `README.md:212-214` vs `dovetail_cli/README.md:658-661`) passam a valer — e o teste que as guarda resolve caminho por `inRepo()` | XS | `m4-require-signature`, `m7-readme-raiz` | — |

---

### Marco 5 — A atualização fecha o laço

**Condição de saída:** `bash tool/ci/prove_update.sh --host macos` sai 0 imprimindo, em ordem: o pid da v1, `installed 2.0.0`, um pid **novo**, e a v2 lida do bundle; depois instala uma v3 que não sobe e assere que o bundle voltou para 2.0.0 com o app rodando.

O laço não fecha em cinco pontos independentes. Formato: `ship_plan.dart:243` registra `.dmg` e `macos_installer.dart:34-42` escreve `update.tar.gz` e roda `tar -xzf` procurando um `.app` — `installer_for_host.dart:21-35` não tem branch de dmg, então toda atualização macOS morre depois do download. **Decisão: muda a esteira**, porque no macOS o `.app` é o que carrega assinatura e ticket, enquanto ensinar `hdiutil` ao instalador montaria uma imagem de terceiro sob `/Volumes` de dentro do app sendo substituído.

Confiança: `release_command.dart:66-87` só recusa chave estranha quando `declared != null`, e `product/vpn_desktop/dovetail.yaml:5-9` não declara `public-key` — então a guarda nunca dispara e a descoberta acontece na máquina de um estranho.

Segurança: `verified_artifact.dart:16-22` deriva `fileName` de `Uri.pathSegments.last`, e `Uri` decodifica escapes — `..%2F..%2Fevil.deb` vira `../../evil.deb`, que `p.join` normaliza para `/evil.deb`, e `linux_installer.dart:101-103` roda `dpkg` nisso como root. Os bytes são verificados; o **nome** vem do manifesto, que não é assinado.

E o comentário confiável assinado nunca é comparado com nada (`update_flow.dart:100-114`): quem responde o endpoint serve o artefato 1.0.0 legitimamente assinado sob um manifesto que declara 3.0.0 — e a política de downgrade (`update_policy.dart:23-28`) depois recusa a 3.0.0 real. Pin permanente, aprovado por assinatura.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m5-fmt-contract` | Uma tabela de formato por plataforma consultada pelo `ManifestWriter`, por cada instalador **e pelo `dovetail probe`** (hoje o probe não olha extensão nenhuma e reporta verde sobre um manifesto que nenhum instalador abre). Inclui o inteiro `format` no manifesto | M | — | — |
| `m5-ship-tarball` | `ship` emite `<binário>_<versão>.app.tar.gz` como artefato de update **e** mantém o `.dmg` como artefato de download; teste de ida-e-volta produtor↔consumidor, não dois fixtures feitos à mão | M | `m5-fmt-contract`, `m4-ship-macos-ordem` | — |
| `m5-public-key-obrigatoria` | `update.public-key` obrigatória quando há bloco `update:`; inclui `config_template.dart:31-39` e todos os fixtures, senão todo projeto recém-gerado passa a ser recusado | M | — | ✔ só uma pessoa sabe qual chave o parque confia; a privada de `A77782E0673FA036` não está nesta máquina |
| `m5-chave-uma-fonte` | Constantes de release geradas de `dovetail.yaml` (+ campo `endpoint`, que `UpdateConfig` não tem); `ship` varre a **saída de build não comprimida** entre sign e bundle — varrer o artefato final é impossível, ele é gzip/LZMA/UDZO | M | `m5-public-key-obrigatoria` | — |
| `m5-release-verifica` | `release` verifica o que assinou com o `MinisignVerifier` do cliente, e recusa quando o último segmento da url difere do basename local (é o que vai no comentário assinado) | S | `m5-public-key-obrigatoria` | — |
| `m5-comentario-ligado` | Comparar `version:` e `file:` do comentário assinado com o manifesto e a url, **dentro** de `download()` antes de construir `VerifiedArtifact`; campo ausente é recusa nomeada (o default do minisign não traz `version:`) | S | `m5-release-verifica` | — |
| `m5-traversal` | `fileName` recusa `/`, `\`, `.`, `..`; instaladores assertam `p.isWithin(scratch, path)` | S | — | — |
| `m5-fetch-timeout` | `HttpClient` sem `connectionTimeout`/`idleTimeout` e sem `.timeout()` no `await for`; `update_flow.dart:47-55` só avança quando o fetch **lança**, então um servidor que trava desativa os outros endpoints. `UpdateWatch` reagenda a cada 6 h | XS | — | — |
| `m5-fetch-redirect` | Redirect https→http é seguido (o guard de `http_artifact_fetcher.dart:18` roda uma vez); e `Accept: application/json` vai também no `.tar.gz` e no `latest` | S | — | — |
| `m5-so-update-failure` | `utf8.decode` em `update_flow.dart:69` está fora do try; corpo não-UTF-8 vira `FormatException` não capturada, assíncrona, a cada 6 h, para sempre | S | — | — |
| `m5-pub-date` | O `ManifestWriter` não emite `pub_date` — o campo que `manifest_parser.dart:117-142` valida com rigor e ninguém produz | XS | — | — |
| `m5-macos-local` | Recusar bundle não-`.app`, sob `AppTranslocation`, ou onde não se pode escrever. O `.dmg` não assinado faz o primeiro install rodar translocado: o update "tem sucesso" num diretório que some no logout | S | — | — |
| `m5-macos-elevacao` | `macos_installer.dart:86-89` monta AppleScript reparseado por shell **como root** com dois valores não escapados, um deles vindo de dentro do arquivo baixado | L | `m5-ship-tarball` | — |
| `m5-tar-membros` | Extração sem `--no-same-owner`, sem `--no-xattrs`, sem listagem de membros e sem teto de tamanho | M | `m5-macos-elevacao` | — |
| `m5-marcador-primeira-partida` | Marcador escrito antes da troca e limpo por uma partida bem-sucedida | XS | — | — |
| `m5-relaunch` | Nada no framework reinicia o app, embora `InstallOutcome` prometa dois modos; no Windows o app precisa sair **antes** do instalador rodar | M | `m5-marcador-primeira-partida` | — |
| `m5-rollback` | Não existe rollback: no macOS o backup é apagado (`:73-75`) e o caminho elevado faz `rm -rf` do único exemplar antes do `mv` (`:82-87`) | L | `m5-macos-elevacao`, `m5-relaunch` | — |
| `m5-installed-path` | `installedPathForHost()` não tem chamador de produção; a fábrica passa `Platform.resolvedExecutable`, que dentro de um AppImage é o squashfs read-only | S | — | — |
| `m5-win-launcher` | Windows resolve um instalador `.exe` sem launcher e lança "no launcher was given" — exatamente o modo de falha que `installer_for_host.dart:28-34` diz existir para evitar | S | — | — |
| `m5-win-formato` | Formato Windows fixado no `dovetail.yaml`, não numa flag; `windows_installer.dart:10-12` passa `/P`, `/R` — que o NSIS ignora, então o modo **default** abre um wizard com UAC achando que é silencioso; e o script gerado nunca fecha o app rodando | M | `m5-win-launcher`, `m3-nsis-real` | — |
| `m5-nsis-in-place` | `InstallDirRegKey` ausente + nenhum `/D=`: quem instalou em `D:\Apps` recebe uma segunda cópia no diretório default e segue rodando a velha | S | `m5-win-formato` | ✔ precisa de Windows real |
| `m5-linux-appimage` | O braço que o updater legitimamente instala; `ship_plan.dart:247` só nomeia `DebBundler`, então rpm e AppImage são inalcançáveis pela esteira | M | `m5-fmt-contract`, `m5-installed-path` | — |
| `m5-linux-sums` | `--linux-format` no ship; `SHA256SUMS` lista exatamente os artefatos que o bundle produziu, e é assinado com minisign (hoje `ChecksumWriter` escreve e ninguém assina, e o `.rpm` ao lado nunca é somado) | M | `m5-linux-appimage` | — |
| `m5-linux-publica` | Deb/rpm: o framework publica e não instala; provenance de instalação gravada e lida, `{{bundle_type}}` deixa de ser inutilizável | L | `m5-linux-sums` | ✔ decidir se haverá repositório apt/dnf e quem assina |
| `m5-piso-versao` | Piso persistido (senão, depois de um rollback o binário reporta a versão velha e aceita o build quebrado de novo — laço de instalação) + teto de frescor usando `pub_date` | M | `m5-pub-date`, `m5-rollback` | — |
| `m5-endpoint-fallback` | Parse fora do try: um primeiro endpoint que responde 200 com HTML aborta a lista inteira, contra o que o README promete | XS | — | — |
| `m5-orquestrador` | O laço em si entra no toolkit: `UpdateSession` (check→download→install→relaunch) com guarda de reentrância e agendamento injetável. Hoje o laço é do **produto** (`update_watch.dart:18-96`), e `dovetail_updater/README.md:113` afirma que `UpdateFlow` amarra as três etapas — ele não tem método `install` | L | `m5-rollback`, `m5-relaunch` | — |
| `m5-scaffold-liga` | `dovetail new` gera um projeto cujo laço de update de fato roda (hoje `grep -rl 'Update' tool/sdk/templates` casa só arquivos vendorizados do cargokit) | L | `m5-orquestrador`, `m5-chave-uma-fonte` | — |
| `m5-e2e-macos` | Prova ponta a ponta no macOS, servida da loopback TLS que já existe, com chave minisign descartável | L | `m5-orquestrador`, `m5-ship-tarball` | — |
| `m5-e2e-linux` | Idem, AppImage, na imagem do gate-linux | M | `m5-e2e-macos`, `m5-linux-appimage` | — |
| `m5-e2e-windows` | Idem, NSIS | M | `m5-e2e-macos`, `m5-win-formato` | ✔ máquina/runner Windows |

---

### Marco 6 — Existe de onde baixar

**Condição de saída:** `curl -fsS https://<host>/latest` devolve uma versão; para cada alvo, `curl` do `.tar.gz` + `.sha256` + `.minisig` e `minisign -V -p tool/sdk/sdk_release.pub` sai 0; republicar a mesma versão é recusado.

Não há host. `docs/instalador.md:68-73` define o layout contra um `<base>` literal, `config_template.dart:38` escreve `https://cdn.example.com/releases` em todo projeto gerado, e `install.sh:19-23` sai 1 sem `DOVETAIL_INSTALL_URL`. Nenhum comando publica: `grep` por `aws s3|gh release|rsync|gcloud storage|wrangler` em `tool/`, `.github/` e no CLI não acha nada, e `tool/release.sh:30-34` termina com `ls -1 dist/*.tar.gz`.

Duas coisas precisam existir **antes** do primeiro binário público, porque não podem ser adicionadas depois: a custódia da chave privada (`keys/sdk.key` existe só aqui, 262 bytes, e `build_sdk.sh:151-155` recusa sem ela — perdê-la significa que nenhum dovetail instalado jamais se atualiza, porque a única chave que confiam está compilada dentro deles, em `dovetail_version.dart:30`) e a **lista** de chaves confiáveis, para que rotação seja possível.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m6-host` | Bucket + CDN + TLS + DNS + read público em quatro formatos de caminho + redirect http→https. Aceite não pode depender de `latest` já existir | M | — | ✔ **domínio, conta, cartão** |
| `m6-publish` | `tool/publish.sh`; aceite exige os **três** arquivos por alvo, incluindo o `.minisig` — `sdk_channel.dart:141-147` recusa sem ele, e `dist/channel/0.2.0/` já é a prova do que acontece sem regra | M | `m6-host` | ✔ credencial de escrita |
| `m6-imutabilidade` | Republicar a mesma versão é recusado; `latest` é escrito por último | S | `m6-publish` | ✔ object-lock no bucket |
| `m6-cache` | `Cache-Control` por prefixo: `/<ver>/*` imutável, `/latest` e `/install.sh` `no-cache` com invalidação no publish; senão o CDN serve versão velha ou cacheia negativamente o 404 | S | `m6-host`, `m6-publish` | — |
| `m6-latest-fanin` | Quatro runners, um `latest`: quem escreve e quando. `targets.json` por versão, `latest` só depois da última perna | S | `m6-publish`, `m6-runner-matrix` | — |
| `m6-key-custody` | `keys/sdk.key` sai deste laptop; `build_sdk.sh` aceita a chave por env/path; prova é uma corrida que produz `.minisig` numa máquina que não é esta | S | `m6-publish` | ✔ **onde a chave mora, quem tem a cópia de escrow, procedimento de rotação** |
| `m6-key-list` | Lista de chaves confiáveis embutida, não uma só. `sdk_channel.dart:25-48` aceita exatamente uma; depois do primeiro binário público a rotação é impossível | S | `m6-key-custody` | ✔ política: quantas chaves de uma vez, por quanto tempo |
| `m6-install-sig` | `install.sh` verifica o `.minisig` (hoje `grep -c minisig` = 0) e recusa sem hasher em vez de extrair calado (`:63-76`). É L porque Ed25519 em sh POSIX não é trivial: ou depende de `minisign` (que quebra a promessa de um comando) ou carrega o verificador | L | `m6-key-list` | ✔ decidir: exigir minisign ou embutir verificador |
| `m6-install-truncado` | O script é plano; um download cortado no meio executa o prefixo. Corpo dentro de função invocada na última linha | XS | — | — |
| `m6-install-x64-recusa` | `install.sh:41-46` resolve `x86_64 → x64` e pede um arquivo que nada constrói: 404 cru vira recusa nomeada. (Produzir binário macOS x64 fica **fora**) | XS | — | — |
| `m6-runner-matrix` | `.github/workflows/release.yml`: qual runner produz qual tarball. Note que só `bin/dovetail` difere entre macos-arm64 e macos-x64 — o xcframework já é universal | M | `m6-key-custody`, `m4-cli-notarizado` | ✔ minutos de Actions |
| `m6-rollback-canal` | Nenhum comando aceita `--version` ou `--allow-downgrade`: se a 0.2.0 sair quebrada e você reapontar `latest` para 0.1.0, todo cliente 0.2.0 diz "nothing to do" para sempre, e a imutabilidade (corretamente) proíbe sobrescrever | S | `m6-publish` | ✔ política de yank escrita em `docs/instalador.md` |
| `m6-sdk-compat` | `dependency_overrides` substitui a origem, então as faixas de versão do app não são consultadas: chave `dovetail-sdk:` mínima, checada por `upgrade` e por `doctor` | M | — | — |
| `m6-host-prereqs` | `doctor` não sonda `flutter`, `dart` nem `cargo`, e nada sonda `libayatana-appindicator3-dev` — que `prove_sdk.sh:50-51` instala dentro do container e nenhuma doc de consumidor menciona. E o `pubspec` gerado declara `flutter: ">=3.24.0"`, um piso que nenhum Flutter com Dart 3.12 satisfaz | M | — | — |
| `m6-canario-real` | `prove_sdk.sh` ganha `--base-url`, copia o `.minisig` (hoje copia o `.sha256` com `\|\| true`) e roda uma perna de `update`/`self-update`, que é o único caminho que verifica assinatura | S | `m6-publish`, `m6-install-sig` | — |

---

### Marco 7 — Um estranho chega ao fim sozinho

**Condição de saída:** `bash tool/ci/prove_quickstart.sh` roda, num container limpo e sem checkouts irmãos, todo bloco ```bash de `docs/quickstart.md` verbatim, e sai 0 — como passo do `gate-linux`.

| id | título | tam | depende de | humano |
|---|---|---|---|---|
| `m7-quickstart-honesto` | Enquanto o canal não existe, `docs/quickstart.md` diz isso na primeira seção; teste recusa `<host>` num documento que promete cinco minutos | XS | — | — |
| `m7-quickstart-ci` | O quickstart vira script e entra no portão | L | `m0-scripts-portateis`, `m6-canario-real`, `m7-quickstart-honesto` | — |
| `m7-scripts-do-app` | Os 31 scripts que `dovetail new` embarca (`run_app.sh:17,20` os invoca) nunca foram executados por este repositório; `shellcheck -S warning` sobre `git ls-files '*.sh'` limpo | M | `m7-quickstart-ci` | — |
| `m7-consumidor-macos` | O tarball macOS é o único sem prova de consumidor, e é o que carrega o `.xcframework` | M | `m6-publish` | — |
| `m7-consumidor-windows` | `build_sdk.sh:74-77` recusa qualquer alvo não-linux: hoje não existe tarball Windows para provar | XL | `m3-flutter-build-fixture`, `m6-runner-matrix` | ✔ máquina/runner Windows |
| `m7-api-golden` | Superfície pública do barrel congelada num golden (81 `export`, ~134 tipos). Gerar de `dovetail_cli` ou de um script com pubspec próprio — `analyzer` não é dependência de nada na árvore e `toolkit/dovetail` resolve com `--enforce-lockfile` | L | — | — |
| `m7-semver` | `docs/api-e-versionamento.md`: o que é público (`lib/src/**` não é), contrato 0.x, caminho de depreciação, ritual de release | S | `m0-licenca` | — |
| `m7-changelog` | Topo do CHANGELOG = `version:` do pubspec, em `package_paperwork_test` (hoje `:87-102` só exige uma linha não-heading) | S | `m7-api-golden`, `m7-semver` | — |
| `m7-barrel-contrato` | Teste tabelado: cada capacidade × cada host, resposta e string de recusa; hoje o contrato vive em seis READMEs e dois estão errados | M | `m3-capabilities` | — |
| `m7-readme-raiz` | `readme_covers_commands_test.dart:20` usa `Directory.current.path` e guarda o README do **pacote**; `grep -c 'dovetail update' README.md` = 0 e `upgrade` idem. As quatro asserções valem para os dois READMEs, com a verificação reversa (`:116`) só depois de trocar o `notCommands` hardcoded por uma regra | XS | — | — |
| `m7-numeros` | Alvo `verify docs` que **deriva**: 818→826 chaves em quatro lugares (e 819 num quinto), 51 vs 53 métodos, "29 testes" vs 132, "doze comandos" vs 19, "vinte e três documentos" vs 31, "1342" vs 1371. Apaga as duplicatas de medição em vez de datá-las | L | `m1-docs-index-varredura` | — |
| `m7-contagens-exatas` | Trocar os três pisos (`docs_index_test.dart:64` `greaterThan(15)`, `package_paperwork_test.dart:49-57`, `config_documented_test.dart:76-81`) por contagens derivadas | S | `m7-numeros` | — |
| `m7-docs-ci` | `docs/ci.md` para de afirmar o que nenhuma corrida estabeleceu; `README.md:95` é editado uma vez, quando uma corrida hospedada ficar verde | S | `m1-baseline-frio` | — |

---

## 4. O caminho crítico

A menor sequência que ainda chega à condição de pronto. Cada elo está aqui porque nada depois dele pode ser **provado** sem ele.

```
m0-toolkit-only (M)          ─ sem isto nenhum aceite abaixo roda fora desta máquina
m0-weave-di (M)              ─ sem isto o app gerado não resolve em lugar nenhum
m1-stderr (S) → m1-lanes (M) → m1-bless-recusa (S)
m1-guards-tabela (S) → m1-fingerprint (M) → m1-baseline-frio (M)
m2-billing (XS, humano)      ─ em paralelo desde o dia 0
m2-primeiro-passo (XS) → m2-tudo-depois-decide (S) → m2-pr-trigger (XS) → m2-branch-protection (S)
m3-win-suite-carrega (M) → m3-win-tools (S) → m3-msvc-cpp (M) → m3-flutter-build-fixture (L)
m3-baseline-por-so (M)
m4-ferramenta-ausente (S) → m4-require-signature (M) → m4-config-chega (L)
m4-signer-dmg (M) → m4-ship-macos-ordem (S) → m4-verify-command (L)
m4-ci-secrets (L, humano)
m5-fmt-contract (M) → m5-ship-tarball (M)
m5-public-key-obrigatoria (M) → m5-chave-uma-fonte (M)
m5-macos-elevacao (L) → m5-relaunch (M) → m5-rollback (L) → m5-orquestrador (L)
m5-e2e-macos (L)
m6-host (M, humano) → m6-publish (M) → m6-key-custody (S, humano) → m6-key-list (S) → m6-install-sig (L)
m6-runner-matrix (M)
m7-quickstart-ci (L)
```

**Soma:** ≈ 99 dias úteis de uma pessoa — **cerca de 20 semanas**, ~5 meses de calendário se as compras (plano do Actions, Developer ID, certificado Authenticode, domínio + bucket) forem disparadas no primeiro dia. A validação de organização de um certificado OV/EV leva de dias a semanas e **não é trabalho** — é latência; se ela começar na semana 12, o caminho crítico cresce, não encolhe.

**O que fica fora do caminho crítico** e pode rodar em paralelo ou depois, sem atrasar produção:

- **Toda a paridade de runtime que não é build**: `m3-si-*`, `m3-copydata-bounds`, `m3-deeplink-*`, `m3-ffi-panic`, `m3-pump-*`, `m3-runtime-blocking`, `m3-spm-*`, `m3-capabilities`, `m3-tray-icon`, `m3-wayland-ci`. São bloqueadores de release por qualidade, não por dependência: nada mais espera por eles. Faça-os em paralelo ao Marco 4, que é gated por compras.
- **Toda a verdade documental**: `m7-numeros`, `m7-contagens-exatas`, `m7-readme-raiz`, `m7-docs-ci`, `m1-skips-gerado`, `m1-cwd`. Independentes de tudo; bons para as janelas em que você está esperando um runner ou um certificado.
- **`m7-api-golden` + `m7-semver` + `m7-changelog`**: só passam a importar no dia em que a segunda pessoa depende do barrel. Antes disso não protegem ninguém.
- **`m5-linux-publica`, `m5-e2e-linux`, `m5-e2e-windows`, `m7-consumidor-windows`**: entram depois do e2e macOS estar verde; cada um é confirmação de uma plataforma, não pré-requisito da outra.
- **`m6-sdk-compat`, `m6-host-prereqs`, `m6-rollback-canal`**: melhoram a primeira hora do consumidor, não desbloqueiam nada.
- **`m2-cache`, `m2-rede`, `m2-politica-gatilho`**: economia e estabilidade. Faça `m2-cache` cedo mesmo assim — pagar 10x sem cache em cada iteração dos Marcos 3 e 4 custa mais do que o tempo de implementá-lo.

---

## 5. O que este roadmap deliberadamente NÃO faz

| Não faz | Por quê |
|---|---|
| **Construir `product/vpn_desktop` em CI** | Puxa quatro crates privadas por path (`product/desktop_core_bridge/rust/Cargo.toml:17-21`). Um vermelho nasceria noutro repositório, e minuto macOS custa 10x. O fixture correto é `dovetail new`: é código do framework e é o que o consumidor recebe. |
| **Fazer os siblings privados compilarem em Linux/Windows** | O conserto mora no outro repositório. `docs/ci.md:52-58` já chama isso de "app-on-other-OS". |
| **Qualquer tela, rota ou widget** | O front do produto é escrito à mão pelo autor. Este roadmap só toca os números que a documentação do framework afirma sobre ele. |
| **Retry-com-quarentena para o flake** | Torna verde compatível com "não provado" — a única patologia que `tool/verify.dart:1-16` existe para impedir. Flake insolúvel vira skip nomeado, visível no baseline. |
| **Um segundo baseline "quente"** | Todo teste que ele protegeria depende do `.app` construído e das duas fatias Apple, reproduzíveis numa máquina só — a premissa que a prova de três SOs existe para quebrar. A dimensão que vale é o **SO** (`m3-baseline-por-so`), não a temperatura. |
| **Um workflow canário nos labels `-latest`** | Queima minutos macOS a 10x, todo mês, para detectar uma aposentadoria que o GitHub anuncia com meses de antecedência e que os pins explícitos de `ci.yml:63,212` já contornam. |
| **Corpus de compatibilidade de manifesto versionado** | Defende uma população de clientes igual a zero: o parque instalado é Tauri e seu plugin de updater nunca é chamado. Sobra o inteiro `format`, que está dentro de `m5-fmt-contract`. Construa o corpus no dia em que existir um cliente real. |
| **`sha256` no manifesto** | O manifesto não é assinado, então o hash é controlado por quem controla o endpoint — não defende contra nada que a assinatura minisign dos bytes já não cubra. O `length` fica, como corte antecipado. |
| **Tap do Homebrew** | Segundo canal a manter em sincronia (url, sha256, bump no publish, repo `homebrew-<org>`) por zero capacidade que o tarball não tenha. Volte a isso quando houver usuários pedindo. |
| **Binário `dovetail` para Windows e para macOS x64** | `build_release.sh:48-52`: `dart compile exe` só cross-compila para linux, e Rosetta traduz x86→ARM, não o contrário. O que fica é a recusa nomeada em `install.sh` e a doc parando de prometer seis tarballs. |
| **Runners self-hosted como resposta principal** | Um runner macOS self-hosted é esta máquina — reinstala a premissa de máquina única. Só se justifica como alavanca de custo depois de Linux e Windows verdes em runners hospedados. |
| **Prova de `makensis` como bloqueio de release** | `ship` já default para `msi` e o `ShipPlan` só emite `--windows-format msi`: o caminho NSIS não está na esteira. Sobra alinhar o default de `bundle_command.dart:81` (XS) e provar makensis quando a perna Windows existir. |
| **Publicar os pacotes runtime no pub.dev** | `docs/instalador.md:148` põe registro público explicitamente fora de escopo e todo pacote declara `publish_to: none`. O tarball do SDK é o mecanismo por desenho. |
| **`rpm -K` / `dpkg-sig`** | Cadeia GPG de gerenciador de pacotes que ninguém exercita num arquivo baixado direto, e uma segunda chave para guardar. `minisign -Vm SHA256SUMS` é o requisito; o resto é opcional e não bloqueia. |
| **Teste de dominância de guarda por análise estática** | Responder "esta chamada é dominada por uma sonda de presença" sobre 101 call-sites é um passe de analyzer inteiro. `m1-guards-tabela` (gerar a tabela) resolve a metade que importa por 1/5 do custo; a estrutural fica para depois, ou vira um helper `requireTool()` obrigatório. |
| **Cobertura nova para comportamento não testado** | Este roadmap torna o portão existente confiável e os números existentes verdadeiros. Escrever provas para o que ninguém testou é outro trabalho. |

---

## 6. A primeira tarefa de amanhã de manhã

**`m0-toolkit-only` — fazer `--only toolkit` valer de verdade para `fast`, `cross` e `all`, e adicionar o job de CI que roda exatamente isso com `SIBLINGS_TOKEN` deliberadamente vazio.**

Porque é a única tarefa cuja ausência torna **todas as outras inverificáveis**. A condição de pronto deste roadmap começa com "uma equipe de engenharia que não é o autor"; hoje o primeiro `git commit` dessa equipe falha, porque `tool/githooks/pre-commit` executa `verify fast`, `case 'fast'` (`tool/verify.dart:83-84`) despacha `_fast()` sem `--only`, e `_fast()` analisa os doze pacotes de `tool/verify.dart:31-44`, dois dos quais resolvem `example-rust` e `example-design-system` por path. E `cross --only toolkit` — que `ci.yml:183` e `:259` já invocam achando que é toolkit-only — chama `_pluginCoverage()` incondicionalmente em `tool/verify.dart:476`, que roda `flutter pub get --enforce-lockfile` contra `product/vpn_desktop`. Um framework que não pode ser verificado sem o produto do qual foi extraído não está separado desse produto, e "framework" aqui significa exatamente essa separação.

Aceite: `git clone <repo> /tmp/solo && cd /tmp/solo && dart tool/verify.dart all --only toolkit` sai 0 numa máquina sem os dois siblings.

**Na mesma hora, dispare as três coisas que são latência e não trabalho** — porque cada dia que elas esperam é um dia somado ao calendário de cinco meses, não subtraído:

1. `m2-billing` — 15 minutos. Destrava simultaneamente as 29 corridas mortas e a proteção de branch, que devolve 403 pelo mesmo motivo.
2. Enrolamento no Apple Developer Program e emissão do Developer ID (`m4-signer-dmg`, `m4-cli-notarizado` dependem).
3. Validação de organização do certificado Authenticode ou assinatura do Azure Trusted Signing / DigiCert KeyLocker (`m4-ev-decisao`) — é a compra de maior latência da lista.

E antes da **primeira corrida paga**, gaste os 20 minutos de `m2-primeiro-passo`: `ci.yml:65-67` aplica `working-directory: dovetail` ao primeiro passo do job, que roda antes de `actions/checkout with: path: dovetail` criar o diretório. Sem esse conserto, a primeira coisa que o dinheiro compra é uma corrida cuja mensagem de erro não consegue ser impressa.