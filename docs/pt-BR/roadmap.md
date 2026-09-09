**Português** · [English](../roadmap.md)

# Roadmap do dovetail

O trabalho se organiza em três áreas: **toolkit/framework** (o runtime e a
mecânica), **CLI** (o binário e a esteira) e **DX** (a experiência de quem
consome o framework). Cada task tem um status; as bloqueadas nomeiam o que
as desbloqueia. As 5 fases de [instalador.md](instalador.md) estão completas
e saem deste arquivo — o que fica aqui é o que veio depois delas.

## Toolkit / framework

| task | status | nota |
|---|---|---|
| Canário do release: `tool/ci/prove_sdk.sh` versionado — container limpo instala o SDK e sustenta o app mínimo (doctor + test + build) | ✅ feito | era manual e descartável; agora é reproduzível do repo |
| Bridge gerado buildando: `tool/ci/prove_bridge.sh` — `bridge init` + codegen + XCFramework + app consumidor, `flutter build macos` verde | ✅ feito | as entradas de produto (api, support, crates irmãos) são completadas pela prova, como o template manda |
| Fuzzing do `ManifestParser`/verificador do updater — entradas malformadas nunca derrubam o cliente | ✅ feito | teste determinístico no `dovetail_updater`; expôs e corrigiu um `FormatException` que vazava no `ascii.decode` dos parsers minisign (DoS no limite de confiança) |
| Build do produto em Windows e Linux (crates do `example-rust`) | bloqueado | precisa de máquina/runner; o Linux pode ir no container do gate, mas é fronteira do repo irmão |
| Backend Wayland do atalho global | recusado | decisão registrada no README, com a sessão nomeada |
| `mobile_scanner` em Windows/Linux | bloqueado | repo irmão (design system), fora do dovetail |

## CLI

| task | status | nota |
|---|---|---|
| Seção `app` no `doctor` — os overrides do consumidor apontam para um SDK que existe? | ✅ feito | fecha o triângulo host-projeto-SDK |
| Seção `spm` no `doctor` — o `.xcframework` existe? | ✅ feito | hoje quem esqueceu o `build_xcframework.sh` só descobre no build |
| Diagnóstico do binário — log estruturado com rotação no catch final | ✅ feito | o AOT hoje morre com stack sem canal de reporte |
| Testes dos wrappers `probe`/`inspect`/`ship` | ✅ feito | apontados pela auditoria de cobertura |
| Orquestração de release — `tool/release.sh` rode os dois builds e os dois canários na ordem | ✅ feito | cada passo já provou verde individualmente; o script é a ordem certa |
| Binário Windows | bloqueado | `dart compile exe` não cross-compila para Windows |
| Binário macOS Intel | bloqueado | sem alvo `x86_64-apple-darwin` neste host |
| Distribuição pública (notarização) | bloqueado | Developer ID + notarização não existem |
| CI hospedado | bloqueado | a conta não executa Actions. O workflow em si está válido (actionlint), e o repositório público não precisa de token: os dez pacotes resolvem entre si por `pubspec_overrides.yaml` |

## DX

| task | status | nota |
|---|---|---|
| `dovetail upgrade` — re-aponta o `pubspec_overrides.yaml` do app para o SDK instalado | ✅ feito | fecha o ciclo de versão que o `doctor` só reporta |
| `dovetail new` fecha o `flutter create` via `--no-create` | ✅ feito | hoje o build falha até o usuário rodar `flutter create --platforms=... .` à mão |
| `dovetail new` gera a estrutura clean-arch do padrão mobile (refinamento do Manguinho: lib/data, lib/domain, lib/infra, lib/main, lib/presentation, lib/shared) | ✅ feito | template do SDK `tool/sdk/templates/app`; provado: `new` + pub get + analyze + 6 testes + suite flutter verde no gerado |
| `dovetail new` embute os checks de conformidade do mobile adaptados ao desktop | ✅ feito | as duas suites embarcam: a flutter do mobile (22 checks) e a rust do desktop (6 checks); provado verde no gerado, com prova negativa (comentário sujo reprova) |
| `dovetail new` gera o núcleo Rust + o bridge FFI (o `core/` e o `core_bridge/` completos) | ✅ feito | bridge reusa o template do `bridge init`; provado: codegen + cargo check no core e no bridge + portão de cobertura com paridade core↔repasse |
| `doctor` como fonte única do host — consolidar as seções do consumidor num só relatório | descartado | o `doctor` sem `--target` já é o relatório único (project + sdk + app + spm juntas), e o exit code é o veredito para scripts — uma quinta seção de resumo duplicaria as quatro |
| Docs do consumidor — `ESCREVER_O_APP.md` e `migrar-do-tauri.md` acompanhando cada mudança | contínuo | o `readme_covers_commands_test` e o `docs_index_test` cobram |

## Como as tasks entram aqui

Uma task entra no roadmap quando tem critério de aceite executável; sai quando
a prova real fecha (o padrão "Provado:" dos commits). A ordem de execução é
por valor — release-robustness primeiro, depois as seções do doctor, e por fim
as tarefas de diagnóstico/fuzz — salvo decisão explícita do dono.

## Melhorias aprovadas (rodada de refinamento)

Dez sugestões surgidas da revisão do gerador/ciclo/release, aprovadas em bloco.
Na ordem recomendada:

| # | melhoria | status |
|---|---|---|
| 1 | `docs/quickstart.md` — o caminho de cinco minutos do consumidor | ✅ feito |
| 4 | `dovetail upgrade --check` — prova que o app resolve depois de re-apontar | ✅ feito |
| 7 | Assinar o canal do SDK — minisign além do sha256+TLS | ✅ feito |
| 9 | Paths com espaço nos overrides (aspas + escape) | ✅ feito |
| 2 | `bridge init --from <bridge>` — replica um bridge existente | ✅ feito |
| 3 | `bridge init` valida o crate cedo (avisa sem `handle.rs`) | ✅ feito |
| 6 | Rodar o `tool/release.sh` de ponta a ponta | ✅ feito |
| 8 | `doctor --check-updates` — compara a versão instalada com o canal | ✅ feito |
| 5 | `dovetail update` — SDK + app numa linha | ✅ feito |
| 10 | Fuzz fundo no minisign (parse/verifier, corpus dedicado) | ✅ feito |
