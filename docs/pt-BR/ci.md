# CI: o portão nos três SOs

> **Contexto para quem chega pelo repositório público.** Este documento cita
> `product/`, que é o app privado onde o toolkit é exercitado, e não existe
> neste repositório. O mecanismo descrito é do toolkit e vale para qualquer
> app; só o caminho do exemplo é de outra árvore.

`.github/workflows/ci.yml` roda o portão fora desta máquina. Este documento
diz o que cada leg executa e **por que** — e o que continua sem prova até uma
corrida hospedada voltar verde.

## O que é, em uma frase

A diferença entre "compila para o alvo" e "rodou no alvo". Esta máquina prova
o macOS arm64; um runner hospedado é onde Windows e Linux ganham a primeira
corrida de verdade.

## O layout, e por que ele é obrigatório

O produto resolve os irmãos por path (`../../../example-rust` no Cargo,
`../../../example-design-system` no pubspec), e os dois repos são privados. O
workflow então:

- faz checkout do `dovetail` em `dovetail/`;
- faz checkout dos irmãos **na raiz do workspace**, ao lado — é a única
  posição em que os `../../..` resolvem;
- lê os irmãos com um PAT privado, `secrets.SIBLINGS_TOKEN`.

Sem o secret, **cada job recusa no primeiro passo**, nomeando o que falta:
um PAT que leia os dois repositórios privados que o monorepo de origem
consome por path. O repositório público não precisa de nenhum: os dez
pacotes resolvem entre si por `pubspec_overrides.yaml`.
Nada aqui assina nem publica — o workflow é um portão, não um `ship`.

## O que cada leg roda, e por que difere

### macOS (`macos-14`, arm64) — o portão inteiro

`dart tool/verify.dart all`: doctor, fast, cross, rust, frb, ffi, release,
readme, test, baseline. É o único leg que compara contra o baseline, porque o
baseline foi gravado na **forma fria** — sem app construído, sem fatias
universais — que é exatamente o que um runner limpo tem. O ffi abre uma janela
de verdade (`-d macos`), então este leg também é a prova de que a ponte
atravessa num runner.

O `release` roda a esteira macOS inteira contra um host local
(`tool/ci/prove_update.sh`, descrito em [release-simulado.md](release-simulado.md)):
assina, empacota, publica, serve por https com CA privada e pergunta ao `probe`.
Ele **pula** quando não há `.app` de Release construído — o caso do worktree do
pre-push e de qualquer clone limpo — e diz o comando que o produz. Construir
dentro do portão custaria dez minutos por push; provar a esteira sobre um build
que já existe custa um minuto.

Esta frase foi falsa até 2026-09-05. O arquivo dizia "forma fria" e era uma
gravação desta máquina quente: `diff tool/skip_baseline.json dist/verify-run.json`
depois de uma corrida normal saía idêntico, e os testes que dependem do `.app`
construído — `real_codesign_test.dart`, `mach_o_test.dart`,
`minimum_system_version_test.dart`, `inspect_test.dart`, `bundle_arch_test.dart`
— apareciam com zero skips. Num runner limpo eles pulam, `_compare` chama cada
um de `SKIP NEW`, e a perna nascia vermelha antes de qualquer defeito real.

Como regravar, quando alguém precisar — e é preciso toda vez que um teste
entra ou sai, porque o baseline guarda `declared` por suíte:
`tool/rebless_cold.sh`. Ele copia os arquivos **rastreados** (o índice: um
arquivo novo precisa de `git add` antes, e o script avisa quais ficariam de
fora) para um diretório irmão deste (os `../../../` do `product/` precisam
alcançar `example-rust` e `example-design-system`), sem `.dart_tool`, sem `build/`
e sem `target/`; roda `dart tool/verify.dart test` lá; traz o
`dist/verify-run.json` de volta, dá `bless --force` e imprime os totais que a
manchete do README tem de dizer. O `git ls-files -z | rsync --files-from=-
--from0` é o que garante que nenhum artefato quente viaje junto. Leva uns cinco
minutos numa máquina com o cache do pub quente.

Frio fica verde nos dois lados, e é por isso que não existe um segundo baseline
quente: nesta máquina os 41 testes a mais rodam, e um skip que deixa de
acontecer é `skip gone` — notícia, nunca problema, porque significa que se
provou mais. O contrário não vale, e foi o que estava no ar.

Instala as ferramentas que a forma fria assume presentes (minisign, msitools,
rpm, makensis via brew) e o `flutter_rust_bridge_codegen` pinado no
`Cargo.toml` do bridge — o `verify all` exige o codegen para o frb conferir de
verdade, não só reportar ausência.

### Linux (`ubuntu-24.04`, x86_64) — a suíte, menos o que é macOS

`doctor`, `fast`, `test`, `rust --only toolkit`, `cross --only toolkit`,
`readme`. Sem baseline (os skips gravados são da forma fria macOS, e um runner
Linux tem um conjunto de ferramentas diferente), sem ffi (o alvo abre uma
janela no único device provado — macOS) e sem frb (a saída do codegen é
independente de host; o leg do macOS é o dono dela). Depois roda as duas
provas de empacotamento:

- `tool/prove_on_linux.sh` — agora herda a arquitetura do host, então num
  runner x86_64 valida o `.deb` e o `.rpm` **x86_64**, o complemento do que o
  arm64 desta máquina prova;
- `tool/prove_guard_on_wine.sh` — o guarda de instância única Windows sob um
  wine **nativo** (sem emulação), no container amd64.

### Windows (`windows-2022`, x86_64) — a suíte, menos o que é macOS

O mesmo que o Linux: `doctor`, `fast`, `test`, `rust --only toolkit`,
`cross --only toolkit`, `readme`. Sem as provas docker, que não têm o que
fazer aqui.

## O `--only toolkit`, e a linha que ele não cruza

`rust` e `cross` aceitam `--only <substr>` (o mesmo `--only` que o `test`
tem). Os legs que não são macOS usam `--only toolkit` para provar os crates do
toolkit e **deixar `product/desktop_core_bridge` de fora**: esse crate arrasta
os crates do `example-rust` por path, e nenhum deles jamais compilou para
um host Linux ou Windows. Prová-los é o item "o app compila em Windows e
Linux", não o item "o portão roda nos três SOs" — e o conserto, se falhar,
mora no repo irmão.

## O que cada leg prova, e o que ainda não provou

## O que foi consertado antes da primeira corrida paga

Quatro defeitos que só apareceriam num runner, e que teriam custado uma corrida
cada — em minuto de macOS, que vale 10x:

- **A guarda do `SIBLINGS_TOKEN` não conseguia imprimir.** `defaults.run.
  working-directory: dovetail` vale já para o **primeiro** passo do job, que
  roda **antes** de `actions/checkout` criar esse diretório. Era a única
  mensagem do arquivo escrita para quem bate nela primeiro, e a única que não
  podia ser vista. Agora esse passo carrega `working-directory: .`.
- **`clippy` e `rustfmt` não chegavam.** `dtolnay/rust-toolchain` instala o
  perfil `minimal`, e nenhum dos dois vem nele — enquanto `verify fast` roda
  `cargo fmt --check` e `cross` roda o clippy. As três pernas ficariam
  vermelhas no primeiro job que a conta deixasse criar.
- **Os seis alvos num `run:` só.** Sob `bash -e` o primeiro não-zero encerra o
  passo e os cinco seguintes não rodam — jogando fora exatamente a propriedade
  que `_all()` tem de propósito: tudo roda, tudo reporta, o código de saída é
  decidido no fim. Numa perna que nunca rodou, isso significa descobrir um
  problema por corrida. Agora é um passo por alvo, com `if: ${{ !cancelled() }}`.
- **Sem gatilho de `pull_request`.** Um check obrigatório reporta no SHA do PR;
  sem o gatilho ele nunca aparece, e a proteção de branch barraria **todo**
  merge em vez dos vermelhos. Entraram `pull_request` e `merge_group`, e o
  `cancel-in-progress` passou a valer só em PR: cancelar em `main` descarta o
  veredito de um commit que já entrou.

O `flutter_rust_bridge_codegen` deixou de ser compilado do fonte em toda
corrida — fica em cache com a chave carregando `FRB_PIN`, e a versão é
conferida em cache hit e em cache miss: um binário restaurado que não seja o
que o pin diz seria pior do que não ter cache, porque o alvo `frb` compara a
saída do codegen com o versionado e culparia o código.

O workflow está escrito; **nenhuma corrida hospedada voltou verde ainda**.
Até a primeira, o verde desta máquina continua o único verde — e este
documento não afirma o contrário. O que a primeira corrida decide:

- se o ffi abre janela num runner macOS sem sessão gráfica garantida;
- se o conjunto de skips do baseline casa com o runner limpo (a forma fria
  foi gravada para isso, e os motivos agora são independentes de máquina);
- se as suítes Dart de `product/` carregam em Linux e Windows — nenhum teste
  do produto rodou nesses hosts;
- se o makensis do runner se comporta como o daqui.

Cada job sobe `dist/verify-run.json` e os relatórios `dist/doctor-*.log`
como artifact, e roda `dovetail doctor` com `continue-on-error`: num runner,
**reportar a ferramenta ausente é o ponto**, não um erro a esconder.

## Disparar

`push` para `main`, ou `workflow_dispatch` à mão. Antes do primeiro push:
criar o secret `SIBLINGS_TOKEN` no repo.

## O `startup_failure` que custou dois dias, e as duas causas

Toda corrida hospedada falhava em `startup_failure` com zero segundos, sem
job e sem log — a run dizia apenas "workflow file issue". Foram **duas**
causas, uma atrás da outra:

1. **`secrets` não é contexto válido em `if:` de step.** O GitHub recusa o
   workflow inteiro antes de criar job nenhum. O `actionlint` nomeia o erro
   em segundos; o padrão sancionado é expor o secret uma vez no `env:` do
   workflow e testar `env.SIBLINGS_TOKEN` em todo lugar — o que o arquivo
   faz hoje.
2. **A conta do dono não executa Actions.** Mesmo um workflow mínimo de um
   `echo` continuou em `startup_failure` com `name` vazio e zero check-runs.
   Repo privado, conta pessoal sem plano — o que desbloqueia é a decisão de
   plano do dono, não o arquivo. O fix do `secrets` era necessário de
   qualquer forma e fica.

## O mesmo portão, sem runner hospedado

Enquanto a conta não executa Actions, o leg do Linux tem um caminho local:
`tool/ci/gate-linux.Dockerfile` constrói o mesmo ambiente do runner
(Ubuntu 24.04 x86_64, Flutter e Rust pinados, as ferramentas do portão) e
roda `doctor`, `fast`, `test`, `rust --only toolkit`, `cross --only toolkit`,
`readme` dentro do container, com os irmãos montados ao lado. É o que provou
que o portão roda num Linux real antes de qualquer runner.

O portão é determinístico onde se mediu: `bash tool/soak.sh 5` deu `5/5 green`
em 2026-09-06, depois das mudanças de assinatura, do `archive` e dos defines.
O número que interessa não é o verde de uma corrida, é o de N.

**O que a emulação NÃO serve para provar.** Rodar esse container no Mac arm64
foi tentado de novo em 2026-09-06 e não produziu resultado utilizável:
`doctor` e `fast` passaram, e o `test` reportou vermelho em **todos** os
pacotes — inclusive `dovetail_form_validation` e `dovetail_process_runner`, que não tocam o
sistema. O que os condenou foi o relógio, não o código: rodado sozinho dentro
do mesmo container, `dovetail_form_validation` deu `All tests passed!`. Os tempos por
pacote, contra os do host na mesma árvore:

| pacote | container x86_64 emulado | host arm64 |
|---|---|---|
| `dovetail_form_validation` | 79,1s | 1,2s |
| `dovetail_process_runner` | 50,5s | 3,5s |
| `dovetail_updater` | 152,5s | 7,3s |
| `dovetail_platform_channel` | 209,0s | 9,0s |
| `dovetail_cli` | 435,8s | 57,0s |

Entre 8 e 65 vezes mais lento, e um `flutter test` acabou pendurado por mais
de seis horas de CPU. Sob esse fator, o que estoura primeiro é o limite de
tempo das suítes, não a asserção — e vermelho por lentidão é pior que nenhuma
corrida, porque parece defeito. Este arquivo diz o que a árvore prova e onde:
o leg Linux precisa de um **runner x86_64 de verdade** (ou de um host Linux
arm64), e enquanto ele não existe, o que roda em container aqui é o
`prove_on_linux.sh` — que empacota e valida com `dpkg` e `rpm` de verdade, sem
emular Dart nenhum.

As provas de empacotamento já rodam nesta máquina sem ele:
`tool/prove_on_linux.sh` provou `.deb` e `.rpm` nos dois lados — inclusive a
recusa do AppImage para produto com serviço — e `tool/prove_guard_on_wine.sh`
provou o guarda de instância única sob wine ("the guard behaved on a machine
that is not Windows"). Re-provado em 2026-09-06 com a árvore do dia, depois
das mudanças de assinatura, do `archive` e dos defines: `both suites passed`,
updater instalando com privilégio pelo rpm, mesma versão reinstalada saindo 0,
remoção limpa. E o macOS tem a sua prova ponta a ponta em
`tool/ci/prove_update.sh` — ver `release-simulado.md`.
