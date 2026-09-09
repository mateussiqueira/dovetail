**English** · [Português](README.pt-BR.md)

# dovetail_signer

> Signs and notarises what the build already produced. Runs **after** the
> build, never inside it — and packages nothing.

## Why this is a separate package from the bundler

The rule "signing runs after the build" is only real if the bundler **cannot**
sign. In the same package, someone wires one into the other in six months and
the coupling is back — which is exactly what ties an installer to
`cargo tauri build` today.

`dovetail_bundler` does not depend on this package. It has no way to sign.

## The policy is the product here

The failures the Tauri survey found are not tool failures, they are **policy**
failures: warning where it should have stopped. Each one became a test.

| In Tauri | Here |
|---|---|
| a key that does not match the public one → warning, the build passes, a release nobody accepts | a **half-complete credential set is a fatal error**, even in a local build |
| `CI=true` with no password → silently assumes an empty password | an undefined password is an **error**; an empty password only if explicitly set |
| incomplete notarisation credentials → warning, delivers an un-notarised app | a fatal error, naming every missing variable |
| `codesign` without `--timestamp` → "sometimes yes, sometimes no" | `--timestamp` on **every** call |
| no `timestampUrl` → `signtool` runs without a timestamp | absence is an **error**, and there is no default |
| one `entitlements.plist` for everything, daemon included | entitlements per path, and never on a framework or a dylib |
| `TAURI_SKIP_SIDECAR_SIGNATURE_CHECK` skips signing entirely | an empty file list is an **error**, not silent success |

And the inverse is policy too: **a local build does not ask for a
certificate**. With no secret, the artefact is left unsigned and the output
says so. With `--require-signature`, which only the pipeline passes, the same
case becomes an error.

## macOS

Inside out, item by item, with `xattr -crs` first — Tauri cites Apple's QA1940
for that. Never `--deep`.

It orders the targets by depth and signs the bundle **last**. Only direct
children of the nested-code folders (`MacOS`, `Frameworks`, `PlugIns`,
`Helpers`, `XPCServices`, `Libraries`), recursing into an embedded `.app`.

Notarisation: `ditto -c -k --keepParent --sequesterRsrc` — not `zip`, because
Tauri's own comment records that this removes almost every false alarm — then
`notarytool submit --wait`, and `stapler staple` only if the status is
`Accepted`.

The `.dmg` is the second seal. `MacosSigner.signFile` signs the image as a flat
file — identity and timestamp, no hardened runtime and no entitlements, which
belong to the code inside it — and `Notarizer.notarizeFile` submits it
directly, without `ditto`, stapling the ticket to the image itself: that is
what the user downloads and what Gatekeeper evaluates on mount. Through the
CLI, `--target macos --file x.dmg [--notarize]`; the `.app` is still
`--bundle`, and the two never in the same call.

## Windows

`signtool sign /fd sha256 /sha1 <thumbprint> /tr <url> /td sha256 <file>`. The
certificate by thumbprint, never a `.pfx` on the command line: it assumes the
certificate is already in the machine's store, which is what the pipeline does
by importing it first.

## Linux

There is no gate. A published `SHA256SUMS`, and the test verifies it with the
system's `shasum -c` — including that a tampered artefact **fails**
verification.

## The proof

What is worth most here is not the count: **this package signs a real `.app`
that the repository actually builds**, inside out, with an ad hoc identity, and
requires the system's `codesign --verify --deep --strict` to accept it. With no
certificate at all.

That test found a real bug: the first version tried to sign **every file**
inside `Frameworks/`, asset directories included
(`App.framework/.../a_design_system/assets/icons/nav`), and `codesign` refuses
with "bundle format unrecognized". You sign the framework's bundle, not its
contents.

## Usage

```bash
dart run dovetail_signer --target macos --bundle build/macos/.../App.app --notarize
```

```bash
dart run dovetail_signer --target windows --file dist/app.exe --file dist/helper.exe --require-signature
```

```bash
dart run dovetail_signer --target linux --file dist/app.deb --out-dir dist
```

## What is missing

- **A detached GPG signature** for `SHA256SUMS` on Linux.
- **A temporary keychain** on a macOS runner, from a base64 certificate.
- ~~**Ordering on Windows**~~ — solved in the pipeline, which is where
  ordering lives. `ship` on Windows emits **two** signatures:
  `sign --directory` over the payload before `bundle`, and `sign --file` over
  the installer afterwards. Signing only the installer produces a file that
  passes SmartScreen and then drops unsigned executables onto the disk of
  whoever installed it — worse than not signing, because it looks right. On
  macOS there are two as well, for a different reason: the `.app` inside out
  (the seal covers the contents) and then the `.dmg`, because Gatekeeper
  evaluates the image on mount and the notarisation is the image's too. Linux
  signs no binary at all.

  What still does not exist is the package **refusing** an installer with an
  unsigned payload on its own: checking that means opening the installer, and
  no machine here runs Windows to prove the reading is right.
