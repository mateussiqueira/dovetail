**English** · [Português](pt-BR/roadmap-producao.md)

# Production roadmap — what is missing, and how you would know it is done

> **Context for anyone arriving through the public repository.** This document
> was born in the monorepo where the toolkit is developed, and it cites paths
> that **do not exist here** — the private app that consumes the toolkit and
> the sibling repository of crates it uses by path. None of that is needed to
> use or contribute to the ten packages: each one runs and tests on its own.
> The document stays because it is the honest inventory of what is missing,
> and it is what lets you pick something to help with.

> **About this English version.** The Portuguese original carries the full
> task-level detail: 166 items with ids, each with an `file:line` reference to
> the code that motivated it, measured on the day it was surveyed. Those
> references age — the line numbers move with every commit — so translating
> them would hand you a document that looks current and is not. What is here
> is the part that does not age: the state, the milestones, what each one has
> to prove, the critical path, and what this roadmap deliberately refuses to
> do. For the task-level detail, read
> [the Portuguese version](pt-BR/roadmap-producao.md); the ids are stable and
> greppable even if you do not read Portuguese.

## 1. Where it stands

The framework is a monorepo that only works on one machine: twelve packages
whose gate does not resolve without two private repositories, a baseline that
was recorded warm and described as cold, twenty-nine CI runs that never created
a job, nothing ever compiled with MSVC, no command that publishes, no
certificate, no host. What separates that from production is not a feature
list: it is that **no claim in the repository had been verified by anyone other
than the author, on any machine other than that one.**

Some of that has moved since. The baseline is now recorded genuinely cold
(`tool/rebless_cold.sh`), the generator no longer emits an SSH alias only the
author's machine resolves, and the ten packages are published on pub.dev — so
a consumer no longer needs the monorepo at all. What has not moved is the part
that is not code: **CI does not run because the account is locked for
billing**, nothing has been compiled with MSVC, and there is neither a
certificate nor a host.

## 2. The milestones

Size convention used throughout: **XS ≤ 0.5 day · S = 1 day · M = 2.5 days ·
L = 5 days · XL = 12 days** (one person, working day).

### Milestone 0 — It leaves this machine

**Exit condition:** `git clone <repo> /tmp/solo && cd /tmp/solo && dart
tool/verify.dart all --only toolkit && dovetail new demo` succeeds on a machine
with no sibling checkouts.

This is the one whose absence makes **every other milestone unverifiable**: an
acceptance criterion you cannot run anywhere else is not an acceptance
criterion.

### Milestone 1 — Green means green

**Exit condition:** `bash tool/soak.sh 10` prints `10/10 green`, and a script
that parks the build artefacts proves the baseline is genuinely the cold shape.

A gate that is green because it skipped is worse than a red one, because it
teaches you to trust it.

### Milestone 2 — The gate runs in CI and blocks a merge

**Exit condition:** a pull request with a red gate refuses `gh pr merge`,
naming the check; branch protection lists the three required contexts.

Blocked on **billing**, which is not a code task. The annotation the API
returns is exact: *"The job was not started because your account is locked due
to a billing issue."*

### Milestone 3 — The native side compiles, links and runs on all three

**Exit condition:** the Windows and Linux legs finish green with `verify
baseline` running on them, and the `.dll`/`.so` a consumer loads is produced by
the same lane that checks it.

Nothing has ever been compiled with MSVC. The Windows leg is code written
blind.

### Milestone 4 — The download opens without a warning

**Exit condition:** for the `.dmg`, `codesign --verify --strict` plus `xcrun
stapler validate` plus `spctl -a -t open` all pass on a machine that never saw
the build.

Blocked on a **Developer ID** and notarisation credentials. The mechanism is
written and exercised with a self-signed certificate; what is missing is the
account.

### Milestone 5 — The update closes the loop

**Exit condition:** `bash tool/ci/prove_update.sh --host macos` exits 0
printing, in order: v1's pid, `installed 2.0.0`, a **new** pid, and the new
version answering.

The end-to-end proof **passes today** with same-contract stand-ins: a
throwaway key pair, an https host on loopback with a private CA, an ad hoc
identity. What is left is what only the real thing proves — notarisation, DNS,
and the installed fleet accepting it.

### Milestone 6 — There is somewhere to download from

**Exit condition:** `curl -fsS https://<host>/latest` returns a version, and
for every target the `.tar.gz`, `.sha256` and `.minisig` fetch and verify.

Blocked on a **host** and on **key custody** — both decisions, not code.

### Milestone 7 — A stranger reaches the end alone

**Exit condition:** a script runs, in a clean container with no sibling
checkouts, every ```bash block in `docs/quickstart.md`, in order, and each one
exits 0.

This is the milestone that says the documentation is true rather than
well-intentioned.

## 3. The critical path

The shortest sequence that still reaches the ready condition. Every link is
here because nothing after it can be **proven** without it.

```
m0-toolkit-only (M)          ─ without this no acceptance criterion below runs off this machine
m0-weave-di (M)              ─ without this the generated app resolves nowhere
m1-stderr (S) → m1-lanes (M) → m1-bless-recusa (S)
m1-guards-tabela (S) → m1-fingerprint (M) → m1-baseline-frio (M)
m2-billing (XS, human)       ─ in parallel from day zero
m2-primeiro-passo (XS) → m2-tudo-depois-decide (S) → m2-pr-trigger (XS) → m2-branch-protection (S)
m3-win-suite-carrega (M) → m3-win-tools (S) → m3-msvc-cpp (M) → m3-flutter-build-fixture (L)
m3-baseline-por-so (M)
m4-ferramenta-ausente (S) → m4-require-signature (M) → m4-config-chega (L)
m4-signer-dmg (M) → m4-ship-macos-ordem (S) → m4-verify-command (L)
m4-ci-secrets (L, human)
m5-fmt-contract (M) → m5-ship-tarball (M)
m5-public-key-obrigatoria (M) → m5-chave-uma-fonte (M)
m5-macos-elevacao (L) → m5-relaunch (M) → m5-rollback (L) → m5-orquestrador (L)
m5-e2e-macos (L)
m6-host (M, human) → m6-publish (M) → m6-key-custody (S, human) → m6-key-list (S) → m6-install-sig (L)
```

Three of those links are **latency, not work** — they wait on someone else and
should be started on day zero:

1. **Unlock Actions on the account** — fifteen minutes. It simultaneously
   unblocks the dead runs and branch protection.
2. **Enrol in the Apple Developer Program** and issue the Developer ID.
3. **Organisation validation** for the Authenticode certificate, or a
   subscription to Azure Trusted Signing / DigiCert KeyLocker.

## 4. What this roadmap deliberately does NOT do

This section is worth as much as the rest: an inventory of what was considered
and refused, with the reason. It is what stops the same idea from coming back
every month.

| Not doing | Why |
|---|---|
| **Building the product app in CI** | It pulls four private crates by path. The fix lives in the other repository. |
| **Making the private siblings compile on Linux/Windows** | Same reason: it is the sibling repo's boundary. |
| **Any screen, route or widget** | The product's frontend is written by hand by its author. This roadmap only touches what is below it. |
| **Retry-with-quarantine for flakes** | It makes "green" compatible with "unproven", which is the one pathology the soak script exists to detect. |
| **A second "warm" baseline** | Every test it would protect depends on a built `.app` and the two universal slices, so it would be a baseline that only one machine can reproduce. |
| **A canary workflow on the `-latest` labels** | It burns macOS minutes at 10x, every month, to detect a retirement that is announced in advance anyway. |
| **A versioned manifest compatibility corpus** | It defends a client population of zero: the installed fleet never calls its updater. |
| **`sha256` in the manifest** | The manifest is signed; a hash inside it is controlled by whoever controls the endpoint, so it adds a field and no guarantee. |
| **A Homebrew tap** | A second channel to keep in sync, for an audience that does not exist yet. |
| **A `dovetail` binary for Windows and macOS x64** | `dart compile exe` does not cross-compile; it needs the host. |
| **Self-hosted runners as the main answer** | A self-hosted macOS runner *is* this machine — it reinstates exactly the problem Milestone 0 exists to remove. |
| **Proving `makensis` as a release blocker** | `ship` already defaults to `msi`, so the NSIS path is not on the belt. |
| **`rpm -K` / `dpkg-sig`** | A package-manager GPG chain nobody exercises on a directly downloaded file. |
| **Guard-dominance testing by static analysis** | Answering "is this call dominated by a probe" needs a real analyser, for a class of bug a test already catches. |
| **New coverage for untested behaviour** | This roadmap makes the *existing* gate trustworthy; growing it is separate work. |

One item on that list stopped being true on 2026-09-09: **publishing the
runtime packages to pub.dev** was explicitly out of scope, and the ten packages
are now published. The signed channel remains for the release machine.

## 5. The first task tomorrow morning

**`m0-toolkit-only`** — make `--only toolkit` genuinely apply to `fast`,
`cross` and `all`, and add a CI job that does not need the private siblings.

Because it is the only task whose absence makes **all the others
unverifiable**. And at the same time, start the three things that are latency
rather than work: the billing unlock, the Apple enrolment, and the
Authenticode validation. Every day they wait is a day added to the end,
whatever else gets done in the meantime.
