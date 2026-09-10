# Changelog

## 0.1.0 — 2026-09-10

Primeira versão.

Instalar o componente privilegiado de um app de desktop é um fluxo de permissão
do sistema, e não havia pacote Flutter que o modelasse. O que existia era o
booleano — `isHelperInstalled()` — que junta "nunca instalado", "instalado e
esperando a aprovação do usuário" e "bloqueado por política" num único `false`,
e faz o app oferecer o mesmo botão para os três.

- `HelperState` com seis estados, espelhando o que o `SMAppService` do macOS 13
  já informa em vez de inventar uma tradução.
- `PrivilegedHelper` com `status`, `register`, `unregister` e
  `openApprovalSettings` — todos devolvendo estado, nenhum devolvendo booleano.
- macOS 13+ por `SMAppService.daemon`, canal de método; abaixo disso responde
  `unsupported` em vez de fingir.
- Windows pelo gerenciador de serviços, por FFI.
- Linux por `systemctl` e polkit, em Dart — o nativo seria só um `Process.run`.
- `HelperWatch`, para reler quando a janela recupera o foco: a aprovação
  acontece fora do app, e quem lê o estado só na abertura mostra o estado
  errado até alguém reiniciar.
- `HelperSpec.macOSRoute`, para o caminho de Network Extension chegar depois
  sem quebrar chamador nenhum.

Windows e Linux não foram compilados nas plataformas alvo.
