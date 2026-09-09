**English** · [Português](pt-BR/instalador.md)

# Installing dovetail: the SDK outside the monorepo

> **Context for anyone arriving through the public repository.** This document
> mentions `product/`, which is the private app where the toolkit is
> exercised, and it does not exist in this repository. The mechanism described
> belongs to the toolkit and holds for any app; only the example's path
> belongs to another tree.

The goal: a desktop app, on any machine, gets the pipeline, the runtime and
the bridge mechanism with one `curl` and one command — without cloning the
monorepo and without `path: ../../`.

Since the packages are on pub.dev, there is now a second route that is simpler
for most people: declare `dovetail: ^0.1.0` and activate `dovetail_cli`. The
signed channel described here is what gives you a self-contained AOT binary
and a versioned SDK on disk, which is what a release machine wants.

## The model

The same as rustup and the Flutter SDK: a single binary (the pipeline) that
installs, updates and controls everything else.

```
curl -fsSL https://<host>/install.sh | sh
  → ~/.dovetail/
      bin/dovetail          ← the pipeline (AOT, already exists)
      sdk/<version>/packages ← the runtime the app imports, versioned
      sdk/<version>/templates/bridge ← the template that generates the product bridge
  → ln -s ~/.dovetail/bin/dovetail ~/.local/bin/dovetail
```

`dovetail init` writes a `pubspec_overrides.yaml` in the app pointing at the
installed SDK — Dart's native mechanism for resolving outside the pubspec, the
same one the Flutter SDK uses to deliver its own packages. The app gets the
framework with one line and one command.

## What goes into the SDK, and what does not

| in | out |
|---|---|
| `dovetail_platform_channel`, `dovetail_shortcut_channel`, `dovetail_updater`, `dovetail_form_validation`, `dovetail_process_runner` — the barrel's runtime | `dovetail_bundler`, `dovetail_signer`, `dovetail_cli` — they live **only inside the binary** (the [barrel's](../toolkit/dovetail/README.md) decision) |
| `dovetail_rust_core` — the Dart↔Rust joint belongs to the framework, not to the monorepo | the product — the SDK knows about no product at all |

The product's bridge package is the **fixture** of the bridge mechanism: the
SDK template reproduces what it is, and Phase 4's acceptance criterion is that
`bridge init` generates something that passes `core_coverage_test` against the
same crate.

## The phases

Every phase has an executable acceptance criterion and only starts after the
previous one proves out. You can stop at any of them with value in hand.

1. **The layout and the release build.** `tool/build_sdk.sh` produces
   `dovetail-sdk-<version>-<os>-<arch>.tar.gz` (macOS/Linux/Windows ×
   arm64/x64) with `bin/`, `sdk/<version>/packages/` and
   `sdk/<version>/templates/bridge/`. Acceptance: the extracted tarball runs
   `dovetail doctor` with no monorepo present.
2. **`init` resolves the runtime from the SDK.** The
   `pubspec_overrides.yaml` points at the SDK. Acceptance: a new app on
   another machine gets green `flutter pub get` and `flutter test` with the
   SDK alone.
3. **The installer and the version cycle.** `install.sh` (curl | sh),
   `dovetail self-install`, `self-update`; doctor checks that the SDK is
   present and which version. Acceptance: a clean container installs, doctor
   is green, and `self-update` switches version without breaking apps pointed
   at the previous one (the SDK is versioned by directory).
4. **`dovetail bridge`.** `bridge init --core <crate> --name <name>`
   generates the `ffiPlugin` (3 OSs) with the crate by configurable path and
   the SDK's `dovetail_rust_core`. Acceptance: what it generates against a
   real crate passes `core_coverage_test` — the reproduced bridge matches the
   versioned one.
5. **End-to-end proof.** The [gate-linux Dockerfile](ci.md) becomes the
   stage: a clean container installs, starts a minimal app and runs doctor +
   test + build with no clone at all.

## The release channel

The host that serves the installation speaks a fixed layout:

```
<base>/latest                                            → "0.2.0"
<base>/install.sh                                        → the curl|sh installer
<base>/<version>/dovetail-sdk-<version>-<os>-<arch>.tar.gz
<base>/<version>/dovetail-sdk-<version>-<os>-<arch>.tar.gz.sha256
```

Two paths do the same work, and both respect `DOVETAIL_HOME`:

```bash
curl -fsSL https://<host>/install.sh | sh   # the one-line path
dovetail self-install --base-url https://<host>
dovetail self-update  --base-url https://<host>
```

The base comes from `--base-url` or from `DOVETAIL_INSTALL_URL`, and without
either the refusal names both. The download is TLS-only (the updater's fetcher
refuses http) and the tarball is checked against the channel's `.sha256`
before a byte touches disk. `self-update` extracts the new version **beside**
the old one and swaps the binary — `sdk/<old>` stays, which is what keeps an
app pointed at it resolving, and the symlink does not even need re-pointing. A
`latest` that is equal or older exits 0 without touching anything. `doctor`
reports the SDK in a section of its own: the installed version, and when it
disagrees with the binary's, which command closes the gap — `off`, never
`missing`, because inside the monorepo the SDK is optional and a developer who
resolves by path should not be blocked.

## The bridge

The SDK carries the bridge template — `sdk/<version>/templates/bridge` — and
the command copies and parameterises it:

```bash
dovetail bridge init --core <crate> --name <name>
```

`--core` is the product crate's directory; the crate's name is read from its
`Cargo.toml`, never guessed. What comes out is the `ffiPlugin` for all three
OSs, with the SDK's `dovetail_rust_core` on both sides — the Dart in the
pubspec, the crate in the `Cargo.toml`. The template reproduces the fixture's
mechanics and deliberately leaves out what belongs to the product: the
forwarders in `rust/src/api/`, the generated Dart, and the `example/`.

The shape gate comes with it: the generated project's `core_coverage_test`
reads the crate's `handle.rs` and the calls under `rust/src/api/`, and refuses
when the core has grown a method that no forwarder exposes. Phase 4's
acceptance criterion is exactly that: the generated bridge, fed the same
`api/` as the versioned one, passes the same gate.

## The end-to-end proof

Phase 5 runs in the gate-linux container: a clean ubuntu installs the SDK from
the https channel, creates the minimal app with `dovetail new --sdk`, and runs
doctor + test + build without cloning the monorepo:

```
install.sh               → dovetail 0.1.0 (linux-x64)
dovetail new --sdk demo
flutter create --platforms=linux .
flutter pub get          → resolves from the SDK, no repo
flutter test             → the SDK's runtime answers in the test
flutter build linux      → ✓ Built build/linux/x64/debug/bundle/demo
dovetail doctor          → sdk ok + project ok
```

What the proof exposed, and the SDK build fixed: the native plugins' platform
directories and the ffiPlugin's vendored cargokit have to travel in the
tarball — `flutter build` runs `add_subdirectory` on them — and the build
artefacts (`target/`, `build/`) have to stay out, otherwise the tarball
carries hundreds of megabytes the consumer does not need. gate-linux gained
the `appindicator` that `tray_manager` requires on Linux.

The proof is versioned: `tool/ci/prove_sdk.sh` runs the flow above in a clean
container from the tarball in `dist/`, and `tool/ci/prove_bridge.sh` proves
the consumer's other path — the generated `bridge init`, with the codegen, the
SPM XCFramework and an app that imports it, building on macOS. Both are the
release canary: no version ships without them green. What is still open, and
in what order, is in the [roadmap](roadmap.md).

## Out of scope

Distributing the product app, and changing the toolkit/product split.

Publishing to pub.dev **was** out of scope and no longer is: the ten packages
are published, and that is now the ordinary route for a consumer. The signed
channel remains, for the release machine that wants an AOT binary and a
versioned SDK.
