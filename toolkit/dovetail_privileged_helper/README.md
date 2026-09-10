**English** · [Português](README.pt-BR.md)

# dovetail_privileged_helper

Installs, reports and removes the privileged component a sandboxed Flutter
desktop app **cannot be**: a launch daemon on macOS, a service on Windows, a
systemd unit on Linux.

It answers with a **state**, never with a bool. That is the whole point.

## The bool that hides three different problems

A VPN client cannot open a tunnel from its GUI process. It needs something
running as root, and *installing that something is an operating-system
permission flow* — not a file copy. Most apps model it as
`isHelperInstalled() -> bool`, and that single bit collapses three situations
that need **opposite** actions from the user:

| What is actually true | What the person must do | What a bool says |
| --- | --- | --- |
| never registered | install it — this will ask for an admin password | `false` |
| registered, waiting for approval in System Settings | **go to Settings and flip the switch**; installing again does nothing | `false` |
| blocked by policy (MDM) | nothing will ever work; ask the administrator | `false` |

An app built on the bool shows one button — *Repair* — for all three. It fixes
the first, is a no-op for the second, and fails forever for the third, and the
person on the other side has no way to tell which one they are in.

```dart
enum HelperState { unsupported, notRegistered, requiresApproval, enabled, blockedByPolicy, failed }
```

The shape is not invented here. macOS 13's `SMAppService.status` reports
exactly `notRegistered`, `enabled`, `requiresApproval` and `notFound`; this
enum mirrors what the platform already says, so nothing is guessed in Dart.

## What it runs on

| Platform | Mechanism | Asks the user | Approval pane |
| --- | --- | --- | --- |
| macOS 13+ | `SMAppService.daemon` | admin password, then an approval switch | Login Items & Extensions |
| macOS < 13 | *unsupported* | — | — |
| Windows | service control manager | UAC elevation | none — UAC is the whole flow |
| Linux | systemd + polkit | polkit prompt | none — polkit has no persistent pane |

`requiresApproval` is a macOS 13 invention and it is the state everyone misses:
the daemon **is** registered, the install succeeded, and it still will not run
until the person finds it in *System Settings → General → Login Items &
Extensions* and turns it on. `openApprovalSettings()` takes them there, and
returns `ApprovalPaneOutcome.absent` on the platforms that have no such pane
rather than pretending it opened one.

## Using it

```dart
final PrivilegedHelper helper = PrivilegedHelpers.of(
  const HelperSpec(
    macOSDaemonPlist: 'io.example.app.helper.plist',
    windowsServiceName: 'ExampleAppHelper',
    linuxUnitName: 'example-app-helper.service',
  ),
);

final HelperStatus status = await helper.status();

switch (status.state) {
  case HelperState.enabled:
    break;
  case HelperState.notRegistered:
    await helper.register();
  case HelperState.requiresApproval:
    await helper.openApprovalSettings();
  case HelperState.blockedByPolicy:
  case HelperState.unsupported:
  case HelperState.failed:
    break;
}
```

`register()` returns the state **after** it ran, not a bool for whether the
call threw. On macOS a successful registration commonly lands in
`requiresApproval`, and a caller that treated the absence of an exception as
success would tell the user they were protected when nothing is running yet.

## Re-read it when your window comes back

The person grants this **outside your app**. They leave, flip a switch in
System Settings, and come back — and an app that read the state once at launch
will still be showing `requiresApproval` until it is restarted.

`HelperWatch` re-reads on a signal you provide; wire it to your window's focus
event. `dovetail_platform_channel` owns the window and exposes one.

## What is not here

**The Network Extension.** On macOS there are two ways to be a system-wide VPN
and this package implements one of them. `HelperSpec.macOSRoute` exists so the
other can arrive without breaking a single caller — see `ARCHITECTURE.md` for
what each route costs, because the choice belongs to the product, not to a
toolkit.

**The helper binary itself.** This package registers, reports and removes it.
What it does once running, how it is signed, and how it talks to the app are
the app's business.

## Status

Written on macOS arm64. The macOS path is exercised; the Windows and Linux
native sides are **written blind and have never been compiled** on their target
platforms — the same caveat the rest of this repository carries. If you run
this on Windows or Linux, an issue with the output is the most useful thing
this package can receive.

Part of [dovetail](https://github.com/mateussiqueira/dovetail). MIT.
