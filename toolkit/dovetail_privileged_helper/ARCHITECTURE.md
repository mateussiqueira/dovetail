# Arquitetura

## 1. Por que estado, e não booleano

Está no README. O que fica aqui é o que ele não cabe: **por que seis estados e
não quatro.**

`SMAppService.status` do macOS informa quatro — `notRegistered`, `enabled`,
`requiresApproval`, `notFound`. Os dois que este pacote acrescenta são
`unsupported` e `blockedByPolicy`, e nenhum dos dois é enfeite.

`unsupported` existe porque `SMAppService` é macOS 13. Num macOS 12 a chamada
não falha de um jeito distinguível de "não registrado" — e responder
`notRegistered` ali faria a interface oferecer instalar algo que nunca vai
instalar. `unsupported` é a única resposta honesta, e `canEverBeEnabled` existe
para a tela não precisar conhecer a lista de plataformas.

`blockedByPolicy` existe porque uma organização pode proibir por MDM. O
sintoma é indistinguível de uma falha comum — a chamada volta erro — e a ação
certa é oposta: numa a pessoa tenta de novo, na outra ela nunca deveria tentar.
Só o Windows distingue isso com clareza hoje (o gerenciador de serviços tem
código de erro próprio para acesso negado por política); no macOS o estado
existe e não é alcançado ainda, e isso está escrito no código onde alguém vá
procurar.

## 2. Três plataformas, três formas, e o Linux sem nativo

O `pubspec.yaml` declara `pluginClass` no macOS, `ffiPlugin` no Windows, e nada
no Linux. Não é inconsistência.

**macOS é canal de método** porque `SMAppService` é Objective-C com
`NSError **` de saída e um guarda de disponibilidade (`@available`). Nada disso
atravessa um ABI de C sem ser achatado antes, e achatar significa inventar uma
tradução dos erros do sistema para inteiros — exatamente o que este pacote
existe para não fazer.

**Windows é FFI** pelo motivo oposto: o gerenciador de serviços responde em
inteiros. Um canal para três inteiros seria serialização, fila de mensagens e
assincronia para ler três inteiros. É a mesma escolha que o guarda de instância
única do pacote ao lado faz.

**Linux não tem nativo** porque o nativo seria um `Process.run('systemctl')`, e
o Dart já faz isso. Escrever C para envolver um `fork` seria adicionar uma
biblioteca compartilhada, uma entrada de CMake e uma superfície de erro nova
para ganhar exatamente nada. O `SystemdHelper` recebe um `ProcessRunner` do
`dovetail_process_runner`, que é como ele fica testável sem systemd nenhum.

## 3. O `SystemdHelper` não é exportado, e o `SystemdUnitState` é

O barril exporta a leitura da resposta do systemd e esconde a classe que a
produz. O motivo é um defeito que o pacote vizinho já publicou: uma classe cujo
argumento padrão nomeava um tipo que o consumidor não resolvia, então **apenas
escrever o construtor** produzia `Undefined class` — o pacote compilava, os
testes passavam, e quem instalava não conseguia usar.

`SystemdHelper` carrega `ProcessRunner` na assinatura, e ninguém que depende
deste pacote declara `dovetail_process_runner`. Quem precisa do helper chega
nele por `PrivilegedHelpers.of`, atrás da interface.

## 4. A bifurcação do macOS, e por que este pacote não a escolhe

Há dois caminhos para um app ser uma VPN de sistema no macOS, e eles não são
alternativas técnicas — são decisões de produto com consequências diferentes.

| | Daemon privilegiado (implementado) | Network Extension |
| --- | --- | --- |
| Distribuição | fora da App Store | **única rota para a Mac App Store** |
| Entitlement | nenhum | `com.apple.developer.networking.networkextension`, que a Apple precisa liberar na conta |
| O que a pessoa vê | senha de administrador, depois uma chave nos Ajustes | "…deseja adicionar configurações de VPN" |
| Onde o túnel roda | processo root que você escreve e assina | extensão em sandbox, com API da Apple |
| Se for revogado | o daemon continua registrado | a configuração some |

`HelperSpec.macOSRoute` é um `DarwinHelperRoute` com um valor hoje —
`privilegedDaemon` — e existe para o segundo caber depois **sem quebrar
chamador nenhum**: quem já escreveu `HelperSpec(...)` sem o campo continua
compilando, e quem quiser a extensão passa o outro valor.

Este pacote não implementa a Network Extension e não recomenda um caminho. Um
toolkit que escolhesse por quem o usa estaria decidindo se o produto pode ir
para a App Store.

## 5. `register()` devolve o estado depois, não o sucesso da chamada

No macOS uma instalação bem-sucedida cai com frequência em `requiresApproval`:
o daemon está registrado, nada falhou, e ele não roda. Um chamador que tratasse
"não lançou exceção" como sucesso diria à pessoa que ela está protegida
enquanto nada está no ar.

Por isso as quatro operações devolvem `HelperStatus`, e não `void` nem `bool`.
A pergunta "deu certo?" não tem resposta útil aqui; "em que estado ficou?" tem.
