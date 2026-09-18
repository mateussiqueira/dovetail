**English** · [Português](pt-BR/release-channel.md)

# The release channel, end to end

This document answers one question: **what has to be true before `dovetail ship`
may hand an artefact to somebody who is not on the team.** It is written from
what was measured on this tree, not from what the commands promise.

The internal channel is the other half — a debug build, ad-hoc signed, no
manifest, an installer that can put the declared privileged component in place.
Everything below is about `--channel release`, the default.

## What the channel requires

| requirement | where it lives | what it buys |
|---|---|---|
| a Developer ID identity | `sign.macos.identity-env` (default `DOVETAIL_MACOS_IDENTITY`), or `APPLE_SIGNING_IDENTITY` | a signature Gatekeeper will evaluate, and the Team ID `SMAppService` demands |
| notarisation credentials | `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`, or `APPLE_API_KEY_ID` + `APPLE_API_ISSUER` + `APPLE_API_KEY_PATH` | a ticket the machine that never saw the build can staple and trust |
| a Windows signing certificate | `sign.windows.certificate-env` (default `DOVETAIL_WINDOWS_CERTIFICATE`), or `WINDOWS_CERTIFICATE_FILE` / `WINDOWS_CERTIFICATE_THUMBPRINT` | an installer, and a payload inside it, that SmartScreen does not scare the user about |
| a timestamp server | `sign.windows.timestamp-url` or `WINDOWS_TIMESTAMP_URL` | a signature that survives the day the certificate expires |
| the minisign **secret** key | `update.key`, on the release machine | a manifest the installed clients accept |
| the minisign **public** key | `update.public-key` | the check that the secret key is the one the shipped app already trusts |
| an https host | `update.base-url` / `update.endpoint` | a transport the updater will speak |
| a version | `version:` in `pubspec.yaml` | monotonicity, and the `release` step |

None of these is code. Each one is a value on the release machine — and every
one the toolkit cannot see is a value it must refuse to invent.

## The ordered steps `ship` builds

`dovetail ship` is a planner: it reads `dovetail.yaml`, prints the steps, and
re-dispatches each one through the CLI itself. The order is the contract.

macOS (release):

```
build macos          flutter build --release, with the update endpoint and public key embedded
sign darwin-universal  codesign the .app inside out (--require-signature --notarize when notarize: true)
bundle darwin-universal  the .dmg the user downloads
sign dmg darwin-universal  codesign the flat .dmg, then notarise and staple it
archive darwin-universal   the .app.tar.gz the updater installs
release <version>          minisign each artefact, write dist/latest.json
```

Windows (release): `build` → `sign payload` (every `.exe`/`.dll` under the
output) → `bundle` → `sign` (the installer). The payload is signed before the
installer wraps it: an installer that passes SmartScreen and then drops
unsigned executables is worse than none, because it looks right.

Linux: `bundle` → `sign`, which writes a `SHA256SUMS` — no identity.

## What is refused before the build, and why

The build is the slow half: `flutter build --release`, `codesign` over the
bundle, `hdiutil`. Every check below runs from the config and the environment in
milliseconds, in `--dry-run` too. A green dry-run over a plan whose last step
refuses is the most expensive lie the command could tell.

```
$ dovetail ship --dry-run
→ build macos
→ sign darwin-universal
→ bundle darwin-universal
→ sign dmg darwin-universal
→ archive darwin-universal
→ release 1.0.0

ship: sign.macos.notarize is true, and neither DOVETAIL_MACOS_IDENTITY nor APPLE_SIGNING_IDENTITY is exported — the sign step would refuse after the build. ...
ship: sign.macos.notarize is true, and no notarisation credential group is complete: APPLE_ID + APPLE_PASSWORD + APPLE_TEAM_ID, or APPLE_API_KEY_ID + APPLE_API_ISSUER + APPLE_API_KEY_PATH. ...
Nothing ran. These are checked from the config, before the build, because the build is the slow half.
$ echo $?
1
```

That much was already true for notarisation. Three more checks were added so
that the question "can this project release?" is answered honestly, and the
same verdict comes from `ship` and from `doctor`:

| what | before | now |
|---|---|---|
| the update **secret** key is not on disk | `ship --dry-run` planned every step, exit 0; the `release` step died last, after the whole build | refused before the build, naming the resolved path |
| the update key has a password, and `update.password-env` is not exported | same late death | refused before the build, naming the variable |
| `sign.windows` is declared and no certificate is present | `sign` printed "the artefact stays unsigned" and exited 0 | the release channel refuses before the build, and the Windows signing steps carry `--require-signature` as a second line of defence |
| `sign.windows` is declared, certificate present, no timestamp | `sign` would refuse "half configured" after the build | refused before the build |

The secret key is the sharpest of the four: it is the half of the pair that
signs. Losing it means no installed client accepts an update again, and it
cannot be reissued without shipping a new installer to every machine.

## What the toolkit does with a credential it does not have

It stops, and says exactly what is missing. It does **not** fall back to an
ad-hoc signature, a self-signed certificate, a placeholder, or a manifest with
an empty signature. `--ad-hoc` exists, but only the internal channel passes it,
and it says out loud that there is no Team ID — which is why the internal
channel cannot register a bundled `SMAppService` daemon.

Concretely, with no Developer ID:

- `dovetail ship --dry-run` exits 1 with the two macOS lines above, before the
  build;
- `dovetail doctor --channel release` prints `missing signing` and exits 2;
- `dovetail sign` without an identity prints, verbatim, `Developer ID signing
  identity: no credentials, so the artefact stays unsigned. Missing
  APPLE_SIGNING_IDENTITY.` on macOS and `Authenticode signing without a Windows
  machine: no credentials, so the artefact stays unsigned. Missing
  WINDOWS_CERTIFICATE_FILE, WINDOWS_TIMESTAMP_URL.` on the cross-host Windows
  path, and exits 0 — which is exactly what makes the pre-build refusal in
  `ship` necessary rather than decorative: on its own, a release would go green
  on an unsigned artefact.

## What the updater does, and what it refuses

The updater is the consumer of everything `release` produces. Its path is
`check` → `download` → `install`, and the trust boundary is between the second
and the third.

- **Download.** `HttpArtifactFetcher` refuses any scheme that is not `https`,
  follows redirects by hand (so an https→http redirect is refused, not
  silently taken), and enforces a 512 MiB ceiling from the declared length and
  mid-stream.
- **Verify.** `MinisignVerifier` is Ed25519, with BLAKE2b-512 prehashing for the
  `ED` algorithm. It checks three things, in order: the key id is the one the
  app trusts; the payload signature covers the bytes; and the trusted comment
  is bound to the signature. Only then does a `VerifiedArtifact` exist.
- **Install.** By host: macOS extracts the `.app.tar.gz` and swaps the bundle;
  Windows runs `msiexec /i` (or a detached NSIS `.exe`); Linux swaps the
  AppImage or runs `pkexec dpkg`/`rpm`.

There is **no SHA256 field** in the manifest, and the manifest is **not
signed** — only each artefact is. The manifest's integrity is the HTTPS
transport; the artefact's integrity is the signature. That is a deliberate
shape, not an oversight, but it is what makes the host decision a security
decision rather than a hosting decision.

What happens when it fails is measured, not described. Building a throwaway
pair, signing an artefact, serving it over a private CA and asking `probe` (the
same parser and verifier the app uses):

```
# the valid case
ok     darwin-universal  the artefact downloads — 38 bytes
ok     darwin-universal  the artefact verifies — the bytes served are the bytes signed
probe: ok — this endpoint serves what the client reads

# one byte flipped in the artefact
FAILED darwin-universal  the artefact verifies — the signature does not cover what the url serves: the artefact does not match its signature.
Nothing is installed. The download was altered or truncated.. Every install would refuse it.

# the manifest's url rewritten to http
Only https carries an update.

# the manifest's signature field replaced with garbage
FAILED darwin-universal  the signature field decodes — it is not base64. ...
```

In every failure the installer never runs. The failure type is `UpdateFailure`
(message + remedy) or `DowngradeRefused`; nothing reaches disk.

## `doctor` answers the same question before the build

`dovetail doctor --channel release` reads `dovetail.yaml`, the environment and
the disk, and returns exit 2 when something it can see would make the release
step refuse:

```
$ dovetail doctor
project
  ok       identifier  com.example.demo
  ok       name  Demo by Demo Inc
  ok       version  1.0.0  (from pubspec)
  ok       targets  darwin-aarch64, darwin-x86_64 on this host of 2
  missing  update  the signing key keys/missing.key is not on disk (...), and the release step signs the artefacts with it at the end of the run — ...
  ok       signing  DOVETAIL_MACOS_IDENTITY, not notarised
  off      service  no privileged component is declared, on any platform
$ echo $?
2
```

`doctor` and `ship` must never disagree about what can ship; each new check in
one is mirrored in the other, and a test pins both. `doctor --channel internal`
answers the internal question, including the one combination `ship` refuses
outright: an internal build of a project that declares `update:`.

## The proof, and its limits

Run on this machine:

- `bash tool/ci/prove_update.sh --host macos` — the whole release loop with
  stand-ins for the three things that do not exist here (throwaway key,
  loopback https host with a private CA, the ad-hoc identity). It needs a
  Release `.app` already built in a product, so it does not run in this
  toolkit-only repository.
- `dart test` in `toolkit/dovetail_cli` (548 passed, 11 skipped) and in
  `toolkit/dovetail_updater` (167 passed).
- The `probe` transcript above.

What it does **not** prove, and only the real account can:

- Gatekeeper accepting the download (`spctl -a -t open` on a machine that never
  saw the build) — needs the real Developer ID and notarisation, not a
  stand-in;
- the installed fleet accepting the update — the manifest is signed with the
  production key, and that key is a custody decision, not code;
- DNS and CDN behaviour;
- anything compiled with MSVC, and any hosted CI run — the account that owns
  this repository has never executed a workflow.

## The day of the real release: swap values, not code

| what | where |
|---|---|
| production minisign key | `update.key` and `update.public-key` (move the staging pair out of the way first; `keygen` refuses to overwrite) |
| host | `update.base-url`, `update.endpoint` |
| Developer ID | `APPLE_SIGNING_IDENTITY` (or the variable `sign.macos.identity-env` names) and `sign.macos.notarize: true` |
| notarisation | the `APPLE_*` group |
| Windows certificate | the variable `sign.windows.certificate-env` names, plus `WINDOWS_TIMESTAMP_URL` |

With `notarize: true` and no credentials, both `ship --dry-run` and `doctor`
refuse before the build, naming exactly the variables above — and that is the
list they name.

## Known gaps in the channel itself

Recorded so nobody re-derives them:

- the manifest is not signed (HTTPS is its integrity);
- the manifest carries no size or hash field, so there is no declared-vs-actual
  cross-check;
- the updater does not cross-check the artefact's filename against the platform
  key it was requested for — a wrong-but-signed artefact verifies and fails
  later, in the installer;
- macOS extraction relies on the system `tar` and is not path-traversal
  hardened;
- there is no notarisation-like opt-in for Windows: the release channel now
  requires a certificate whenever `sign.windows` is declared, and the internal
  channel is the escape hatch for an unsigned tester build.
