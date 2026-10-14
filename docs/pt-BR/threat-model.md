**Português** · [English](../threat-model.md)

# Modelo de ameaça

O que o dovetail defende, contra quem, e onde para. Cada mitigação cita o código que a faz e o teste que a prova; uma defesa sem teste é um [furo conhecido](#furos-conhecidos), não uma mitigação. Medido na `main` em `70e3507`: tudo rodou num macOS arm64, o Linux só em contêiner, e o código de Windows nunca rodou.

Para relatar uma vulnerabilidade, leia o [`SECURITY.pt-BR.md`](../../SECURITY.pt-BR.md). Os caminhos partem de `toolkit/`; `channel/` quer dizer `dovetail_privileged_channel/rust/src/` e `daemon/`, `dovetail_privileged_daemon/rust/src/`.

## Contra quem

| atacante | o que tem |
|---|---|
| local | uma conta ou um processo na máquina, sem direito de administrador |
| rede | o caminho entre o app e o host de update |
| host de update | o servidor ou espelho que responde ao updater, ou um certificado para o nome dele |
| dependência | um pacote Dart ou um crate Rust que o app ou o toolkit puxa |

Fora do escopo: quem já é root ou administrador, o acesso físico, e o que significam os comandos do próprio app. O canal decide *quem* pode falar com o daemon; o `DaemonApp::validate` do app decide *o que* pode ser dito.

## 1. Pacotes de terceiros no processo do app

Nada separa os pacotes dentro do app: todo pacote Dart e todo crate Rust que ele linka roda com os direitos do app. Capabilities e CSP contêm conteúdo web, e o dovetail não renderiza nenhum, então aqui elas não teriam o que conter. O que o dovetail faz é manter fora desse processo o que precisa de mais direitos que os do app.

| mitigação | código | teste |
|---|---|---|
| o trabalho privilegiado roda num daemon à parte, e todo chamador passa pela checagem do par da seção 2 | `daemon/server.rs` | os testes da seção 2, a começar por `the_policy_the_app_declares_reaches_the_endpoint` no mesmo arquivo |
| a esteira de release, que lida com as chaves de assinatura, nunca entra no app | `dovetail/lib/dovetail.dart` | `dovetail/test/barrel_test.dart`: "it should not reach the packages that only run in the pipeline" |
| no macOS o app mantém o App Sandbox do template do Flutter, e o daemon embutido é assinado com os entitlements dele, nunca com os do app | `dovetail_cli/lib/src/command/sign_command.dart` | `dovetail_cli/test/sign_command_test.dart`: "the declared entitlements of an embedded component should reach codesign for that binary, and not the app's"; `../tool/ci/prove_service.sh`, asserção 6 |

## 2. O daemon privilegiado e o canal até ele

O daemon roda como root ou SYSTEM, e o app chega a ele por um socket local ou um named pipe. O canal julga o par no `accept`, antes de ler um byte dele.

| mitigação | código | teste |
|---|---|---|
| macOS: o código do par tem de satisfazer o requisito que o produto declara | `channel/transport/macos.rs:41-45`, `channel/code_signature.rs` | `channel/code_signature_tests.rs` (2) |
| macOS: um build de release sem requisito recusa todo par | `channel/peer_auth.rs:139-146` | `em_release_o_peer_e_recusado_sem_codesign`, no mesmo arquivo, com `cargo test --release` |
| macOS: o socket de release é `0600` numa pasta `0700`, então só o dono do daemon chega a ele | `channel/transport/macos.rs:16-24` | `aplica_o_modo_do_perfil_no_diretorio_e_no_socket`, no mesmo arquivo |
| Linux: um par só entra quando o uid ou o gid dele está na `PeerPolicy`; sem política ninguém entra, nem o root | `channel/peer_policy.rs:44-61` | `without_a_policy_even_root_is_refused_and_told_what_to_declare`, `a_policy_that_names_neither_the_uid_nor_the_gid_refuses_the_peer`, no mesmo arquivo |
| Linux: o socket só abre para outros usuários quando uma política decide quem fica | `channel/peer_policy.rs:70-81` | `channel/transport/linux.rs` (2) |
| o daemon entrega a política do app ao canal antes do bind | `daemon/server.rs` | `the_policy_the_app_declares_reaches_the_endpoint`, no mesmo arquivo |
| um par recusado é desconectado e não segura o próximo | `channel/transport/mod.rs:58-64`, `daemon/server.rs` | `a_refused_peer_is_not_an_io_error_and_its_connection_is_closed`; `the_app_is_served_without_waiting_behind_a_refused_peer` |
| um cliente que não termina o handshake em 3 s, ou manda um frame acima de 64 KiB, é recusado no fio | `channel/limits.rs`, `channel/handshake_server.rs` | `daemon/connection_tests.rs`: `a_silent_client_is_refused_at_the_deadline`, `a_frame_above_the_cap_is_refused` |
| uma rajada de recusas escreve uma linha de log por minuto, não uma por recusa | `daemon/refusal_log.rs` | os 4 testes do mesmo arquivo |

## 3. O canal de update

| mitigação | código | teste |
|---|---|---|
| um artefato só chega ao instalador depois que a assinatura minisign confere com a chave pública que o app entrega ao `UpdateFlow` | `dovetail_updater/lib/src/flow/update_flow.dart` | `update_flow_test.dart`: "should refuse an artefact whose bytes were altered" |
| uma assinatura de outra chave, ou com o comentário confiável editado, é recusada | `dovetail_updater/lib/src/minisign/minisign_verifier.dart` | `minisign_test.dart`: "should refuse a key that did not make it", "should refuse a trusted comment that was edited after signing" |
| o endpoint e todo redirecionamento têm de ser https | `dovetail_updater/lib/src/endpoint/endpoint_template.dart`, `dovetail_updater/lib/src/fetch/http_artifact_fetcher.dart` | `manifest_test.dart`: "should refuse an endpoint that is not https"; `http_artifact_fetcher_test.dart`: "should refuse anything that is not https" |
| uma versão mais velha é recusada, salvo se quem chama pedir | `dovetail_updater/lib/src/policy/update_policy.dart` | `manifest_test.dart`: "an older version should be refused, not merely skipped" |
| um manifesto ou uma assinatura malformados são recusados, nunca derrubam o app | `dovetail_updater/lib/src/manifest/manifest_parser.dart`, `dovetail_updater/lib/src/minisign/` | `fuzz_manifest_test.dart`, `fuzz_minisign_test.dart` |

## 4. A cadeia de build

| mitigação | código | teste |
|---|---|---|
| o CLI só instala ou atualiza um SDK com assinatura minisign da chave embutida nele | `dovetail_cli/lib/src/sdk/sdk_channel.dart` | `sdk_channel_test.dart`: "a channel without the minisig should refuse", "a tarball signed by another key should refuse" |
| meia credencial de assinatura é fatal mesmo num build local, e uma senha não definida nunca vira senha vazia | `dovetail_signer/lib/src/policy/signing_policy.dart` | `signing_policy_test.dart`: "a half configured set should be fatal even on a local build", "an unset password should be fatal instead of assumed empty" |
| o app e o daemon embutido nele têm de carregar o mesmo Team ID | `dovetail_cli/lib/src/command/sign_command.dart` | `sign_command_test.dart`: "a daemon whose Team ID differs from the app's should be refused, naming both values and where the daemon sits" |
| o `keygen` nunca sobrescreve um par de chaves de update | `dovetail_cli/lib/src/command/keygen_command.dart` | `keygen_command_test.dart`: "a second run should refuse rather than strand the park" |
| um commit com chave privada ou com um formato de token conhecido é recusado | `../scripts/checks/pre_commit.sh` | `../scripts/checks/pre_commit_selftest.sh` |

## Furos conhecidos

Cada furo diz o que o contém hoje e onde é acompanhado. Ids como `m6-install-sig` são linhas do [roadmap de produção](roadmap-producao.md).

| furo | contido hoje por | acompanhado em |
|---|---|---|
| macOS: o transporte por socket confere o código uma vez, no `accept`, e o `LOCAL_PEERTOKEN` descreve o processo como ele está na hora da consulta, então um processo passa fazendo exec de um programa admitido e deixa a conexão com um filho do fork | no macOS o daemon atende por XPC, e o sistema confere o remetente de toda mensagem contra o requisito (`channel/xpc_listener.rs`); a prova, que exige root, é `dovetail_privileged_channel/rust/tests/xpc_escalation.rs` e não roda no CI | o [README do canal](../../toolkit/dovetail_privileged_channel/README.md) |
| macOS: o transporte por socket (`bind`, `Listener`, `Stream`) continua público no crate do canal e continua compilando lá, então um app consegue montar o próprio daemon sobre a checagem feita uma vez no `accept` | o daemon privilegiado não o usa mais no macOS e atende por XPC (`daemon/server.rs`) | sem issue ainda |
| macOS: quando o próprio listener XPC falha (o serviço não está no launchd, ou o launchd o derruba), o fluxo de accept termina, o daemon sai do loop de accept e devolve `Ok`, e nada registra o motivo | o `KeepAlive` do launchd, quando o produto o liga | sem issue ainda |
| o canal declara `rust-version = "1.80"`, e os callbacks XPC que o shim chama (`admit_peer`, `deliver_bytes`, `free_boxed`) são `extern "C"`: antes do Rust 1.81 um pânico que escapa de um deles é comportamento indefinido, a partir do 1.81 ele aborta o daemon | os callbacks não fazem unwrap; um lock envenenado é recuperado | sem issue ainda |
| este modelo de ameaças ainda lista o socket do macOS como a mitigação do daemon na seção 2, e faltam lá as linhas do XPC: o requisito conferido em toda mensagem, o requisito fraco recusado no boot, o `--peer-requirement` aceito só de um property list `root:wheel` e o par recusado cancelado antes de qualquer escrita, cada uma com o seu teste | o [README do daemon](../../toolkit/dovetail_privileged_daemon/README.md) e o [README do canal](../../toolkit/dovetail_privileged_channel/README.md) os descrevem | sem issue ainda |
| macOS: um build de debug do daemon abre o socket para todo usuário local e, sem requisito declarado, admite qualquer par | o perfil de release; o build de debug registra um aviso | por desenho |
| o Linux autentica a conta, não o programa: qualquer processo de um uid ou gid admitido entra | os uids e gids que o produto escolhe | sem issue ainda |
| Windows: o pipe admite qualquer usuário local autenticado, a única checagem é que o executável do cliente esteja na pasta do daemon, e a `PeerPolicy` não é lida. Nada disso rodou | o SDDL do pipe, sem teste | sem issue ainda; o marco 3 do roadmap de produção cobre rodar |
| o daemon roda o `validate` antes do `dispatch` e limita cada comando com o `command_timeout` (`daemon/connection.rs:95-110`), mas nenhum teste prova nenhum dos dois | só o código | sem issue ainda |
| o manifesto não é assinado, e a versão que ele anuncia não está presa à assinatura: um host que serve um artefato assinado mais velho sob um número mais novo consegue instalá-lo, passando pela política de downgrade | o https, e quem opera o host de update | `m5-comentario-ligado` |
| o nome do arquivo do artefato vem da URL, e os instaladores de Linux e de Windows o juntam à pasta temporária sem recusar separador nem `..` | os bytes gravados continuam sendo o artefato assinado | `m5-traversal` |
| o instalador de Windows nunca aplicou um update de verdade, e os caminhos do `.deb` e do `.rpm` estão provados até o comando que montam | — | marcos 3 e 5 do roadmap de produção |
| o `tool/sdk/install.sh`, o caminho do `curl \| sh`, confere só um `.sha256` servido pelo mesmo host, e pula até isso quando não há ferramenta de hash; um CLI compilado sem a chave de release cai para esse mesmo `.sha256` | o https | `m6-install-sig` |
| a chave de release do SDK mora numa máquina só, e o CLI confia nessa única chave, sem lista para rotacionar | — | `m6-key-custody`, `m6-key-list` |
| ainda não há Developer ID, notarização, certificado Authenticode nem chave GPG | — | marco 4 do roadmap de produção |
| a CI hospedada não roda, então todo portão acima roda só na máquina do mantenedor | — | `m2-billing` |
| não há auditoria de dependências (`cargo audit`, `cargo deny`), SBOM nem build reprodutível | — | sem issue ainda |
| não há manifesto de menor privilégio por pacote dentro do app | a revisão que o próprio app faz do que usa | sem issue ainda |
| fora destas quatro fronteiras: o socket de instância única e o guarda do Windows aceitam qualquer par local, e um deep link de qualquer esquema chega a um app que não declara lista de esquemas | — | `m3-si-peer-unix`, `m3-si-peer-win`, `m3-deeplink-schemes` |
