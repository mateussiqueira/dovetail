# dovetail_platform_channel — decisões


O `README.md` diz o que este package faz. Aqui está por que ele faz assim, e o
que ficou de fora de propósito.

## A regra que decide tudo

Este package expõe capacidade e devolve evento. **Não decide.**

O teste é sempre o mesmo: se a resposta a "o que acontece agora?" depende do
produto, então não pertence aqui.

- Fechar a janela **para a bandeja** em vez de sair é política. `closeRequests()`
  é um `Stream`, e o app escolhe.
- Ligar o item de login **na primeira execução** é política. `LaunchAtLogin`
  expõe `isEnabled`, `enable` e `disable`, e nada mais.
- O texto do tooltip é produto, e num white-label é decisão de revenda.

Isso não é preferência de estilo. É o que mantém o package reutilizável entre
revendas e o que faz o grep de pureza continuar vazio:

```bash
grep -rniE "vpn|tunnel|reseller|myid" lib
```

## O menu de bandeja é dado, não callback

`TrayCommand`, `TraySeparator` e `TraySubmenu` formam uma hierarquia selada. O
id volta por `commands()`.

A alternativa — passar closure em cada entrada — parece mais direta e custa
duas coisas: o menu deixa de ser serializável (logar, testar e comparar ficam
difíceis) e o package passa a executar código do app, o que é exatamente a
inversão que a regra acima proíbe. O Tauri fazia o mesmo emitindo evento em vez
de chamar função, e por esse motivo.

## Capacidade ausente reporta; nunca finge

Três capacidades faltam em alguma plataforma, e cada uma tem um caminho de
queda escrito, não um silêncio:

**Tooltip de bandeja, ausente no Linux.** O `tray_manager` não o implementa lá.
Como o tooltip é hoje o único canal de uma mensagem que importa,
`setTooltip` grava uma **entrada desabilitada no topo do menu**, sob uma chave
reservada que `commands()` filtra. A mensagem chega; o app não precisa saber
por qual caminho.

**Painel ancorado, ausente no Linux.** Dois motivos somados: o
`StatusNotifierItem` publica menu e nada além, e o Wayland não permite que um
cliente posicione o próprio toplevel. `MenuOnlyPanelSurface` responde que não
há painel. Mostrar uma janela solta no meio da tela seria pior do que não
mostrar nada.

**Instância única, ausente no Windows.** No macOS e no Linux um socket de
domínio Unix resolve, e o `dart:io` os suporta nessas duas. No Windows a receita
é outra — mutex nomeado, janela oculta e `WM_COPYDATA` — e está escrita em
`windows/single_instance_guard.cpp`. **Nunca foi compilada**, porque nenhuma
máquina aqui é Windows, então a capacidade responde `false`. Isso é declarado com
teste, para ninguém confundir *escrito* com *funciona*.

## Permissão não é capacidade, e juntar as duas custa caro

`PlatformCapability` responde uma pergunta que não muda: esta plataforma sabe
notificar? A resposta vale para a vida inteira do processo, sai de
`defaultTargetPlatform` e não pergunta nada ao sistema.

Permissão é a pergunta oposta. Muda enquanto o app está aberto, por uma decisão
tomada **fora** dele, e some depois de ter sido dada. O pacote não tinha esse
conceito, e a falta dele produziu dois defeitos que estavam no ar:

1. `DarwinInitializationSettings` liga os três pedidos de permissão sozinho, e
   nenhum código daqui os desligava. O diálogo do macOS aparecia como efeito
   colateral do boot, antes de a pessoa ter qualquer ideia do que o app quer
   notificar. Um "não" ali é definitivo: o sistema não reexibe o diálogo.
2. `initialize()` devolve `Future<bool?>`, que no macOS **é o veredito da
   concessão**, e a resposta era descartada. `isAvailable` dizia `true` depois
   de a pessoa apertar "Não permitir", e `show()` sumia com o aviso em silêncio.

`PermissionState` tem quatro estados e mais um, e nenhum é decorativo:

| estado | quem produz | o que a UI faz |
|---|---|---|
| `notDetermined` | macOS antes do diálogo | pode pedir; `request()` funciona |
| `granted` | os três | nada |
| `denied` | macOS depois do "não"; Windows com o app desligado nos Ajustes | só `openSettings()`; pedir de novo não faz nada |
| `restricted` | Windows sob `NoToastApplicationNotification` | nem os Ajustes resolvem; é política |
| `unsupported` | Linux, e todo build sem o nativo | entrega, e não oferece botão nenhum |

O booleano juntaria `notDetermined` e `denied`, que pedem jornadas opostas: no
primeiro o diálogo ainda abre, no segundo ele nunca mais abre. Uma tela feita
sobre "pode ou não pode" manda a pessoa apertar um botão que deixou de fazer
efeito, e ninguém descobre por quê.

Não existe `PlatformCapability.notificationPermission`, e a ausência é
deliberada: seriam duas fontes para a mesma pergunta, e uma hora elas
discordam — a lista dizendo "esta plataforma pede permissão" enquanto o nativo
não carregou e `state()` já respondeu `unsupported`.

## O canal de método que quebra a regra do FFI

O nativo deste pacote é `ffiPlugin`: função C, inteiro de volta. A autorização
de notificação do macOS não cabe nessa forma —
`UNUserNotificationCenter.requestAuthorization` recebe um bloco de conclusão e
responde quando a pessoa clicar, que pode ser nunca. O pubspec declara
`pluginClass` **e** `ffiPlugin: true` para o macOS por isso; a aparência
continua atravessando por FFI, e só a permissão usa canal.

O Windows fica no FFI porque lá não há diálogo nenhum: a permissão é uma chave
de registro, e ler uma chave é síncrono.

## A permissão volta de fora, e a janela é quem percebe

O caso que todo mundo esquece: a pessoa concede nos Ajustes do sistema, volta
para o app, e o app continua dizendo "negado" até ser reiniciado. Não há
notificação de mudança para escutar — o que existe é o retorno do foco.

`WindowSurface.focusGains()` é esse sinal, e é uma stream separada de
`frameChanges()` de propósito: o quadro publica a cada redimensionamento e a
cada maximizar, e uma releitura de permissão presa nele iria ao sistema durante
todo arrasto de borda.

## A geometria do painel, e o ramo morto que ela tinha

`PanelGeometry` escolhe o lado a partir de **qual lado tem espaço**, não de qual
metade da tela o âncora está.

A primeira versão usava o ponto médio da área útil e caía para o outro lado
quando o preferido não caberia. Esse fallback era **inalcançável**: com uma
preferência por ponto médio, o lado preferido só deixa de caber em áreas onde o
outro também não cabe. Era código morto vestido de salvaguarda.

Com a regra por espaço, os dois comportamentos que importam caem fora sozinhos —
barra de menu no topo abre para baixo, barra de tarefas embaixo abre para cima —
e não existe ramo que nunca roda.

Um painel maior que a área útil é **encolhido**, não cortado. Quando nenhum lado
cabe, ele é grudado dentro da tela mesmo cobrindo o âncora: cobrir o ícone é
melhor do que ficar invisível.

## O caminho do executável não é `Platform.resolvedExecutable`

`ExecutablePath` existe porque três plataformas discordam sobre o que "o
executável" significa:

- **macOS**: o item de login precisa apontar para o `.app`, não para o Mach-O
  dentro dele. Apontar para o binário lista o item como "Unix Executable" nas
  Preferências do Sistema. Isso foi encontrado lendo o fonte do Tauri.
- **Linux sob AppImage**: `resolvedExecutable` devolve o ponto de montagem FUSE
  temporário, que deixa de existir quando o app fecha. `$APPIMAGE` é o caminho
  estável.
- **Windows**: o caminho direto serve.

## O formato de fio dos dois guardas é o mesmo

O guarda por socket (macOS, Linux) e o guarda em C++ (Windows) encaminham a
mesma coisa — diretório de trabalho e argumentos — e usam **NUL como separador**:
`\0\0` entre os campos, `\0` entre argumentos.

Espaço não serve. `C:\Program Files\...` tem espaço, e um separador por espaço
transformaria um caminho em dois argumentos errados. O formato é o mesmo que o
Tauri usa no macOS, e há teste comparando os dois lados byte a byte.

Do lado do FFI, `DovetailTakeForwardedLaunch` devolve o comprimento por
parâmetro de saída. Sem isso, `toDartString()` pararia no primeiro NUL e o Dart
receberia só o diretório de trabalho.

## Colocação de janela é validada contra as telas de agora

`PlacementGuard` recusa uma posição salva que não tem mais tela sob ela — um
monitor desconectado deixa a janela fora de alcance, e o usuário não tem como
trazê-la de volta. A régua é um retalho visível mínimo de 96×48; abaixo disso a
posição é descartada e o tamanho é mantido.

## O que não entra aqui, e por quê

- **Clipboard.** O `Clipboard.setData` do Flutter já resolve. Package para isso
  seria peso morto.
- **Registrar o esquema de deep link.** No Windows é escrita em `HKLM`, que só o
  instalador elevado faz; no Linux é um `.desktop` instalado pelo pacote. É do
  instalador, não do app em execução — ver `dovetail_bundler`.
- **Instalar o serviço privilegiado.** Do instalador, e o próprio helper do
  produto declara isso: no Linux e no macOS o registro é do pacote.
- **Multi-janela.** A API oficial do Flutter é `master`-only por declaração no
  fonte da ferramenta, `@internal` num arquivo que `widgets.dart` não exporta, e
  quebra `flutter test` quando ligada. O `desktop_multi_window` é bem cuidado e
  ainda assim errado aqui: cria **um engine por janela**, o que neste produto
  significa um segundo runtime tokio e um segundo dono do estado do túnel. O que
  um cliente de bandeja precisa não é janela — é colocação da única que ele tem,
  e isso é o `PanelSurface`.
- **Atalho global.** Package próprio, `dovetail_shortcut_channel`, porque precisa
  de Rust e de um contrato de recusa por sessão que não se parece com nada aqui.

## O que não dá para provar nesta máquina

Tudo abaixo é lido de documentação, não medido:

- O guarda em C++ do Windows, inteiro. Nunca compilou.
- `XGrabKey`, `HKLM`, `WM_COPYDATA`, mutex nomeado.
- O `StatusNotifierItem` real de qualquer ambiente Linux.
- O item de login aparecendo com o nome certo nas Preferências do Sistema.
- As duas chaves de registro da permissão de notificação:
  `Notifications\Settings\<AppUserModelId>\Enabled` e a política
  `NoToastApplicationNotification`. O `.cpp` compila em `mingw` daqui — o
  `tool/build_guard_probe.sh` é o molde —, e compilar não é ler o registro de
  ninguém.
- O diálogo do macOS aparecendo, e o painel `x-apple.systempreferences:` abrindo
  na página certa. Isso pede um `.app` empacotado e assinado; o que está provado
  aqui é que o canal chama `state` e `request` e traduz os cinco códigos.

O que está provado aqui é contrato e cálculo: a geometria do painel por
aritmética, o formato de fio por comparação byte a byte, e o mapeamento de cada
superfície por dublê.
