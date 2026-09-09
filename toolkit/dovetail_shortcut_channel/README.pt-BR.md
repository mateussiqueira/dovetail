**Português** · [English](README.md)

# dovetail_shortcut_channel

Prende um acorde de teclado que o sistema operacional entrega ao app **mesmo
quando nenhuma janela dele tem foco**, e recusa em voz alta em toda sessão onde
nenhum acorde desses pode ser concedido.

Nada aqui sabe o que é VPN. O app decide qual acorde oferecer e o que uma
pressão significa; este package o prende, ou diz por que não pode.

## Onde ele roda

| Sessão | Mecanismo | Quem escolhe o acorde | Pede permissão |
| --- | --- | --- | --- |
| Windows | `RegisterHotKey` | o app | não |
| macOS | Carbon `RegisterEventHotKey` | o app | não |
| Linux, X11 | `XGrabKey` na janela raiz | o app | não |
| Linux, Wayland | *recusado* | — | — |

Os três que funcionam passam pela crate [`global-hotkey`][crate] — a mesma que
o build Tauri já usa, então o comportamento do parque instalado não muda quando
a interface muda.

O macOS usa deliberadamente a API Carbon depreciada em vez de `CGEventTap` ou
`NSEvent.addGlobalMonitorForEvents`. O Carbon não pede permissão de privacidade
nenhuma: o app diz *me acorde neste acorde* e nunca vê outra tecla. Os dois
caminhos modernos exigem Input Monitoring ou Acessibilidade, o que num cliente
de VPN significa pedir ao usuário a permissão de um keylogger. Essa troca não
vale a pena.

## Wayland é recusado, não fingido

Um compositor Wayland concede atalho de sistema só pelo portal
`org.freedesktop.portal.GlobalShortcuts`, onde **o compositor é dono do
acorde** — o app manda um gatilho preferido e o usuário confirma ou muda num
diálogo do sistema. Esse portal é implementado pelo Plasma e pelo GNOME a
partir do 48; sway, river, niri e todo outro compositor wlroots não têm
implementação nenhuma, e o Hyprland aceita o bind ignorando o gatilho
preferido, que é o pior desfecho disponível: um sucesso que o usuário não
consegue pressionar.

Então este package reporta `ShortcutBackend.waylandPortal` com
`available: false` e a sessão nomeada na recusa. Um atalho que reporta sucesso
e nunca dispara custa mais caro que um que diz não.

Falar esse portal é uma decisão com conta anexada: é nosso código para sempre
(a crate declara Linux X11 apenas e não tem plano para Wayland), muda a cada
versão do portal, e nada disso pode ser testado sem pelo menos uma VM com
Plasma, uma com GNOME e uma sessão sway. É uma costura, não uma lacuna.

## A armadilha para a qual a sonda existe

Sob XWayland existe um `DISPLAY` definido, então uma sonda ingênua lê a sessão
como X11 e chama `XGrabKey` — que tem sucesso e nunca dispara, porque o grab
nunca vê as teclas do compositor. Por isso `XDG_SESSION_TYPE` vence um
`DISPLAY` presente, e a sonda lê um ambiente injetado para que essa regra seja
testável em vez de afirmada.

## A política, e por que ela mora aqui

`ShortcutPolicy` recusa um acorde antes de o backend vê-lo:

- **Sem modificador primário** — um acorde sem Control, Command ou Meta está a
  uma tecla de distância de qualquer outro aplicativo da máquina.
- **F12** — reservado para o depurador no Windows. Um acorde que funciona em
  duas plataformas de três é uma chamada de suporte.
- **A tecla Windows, no Windows** — o sistema as reserva; o `RegisterHotKey`
  as recusa.
- **Só Option e Option+Shift, no macOS** — o macOS 15.0 parou de entregá-los a
  apps em sandbox, e o fez sem erro no ponto de chamada.

Isso é formato e mecânica, não regra de negócio: o package recusa o acorde
impróprio, o app decide qual acorde oferecer.

## Construir e provar

```bash
cd rust && cargo test && cargo build --release --features test-probe
flutter test
```

O `cargo build --release` é o que deixa o `flutter test` dirigir o registro de
verdade — a suíte carrega a biblioteca construída e prende acordes reais pela
API real da plataforma. Sem ele a suíte nativa se pula e diz isso, em vez de
passar por vacuidade.

O `--features test-probe` é o que deixa a suíte entregar uma pressão. A função
que ele acrescenta, `dovetail_shortcut_emit_probe`, permite a qualquer processo
que carregue a biblioteca sintetizar uma pressão de atalho, então ela está
desligada por padrão e nenhum build entregue a carrega — medido com `nm`, não
suposto. Uma corrida da suíte contra um build sem ela passa e pula os três
testes que dirigem a bomba, nomeando a feature de que precisam.

Num build de app, o cargokit dirige o cargo a partir do `flutter build`, e a
biblioteca Rust tem de continuar com o nome do plugin: o carregador procura
pelo stem, então uma renomeação produz uma falha de `dlopen` nomeando os dois
nomes sob os quais ela é construída no macOS —
`dovetail_shortcut_channel.framework/dovetail_shortcut_channel` e
`libdovetail_shortcut_channel.dylib` — e nenhum dos dois menciona a
renomeação.

## O que não está provado aqui

O caminho do macOS é exercitado nesta máquina: o registro abre, acordes reais
prendem, e uma pressão atravessa uma thread do sistema até o isolate do Dart.
Todo o resto é lido da documentação da plataforma e da crate:

- **Windows** — `RegisterHotKey`, `MOD_NOREPEAT`, o `WM_HOTKEY` chegando na
  thread da bomba, e a recusa de já-tomado-por-outro-app.
- **X11** — `XGrabKey`, conflitos com o gerenciador de janelas, outros layouts
  de teclado.
- **Wayland** — o caminho inteiro do portal, deliberadamente ausente.

[crate]: https://crates.io/crates/global-hotkey
