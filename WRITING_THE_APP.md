**English** · [Português](ESCREVER_O_APP.md)

# Writing the app with dovetail

This repository's `README.md` describes the **pipeline**: how a project becomes
a signed `.dmg`, `.msi`, `.deb` and a manifest. This document is the other
side — how you write the application the pipeline packages.

Everything here was checked against the code. Where something does not exist
yet, it says so rather than leaving it out.

---

## The boundary, and why it is the most important subject

dovetail **exposes capability and returns events. It does not decide.**

That is not library modesty: it is the rule that avoids the problem that led
out of Tauri. The shortest example:

```dart
platform.window.closeRequests().listen((_) => platform.window.hide());
```

`closeRequests()` is a `Stream`. **Closing to the tray is policy**, and policy
belongs to the app. If the package hid the window on its own, the day the
product wanted to ask first would become a fork.

The same rule holds everywhere:

| dovetail gives you | you decide |
|---|---|
| the request to close the window | hide, ask, or quit |
| the tray command that was clicked | what each command does |
| the typed failure from the Rust core | the sentence on screen |
| which form rule broke | the message, and in which language |
| the single-instance verdict | run, focus the other one, or warn |
| that a new version exists | notify, download silently, or require it |

If at any point the framework seems to have decided for you, that is a bug —
open an issue instead of working around it.

---

## The shortest path that works

```yaml
dependencies:
  dovetail: ^0.1.0
```

```dart
import 'package:dovetail/dovetail.dart';
```

One import brings the window, the tray, the anchored panel, single instance,
deep links, notifications, the global shortcut, the updater, form validation
and the process runner. What does **not** come in is `dovetail_bundler`,
`dovetail_signer` and `dovetail_cli`: packaging and signing happen on the
release machine, and dragging them in here would put a code-signing toolchain
inside every user build.

Then let the CLI read the project:

```bash
dart pub global activate dovetail_cli
dovetail init
```

`init` reads the project and writes `dovetail.yaml` — identifier, name,
targets, update key.

---

## The boot, and why the order matters

```dart
Future<void> main() async {
  // 1. Before anything expensive. A second instance finds out it is second
  //    BEFORE opening a window, loading a core or touching the disk.
  final SingleInstanceVerdict verdict =
      await DesktopPlatformChannel.claimSingleInstance('com.example.app');
  if (!verdict.mayRun) {
    // Say why you are leaving. A silent `return` here is an app that "does
    // not open" with exit 0 and not one line of log — and the most common
    // cause is another live instance that received this launch (arguments
    // and deep links included). Whoever debugs it needs to read this in the
    // terminal.
    stderr.writeln(
      'another instance is already running; this launch was forwarded to it.',
    );
    return;
  }

  // 2. The window and the rest of the OS.
  final DesktopPlatform platform =
      await DesktopPlatformChannel.ensureInitialized(
    const DesktopAppSpec(
      window: WindowSpec(size: Size(1200, 720), minimumSize: Size(1024, 640)),
      applicationId: 'com.example.app',
      displayName: 'Example',
      notificationGuid: '00000000-0000-0000-0000-000000000000',
    ),
  );

  // 3. The Rust core, which is expensive and can fail.
  await DesktopCoreBridge.ensureInitialized();
  final core = await RustCore.start();

  runApp(App(platform: platform, core: core));
}
```

Step 1's `stderr` comes from `dart:io`, and `Size` and `runApp` from
`package:flutter/material.dart` — the snippet shows only the body of `main`,
and dovetail's only import is the one from the previous section.

None of the numbers above are package defaults. `1200x720` and the name come
from the app, because window size and name are a product decision — and under
white-labelling, a reseller's.

**Step 3 can fail, and failing is a state of the interface.** An app that
hangs on the splash screen because the core did not come up is worse than one
that shows the reason and a retry button.

---

## Text

Strings live in `lib/l10n/app_{pt,en,es}.arb`. In the migration measured here
there were 818 keys, imported from the React frontend by
`tool/import_locales.dart`. The generated `AppL10n` comes out of `flutter pub
get` — the generated Dart **is not committed**, because keeping ten thousand
lines in the diff over one word does not pay.

In `MaterialApp`:

```dart
MaterialApp(
  localizationsDelegates: AppL10n.localizationsDelegates,
  supportedLocales: AppL10n.supportedLocales,
  home: const HomePage(),
)
```

In the screen:

```dart
final AppL10n t = AppL10n.of(context);
Text(t.homeConnect);                    // "Connect"
Text(t.homeExpiryTitle(days));          // "Your plan expires in 3 day(s)"
```

**To add a key**, write it in all the `.arb` files — the template is the
language the sentences were written in. `flutter test test/l10n` refuses when a
key exists in one language and not another, or when its arguments change
between languages: both errors compile without complaint and show up as the
wrong language on the screen of someone who asked for another.

---

## Forms

```dart
final ValidationComposite rules = ValidationComposite(<FieldValidation>[
  ...Field('email').email().rules,
  ...Field('password').min(8).rules,
  ...Field('passwordConfirmation').sameAs('password').rules,
]);

final ValidationFailure? error = rules.validate(<String, String?>{
  'email': emailController.text,
  'password': passwordController.text,
  'passwordConfirmation': confirmationController.text,
});
```

The failure says **which rule broke**, not the sentence. The screen turns it
into text with an exhaustive `switch` — with no `default`, so that adding a
rule breaks at compile time instead of becoming empty text in front of
someone. `dovetail_form_validation`'s README carries the whole `switch`, with
the `l10n` keys checked against the `.arb`.

---

## The bridge to the Rust core

```dart
final session = await core.login(username: 'user', password: 'secret');

core.stateChanges().listen((TunnelStateChange change) => setState(...));

await core.connect(
  request: ConnectRequest(
    serverId: (await core.listServers()).first.id,
    splitTunnel: SplitTunnelRule(
      mode: SplitTunnelMode.everything,
      values: const <String>[],
    ),
    killSwitch: true,
  ),
);
```

**The error arrives typed.** There is no text prefix to search for:

```dart
try {
  await core.listServers();
} on CoreFailure catch (failure) {
  switch (failure.kind) {
    case CoreFailureKind.tooManyRequests:  // wait and retry
    case CoreFailureKind.transport:        // never reached the backend
    case CoreFailureKind.unauthorized:     // the session died
    // ...
  }
}
```

In the product measured here, 50 of the core handle's 51 public methods cross
over to Dart — the only one left out is the constructor, and a test pins that:
the core growing while the bridge stays quiet is the one direction the
compiler does not catch.

The bridge **decides nothing**: it does not validate, does not orchestrate,
does not hold flow state, does not know in what order the screens happen. Each
method is a forwarder and each type is a mirror.

### If you are going to touch the Rust, leave this running

```bash
flutter_rust_bridge_codegen generate --watch
```

The Dart under `lib/src/rust/` is generated. Without the watcher, the cliff is
this: you add `pub fn new_thing()` under `rust/src/api/`, `cargo check`
passes, the app compiles, the tests pass — **and the method does not exist on
the Dart side**. There is no error anywhere. You will go looking for why
`core.newThing()` does not exist, and the answer is "run the codegen".

That was measured, not assumed. `dart tool/verify.dart frb` is the net: it
generates, compares, restores the tree and names the command.

And hot reload crosses the bridge — 48 ms, restart in 352 ms — but **only the
Dart**. A change in Rust asks for a rebuild, and that is FFI, not
configuration.

---

## Global shortcut

```dart
final List<ShortcutOutcome> outcomes = await surface.bind(<ShortcutRequest>[
  ShortcutRequest(
    name: 'toggle',
    chord: ShortcutChord.parse('CommandOrControl+Shift+V'),
  ),
]);

for (final ShortcutOutcome outcome in outcomes) {
  switch (outcome) {
    case ShortcutBound():
      break;
    case ShortcutRefused(:final ShortcutRefusal reason, :final String detail):
      // `reason` is an enum — sessionUnsupported, takenBySystem, alreadyBound…
      // `detail` is the sentence naming the concrete case.
      showWarning(reason, detail);
  }
}

surface.presses().listen((ShortcutPress press) {
  if (press.pressed) toggleWindow(press.name);
});
```

**A refusal is data, not an exception.** On Wayland the package reports
`ShortcutBackend.waylandPortal` with `available: false` and **names the
session** — because a shortcut that reports success and never fires costs more
than one that says no. On macOS the backend is the deprecated Carbon API on
purpose: it asks for no privacy permission at all, while `CGEventTap` would
require asking, in a VPN client, for a keylogger's permission.

---

## Updating

```dart
final UpdateFlow flow = UpdateFlow(
  fetcher: HttpArtifactFetcher(),
  publicKey: release.publicKey,
  platformKey: PlatformKey.current().wireName,
);

final UpdateCheck check = await flow.check(
  endpoints: <String>[release.endpoint],
  installed: Version.parse(release.version),
);

if (check.shouldUpdate) {
  final VerifiedArtifact artefact = await flow.download(check.manifest!);
  final InstallOutcome outcome = await InstallerForHost.resolve(
    runner: const SystemProcessRunner(),
    installedPath: Platform.resolvedExecutable,
  ).install(artefact);

  // The two outcomes are different, and confusing them leaves the user
  // looking at a window that is no longer the app they installed.
  switch (outcome) {
    case InstallOutcome.installedRestartNeeded:  // swap when they let you
    case InstallOutcome.installerLaunchedAppMustExit:  // exit now
  }
}
```

`download` only returns a `VerifiedArtifact` after the minisign signature
passes, the trusted comment matches and a downgrade is refused. An endpoint
that is not `https` is refused before anything else: **the manifest is not
signed**, so its integrity rests entirely on the transport.

Before trusting an endpoint, ask it:

```bash
dovetail probe --url https://api.example.com/manifest/darwin \
  --public-key keys/update.pub --installed 1.0.0 --download
```

`probe` uses the **same** parser, the same policy and the same verifier the app
loads. Green is not an opinion about the format: it is the client saying yes.

The key the app trusts and the endpoint it queries are not your constants: read
them with `String.fromEnvironment('dovetail.update.public_key')` and
`'dovetail.update.endpoint'`, with the product's defaults as `defaultValue`.
`dovetail build` embeds what `dovetail.yaml` declares, so the same file that
signs the release decides who the app trusts — and a staging build points at a
staging host without touching the app. `flutter run` without dovetail keeps the
defaults.

Against an endpoint that does not answer it gives up after 15 s and says so,
instead of waiting for whatever the system waits; `--timeout <s>` changes the
deadline, and `0` returns the system's wait.

---

## Publishing

```bash
dovetail ship            # the whole pipeline, from dovetail.yaml
dovetail ship --dry-run  # prints the steps and runs none
```

`ship` assembles the pipeline as **data** and prints it before running.
Measured on one machine: an 82.9 MB `.app` → a 33 MB dmg → a signed manifest
that the reference `minisign` accepts.

Without `APPLE_SIGNING_IDENTITY` the signing step **says the artefact is left
unsigned** and carries on, instead of pretending.

---

## Where dovetail will tell you no

Worth knowing before you hit it:

- **An `http` endpoint.** Refused, with the reason written out.
- **A signature in the manifest as a path or a URL.** Refused: it would be
  silently unverifiable.
- **A downgrade.** An error, not the client's choice. Allowing it means asking
  on purpose.
- **A `.app` with no `LSMinimumSystemVersion`.** The dmg refuses: without the
  key, an old Mac opens the app and dies on a missing symbol.
- **A development key with a production address.** Refused — it is the
  combination that produces a publishable, useless artefact.
- **A shortcut on Wayland.** Refused with the session named, instead of
  accepted and mute.
- **Two releases for the same platform in one manifest.** Refused, instead of
  the second silently replacing the first.
- **`dovetail keygen` over an existing pair.** Refused, because the recovery is
  reinstalling on every machine.

---

## What does not exist yet

- **Running on Windows and on Linux.** The C++ single-instance guard compiles
  under mingw and the symbols match what `dart:ffi` looks for; Linux's
  `XGrabKey` has never executed. Compiling is not working.
- **An update installer on Linux.** It exists for macOS and Windows. On Linux
  the update is the distribution's package manager — that is a decision, not a
  gap.
- **Swift Package Manager in the Rust plugins.** Solved: a prebuilt
  XCFramework as a `binaryTarget` (`tool/build_xcframework.sh`); the podspec
  stays as the CocoaPods fallback.
- **Native file dialog and clipboard on desktop.** Measured on pub.dev (June
  2026). `file_selector` (flutter.dev) covers Linux, macOS and Windows.
  `super_clipboard` (nativeshell.dev, Rust underneath) covers Linux, macOS and
  Windows. `pasteboard` is a simpler alternative with the same coverage. This
  is not a gap: dovetail does not need its own plugin for it — depend on those
  packages when the desktop UI needs a file picker or clipboard access.

---

## When something does not match this document

It was written checking every name against the code, and every number against
a measurement. If it diverges, **the code is right and this file is old** — and
fixing the file is worth more than working around it.
