**English** · [Português](pt-BR/roadmap.md)

# dovetail roadmap

The work is organised into three areas: **toolkit/framework** (the runtime and
the mechanics), **CLI** (the binary and the pipeline) and **DX** (the
experience of whoever consumes the framework). Every task has a status; the
blocked ones name what unblocks them. The five phases from
[instalador.md](instalador.md) are complete and have left this file — what
stays here is what came after them.

## Toolkit / framework

| task | status | note |
|---|---|---|
| Release canary: versioned `tool/ci/prove_sdk.sh` — a clean container installs the SDK and sustains the minimal app (doctor + test + build) | ✅ done | it used to be manual and disposable; now it is reproducible from the repo |
| Generated bridge building: `tool/ci/prove_bridge.sh` — `bridge init` + codegen + XCFramework + consumer app, `flutter build macos` green | ✅ done | the product entries (api, support, sibling crates) are completed by the proof, as the template requires |
| Fuzzing the updater's `ManifestParser`/verifier — malformed input never takes the client down | ✅ done | deterministic test in `dovetail_updater`; it exposed and fixed a `FormatException` leaking out of `ascii.decode` in the minisign parsers (a DoS at the trust boundary) |
| Building the product on Windows and Linux (the sibling repo's crates) | blocked | needs a machine/runner; Linux could go in the gate container, but it is the sibling repo's boundary |
| Wayland backend for the global shortcut | refused | decision recorded in the README, with the session named |
| `mobile_scanner` on Windows/Linux | blocked | sibling repo (design system), outside dovetail |

## CLI

| task | status | note |
|---|---|---|
| `app` section in `doctor` — do the consumer's overrides point at an SDK that exists? | ✅ done | closes the host–project–SDK triangle |
| `spm` section in `doctor` — does the `.xcframework` exist? | ✅ done | today, whoever forgot `build_xcframework.sh` only finds out at build time |
| Binary diagnostics — structured log with rotation in the final catch | ✅ done | the AOT build used to die with a stack trace and no reporting channel |
| Tests for the `probe`/`inspect`/`ship` wrappers | ✅ done | flagged by the coverage audit |
| Release orchestration — `tool/release.sh` runs both builds and both canaries in order | ✅ done | each step had already proven green on its own; the script is the right order |
| Windows binary | blocked | `dart compile exe` does not cross-compile to Windows |
| macOS Intel binary | blocked | no `x86_64-apple-darwin` target on this host |
| Public distribution (notarisation) | blocked | Developer ID and notarisation do not exist |
| Hosted CI | blocked | the account does not run Actions. The workflow itself is valid (actionlint), and the public repository needs no token: the ten packages resolve against each other through `pubspec_overrides.yaml` |

## DX

| task | status | note |
|---|---|---|
| `dovetail upgrade` — re-points the app's `pubspec_overrides.yaml` at the installed SDK | ✅ done | closes the version cycle that `doctor` only reports |
| `dovetail new` finishes `flutter create` via `--no-create` | ✅ done | the build used to fail until the user ran `flutter create --platforms=... .` by hand |
| `dovetail new` generates the clean-architecture layout of the mobile standard (Manguinho's refinement: lib/data, lib/domain, lib/infra, lib/main, lib/presentation, lib/shared) | ✅ done | SDK template at `tool/sdk/templates/app`; proven: `new` + pub get + analyze + 6 tests + a green flutter suite in the generated project |
| `dovetail new` embeds the mobile conformance checks, adapted to desktop | ✅ done | both suites ship: the mobile flutter one (22 checks) and the desktop rust one (6 checks); proven green in the generated project, with a negative proof (a dirty comment fails it) |
| `dovetail new` generates the Rust core + the FFI bridge (a complete `core/` and `core_bridge/`) | ✅ done | the bridge reuses the `bridge init` template; proven: codegen + cargo check on the core and the bridge + the coverage gate with core↔forwarder parity |
| `doctor` as the single source about the host — consolidate the consumer sections into one report | dropped | `doctor` without `--target` already *is* the single report (project + sdk + app + spm together), and the exit code is the verdict for scripts — a fifth summary section would duplicate the four |
| Consumer docs — `ESCREVER_O_APP.md` and `migrar-do-tauri.md` following every change | ongoing | `readme_covers_commands_test` and `docs_index_test` enforce it |

## How tasks get in here

A task enters the roadmap when it has an executable acceptance criterion; it
leaves when the real proof closes (the "Proven:" pattern in the commits).
Execution order is by value — release robustness first, then the doctor
sections, and diagnostics/fuzzing last — unless the owner decides otherwise.

## Approved improvements (refinement round)

Ten suggestions that came out of reviewing the generator, the cycle and the
release, approved as a block. In the recommended order:

| # | improvement | status |
|---|---|---|
| 1 | `docs/quickstart.md` — the consumer's five-minute path | ✅ done |
| 4 | `dovetail upgrade --check` — proves the app resolves after re-pointing | ✅ done |
| 7 | Sign the SDK channel — minisign on top of sha256+TLS | ✅ done |
| 9 | Paths with spaces in the overrides (quoting + escaping) | ✅ done |
| 2 | `bridge init --from <bridge>` — replicates an existing bridge | ✅ done |
| 3 | `bridge init` validates the crate early (warns when `handle.rs` is absent) | ✅ done |
| 6 | Run `tool/release.sh` end to end | ✅ done |
| 8 | `doctor --check-updates` — compares the installed version against the channel | ✅ done |
| 5 | `dovetail update` — SDK + app in one line | ✅ done |
| 10 | Deep fuzzing on minisign (parser/verifier, dedicated corpus) | ✅ done |
