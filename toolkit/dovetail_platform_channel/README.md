**English** · [Português](README.pt-BR.md)

# dovetail_platform_channel

> The channel between Flutter and the desktop operating system. Window, tray,
> login item, deep link, notification and handing off to the default
> application — on Windows, macOS and Linux.

When Tauri leaves, the webview goes with it, and with the webview go things
nobody had listed: the borderless window, the tray icon, opening a link in the
system browser. This package is where those capabilities live.

## The boundary

```
Flutter desktop app             <- the business rules, and only here
  ├── your bridge package       <- channel to the Rust core
  ├── dovetail_platform_channel <- this package: channel to the OS
  └── dovetail_rust_core        <- Dart<->Rust mechanics
```

This package **decides nothing**. It does not hide the window instead of
closing it, does not enable autostart on first run, does not choose the
tooltip's text. It exposes the capability and returns the event; the app
decides.

The clearest example: `WindowSurface.closeRequests()` is a `Stream`.
Close-to-tray is policy, and policy belongs to the app.

## Installation

```yaml
dependencies:
  dovetail_platform_channel: ^0.1.0
```

## Usage

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

None of the numbers here are package defaults: `1200x720` and the name come
from the app, because window size and name are a product decision — and under
white-labelling, a reseller's.

## The capability probe

Instead of `Platform.isLinux` scattered through the app:

```dart
if (platform.supports(PlatformCapability.trayTooltip)) {
  await platform.tray.setTooltip(message);
}
```

The table as measured today:

| Capability | Windows | macOS | Linux |
|---|:-:|:-:|:-:|
| borderless window, prevent close, skip taskbar | ✓ | ✓ | ✓ |
| tray icon and menu | ✓ | ✓ | ✓ |
| **tray tooltip** | ✓ | ✓ | **✗** |
| **panel anchored to the tray** | ✓ | ✓ | **✗** |
| login item | ✓ | ✓ | ✓ |
| deep link | ✓ | ✓ | ✓ |
| notification | ✓ | ✓ | ✓ |
| open in the default application | ✓ | ✓ | ✓ |
| **single instance** | **✗** | ✓ | ✓ |

A deep link that arrives while the app is already running comes through a
second process, not through `app_links`. The `deepLinks` the channel delivers
joins both sources: whoever listens to `links()` sees the system's URL as well
as the one the single-instance guard forwarded. Without that join, a
`ForwardedLaunch` arrived with the URL in `arguments` and never reached the
inbox.

On Windows `claimSingleInstance` answers `unavailable`, not `primary`: the
named guard exists in `windows/single_instance_guard.cpp` and is not yet wired
to Dart, so two clicks open two windows and each deep link opens a third.
`mayRun` is `true` in both states that may proceed — use it to decide whether
to run, and `isGuarded` to know whether the guarantee actually exists on this
platform.

The tooltip does not exist on Linux because `tray_manager` does not implement
it there. Since the tooltip is today the only channel for a message that
matters, `setTooltip` **falls back to a disabled entry at the top of the menu**
instead of vanishing silently — and that entry never appears in `commands()`.

The anchored panel does not exist on Linux for two reasons combined:
`StatusNotifierItem` publishes a menu and nothing else, and Wayland does not
let a client position its own toplevel. There, `MenuOnlyPanelSurface`
**reports that there is no panel** instead of showing an empty window.

Single instance is ✓ on macOS and Linux, where a Unix domain socket solves it —
`dart:io` supports them on those two. On Windows it does not: there it needs a
named mutex plus a hidden window with `WM_COPYDATA`, and that is C++ that
**has never been compiled**, because no machine here is Windows. It is declared
false on purpose, with a test, so nobody confuses "written" with "works".

## Surfaces

| Surface | Contract |
|---|---|
| `WindowSurface` | show/hide/focus/minimize/restore/maximize, dragging by a custom bar, prevent close, skip taskbar, always-on-top, `setBounds`/`bounds`, `frameChanges()`, `closeRequests()` |
| `TraySurface` | icon, menu as sealed data, tooltip with the Linux fallback, `commands()`, `gestures()` |
| `PanelSurface` | opens the main window anchored to the tray, `dismissals()`; on Linux it reports absence |
| `DisplayProbe` | cursor point, work area of the display under a point, all work areas |
| `WindowPlacement` · `WindowStateStore` · `WindowStateKeeper` | remembers size, position and maximised state between sessions, when `DesktopAppSpec.stateDirectory` says where |
| `SingleInstanceVerdict` · `ForwardedLaunch` | `primary`/`secondary`, and the arguments the second instance forwarded |
| `LaunchAtLogin` | `isEnabled` · `enable` · `disable` |
| `DeepLinkInbox` | `initialLink()` · `links()` |
| `SystemNotifier` | `show` · `cancel` · `cancelAll` |
| `ExternalOpener` | `openUrl` · `canOpenUrl` |
| `BundleInfo` | name, version, build, identifier |

Window state is opt-in for one reason: the package does not choose where to
write on the user's disk. Pass `stateDirectory` in the `DesktopAppSpec` — the
app's support directory, typically — and the channel loads the saved position,
clamps it to the displays that exist now, and starts saving it back. Without
it, nothing is read or written.

A position saved on a display that was disconnected between sessions is not
applied: the window would open where the user cannot find it. And saving waits
for the window to settle, because dragging emits one event per pixel and
writing on each turns a window move into hundreds of disk writes.

The menu is data, not a callback: `TrayCommand`, `TraySeparator` and
`TraySubmenu` in a sealed hierarchy. The id comes back through `commands()` and
the app decides what to do — the same as what Tauri did by emitting an event
instead of calling a function.

## What does not come in here

- **Clipboard.** Flutter already does it, with `Clipboard.setData`. A package
  for that would be dead weight.
- **Registering the deep link scheme.** On Windows it is a write to `HKLM`
  that only the elevated installer performs; on Linux it is a `.desktop` file
  installed by the package. It belongs to the installer, not to the running
  app.
- **Installing the privileged service and the updater.** Those belong to the
  installer and the pipeline.
- **Any policy.** See above.

## Development

```bash
flutter test
```

```bash
flutter analyze
```

The decisions, and what was left out, are in `ARCHITECTURE.md`.
