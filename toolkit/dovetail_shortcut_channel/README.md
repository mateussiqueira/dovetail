# dovetail_shortcut_channel

Binds a keyboard chord the operating system delivers to the app **even when no
window of the app has focus**, and refuses out loud in every session where no
such chord can be granted.

Nothing here knows what a VPN is. The app decides which chord to offer and what
a press means; this package binds it, or says why it cannot.

## What it runs on

| Session | Mechanism | Who picks the chord | Asks permission |
| --- | --- | --- | --- |
| Windows | `RegisterHotKey` | the app | no |
| macOS | Carbon `RegisterEventHotKey` | the app | no |
| Linux, X11 | `XGrabKey` on the root window | the app | no |
| Linux, Wayland | *refused* | — | — |

The three that work go through the [`global-hotkey`][crate] crate — the same
crate the Tauri build already uses, so the behaviour of the installed park does
not change when the UI does.

macOS deliberately uses the deprecated Carbon API rather than `CGEventTap` or
`NSEvent.addGlobalMonitorForEvents`. Carbon asks for no privacy permission: the
app says *wake me on this chord* and never sees another keystroke. The two
modern paths require Input Monitoring or Accessibility, which in a VPN client
means asking the user for a keylogger's permission. That trade is not worth
making.

## Wayland is refused, not faked

A Wayland compositor grants a system-wide shortcut only through
`org.freedesktop.portal.GlobalShortcuts`, where the **compositor owns the
chord** — the app sends a preferred trigger and the user confirms or changes it
in a system dialog. That portal is implemented by Plasma and by GNOME from 48;
sway, river, niri and every other wlroots compositor have no implementation at
all, and Hyprland accepts the bind while ignoring the preferred trigger, which
is the worst outcome available: a success the user cannot press.

So this package reports `ShortcutBackend.waylandPortal` with `available: false`
and the session named in the refusal. A shortcut that reports success and never
fires costs more than one that says no.

Speaking that portal is a decision with a real bill attached: it is our code
forever (the crate declares Linux X11 only and has no Wayland plan), it changes
with each portal version, and none of it can be tested without at least a Plasma
VM, a GNOME VM and a sway session. It is a seam, not a gap.

## The trap the probe exists for

Under XWayland a `DISPLAY` is set, so a naive probe reads the session as X11 and
calls `XGrabKey` — which succeeds and never fires, because the grab never sees
the compositor's keys. `XDG_SESSION_TYPE` therefore beats a present `DISPLAY`,
and the probe reads an injected environment so that rule is testable rather
than asserted.

## The policy, and why it is here

`ShortcutPolicy` refuses a chord before the backend sees it:

- **No primary modifier** — a chord without Control, Command or Meta is one
  keystroke away from every other application on the machine.
- **F12** — reserved for the debugger on Windows. A chord that works on two
  platforms out of three is a support call.
- **The Windows key, on Windows** — the OS reserves those; `RegisterHotKey`
  refuses them.
- **Option-only and Option+Shift, on macOS** — macOS 15.0 stopped delivering
  these to sandboxed apps, and it did so with no error at the call site.

This is format and mechanics, not business rule: the package refuses the
improper chord, the app decides which chord to offer.

## Building and proving it

```bash
cd rust && cargo test && cargo build --release --features test-probe
flutter test
```

`cargo build --release` is what lets `flutter test` drive the real registry —
the suite loads the built library and binds real chords through the real
platform API. Without it the native suite skips itself and says so instead of
passing vacuously.

`--features test-probe` is what lets the suite deliver a press. The function
it adds, `dovetail_shortcut_emit_probe`, lets any process holding the library
synthesise a shortcut press, so it is off by default and no shipped build
carries it — measured with `nm`, not assumed. A suite run against a build
without it passes and skips the three tests that drive the pump, naming the
feature they need.

In an app build, cargokit drives cargo from `flutter build`, and the Rust
library must stay named after the plugin: the loader searches by stem, so a
rename produces a `dlopen` failure naming the two names it is built under on
macOS — `dovetail_shortcut_channel.framework/dovetail_shortcut_channel` and
`libdesktop_shortcut_channel.dylib` — and neither of them mentions the rename.

## What is not proven here

The macOS path is exercised on this machine: the registry opens, real chords
bind, and a press crosses an OS thread into the Dart isolate. Everything else
is read from the platform documentation and from the crate:

- **Windows** — `RegisterHotKey`, `MOD_NOREPEAT`, `WM_HOTKEY` arriving on the
  pump thread, and the already-taken-by-another-app refusal.
- **X11** — `XGrabKey`, conflicts with the window manager, other keyboard
  layouts.
- **Wayland** — the whole portal path, deliberately absent.

[crate]: https://crates.io/crates/global-hotkey
