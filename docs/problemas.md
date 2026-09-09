**English** · [Português](pt-BR/problemas.md)

# When something goes wrong

Every item here actually happened in this project, and it is written by **the
message you will see** — not by the cause, which is the part you do not know
yet.

---

## I wrote a Rust method and it does not exist in Dart

No message at all. `cargo check` passes, the app compiles, the tests pass, and
`core.newThing()` simply does not exist.

The Dart under `core_bridge/lib/src/rust/` is **generated**, and nothing warns
you when it has fallen behind.

```bash
make codegen          # regenerates the bridge from the Rust
```

To stop falling into it again, leave the watcher running while you touch Rust:

```bash
dovetail dev          # regenerates on every saved .rs; --check only verifies and exits
```

And the net that catches this without anyone remembering: `make tests` also
runs `core_bridge/test/core_coverage_test.dart`, which compares the core's
public methods against the ones that reached Dart and fails naming what is
missing.

---

## An error about a content hash, or a bridge that worked and stopped

If the message mentions a *content hash* or a codegen version, the CLI that
generated the code and the runtime executing it are different versions. The
CLI is global, the runtime is pinned in `Cargo.toml`, and nothing was keeping
them together.

```bash
flutter_rust_bridge_codegen --version                  # the generating CLI
grep flutter_rust_bridge core_bridge/rust/Cargo.toml   # the pinned runtime
cargo install flutter_rust_bridge_codegen --version <the one from Cargo.toml>
```

*(In the dovetail monorepo, `dart tool/verify.dart frb` makes that comparison
and says which one is out — but that command only exists there.)*

Fix the tool, **not the pin**. And if you regenerated with the wrong CLI and
committed it, the code breaks on everyone else's machine — not on yours.

---

## `Failed to load dynamic library`, with ten paths listed

```
Invalid argument(s): Failed to lookup symbol ...
dlopen(core_bridge.framework/core_bridge, 0x0001): tried: ...
```

The loader looks for the framework by the **crate name's stem**. A crate named
differently from the plugin produces a loader looking for a framework that does
not exist: the symbols end up linked and **unreachable**, which is why the list
of paths looks entirely wrong.

The crate name in `core_bridge/rust/Cargo.toml` has to be the plugin's name —
`dovetail new` already leaves them identical, and it is renaming one of the two
by hand that lands you here. The rule and the reasoning are in the generated
bridge's README.

---

## `MissingPluginException` when bringing up the platform channel

```
MissingPluginException(No implementation found for method ensureInitialized
on channel window_manager)
```

Two cases, with the same face.

**In `flutter test`, on any system.** There is no native side in a widget
test, so the first call to `DesktopPlatformChannel.ensureInitialized` — which
goes to `window_manager` — finds nobody. This is not a defect: it is a test
that wants the real window. Whoever tests code that depends on the channel
injects the double (`DesktopPlatform` is an interface) instead of calling
`ensureInitialized`; and dovetail now rethrows that error naming the channel
and saying this, rather than letting `window_manager`'s raw text reach someone
who does not know what it is.

**Running the app, on one system only.** Then a plugin somewhere in the
dependency tree has no implementation for that desktop. dovetail itself only
depends on plugins that have all three; what usually drags in one that does not
is a dependency of **your** app — a UI package exporting a camera widget, for
instance. The path is the `pubspec.lock`: find the plugin the message names and
see who brought it in. The fix is not in dovetail.

*(In the dovetail monorepo, `dart tool/verify.dart cross` lists every plugin
missing an implementation on any of the three desktops — but that command only
exists there.)*

---

## The app opens on an old Mac and dies saying nothing

Symptom: the window flashes, or the app closes, or it complains about a missing
symbol.

`LSMinimumSystemVersion` is the only thing that stops the system from opening a
binary it cannot run. Without the key, macOS tries.

`dovetail bundle` refuses a `.app` that does not declare it, refuses one left
as `$(MACOSX_DEPLOYMENT_TARGET)` **unexpanded** (which macOS reads as no
version at all), and refuses one that disagrees with what the release declares.

**Coming from Tauri, check the number.** The Flutter template writes `10.15`
and nobody chose it; `tauri.conf.json` may declare a different one, chosen on
purpose — in the product measured here, `13.0`, because the helper's
installation path on macOS goes through `SMAppService`, which exists from 13
onwards.

---

## `signtool` signed the installer and Windows complains about the binaries

The installer passes, and the executables it drops have no signature.

That was a pipeline defect and it is fixed: on Windows, `ship` signs **twice** —
`sign --directory` over the payload **before** `bundle`, and `sign --file` over
the installer afterwards. Signing by hand, the order is yours:

```bash
dovetail sign --target windows --directory build/windows/x64/runner/Release
dovetail bundle --target windows ...
dovetail sign --target windows --file dist/app_1.0.0_x64_setup.exe
```

---

## `pkexec` exited with 126 or 127

126 is the authorisation dialog being **dismissed**. 127 is the dialog that
**could not be shown** — which happens over ssh with no session bus.

In both cases nothing was replaced, and `LinuxInstaller`'s message says which
of the two it was.

---

## `dovetail bundle --linux-format appimage` was refused

```
this project declares a service (demo-helper.service), and an AppImage
cannot install one.
```

An AppImage runs from a file instead of installing: no systemd unit, no
privileged helper, no kill switch. The three routes to privilege are **closed,
not hard** — `fusermount` forces `nosuid` on the mount,
`--appimage-extract-and-run` cannot `chown` to root, and asking for a password
at runtime is refused by the product itself.

Build `.deb` and `.rpm`, whose `postinst` and `%post` install the unit and the
policy. If your product genuinely has no privileged service, remove the
`service` section from `dovetail.yaml`.

---

## `makensis` aborts with `std::bad_alloc`

```
libc++abi: terminating due to uncaught exception of type std::bad_alloc
```

On this machine, the Homebrew arm64 build aborts **even on a four-line
script**. It is not the generated script. That proof belongs to a Windows
runner, and the test that depends on it skips with exactly that reason written
out.

---

## The client refuses the release, and the signature is correct

The manifest's `signature` field carries **base64 on top of the minisign
text**, never the raw text. A client in the field decodes before parsing and
has no fallback — so the raw form decodes to nothing, and it finds that out on
a machine you cannot see.

`ManifestWriter` is what decides that encoding, and it accepts both forms on
input precisely so that the caller does not need to know. To check from
outside:

```bash
dovetail probe --url <manifest> --public-key keys/update.pub
```

It decodes base64 **first, with no fallback**, exactly as the client does.

---

## The endpoint returns 500 for `darwin` and 200 for `macos`

Two words for the same thing. The app asks for the platform by the name Rust
uses — `darwin` — and the backend's table keeps the row under `macos`; the raw
value reaches Postgres, which refuses anything outside the enum.

It is a vocabulary disagreement, not missing functionality, and the fix is on
the server: accept both spellings and answer **404** for what it does not
know, which is the honest answer for a platform that does not exist.

---

## minisign says `Wrong password`, and the password is right

Check whether the key really is password-protected. Calling a key that has a
password `--unencrypted-key` fails loudly in real `minisign` — and so does the
opposite.

An unexported password variable is **a refusal naming that variable**, never an
assumed empty password.

---

## The global shortcut reports success and never fires

You are on Wayland. A Wayland compositor only grants a system shortcut through
the `org.freedesktop.GlobalShortcuts` portal, where **the compositor owns the
chord** — and under XWayland a `DISPLAY` exists, so a naive probe reads the
session as X11 and calls `XGrabKey`, which **succeeds and never fires**.

`dovetail_shortcut_channel` refuses for that reason, reporting
`ShortcutBackend.waylandPortal` with `available: false` and **naming the
session**. `XDG_SESSION_TYPE` beats a present `DISPLAY`, and the probe reads
the injected environment so that this rule is testable rather than asserted.

---

## `flutter --version` says `0.0.0-unknown`

The SDK's `bin/cache/flutter.version.json` points at a revision that is not in
its git history. It happened on this machine.

Delete the cache and let Flutter regenerate it:

```bash
mv "$(dirname "$(which flutter)")/cache/flutter.version.json" /tmp/
flutter --version
```

---

## The gate says `UNTRACKED` about a test file

*(dovetail monorepo: the gate is `dart tool/verify.dart`, which a generated
project does not have.)*

```
UNTRACKED toolkit/some_package/test/something_test.dart — it counts here
and exists nowhere else. git add it, or delete it.
```

The suite counts in the run and does not exist in git, so the local count
corresponds to no clone. It is `git add` or `git rm` — and this has already
caught a real case of `.gitignore` swallowing a test file, through a pattern
(`**/probe_test.dart`) that existed for temporary probing.

---

## `Developer ID signing identity has no credentials and a signature was required`

`dovetail.yaml` has `sign.macos.notarize: true` and no identity is exported —
neither the variable named by `identity-env` nor `APPLE_SIGNING_IDENTITY`.
`notarize: true` is declaring a real release, and going unsigned then is an
error. `ship --dry-run` and `doctor` say so **before** the build; if you
reached this message after a build, you ran `sign` by hand.

Export the identity (`Developer ID Application: …`) in the variable the config
names, or set `notarize: false` for a local build with no signature. The remedy
the message suggests, dropping `--require-signature`, applies to a standalone
`sign`; in `ship` the flag comes from `notarize`.

---

## `macos signs --bundle or --file in one call, not both`

They are two seals, in two steps: the `.app` with `--bundle` (inside out, with
the hardened runtime and entitlements) and the `.dmg` with `--file` (a flat
file, signed after being built, and it is the one you notarise). `ship` runs
both in that order; by hand, it is two calls.

---

## `missing  update  update.public-key is not declared`

`doctor` is telling you what `ship` will refuse at the last step: the public
key the app embeds is not in `dovetail.yaml`, and without it a release signed
by any other key would be published with nothing complaining. `dovetail keygen`
prints the line ready to paste; if the pair already exists, it is the contents
of the `.pub`, as a block:

```yaml
update:
  public-key: |
    untrusted comment: minisign public key 1234567890ABCDEF
    RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
```

---

## The app was closing on its own, with no log

This was a defect and it is fixed, but the shape is worth knowing: a poisoned
`Mutex` in `PumpTable` called `.expect(...)`, and that table is reached by the
bridge's **synchronous** methods, which do not go through the runtime that
catches panics. A panic there crosses the FFI and **aborts the process** — no
message, no log, no error screen.

If you write new code reached by a `#[frb(sync)]` method, this is the rule:
**no `unwrap`, `expect`, `panic!` or indexing**. The async side is covered by
`support::run`; the synchronous side is covered by nothing.
