**English** · [Português](README.pt-BR.md)

# dovetail_updater

> Reads the update manifest and verifies the downloaded artefact — minisign
> signature, trusted comment checked, downgrade refused.

## Corrected: this is not compatibility, it is delivery

This README used to open by saying there were installations in the field
trusting a minisign key baked into `tauri.conf.json`, and that bit-for-bit
compatibility was the project's hard external constraint. **Measured against
production on 2026-09-02, that is not the case.**

`tauri_plugin_updater` was registered in the Tauri app's `main.rs` and
**invoked nowhere** — zero calls in Rust, and the JS package was not even in
the frontend's `package.json`. What the screen received was a notice with a
link. The `sha256` the endpoint returned was consumed by nothing, and
`mandatory` was hard-coded `false`. **There was no signature or hash
verification on the live path.**

That does not invalidate a line of this package — it changes its justification
from *not breaking what exists* to **delivering what never existed**. And the
double base64 layer, described below, stopped being an obligation and became a
choice: kept because it costs nothing and preserves the option of wiring the
plugin up one day.

The signature scheme is the same between Tauri v1 and v2 — only the artefact
packaging changes. So compatibility remains reachable, with one catch that
anyone reimplementing from memory gets wrong.

## The double base64 layer

Neither the `.sig` nor the `pubkey` field is in raw minisign format. Both are
**base64 on top of minisign's standard text**.

Checked against a real key: decoding the base64 gives back

```
untrusted comment: minisign public key: 1234567890ABCDEF
RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
```

And that second line, decoded, is **42 bytes**: algorithm `Ed`, plus a key id
that reversed is precisely what the comment declares. The format is understood
byte by byte, not by analogy.

`MinisignPublicKey.parse` and `MinisignSignature.parse` accept both forms: the
plain text and the text wrapped in base64.

## The proof

**A signature made by the reference `minisign`, verified by this code.** The
test loads a key pair and a signature produced by the official tool, and
requires the verification to pass — and to fail when a single byte of the
payload changes, when the key is a different one, and when the trusted comment
has been edited.

Discovered along the way: modern minisign signs **prehashed** by default. A
real signature starts with `RUQ`, which decodes to `ED`, and the trusted
comment says `hashed`. So verification goes through BLAKE2b-512 before
Ed25519. We support both: `Ed` over the raw message, `ED` over the digest.

## Three things we do that Tauri does not

**We verify the trusted comment.** It carries the timestamp and the file name,
and it is signed — but Tauri's client never checks it. Without that, a valid
signature can be reused for a different file name. A test edits
`file:small.bin` into `file:malware.exe` and requires verification to refuse.

**A downgrade is an error, not the client's choice.** The signature alone does
not prevent a rollback: any older artefact signed with the same key verifies.
In Tauri the defence is a replaceable client-side comparison. Here it is the
policy that refuses, and allowing it means asking on purpose.

**One broken platform block invalidates the manifest for everyone.** That is
Tauri's behaviour and it is right — a malformed block means a release was
published wrong — but the message here says which block and what is missing
from it.

## The manifest

Both formats, told apart by the presence of `platforms`. The key is `OS-ARCH`.
`signature` is the **content** of the `.sig`, and a path or URL there is an
explicit error, because it would be silently unverifiable.

Endpoint variables: `{{current_version}}`, `{{target}}`, `{{arch}}` and
`{{bundle_type}}` — the last one does not appear in Tauri's documentation, only
in its code, and it is what allows serving the right update to whoever
installed a `.deb` versus another format on the same architecture.

An endpoint that is not `https` is refused: **the manifest is not signed**, so
the integrity of the redirection rests entirely on the transport.

## What is missing

- ~~**A Linux installer.**~~ That item was stale: `LinuxInstaller` exists and
  has 18 tests. It reads the format from the artefact's name and does what each
  one asks — `.deb` and `.rpm` go to the package manager through `pkexec` (and
  directly, without asking for authorisation, when the process is already
  root), and an AppImage is replaced in place, with the previous one kept and
  restored if the write fails. What resolves all three is
  `InstallerForHost.resolve`, which **refuses by name** the system that has no
  installer, instead of downloading and verifying an update it does not know
  how to apply.
- **Running on Windows.** `WindowsInstaller` has never executed a real
  installer; what is proven is which executable it calls and with which
  arguments.

## Which installer runs here

`InstallerForHost.resolve` picks by the running system and **refuses** a host
with no installer, rather than returning null. A client that downloads, checks
the signature and only then discovers it cannot apply it has already told the
user there is a new version.

On macOS it resolves the path to the bundle: `Platform.resolvedExecutable`
points inside the `.app`, and replacing only that file leaves a bundle whose
seal no longer matches its contents. On Linux the path comes from `APPIMAGE` —
a `.deb` or `.rpm` is replaced by the package manager and needs no path at all.

## Applying on Linux

`LinuxInstaller` separates the two cases Linux has. An `.AppImage` is a single
file: the installer renames the running one to `.previous`, writes the new one
in its place, marks it executable and only then deletes the previous — if the
write fails, the previous one comes back and the installation stays standing. A
`.deb` or `.rpm` goes to the package manager through `pkexec`, which is what
asks for authorisation; `rpm --upgrade --replacepkgs`, because `-U` exits 2
when the version is already installed, which is exactly the case of repeating a
half-finished update.

What has not been proven on a Linux machine: whether `dpkg`/`rpm` actually
accept the package, and whether `pkexec` exits 126 when the dialog is dismissed
and 127 with no session bus. Command assembly and the AppImage swap are proven
here.

## The end-to-end flow

`UpdateFlow` ties the three stages together — `check`, `download`, `install` —
and it is what a client actually calls. `test/update_flow_test.dart` covers the
whole path with a fake `ScriptedFetcher`.

**`check`** queries a list of endpoints in order and stops at the first that
answers. An endpoint returning `204` is read as "no update" and the query
**stops there** — it does not try the next one. An endpoint that is down or
returns an error status (say `500`) makes the flow fall through to the next. If
all of them fail, the error says "every update endpoint failed" and carries the
last one's reason. With no endpoint configured at all, `check` refuses.

**`download`** fetches the artefact the manifest points at, reports progress
through `onProgress`, and **only returns a `VerifiedArtifact`** — meaning the
artefact has already passed minisign verification. One altered byte in the
payload is refused with "does not match its signature", and an artefact the
server does not serve (say a `404`) is refused too.

**`install`** hands the verified artefact to the platform's installer. On macOS
the real test swaps the bundle: it creates a `.app` with a `version.txt`,
packages a new one as `tar.gz`, installs it and checks the file became
`2.0.0`. An archive with no bundle is refused with "Nothing was replaced" and
the old bundle stays intact, and nothing is left over after the swap — the
`.previous` is deleted.

## The writing side: `ManifestWriter`

The package does not only read the manifest — it also **writes** it, and
`test/manifest_writer_test.dart` guarantees that what comes out is exactly what
the parser accepts back (a round trip).

The parser's rules apply on the way out too, and they are refused rather than
silenced:

- a version the client cannot parse (say `banana`) is refused, with the warning
  that it would produce "no update ever arriving";
- the same `platformKey` twice is refused, not overwritten — no "silently
  replace";
- an empty signature is refused;
- an `http` URL (no TLS) is refused, because the manifest is not signed and its
  integrity rests on the transport;
- no platforms at all is refused;
- something that is not a minisign signature (say a path like
  `dist/app.dmg.minisig`) is refused with "not a minisign signature".

Format details: a blank `notes` does not become a field, the output is
deterministic byte for byte, and it ends in a newline, like a file on disk. The
signature is written **base64 on top of the minisign text** — and if it arrives
already wrapped, it is not wrapped again.

## `pub_date`: strict publication date

`test/pub_date_test.dart` proves the parsing of `pub_date`. A real date passes,
absence stays `null`, and what is not a date is **refused**, not read as absent
— a typo does not silently remove the publication date. Out-of-range fields
(month 13, the 30th of February) are refused rather than rolled over into a
plausible date, and a valid leap day is accepted. A date-only value (no time)
passes as well.

## `PlatformKey`: the six targets and the real architecture

`test/platform_key_arch_test.dart` proves how the package decides which
artefact to ask for. The architecture comes from the ABI the VM reports —
`macos_arm64` → `arm64`, `windows_x64` → `x64`, `linux_arm64` → `arm64`. A
string it cannot read is refused, because the previous fallback to `x64`
downloaded an x86 artefact on an arm machine and reported success. The six
targets — 3 systems × 2 architectures — have distinct wire names
(`darwin-aarch64`, `windows-x86_64`, `linux-aarch64`, and so on), and an
architecture with no name in the protocol is refused.

## The real fetcher: HTTPS over loopback TLS

`test/http_artifact_fetcher_test.dart` exercises the real `HttpArtifactFetcher`
against a loopback TLS server built with `openssl`, instead of a fake. It is
the proof that a real download respects the HTTPS transport and reports
progress — the rest of the flow uses `ScriptedFetcher` precisely to isolate the
logic from the network.
