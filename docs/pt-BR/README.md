**Português** · [English](../README.md)

# Documentação do dovetail

Este índice existe porque um documento que você não encontra não está escrito.
Cada linha diz **qual pergunta** o arquivo responde — e um teste recusa quando
algum deles não é citado aqui.

## Comece aqui

| se você quer | leia |
|---|---|
| começar a usar em cinco minutos | [quickstart.md](quickstart.md) |
| entender o que o projeto é, e o que já está provado | [`../README.md`](../../README.md) |
| **escrever telas** contra o framework | [`../ESCREVER_O_APP.md`](../../ESCREVER_O_APP.md) |
| **sair do Tauri** num produto que já existe | [migrar-do-tauri.md](migrar-do-tauri.md) |
| saber o que cada chave do `dovetail.yaml` faz | [configuracao.md](configuracao.md) |
| descobrir por que algo quebrou | [problemas.md](problemas.md) |
| o que o CI roda em cada sistema, e o que ainda não provou | [ci.md](ci.md) |
| instalar o dovetail fora do monorepo, e as fases até lá | [instalador.md](instalador.md) |
| o que vem depois das 5 fases, por área (toolkit, CLI, DX) | [roadmap.md](roadmap.md) |
| o caminho até **produção**: marcos, critérios de aceite e o que está bloqueado fora do código | [roadmap-producao.md](roadmap-producao.md) |
| rodar a esteira **inteira** sem chave de produção, host nem Developer ID, com substitutos que seguem o mesmo contrato | [release-simulado.md](release-simulado.md) |
| entregar um artefato a um **usuário final de verdade**: o que o canal de release exige, o que `ship` e `doctor` recusam antes de um build, e o que o updater faz quando um download corrompe ou um manifesto mente | [release-channel.md](release-channel.md) |
| saber o que o dovetail defende, contra quem, e os furos já conhecidos | [threat-model.md](threat-model.md) |
| relatar uma vulnerabilidade, e o que está no escopo | [`../SECURITY.pt-BR.md`](../../SECURITY.pt-BR.md) |
| contribuir, e o que ajuda mais neste momento | [`../CONTRIBUTING.pt-BR.md`](../../CONTRIBUTING.pt-BR.md) |

## A esteira

Empacotar, assinar e publicar. Roda na máquina de release, nunca dentro do app.

| pacote | o que responde |
|---|---|
| [`toolkit/dovetail_cli`](../../toolkit/dovetail_cli/README.md) | os dezenove comandos, e o que cada um recusa |
| [`toolkit/dovetail_bundler`](../../toolkit/dovetail_bundler/README.md) | nsis, msi, dmg, deb, rpm — e as armadilhas do Tauri que aqui são erro fatal |
| [`toolkit/dovetail_signer`](../../toolkit/dovetail_signer/README.md) | codesign, notarização, Authenticode, SHA256SUMS |

## O runtime

O que o app carrega. Entra tudo por um barril: `package:dovetail/dovetail.dart`.

| pacote | o que responde |
|---|---|
| [`toolkit/dovetail`](../../toolkit/dovetail/README.md) | o barril: o que entra, o que fica de fora e por quê |
| [`toolkit/dovetail_platform_channel`](../../toolkit/dovetail_platform_channel/README.md) | janela, bandeja, painel ancorado, instância única, deep link, notificação |
| [`toolkit/dovetail_shortcut_channel`](../../toolkit/dovetail_shortcut_channel/README.md) | atalho global, e por que Wayland é recusado em vez de fingido |
| [`toolkit/dovetail_updater`](../../toolkit/dovetail_updater/README.md) | manifesto, verificação minisign, instalação nos três sistemas |
| [`toolkit/dovetail_form_validation`](../../toolkit/dovetail_form_validation/README.md) | as sete regras de formulário, e por que a falha é tipo selado |
| [`toolkit/dovetail_process_runner`](../../toolkit/dovetail_process_runner/README.md) | rodar processo sem os três impasses que `Process.run` tem |
| [`toolkit/dovetail_rust_core`](../../toolkit/dovetail_rust_core/README.md) | a mecânica Dart↔Rust: runtime tokio, bomba de eventos, sonda |

## Ao lado do runtime

Fora do barril: o app declara cada um por conta própria, quando precisa.

| pacote | o que responde |
|---|---|
| [`toolkit/dovetail_privileged_helper`](../../toolkit/dovetail_privileged_helper/README.pt-BR.md) | instalar, relatar e remover o componente privilegiado, com um estado em vez de um bool |
| [`toolkit/dovetail_privileged_channel`](../../toolkit/dovetail_privileged_channel/README.md) | o canal Rust até esse componente: transporte, autenticação do par, framing, handshake |
| [`toolkit/dovetail_privileged_daemon`](../../toolkit/dovetail_privileged_daemon/README.md) | o esqueleto Rust do próprio daemon: instalação do serviço, laço de accept, validação, logs |
| [`toolkit/dovetail_http_client`](../../toolkit/dovetail_http_client/README.md) | um cliente HTTP tipado para a API do próprio produto, e onde o token mora |
| [`toolkit/dovetail_screenshots`](../../toolkit/dovetail_screenshots/README.md) | cada tela e estado capturados em PNG, sem `pumpAndSettle` e com as fontes de ícone |

Os quatro últimos só existem em inglês.

## O que não está aqui

O app que consome o toolkit, e a ponte com o núcleo Rust dele, moram noutro
repositório: são produto, não framework. O que este repositório carrega é o
toolkit inteiro — que é tudo de que qualquer app precisa para ser construído,
empacotado, assinado e atualizado.

Alguns documentos ainda mencionam `product/` como o caminho do exemplo que
exercita um mecanismo. Esses levam no topo uma nota dizendo isso.

## As decisões, com o porquê

`ARCHITECTURE.md` é onde mora o raciocínio que não cabe num README:

- [`dovetail_rust_core`](../../toolkit/dovetail_rust_core/ARCHITECTURE.md) — por que uma instância
  em vez de estado global, e por que não existe `resetForTesting()`.
- [`dovetail_platform_channel`](../../toolkit/dovetail_platform_channel/ARCHITECTURE.md)
  — por que o painel é calculado e não medido, e o formato de fio comparado
  byte a byte.
- [`dovetail_privileged_helper`](../../toolkit/dovetail_privileged_helper/ARCHITECTURE.md)
  — por que seis estados e não os quatro que o macOS informa.

## O que a documentação promete, e quem cobra

Cinco coisas aqui são conferidas por teste, porque documento envelhece calado:

| o que | quem cobra |
|---|---|
| toda chave do `dovetail.yaml` está em `configuracao.md` | `config_documented_test.dart` |
| todo comando do CLI está no README dele | `readme_covers_commands_test.dart` |
| a tabela de testes do README bate com a corrida | `verify test` |
| todo pacote tem README, CHANGELOG, LICENSE | `package_paperwork_test.dart` |
| todo documento é citado neste índice, e todo link resolve | `docs_index_test.dart` |

E o resto é prosa, que ninguém consegue cobrar. Se algo aqui divergir do
código, **o código está certo e o documento está velho** — e vale mais
corrigir o documento do que contornar.
