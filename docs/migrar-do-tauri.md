**English** · [Português](pt-BR/migrar-do-tauri.md)

# Migrating from Tauri to dovetail

Written while a real migration was happening, so every claim here comes from a
measurement on an actual product, not from reading documentation.

The summary: **the Rust core does not move.** What goes is the shell — the
webview, the `#[tauri::command]`s and `tauri.conf.json`. What arrives is
Flutter talking to the same Rust over FFI, and a CLI that does what Tauri's
pipeline did.

---

## What actually changes, and what only changes place

| in Tauri | in dovetail | is it the same? |
|---|---|---|
| `#[tauri::command]` + `invoke()` in JS | a Rust method plus a generated Dart method | **no**: it stops being JSON round-tripping and becomes a function call |
| webview + SPA | compiled Flutter | **no**: the screens are recreated, not ported |
| `tauri.conf.json` | `dovetail.yaml` | almost — see the map below |
| `tauri build` | `dovetail ship` | yes, and the plan is printable before running |
| `installer/hooks.nsh` | the same file, untouched | yes, on purpose |
| `tauri_plugin_updater` | `dovetail_updater` | **no**: see the updater section |
| `app.security.csp` | nothing | the webview is gone, and the CSP with it |

The core, the API client, the WireGuard engine, the IPC protocol and the
privileged helper **are not touched**. In the migration measured here, 61 Tauri
commands covered what are today 51 public methods on the core handle, and 50 of
them cross over to Dart — the only one left out is the constructor, because the
bridge owns the lifecycle.

---

## The `tauri.conf.json` map

This is a real product's file, key by key.

### Goes straight across

| `tauri.conf.json` | `dovetail.yaml` |
|---|---|
| `productName` | `name` |
| `identifier` | `identifier` |
| `version` | **does not exist** — it comes from `pubspec.yaml` |
| `bundle.targets` | `targets`, as system-architecture pairs |
| `bundle.macOS.entitlements` | `sign.macos.entitlements` |
| `bundle.macOS.minimumSystemVersion` | `MACOSX_DEPLOYMENT_TARGET`, in the Xcode project |
| `bundle.windows.nsis.installMode` | `InstallMode`, in `bundle` |
| `bundle.windows.nsis.installerHooks` | `--installer-hooks` |
| `bundle.windows.nsis.languages` | `--installer-language`, repeatable |
| `plugins.updater.endpoints` | `update.endpoint` — where the app asks for the manifest |
| *(no Tauri equivalent)* | `update.base-url` — the root the artefacts are downloaded from |
| `plugins.updater.pubkey` | `update.public-key` |

### Changes shape

**`bundle.targets` stops being a list of formats and becomes a list of
targets.** In Tauri, `["nsis","dmg","deb","rpm","appimage"]` says *what to
package*; in dovetail, `targets` says *who to publish for* — `darwin-aarch64`,
`windows-x86_64` — and the format comes from `bundle --linux-format` and
`--windows-format`. The reason is the updater: the manifest's key is
`system-architecture`, and a format that does not become a key is a release no
client ever asks for.

**`appimage` will probably leave the list.** `dovetail bundle` **refuses**
AppImage when `dovetail.yaml` declares a service, and a VPN product does: an
AppImage installs nothing, so there is no systemd unit, no privileged helper
and no kill switch. Tauri built the file anyway, and what came out was not a
degraded product — it was a window that cannot connect.

**`signingIdentity: "-"` becomes `APPLE_SIGNING_IDENTITY=-`** (or the variable
named by `identity-env`): `-` is an ad hoc signature and `sign` passes it to
`codesign` as-is — it is what `tool/ci/prove_update.sh` uses to simulate the
pipeline. With no identity exported at all, and `notarize: false`, the signing
step **says the artefact is left unsigned** and carries on; with
`notarize: true`, a missing identity is refused before the build.

**`build.beforeBuildCommand` disappears.** That script compiled the helper and
the frontend. The frontend stops existing, and building the helper is the
product's step — not the bundler's.

### Has nowhere to go

- `build.frontendDist`, `build.devUrl`, `build.beforeDevCommand` — there is no
  web frontend.
- `app.security.csp` — the CSP was the webview's defence against the very HTML
  it rendered. With no webview, the whole class of concern goes away.
- `app.windows[]` — window size, title and decoration become a `WindowSpec`,
  in code, because under white-labelling they are a reseller's decision rather
  than a build's.

---

## The trap that is worth more than this whole document

That product's `tauri.conf.json` declares:

```json
"bundle": { "macOS": { "minimumSystemVersion": "13.0" } }
```

And a freshly created Flutter project declares:

```
MACOSX_DEPLOYMENT_TARGET = 10.15;
```

**This is not a build detail.** `10.15` is the Flutter template's default, and
nobody chose it. `13.0` *was* chosen: the helper's installation path on macOS
goes through `SMAppService`, which **exists from macOS 13 onwards** — it is
written in the core, as the phase's plan.

Leaving `10.15` means the app **opens** on a Mac running macOS 11 and the
helper **can never be installed there**. The user sees a window that will not
connect, and nothing explains why — the system did not refuse, because the app
said it was supported.

`dovetail bundle` refuses a `.app` that declares no minimum at all, and refuses
one that disagrees with what the release declares. It **does not** know which
number is right: that is the number the migration has to bring by hand.

> When migrating, copy `minimumSystemVersion` from `tauri.conf.json` into the
> Xcode project's `MACOSX_DEPLOYMENT_TARGET`, **before** the first release.

---

## The updater: read this before planning compatibility

The natural assumption is that there are installations in the field trusting
the minisign key baked into `tauri.conf.json`, and that the new pipeline has to
speak exactly the same language. **In this product, measured against
production, that was not the case** — and checking it cost three `curl`s and
two `grep`s:

- `tauri_plugin_updater` was registered in `main.rs` and **invoked nowhere**:
  zero calls in Rust, and the JS package was not even in the frontend's
  `package.json`.
- What the screen received was a notice with a link. The `sha256` the endpoint
  returned was consumed by nothing, and `mandatory` was hard-coded `false`.
- **There was no signature or hash verification on the live path.**

So **check before you assume**. If your project's plugin really is called,
compatibility is an obligation; if it is not, it is a choice — and you gain the
freedom to design the manifest, plus the riskiest item on the plan leaves the
list.

`dovetail_updater` keeps Tauri's double base64 layer because it costs nothing
and preserves the option. And it does three things Tauri's client does not: it
checks the trusted comment (which carries the file name and timestamp, and is
signed), it refuses a downgrade as an error rather than a client's choice, and
it names which platform block is broken.

Before trusting an endpoint, ask it:

```bash
dovetail probe --url https://api.example.com/manifest/darwin \
  --public-key keys/update.pub --installed 1.0.0 --download
```

---

## The 280 NSIS hooks come across untouched

That product's `installer/hooks.nsh` is 280 lines that install and register
the privileged service. dovetail's generator exposes **the four hooks with the
same names and the same positions** as Tauri's template, guarded by
`!ifmacrodef` — so the file goes in unchanged.

*It should*: `makensis` has never compiled the generated script with that file
included, on any host. On this machine it aborts with `std::bad_alloc` even on
a four-line script, so that proof belongs to a Windows runner. It is a known
gap, not a hidden assumption.

---

## The order worth doing it in

Doing B before A costs weeks of rework, and the reason is not taste: a screen
designed against a use case that does not exist is born wired to nothing.

1. **The bridge, and only the bridge.** One Rust method reaching Dart, with a
   test proving it crosses. Until that passes, nothing above it exists.
2. **The text catalogue.** It is the only thing from the old frontend that
   survives whole. Every screen written before it is born with a literal
   string inside, and rewriting later costs more than porting now. In the
   product measured here it was 819 keys × 3 languages, and the importer in
   `tool/import_locales.dart` refuses rather than guesses.
3. **The validation rules.** The other surviving piece: business rules, not
   visuals. Seven rules, in `dovetail_form_validation`.
4. **Session and authentication.** It decides whether a screen opens at all,
   so everything above depends on it.
5. **Each area's domain**, on top of a bridge that already answers.
6. **The navigation shell**, once there is something to navigate.
7. **The screens.** They are not ported, they are recreated.

From the old frontend, the text catalogue and the validation rules survive. The
other 92% is visual, and the visual is redesigned.

---

## What the migration gains, beyond leaving the webview

- **Hot reload over the Rust core**: 48 ms, restart in 352 ms, measured.
- **A typed error at the boundary.** The failure arrives with a `kind`, and the
  screen switches on it. There is no text prefix to search for.
- **A test that proves the bridge covers the core.** The compiler catches a
  bridge calling a method that does not exist; the direction nobody catches is
  the core growing while the bridge stays quiet, and there is a test for that.
- **A printable pipeline.** `dovetail ship --dry-run` shows the steps as data
  before running any of them.

And what it costs, said plainly: **the screens are recreated.** If your
project's value is in the HTML, this migration is very expensive. If it is in
the Rust core — as it was here — the webview was only the shell.

---

## What bites along the way

It is all in [problemas.md](problemas.md), with each one's error message. The
three that cost the most time:

1. **A Rust method invisible from Dart.** You write it, everything compiles,
   and it does not exist on the other side. The codegen has not run, and
   nothing says so.
2. **`dlopen` listing ten paths.** The crate's name has to match the plugin's
   name, or the symbols end up linked and unreachable.
3. **`MissingPluginException` on Windows only.** A dependency that exists on
   macOS and not on the other two, dragged in by a barrel.
