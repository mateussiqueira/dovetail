<!-- English. Versão em português: [README.pt-BR.md](README.pt-BR.md) -->

**English** · [Português](README.pt-BR.md)

# dovetail

> The joint between Flutter and Rust on the desktop. In place of Tauri.

A *dovetail* joint locks two pieces of different material together and gets
firmer under load, without glue or screws. That is what this project is: the
joint between a Flutter UI and a Rust core, plus the tooling to build, sign
and ship it on Windows, macOS and Linux.

## Where this actually stands

This is open **because it is not finished**, and the list below is the
invitation.

What is proven on one machine: the ten packages pass their own tests, the CLI
builds, bundles, signs and verifies a release end to end against a local host
with a private CA, and the updater refuses a manifest without a valid
signature.

What is **not** proven:

- **Nothing has run outside one macOS arm64 machine.** The workflow exists,
  with legs for `macos-14`, `ubuntu-24.04` and `windows-2022`, and not one of
  them has ever executed: the account that publishes this repository has no
  GitHub Actions available. **In a fork it runs** — Actions is free on public
  repositories. If you fork this and the matrix passes (or fails) on Windows
  or Linux, that is the single most valuable thing this project can receive
  right now.
- **Nothing has been compiled with MSVC.** The Windows leg is code written
  blind.
- macOS signing was exercised with a self-signed certificate. A real Developer
  ID and notarisation have never been through here.

If something does not work on your machine, that is not a surprise — it is the
missing information. Open an issue with your operating system and the output.

## The packages

| package | what it does |
| --- | --- |
| [`dovetail`](https://pub.dev/packages/dovetail) | the umbrella: the whole runtime behind one dependency |
| [`dovetail_cli`](https://pub.dev/packages/dovetail_cli) | the pipeline: `init`, `doctor`, `build`, `sign`, `ship`, `release` |
| [`dovetail_rust_core`](https://pub.dev/packages/dovetail_rust_core) | the bridge to the Rust core, over flutter_rust_bridge |
| [`dovetail_bundler`](https://pub.dev/packages/dovetail_bundler) | packages it: `.app`, `.dmg`, `.msi`, `.deb`, `.rpm`, AppImage |
| [`dovetail_signer`](https://pub.dev/packages/dovetail_signer) | signs and notarises, and refuses when it cannot prove it |
| [`dovetail_updater`](https://pub.dev/packages/dovetail_updater) | verifies a minisign-signed manifest and updates |
| [`dovetail_platform_channel`](https://pub.dev/packages/dovetail_platform_channel) | single instance and window integration |
| [`dovetail_shortcut_channel`](https://pub.dev/packages/dovetail_shortcut_channel) | global shortcut, with or without window focus |
| [`dovetail_process_runner`](https://pub.dev/packages/dovetail_process_runner) | external process with a timeout and a typed outcome |
| [`dovetail_form_validation`](https://pub.dev/packages/dovetail_form_validation) | form validation that does not depend on a widget |

## Getting started

Everything the runtime needs comes behind one dependency:

```yaml
dependencies:
  dovetail: ^0.1.0
```

And the pipeline is a command:

```bash
dart pub global activate dovetail_cli
dovetail --help
```

To work on the toolkit itself:

```bash
git clone https://github.com/mateussiqueira/dovetail
cd dovetail/toolkit/dovetail_cli
dart pub get
dart run bin/dovetail.dart --help
```

The repository is a monorepo of packages under `toolkit/`. Each one publishes
on its own and declares the others by version; every package's
`pubspec_overrides.yaml` points at its local neighbour, so `dart pub get`
resolves without going through pub.dev.

## The commands

The whole pipeline is one binary. Nothing it does needs its own source.

| command | what it does |
| --- | --- |
| `dovetail init` | reads the project and writes `dovetail.yaml` |
| `dovetail doctor` | can this host build what was declared? |
| `dovetail new` | scaffolds a new project, already wired to the runtime |
| `dovetail bridge` | generates the FFI plugin that talks to the Rust core |
| `dovetail build` | compiles the Flutter app with the defines from the config |
| `dovetail bundle` | packages it: `.app`, `.dmg`, `.msi`, `.deb`, `.rpm`, AppImage |
| `dovetail sign` | signs and, on macOS, notarises |
| `dovetail icon` | derives every platform's icons from a single image |
| `dovetail inspect` | says what an artefact is, by reading its header |
| `dovetail keygen` | creates the minisign key pair for the update channel |
| `dovetail manifest` | writes and signs the manifest the app will read |
| `dovetail ship` | the whole pipeline, from the config |
| `dovetail release` | publishes the version and moves the channel |
| `dovetail probe` | verifies a published manifest the way the app would |
| `dovetail update` | applies an update, the way the app would |
| `dovetail dev` | runs the app with the Rust core in development mode |
| `dovetail upgrade` | updates the toolkit packages a project uses |
| `dovetail self-install` | installs this binary on the `PATH` |
| `dovetail self-update` | updates this binary through the signed channel |

## Documentation

The deep documentation lives in [`docs/`](docs/README.md), in English, with the
Portuguese originals under [`docs/pt-BR/`](docs/pt-BR/README.md).

- [Quickstart](docs/quickstart.md) — from an installed CLI to the first ship
- [Configuration](docs/configuracao.md) — every key of `dovetail.yaml`
- [Troubleshooting](docs/problemas.md) — what breaks, and what the message means
- [Migrating from Tauri](docs/migrar-do-tauri.md) — what carries over and what does not
- [Writing the app](WRITING_THE_APP.md) — the architecture on top of the toolkit
- [Production roadmap](docs/roadmap-producao.md) — the honest inventory of what is missing

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). The short version: run the tests of
the package you touched, and say in the pull request description **which
operating system** you measured on. This project has one specific debt —
almost everything was verified in a single place — and a pull request saying
"tested on Windows 11, this failed like so" is worth more here than a new
feature.

## Licence

MIT. See [LICENSE](LICENSE).
