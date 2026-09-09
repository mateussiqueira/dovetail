**English** · [Português](README.pt-BR.md)

# dovetail

One dependency for everything the app **runs**.

Researching what already exists in the Flutter desktop ecosystem always led to
the same answer: the pieces are all there — `window_manager`, `tray_manager`,
`hotkey_manager`, `auto_updater`, Fastforge — except each one has a different
author, its own configuration and its own release cycle.
`awesome-flutter-desktop`, which is the canonical list, does not even have a
category for code signing. Tauri's value was never one piece: it was a CLI and
a file.

```yaml
dependencies:
  dovetail: ^0.1.0
```

```dart
import 'package:dovetail/dovetail.dart';
```

## What comes in

| package | what it brings |
|---|---|
| `dovetail_platform_channel` | window, tray, anchored panel, single instance, deep link, notification, login item |
| `dovetail_shortcut_channel` | global shortcut, through the same `global-hotkey` crate Tauri uses |
| `dovetail_updater` | manifest, download with a ceiling, minisign verification, installing on all three OSs |
| `dovetail_form_validation` | the seven form rules, with a failure that says which one broke |
| `dovetail_process_runner` | the runner the installers receive |

## What stays out, on purpose

`dovetail_bundler`, `dovetail_signer` and `dovetail_cli` do **not** come in.
Packaging and signing happen on the release machine, never inside the app;
dragging them in here would put a code-signing toolchain inside every user
build. Those three already have an entry point, and it is `dovetail_cli`.

A product's bridge package stays out too: it carries one specific product's
Rust API, and a toolkit package knows about no product at all.

## What this does not solve

Having a barrel does not make what is behind it ready. Each package documents
what it proves on one machine and what needs another operating system; the
barrel does not change a line of that.
