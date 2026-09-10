[English](README.md) · **Português**

# dovetail_privileged_helper

Instala, informa e remove o componente privilegiado que um app Flutter de
desktop em sandbox **não pode ser**: um daemon no macOS, um serviço no Windows,
uma unidade systemd no Linux.

Ele responde com um **estado**, nunca com um booleano. É esse o ponto.

## O booleano que esconde três problemas diferentes

Um cliente de VPN não abre túnel a partir do processo da interface. Ele precisa
de algo rodando como root — e *instalar esse algo é um fluxo de permissão do
sistema operacional*, não uma cópia de arquivo. A maioria dos apps modela isso
como `isHelperInstalled() -> bool`, e esse único bit junta três situações que
exigem ações **opostas**:

| O que é verdade | O que a pessoa precisa fazer | O que o booleano diz |
| --- | --- | --- |
| nunca foi registrado | instalar — vai pedir senha de administrador | `false` |
| registrado, esperando aprovação nos Ajustes | **ir aos Ajustes e ligar a chave**; instalar de novo não faz nada | `false` |
| bloqueado por política (MDM) | nada vai funcionar; falar com quem administra | `false` |

Um app construído sobre o booleano mostra um botão só — *Reparar* — para os
três. Ele conserta o primeiro, é inócuo no segundo e falha para sempre no
terceiro, e quem está do outro lado não tem como saber em qual está.

```dart
enum HelperState { unsupported, notRegistered, requiresApproval, enabled, blockedByPolicy, failed }
```

A forma não foi inventada aqui. O `SMAppService.status` do macOS 13 informa
exatamente `notRegistered`, `enabled`, `requiresApproval` e `notFound`; este
enum espelha o que a plataforma já diz, então nada é adivinhado em Dart.

## Onde roda

| Plataforma | Mecanismo | Pergunta ao usuário | Painel de aprovação |
| --- | --- | --- | --- |
| macOS 13+ | `SMAppService.daemon` | senha de admin, depois uma chave de aprovação | Itens de Login e Extensões |
| macOS < 13 | *não suportado* | — | — |
| Windows | gerenciador de serviços | elevação UAC | nenhum — o UAC é o fluxo inteiro |
| Linux | systemd + polkit | prompt do polkit | nenhum — o polkit não tem painel |

`requiresApproval` é invenção do macOS 13 e é o estado que todo mundo esquece:
o daemon **está** registrado, a instalação deu certo, e mesmo assim ele não
roda até a pessoa encontrá-lo em *Ajustes → Geral → Itens de Login e Extensões*
e ligar. `openApprovalSettings()` leva até lá, e devolve
`ApprovalPaneOutcome.absent` nas plataformas que não têm esse painel em vez de
fingir que abriu um.

## Releia quando a sua janela voltar

A pessoa concede isso **fora do seu app**. Ela sai, liga uma chave nos Ajustes
e volta — e um app que leu o estado uma vez na abertura vai continuar mostrando
`requiresApproval` até ser reiniciado.

`HelperWatch` relê a partir de um sinal que você fornece; ligue-o ao evento de
foco da sua janela. Quem é dono da janela é o `dovetail_platform_channel`, e
ele expõe um.

## O que não está aqui

**A Network Extension.** No macOS há dois caminhos para ser uma VPN de sistema
e este pacote implementa um. O `HelperSpec.macOSRoute` existe para o outro
chegar sem quebrar nenhum chamador — veja o `ARCHITECTURE.md` para o que cada
caminho custa, porque essa escolha é do produto, não de um toolkit.

**O binário do helper.** Este pacote registra, informa e remove. O que ele faz
rodando, como é assinado e como conversa com o app é assunto do app.

## Estado

Escrito num macOS arm64. O caminho do macOS é exercitado; os nativos de Windows
e Linux foram **escritos às cegas e nunca compilados** nas plataformas alvo — a
mesma ressalva que o resto deste repositório carrega. Se você rodar no Windows
ou no Linux, uma issue com a saída é a coisa mais útil que este pacote pode
receber.

Parte do [dovetail](https://github.com/mateussiqueira/dovetail). MIT.
