**English** · [Português](README.pt-BR.md)

# dovetail_bundler

> Packages a Flutter desktop app with a Rust core, calling each platform's own
> tool. In place of Tauri's bundler.

Tauri's bundler does not package: it **orchestrates other people's tools**. It
calls `makensis` on Windows, WiX for MSI, `hdiutil` on macOS, `linuxdeploy` for
AppImage — and for `.deb`/`.rpm` it calls nothing at all, having reimplemented
them in Rust because they are `ar` + `tar` + `md5`. This package does the same,
in Dart.

Why Dart: it is the team's language from here on, the `cargokit` already used
to compile the Rust is exactly this, and — the deciding reason — **Tauri's
failure modes are logic failures, not tool failures**. Wrong order for
`!addplugindir`, a warning where it should have been an error, a missing
timestamp. That is what tests catch; three divergent shell scripts have no
tests.

## State

| Target | Situation | What is proven here |
|---|---|---|
| Windows, NSIS | **built here**, with a caveat | script order, escaping, staging, invocation. Compiles on macOS with `unicode: false`; the Unicode stub blows up with `std::bad_alloc` on arm64 |
| Windows, MSI | **built here** | two backends: `wix` on Windows, `wixl` on any other host. The generated `.wxs` is validated by `xmllint`, the GUID has a golden test, and the produced MSI is checked with `msiinfo` and `msiextract` |
| macOS, `.dmg` | written | refuses a `.app` that does not carry the promised architectures, before `hdiutil` |
| macOS, `.app.tar.gz` | written | the signed bundle at the root of the tar, with no `._*` entries (`COPYFILE_DISABLE`); it is what the updater extracts and the manifest publishes — `bundle --macos-format tar` |
| macOS, universal `.app` | written | `UniversalBundle` merges two single-architecture builds, proven with real `rustc` and `lipo` |
| Linux, `.deb` | written | read back by the system's `ar` and `tar`, with file modes and maintenance scripts |
| Linux, `.rpm` | written | spec and scriptlets; the local `rpmbuild` only knows `aarch64` |
| Icons | written | the `.icns` taken apart by Apple's `iconutil`, the `.ico` read by `file` |

Test counts are not written here, because they age. `dart test` says.

## Tauri's traps, which are a fatal error here

A survey of Tauri as prior art found around thirty warnings they had paid for.
Three became tests:

**`!addplugindir` before any `!include`.** Anywhere but the absolute top,
`makensis` silently falls back to the toolset's **unsigned** DLLs, even though
the signing step passed. That was a production bug there. A test compares the
`!addplugindir` line against the first `!include`.

**Non-numeric build metadata is an error, not a silent zero.** Tauri replaces
`1.2.3+abc` with `0` in `VIProductVersion` with a warning and carries on.
`AppVersion.parse` refuses, and the message says what to do.

**`DovetailStrContains` exists twice, and it has to.** NSIS refuses a `Call` in
an uninstall section unless the function is named `un.something` — so the body
is instantiated with and without the prefix, and `CheckIfAppIsRunning` is told
which to use. Without that the generated script **did not compile on any
host**, Windows included; the Unicode stub blowing up on arm64 hid the real
error behind an earlier crash.

**The Unicode stub does not compile on Apple silicon.** `makensis` 3.12 blows
up with `std::bad_alloc` while writing its output, on a four-line script, and
building from source does not change it. With `unicode: false` it compiles, at
the real cost of an ANSI installer: paths and strings are read in the system's
code page, and a machine whose install path falls outside it installs in the
wrong place. The alternative with no caveat is the MSI, which `wixl` builds on
any host.

**`CheckIfAppIsRunning` immediately after `NSIS_HOOK_PREINSTALL`.** That order
was fixed after a bug reported twice in Tauri. A test requires that only the
`!endif` sits between the two lines.

## An existing `hooks.nsh` passes through untouched

The four hooks have the same names and positions as Tauri's template —
`NSIS_HOOK_PREINSTALL`, `POSTINSTALL`, `PREUNINSTALL`, `POSTUNINSTALL`, all
guarded by `!ifmacrodef`. In the migration measured here, 280 lines of an
existing `installer/hooks.nsh`, which install and register a privileged
service, went in unchanged.

And there is no dependency on Tauri's plugin: **it was measured that that hook
uses only `nsExec` and `taskkill`**, both native. The `CheckIfAppIsRunning`
macro here is implemented with `nsExec` + `tasklist`, without
`nsis_tauri_utils.dll`.

## Usage

```bash
dart run dovetail_bundler \
  --product-name "Example" \
  --manufacturer "Example Ltd" \
  --identifier com.example.app \
  --version 1.2.3+47 \
  --main-binary example \
  --app-dir build/windows/x64/runner/Release \
  --out-dir dist \
  --hooks installer/hooks.nsh
```

It writes the installer's path to standard output. It fails with code 1 and a
message that carries the remedy.

## The dmg refuses a `.app` that does not say which macOS it needs

`LSMinimumSystemVersion` is the only thing that stops an old Mac from opening a
binary it cannot run. Without the key the app opens and dies on a missing
symbol, which reaches us as *"it just closes"* and reaches the user as nothing.

Before `hdiutil`, not after — a dmg that exists is a dmg somebody uploads.
Three refusals: a bundle with no key; a bundle whose key carries
`$(MACOSX_DEPLOYMENT_TARGET)` **unexpanded**, which macOS reads as no version
at all; and a bundle that disagrees with what the release declares, saying
which of the two the system obeys.

Xcode fills the key in from `MACOSX_DEPLOYMENT_TARGET`, so a correct project
already has one — this exists for the day someone edits the template.

## What is not proven here

**That `makensis` accepts the generated script.** The structure is tested, but
NSIS validity is only proven by compiling — and Homebrew's `makensis` 3.12 on
arm64 macOS **aborts with `std::bad_alloc` even on a minimal four-line
script**. The test probes usability, not presence: if the local `makensis`
cannot compile a trivial script, it is marked as skipped with that reason
rather than giving a false green.

That proof belongs to a Windows runner, which is where the installer matters.

## Signing

It is not here, on purpose. Signing is a step **after** the build, never inside
it — the inverse coupling is what ties an installer to `cargo tauri build`
today. With no secret, an unsigned artefact and a warning; with
`--require-signature`, which only the pipeline passes, the same warning becomes
an error.
