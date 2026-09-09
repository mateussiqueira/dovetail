**English** · [Português](pt-BR/README.md)

# dovetail documentation

This index exists because there are twenty-five documents, and a document you
cannot find is not written. Every line says **which question** the file
answers — and a test refuses when one of them is not listed here.

## Start here

| if you want to | read |
|---|---|
| get going in five minutes | [quickstart.md](quickstart.md) |
| understand what the project is, and what is already proven | [`../README.md`](../README.md) |
| **write screens** against the framework | [`../WRITING_THE_APP.md`](../WRITING_THE_APP.md) |
| **leave Tauri** in a product that already exists | [migrar-do-tauri.md](migrar-do-tauri.md) |
| know what every key of `dovetail.yaml` does | [configuracao.md](configuracao.md) |
| find out why something broke | [problemas.md](problemas.md) |
| see what CI runs on each system, and what it has not proven yet | [ci.md](ci.md) |
| install dovetail outside the monorepo, and the phases to get there | [instalador.md](instalador.md) |
| what comes after the five phases, by area (toolkit, CLI, DX) | [roadmap.md](roadmap.md) |
| the path to **production**: milestones, acceptance criteria, and what is blocked outside the code | [roadmap-producao.md](roadmap-producao.md) |
| run the **whole** pipeline with no production key, host or Developer ID, using stand-ins that honour the same contract | [release-simulado.md](release-simulado.md) |
| contribute, and what helps most at this point | [`../CONTRIBUTING.md`](../CONTRIBUTING.md) |

## The pipeline

Package, sign and publish. Runs on the release machine, never inside the app.

| package | what it answers |
|---|---|
| [`dovetail_cli`](../toolkit/dovetail_cli/README.md) | the nineteen commands, and what each one refuses |
| [`dovetail_bundler`](../toolkit/dovetail_bundler/README.md) | nsis, msi, dmg, deb, rpm — and the Tauri traps that are a fatal error here |
| [`dovetail_signer`](../toolkit/dovetail_signer/README.md) | codesign, notarisation, Authenticode, SHA256SUMS |

## The runtime

What the app loads. It all comes in through one barrel:
`package:dovetail/dovetail.dart`.

| package | what it answers |
|---|---|
| [`dovetail`](../toolkit/dovetail/README.md) | the barrel: what goes in, what stays out, and why |
| [`dovetail_platform_channel`](../toolkit/dovetail_platform_channel/README.md) | window, tray, anchored panel, single instance, deep link, notification |
| [`dovetail_shortcut_channel`](../toolkit/dovetail_shortcut_channel/README.md) | global shortcut, and why Wayland is refused instead of faked |
| [`dovetail_updater`](../toolkit/dovetail_updater/README.md) | manifest, minisign verification, installing on all three systems |
| [`dovetail_form_validation`](../toolkit/dovetail_form_validation/README.md) | the seven form rules, and why the failure is a sealed type |
| [`dovetail_process_runner`](../toolkit/dovetail_process_runner/README.md) | running a process without the three deadlocks `Process.run` has |
| [`dovetail_rust_core`](../toolkit/dovetail_rust_core/README.md) | the Dart↔Rust mechanics: tokio runtime, event pump, probe |

## What is not here

The app that consumes the toolkit, and the bridge to its Rust core, live in
another repository: they are product, not framework. What this repository
carries is the entire toolkit — which is everything any app needs in order to
be built, packaged, signed and updated.

Some documents still mention `product/` as the path of the example that
exercises a mechanism. Those carry a note at the top saying so.

## The decisions, with the reasoning

`ARCHITECTURE.md` is where the reasoning that does not fit in a README lives:

- [`dovetail_rust_core`](../toolkit/dovetail_rust_core/ARCHITECTURE.md) — why
  an instance instead of global state, and why there is no
  `resetForTesting()`.
- [`dovetail_platform_channel`](../toolkit/dovetail_platform_channel/ARCHITECTURE.md)
  — why the panel is computed rather than measured, and the wire format
  compared byte for byte.

## What the documentation promises, and who enforces it

Six things here are checked by a test, because a document ages quietly:

| what | who enforces it |
|---|---|
| every `dovetail.yaml` key is in `configuracao.md` | `config_documented_test.dart` |
| every CLI command is in its README | `readme_covers_commands_test.dart` |
| the README's test table matches the actual run | `verify test` |
| every package has a README, CHANGELOG and LICENSE | `package_paperwork_test.dart` |
| every document is listed in this index, and every link resolves | `docs_index_test.dart` |
| a Dart call reaches Rust and comes back | `verify ffi` |

The rest is prose, which nobody can enforce. If something here diverges from
the code, **the code is right and the document is old** — and fixing the
document is worth more than working around it.
