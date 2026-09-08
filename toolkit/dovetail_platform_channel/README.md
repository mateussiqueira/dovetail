# dovetail_platform_channel


> O canal entre o Flutter e o sistema operacional no desktop. Janela, bandeja, item de login, deep link, notificação e entrega ao aplicativo padrão — em Windows, macOS e Linux.

Quando o Tauri sai, o webview vai com ele, e com o webview vão coisas que ninguém tinha listado: a janela sem borda, o ícone de bandeja, abrir um link no navegador do sistema. Este package é o lugar dessas capacidades.

## A fronteira

```
app Flutter desktop            <- a regra de negócio, e só aqui
  ├── desktop_core_bridge      <- canal para o núcleo Rust
  ├── dovetail_platform_channel <- este package: canal para o SO
  └── dovetail_rust_core                <- mecânica Dart<->Rust
```

Este package **não decide nada**. Ele não esconde a janela em vez de fechar, não liga o autostart na primeira execução, não escolhe o texto do tooltip. Ele expõe a capacidade e devolve o evento; quem decide é o app.

O exemplo mais claro: `WindowSurface.closeRequests()` é um `Stream`. Fechar-para-bandeja é política, e política é do app.

## Instalação

```yaml
dependencies:
  dovetail_platform_channel:
    path: ../dovetail_platform_channel
```

## Uso

```dart
import 'package:dovetail_platform_channel/dovetail_platform_channel.dart';

Future<void> main() async {
  final SingleInstanceVerdict verdict =
      await DesktopPlatformChannel.claimSingleInstance('com.example.app');
  if (!verdict.mayRun) {
    return;
  }

  final DesktopPlatform platform = await DesktopPlatformChannel.ensureInitialized(
    const DesktopAppSpec(
      window: WindowSpec(
        size: Size(1200, 720),
        minimumSize: Size(1024, 640),
      ),
      applicationId: 'com.example.app',
      displayName: 'Example',
      notificationGuid: '00000000-0000-0000-0000-000000000000',
    ),
  );

  platform.window.closeRequests().listen((_) => platform.window.hide());

  await platform.tray.attach(
    icon: const TrayIconAsset('assets/tray.png'),
    menu: const <TrayEntry>[
      TrayCommand(id: 'open', label: 'Open'),
      TraySeparator(),
      TrayCommand(id: 'quit', label: 'Quit'),
    ],
  );
  platform.tray.commands().listen(handleTrayCommand);

  runApp(const App());
}
```

Nenhum número aqui é padrão do package: `1200x720` e o nome vêm do app, porque tamanho de janela e nome são decisão de produto — e no white-label, decisão de revenda.

## A sonda de capacidade

Em vez de `Platform.isLinux` espalhado pelo app:

```dart
if (platform.supports(PlatformCapability.trayTooltip)) {
  await platform.tray.setTooltip(message);
}
```

A tabela hoje, medida:

| Capacidade | Windows | macOS | Linux |
|---|:-:|:-:|:-:|
| janela sem borda, prevent close, skip taskbar | ✓ | ✓ | ✓ |
| ícone e menu de bandeja | ✓ | ✓ | ✓ |
| **tooltip de bandeja** | ✓ | ✓ | **✗** |
| **painel ancorado na bandeja** | ✓ | ✓ | **✗** |
| item de login | ✓ | ✓ | ✓ |
| deep link | ✓ | ✓ | ✓ |
| notificação | ✓ | ✓ | ✓ |
| abrir no aplicativo padrão | ✓ | ✓ | ✓ |
| **instância única** | **✗** | ✓ | ✓ |

Um deep link que chega enquanto o app já roda vem por um segundo processo, e
não pelo `app_links`. O `deepLinks` que o canal entrega junta as duas fontes:
quem escuta `links()` vê tanto a URL do sistema quanto a que o guarda de
instância única encaminhou. Sem essa junção o `ForwardedLaunch` chegava com a
URL em `arguments` e nunca alcançava o inbox.

No Windows `claimSingleInstance` responde `unavailable`, e não `primary`: o guarda
nomeado existe em `windows/single_instance_guard.cpp` e ainda não está ligado ao
Dart, então dois cliques abrem duas janelas e cada deep link abre uma terceira.
`mayRun` é `true` nos dois estados que podem seguir — use-o para decidir se roda, e
`isGuarded` para saber se a garantia de fato existe nesta plataforma.

O tooltip não existe no Linux porque o `tray_manager` não o implementa lá. Como o tooltip é hoje o único canal de uma mensagem que importa, `setTooltip` **cai para uma entrada desabilitada no topo do menu** em vez de sumir em silêncio — e essa entrada nunca aparece em `commands()`.

O painel ancorado não existe no Linux por dois motivos somados: o `StatusNotifierItem` publica menu e nada mais, e o Wayland não deixa um cliente posicionar o próprio toplevel. Lá `MenuOnlyPanelSurface` **reporta que não há painel** em vez de mostrar uma janela vazia.

Instância única é ✓ no macOS e no Linux, onde um socket de domínio Unix resolve — o `dart:io` os suporta nessas duas. No Windows não: lá precisa de mutex nomeado mais janela oculta com `WM_COPYDATA`, e isso é C++ que **nunca foi compilado**, porque nenhuma máquina aqui é Windows. Está declarado como falso de propósito, com teste, para ninguém confundir "escrito" com "funciona".

## Superfícies

| Superfície | Contrato |
|---|---|
| `WindowSurface` | show/hide/focus/minimize/restore/maximize, arraste da barra própria, prevent close, skip taskbar, always-on-top, `setBounds`/`bounds`, `frameChanges()`, `closeRequests()` |
| `TraySurface` | ícone, menu como dado selado, tooltip com queda no Linux, `commands()`, `gestures()` |
| `PanelSurface` | abre a janela principal ancorada na bandeja, `dismissals()`; no Linux reporta ausência |
| `DisplayProbe` | ponto do cursor, área útil do monitor sob um ponto, todas as áreas úteis |
| `WindowPlacement` · `WindowStateStore` · `WindowStateKeeper` | lembra tamanho, posição e maximizado entre sessões, quando `DesktopAppSpec.stateDirectory` diz onde |
| `SingleInstanceVerdict` · `ForwardedLaunch` | `primary`/`secondary`, e os argumentos que a segunda instância encaminhou |
| `LaunchAtLogin` | `isEnabled` · `enable` · `disable` |
| `DeepLinkInbox` | `initialLink()` · `links()` |
| `SystemNotifier` | `show` · `cancel` · `cancelAll` |
| `ExternalOpener` | `openUrl` · `canOpenUrl` |
| `BundleInfo` | nome, versão, build, identificador |

Isso é opt-in por um motivo: o pacote não escolhe onde escrever no disco do
usuário. Passe `stateDirectory` no `DesktopAppSpec` — o diretório de suporte do
app, tipicamente — e o canal carrega a posição salva, prende-a às telas que
existem agora e passa a salvar de volta. Sem ele, nada é lido nem escrito.

Uma posição salva num monitor que foi desconectado entre sessões não é
aplicada: a janela abriria onde o usuário não a encontra. E o salvamento espera
a janela assentar, porque arrastar emite um evento por pixel e gravar em cada
um transforma um movimento de janela em centenas de escritas em disco.

O menu é dado, não callback: `TrayCommand`, `TraySeparator` e `TraySubmenu` numa hierarquia selada. O id volta por `commands()` e o app decide o que fazer — igual ao que o Tauri fazia emitindo evento em vez de chamar função.

## O que não entra aqui

- **Clipboard.** O Flutter já faz, com `Clipboard.setData`. Package para isso seria peso morto.
- **Registrar o esquema de deep link.** No Windows é escrita em `HKLM` que só o instalador elevado faz; no Linux é um `.desktop` instalado pelo pacote. É do instalador, não do app em execução.
- **Instalar o serviço privilegiado e o updater.** São do instalador e da esteira.
- **Qualquer política.** Ver acima.

## Desenvolvimento

```bash
flutter test
```

```bash
flutter analyze
```

As decisões e o que ficou de fora estão em `ARCHITECTURE.md`.
