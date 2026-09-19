<!-- English. Versão em português: [README.pt-BR.md](README.pt-BR.md) -->

**English** · [Português](README.pt-BR.md)

# dovetail

> The joint between Flutter and Rust on the desktop. In place of Tauri.

A *dovetail* joint locks two pieces of different material together and gets
firmer under load, without glue or screws. That is what this project is: the
joint between a Flutter UI and a Rust core, plus the tooling to build, sign
and ship it on Windows, macOS and Linux.

## Where this actually stands

**Beta.** Not because a version number moved, but because the thing finally
happened: a real product shipped on this toolkit, went out to roughly a
hundred people, and came back with praise instead of a bug list.

That product is a commercial VPN client — Flutter on top of a Rust core, with a
privileged daemon that has to install itself and survive a reboot. It is the
hardest shape this toolkit claims to support, and the internal distribution
channel carried it: `dovetail ship --channel internal` produced a `.pkg` that
installs the declared daemon, wrapped in a `.dmg` a tester knows how to open,
universal across Intel and Apple Silicon. Installed, ran, survived a restart,
uninstalled without residue. That is what moved this out of alpha.

What is proven, and measured rather than remembered:
**1513 testes Dart declarados, 45 pulados**, plus the Rust crates. `dart tool/verify.dart`
compares that sentence against what the suites just reported and fails when
they disagree, so a README that overstates its own coverage cannot be
committed. The skipped ones are named in `tool/skip_baseline.json`, with the
reason.

What is still **not** proven, and we would rather say it than have you find it:

- **Almost everything ran on one macOS arm64 machine.** The CI workflow has
  legs for `macos-14`, `ubuntu-24.04` and `windows-2022`, and none has ever
  executed — the account publishing this has no Actions minutes. **In a fork it
  runs**, because Actions is free on public repositories. If you fork this and
  the matrix passes on Windows or Linux — or fails — that is still the single
  most useful thing this project can receive.
- **Nothing has been compiled with MSVC.** The Windows code typechecks for
  `x86_64-pc-windows-msvc` and has never met a real Windows.
- **The release channel has not met a real Developer ID.** Signing was
  exercised with a self-signed certificate; notarisation has never been through
  here. The internal channel, which needs neither, is the one with mileage.

If something breaks on your machine, that is not a surprise — it is the
information we do not have. Open an issue with your operating system and the
output.

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
| [`dovetail_privileged_helper`](https://pub.dev/packages/dovetail_privileged_helper) | the root daemon, service or unit a sandboxed app cannot be |
| `dovetail_privileged_channel` | the wire to that daemon: socket or pipe, and who is allowed to speak |
| `dovetail_privileged_daemon` | the daemon's own skeleton: install, accept, validate, log |
| `dovetail_http_client` | a typed HTTP client, and the OS keychain the token lives in |
| [`dovetail_shortcut_channel`](https://pub.dev/packages/dovetail_shortcut_channel) | global shortcut, with or without window focus |
| [`dovetail_process_runner`](https://pub.dev/packages/dovetail_process_runner) | external process with a timeout and a typed outcome |
| [`dovetail_form_validation`](https://pub.dev/packages/dovetail_form_validation) | form validation that does not depend on a widget |

### What the suites actually cover

Counts come from the run, not from memory: `dart tool/verify.dart` compares
every row below against what the suites just reported, and fails on the first
one that has aged. Four rows had already aged in a single day before this
check existed.

| package | tests | what they prove |
| --- | --- | --- |
| `toolkit/dovetail` | 7 Dart | the umbrella re-exports the runtime, and a test proves the surface does not drift |
| `toolkit/dovetail_cli` | 565 Dart | the pipeline, end to end, against a local host with a private CA |
| `toolkit/dovetail_bundler` | 321 Dart | every artefact format, read back by its own header |
| `toolkit/dovetail_updater` | 172 Dart | a manifest without a valid signature is refused |
| `toolkit/dovetail_platform_channel` | 201 Dart | window, tray, single instance, deep links, appearance |
| `toolkit/dovetail_signer` | 94 Dart | signing refuses what it cannot prove |
| `toolkit/dovetail_privileged_helper` | 23 Dart | the state a bool collapses, and the refusal paths |
| `toolkit/dovetail_shortcut_channel` | 55 Dart | the global shortcut, with and without window focus |
| `toolkit/dovetail_form_validation` | 29 Dart | validation with no widget in sight |
| `toolkit/dovetail_process_runner` | 23 Dart | timeout and typed outcome |
| `toolkit/dovetail_rust_core` | 13 Dart | the bridge surface |
| `toolkit/dovetail_screenshots` | 10 Dart | the capture mechanism, bounded frames, loaded icon fonts |
| `toolkit/dovetail_http_client` | 32 Rust | typed calls, safe routes, and the keychain round trip |
| `toolkit/dovetail_privileged_channel` | 21 Rust | the handshake, the framing, and who may speak |
| `toolkit/dovetail_privileged_daemon` | 10 Rust | the service lifecycle on three platforms |

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

### Two channels, and the one with mileage

`dovetail ship` has two: `release`, which wants a Developer ID and produces
something a stranger can install, and `internal`, which wants nothing and
produces something your team can install this afternoon.

The internal channel exists because every project needs to hand a build to
testers long before it has a signing identity, and the usual answer — "just
build it and pass the folder around" — falls apart the moment the app has a
privileged component. So `--channel internal` keeps the debug symbols, signs
ad-hoc, refuses to write an updater manifest (an internal artefact must never
reach the channel your released users watch), and picks the installer format
that can actually install what the project declared.

On macOS that means a `.pkg`, because it is the only format there that runs a
postinstall as root — and the `.pkg` travels inside a `.dmg`, because that is
what a person knows how to open. Familiar on the outside, correct on the
inside.

This is the path that carried a real product to a hundred testers. It is the
most exercised thing in the repository.
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
