**English** · [Português](pt-BR/ci.md)

# CI: the gate on all three OSs

> **Context for anyone arriving through the public repository.** This document
> mentions `product/`, which is the private app where the toolkit is
> exercised, and it does not exist in this repository. The mechanism described
> belongs to the toolkit and holds for any app; only the example's path
> belongs to another tree.

`.github/workflows/ci.yml` runs the gate off this machine. This document says
what each leg executes and **why** — and what stays unproven until a hosted
run comes back green.

## What it is, in one sentence

The difference between "compiles for the target" and "ran on the target". This
machine proves macOS arm64; a hosted runner is where Windows and Linux get
their first real run.

## The layout, and why it is mandatory

The product resolves its siblings by path, and both of those repositories are
private. So the workflow:

- checks out `dovetail` into `dovetail/`;
- checks out the siblings **at the workspace root**, beside it — the only
  position where the `../../..` paths resolve;
- reads the siblings with a private PAT, `secrets.SIBLINGS_TOKEN`.

Without the secret, **every job refuses at the first step**, naming what is
missing: a PAT that can read the two private repositories the origin monorepo
consumes by path. The public repository needs none: the ten packages resolve
against each other through `pubspec_overrides.yaml`. Nothing here signs or
publishes — the workflow is a gate, not a `ship`.

## What each leg runs, and why they differ

### macOS (`macos-14`, arm64) — the whole gate

`dart tool/verify.dart all`: doctor, fast, cross, rust, frb, ffi, release,
readme, test, baseline. It is the only leg that compares against the baseline,
because the baseline was recorded in the **cold shape** — no built app, no
universal slices — which is exactly what a clean runner has. The ffi target
opens a real window (`-d macos`), so this leg is also the proof that the
bridge crosses on a runner.

`release` runs the entire macOS pipeline against a local host
(`tool/ci/prove_update.sh`, described in
[release-simulado.md](release-simulado.md)): it signs, packages, publishes,
serves over https with a private CA and asks `probe`. It **skips** when there
is no Release `.app` built — the case for the pre-push worktree and for any
clean clone — and names the command that produces one. Building inside the
gate would cost ten minutes per push; proving the pipeline over a build that
already exists costs one minute.

That sentence was false until 2026-09-05. The file said "cold shape" and it
was a recording from this machine, warm: `diff tool/skip_baseline.json
dist/verify-run.json` after a normal run came out identical, and the tests
that depend on the built `.app` — `real_codesign_test.dart`,
`mach_o_test.dart`, `minimum_system_version_test.dart`, `inspect_test.dart`,
`bundle_arch_test.dart` — showed up with zero skips. On a clean runner they
skip, `_compare` calls each one `SKIP NEW`, and the leg would be born red
before any real defect.

How to re-record it, when someone needs to — and it is needed every time a
test enters or leaves, because the baseline stores `declared` per suite:
`tool/rebless_cold.sh`. It copies the **tracked** files (the index: a new file
needs `git add` first, and the script says which would be left out) into a
directory beside this one (the product's `../../../` paths have to reach the
siblings), without `.dart_tool`, `build/` or `target/`; runs `dart
tool/verify.dart test` there; brings `dist/verify-run.json` back, does
`bless --force` and prints the totals the README's headline has to state. The
`git ls-files -z | rsync --files-from=- --from0` is what guarantees no warm
artefact travels along. It takes about five minutes on a machine with a warm
pub cache.

Cold comes out green on both sides, and that is why there is no second warm
baseline: on this machine the extra 41 tests do run, and a skip that stops
happening is `skip gone` — news, never a problem, because it means more was
proven. The reverse does not hold, and the reverse is what used to be shipped.

The leg installs the tools the cold shape assumes present (minisign, msitools,
rpm, makensis via brew) and the `flutter_rust_bridge_codegen` pinned in the
bridge's `Cargo.toml` — `verify all` requires the codegen so that frb checks
for real rather than merely reporting absence.

### Linux (`ubuntu-24.04`, x86_64) — the suite, minus what is macOS

`doctor`, `fast`, `test`, `rust --only toolkit`, `cross --only toolkit`,
`readme`. No baseline (the recorded skips are from the macOS cold shape, and a
Linux runner has a different tool set), no ffi (the target opens a window on
the only proven device — macOS) and no frb (the codegen's output is
host-independent; the macOS leg owns it). Then it runs the two packaging
proofs:

- `tool/prove_on_linux.sh` — it now inherits the host's architecture, so on an
  x86_64 runner it validates the **x86_64** `.deb` and `.rpm`, the complement
  of what this machine's arm64 proves;
- `tool/prove_guard_on_wine.sh` — the Windows single-instance guard under a
  **native** wine (no emulation), in the amd64 container.

### Windows (`windows-2022`, x86_64) — the suite, minus what is macOS

The same as Linux: `doctor`, `fast`, `test`, `rust --only toolkit`,
`cross --only toolkit`, `readme`. Without the docker proofs, which have
nothing to do here.

## `--only toolkit`, and the line it does not cross

`rust` and `cross` accept `--only <substr>` (the same `--only` that `test`
has). The non-macOS legs use `--only toolkit` to prove the toolkit's crates
and **leave the product's bridge crate out**: that crate drags in the sibling
repository's crates by path, and none of them has ever compiled for a Linux or
Windows host. Proving them is the item "the app compiles on Windows and Linux",
not the item "the gate runs on all three OSs" — and the fix, if it fails,
lives in the sibling repo.

## What was fixed before the first paid run

Four defects that would only show up on a runner, and would have cost one run
each — in macOS minutes, which are worth 10x:

- **The `SIBLINGS_TOKEN` guard could not print.** `defaults.run.
  working-directory: dovetail` already applies to the job's **first** step,
  which runs **before** `actions/checkout` creates that directory. It was the
  only message in the file written for whoever hits it first, and the only one
  that could not be seen. That step now carries `working-directory: .`.
- **`clippy` and `rustfmt` never arrived.** `dtolnay/rust-toolchain` installs
  the `minimal` profile, and neither comes with it — while `verify fast` runs
  `cargo fmt --check` and `cross` runs clippy. All three legs would be red in
  the first job the account allowed to be created.
- **The six targets in a single `run:`.** Under `bash -e` the first non-zero
  ends the step and the following five never run — throwing away exactly the
  property `_all()` has on purpose: everything runs, everything reports, the
  exit code is decided at the end. On a leg that has never run, that means
  discovering one problem per run. It is now one step per target, with
  `if: ${{ !cancelled() }}`.
- **No `pull_request` trigger.** A required check reports on the PR's SHA;
  without the trigger it never appears, and branch protection would block
  **every** merge instead of the red ones. `pull_request` and `merge_group`
  went in, and `cancel-in-progress` now applies only to PRs: cancelling on
  `main` throws away the verdict for a commit that already landed.

`flutter_rust_bridge_codegen` is no longer compiled from source on every run —
it is cached with a key carrying `FRB_PIN`, and the version is checked on both
cache hit and cache miss: a restored binary that is not what the pin says
would be worse than having no cache, because the `frb` target compares the
codegen's output against the versioned one and would blame the code.

## What is still unproven

The workflow is written; **no hosted run has come back green yet.** Until the
first one, this machine's green is the only green — and this document does not
claim otherwise. What the first run decides:

- whether ffi opens a window on a macOS runner with no guaranteed graphical
  session;
- whether the baseline's skip set matches a clean runner (the cold shape was
  recorded for that, and the reasons are now machine-independent);
- whether the product's Dart suites even load on Linux and Windows — no
  product test has ever run on those hosts;
- whether the runner's makensis behaves like the one here.

Every job uploads `dist/verify-run.json` and the `dist/doctor-*.log` reports
as artefacts, and runs `dovetail doctor` with `continue-on-error`: on a runner,
**reporting the missing tool is the point**, not an error to hide.

## Triggering it

`push` to `main`, or `workflow_dispatch` by hand. Before the first push:
create the `SIBLINGS_TOKEN` secret on the repository.

## The `startup_failure` that cost two days, and its two causes

Every hosted run failed with `startup_failure` in zero seconds, with no job
and no log — the run said only "workflow file issue". There were **two**
causes, one behind the other:

1. **`secrets` is not a valid context in a step's `if:`.** GitHub refuses the
   whole workflow before creating any job. `actionlint` names the error in
   seconds; the sanctioned pattern is to expose the secret once in the
   workflow's `env:` and test `env.SIBLINGS_TOKEN` everywhere — which is what
   the file does today.
2. **The owner's account does not execute Actions.** Even a minimal `echo`
   workflow stayed in `startup_failure` with an empty `name` and zero check
   runs. The annotation says it plainly: *"The job was not started because
   your account is locked due to a billing issue."* What unblocks it is a
   billing decision, not the file. The `secrets` fix was necessary anyway and
   stays.

## The same gate, without a hosted runner

While the account does not execute Actions, the Linux leg has a local path:
`tool/ci/gate-linux.Dockerfile` builds the same environment as the runner
(Ubuntu 24.04 x86_64, pinned Flutter and Rust, the gate's tools) and runs
`doctor`, `fast`, `test`, `rust --only toolkit`, `cross --only toolkit`,
`readme` inside the container, with the siblings mounted beside it. It is what
proved the gate runs on a real Linux before any runner existed.

The gate is deterministic where it was measured: `bash tool/soak.sh 5` gave
`5/5 green` on 2026-09-06, after the signing changes, `archive` and the
defines. The number that matters is not one green run, it is N of them.

**What emulation is NOT good for proving.** Running that container on the arm64
Mac was tried again on 2026-09-06 and produced nothing usable: `doctor` and
`fast` passed, and `test` reported red on **every** package — including
`dovetail_form_validation` and `dovetail_process_runner`, which touch no system
at all. What condemned them was the clock, not the code: run alone inside the
same container, `dovetail_form_validation` said `All tests passed!`. The
per-package times, against the host's on the same tree:

| package | emulated x86_64 container | arm64 host |
|---|---|---|
| `dovetail_form_validation` | 79.1s | 1.2s |
| `dovetail_process_runner` | 50.5s | 3.5s |
| `dovetail_updater` | 152.5s | 7.3s |
| `dovetail_platform_channel` | 209.0s | 9.0s |
| `dovetail_cli` | 435.8s | 57.0s |

Between 8 and 65 times slower, and one `flutter test` ended up hanging for
more than six hours of CPU. Under that factor, what blows first is the suites'
time limit, not the assertion — and red from slowness is worse than no run at
all, because it looks like a defect. This file says what the tree proves and
where: the Linux leg needs a **real x86_64 runner** (or an arm64 Linux host),
and while that does not exist, what runs in a container here is
`prove_on_linux.sh` — which packages and validates with real `dpkg` and `rpm`,
emulating no Dart at all.

The packaging proofs already run on this machine without it:
`tool/prove_on_linux.sh` proved `.deb` and `.rpm` on both sides — including
the AppImage refusal for a product with a service — and
`tool/prove_guard_on_wine.sh` proved the single-instance guard under wine
("the guard behaved on a machine that is not Windows"). Re-proven on
2026-09-06 with that day's tree, after the signing changes, `archive` and the
defines: `both suites passed`, the updater installing with privilege through
rpm, the same version reinstalled exiting 0, a clean removal. And macOS has
its own end-to-end proof in `tool/ci/prove_update.sh` — see
`release-simulado.md`.
