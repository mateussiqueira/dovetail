**English** · [Português](pt-BR/configuracao.md)

# `dovetail.yaml`, key by key

One file, at the root of the project. `dovetail init` writes it, deducing what
it can, and the entire pipeline comes out of it.

This document is checked by a test: every key the parser reads has to appear
here, and a documented key the parser does not know also fails. See
`toolkit/dovetail_cli/test/config_documented_test.dart`.

---

## The minimum that runs

```yaml
identifier: com.example.demo
name: Demo
manufacturer: Example Ltd
targets:
  - darwin-aarch64
  - windows-x86_64
```

**There is no version key.** It lives in `pubspec.yaml` and is read from
there, without the `+build`. Duplicating it would only create two places to
disagree.

**No identity is written here**, only the name of the environment variable
that carries it — and that is why this file can be committed.

---

## Identity

### `identifier`

A reverse-domain name: `com.example.demo`. It is not decoration — the **single
instance** and the **deep link** anchor on it, and polkit names the policy file
after its namespace.

`init` deduces it from `AppInfo.xcconfig`, never from `RunnerTests` — which is
the only `PRODUCT_BUNDLE_IDENTIFIER` in a freshly created `project.pbxproj`.
When the platforms declare different identifiers, it **reports both** instead
of choosing silently: diverging there is a defect.

### `name`

The name a user sees: window title, dmg volume name, menu entry. Deduced from
`pubspec.yaml`.

### `manufacturer`

Who publishes it. It goes into the MSI (which requires a manufacturer), the
`.deb`'s `Maintainer` field, the `.rpm`'s `Vendor`, and polkit's `vendor` when
the service section does not declare its own.

### `targets`

The publication matrix, as `system-architecture` pairs:

```yaml
targets: [darwin-aarch64, darwin-x86_64, windows-x86_64, linux-x86_64]
```

Validated against **the update manifest's own vocabulary**. A key the client
never asks for is a release nobody can see, and `darwin-arm64` is exactly that
mistake: `arm64` is how Apple and WiX spell it, `aarch64` is how the protocol
spells it.

On macOS the two architectures become **one** universal bundle, published under
`darwin-universal` — the key `releaseFor` resolves when a client asks for
`darwin-aarch64`. And targets belonging to another system are set aside: a host
whose share of the matrix lives elsewhere exits 0 doing nothing, because that
is a runner with no work, not an error.

---

## `update`

The section that makes `ship` sign and write the manifest. Without it, `ship`
stops after packaging.

```yaml
update:
  key: keys/update.key
  password-env: DOVETAIL_UPDATE_KEY_PASSWORD
  base-url: https://cdn.example.com/releases
  manifest: dist/latest.json
  endpoint: https://api.example.com/desktop-version/check/{{target}}
  public-key: |
    untrusted comment: minisign public key 1234567890ABCDEF
    RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
  unencrypted: false
```

### `key`

Path to the minisign private key. `dovetail keygen` creates it and **refuses to
overwrite an existing pair**, because losing the private key is not losing a
file: it is losing the update path for every installation in the field, and the
recovery is reinstalling on each machine.

It warns when the destination is not in `.gitignore`.

### `password-env`

The **name** of the environment variable that carries the key's password, never
the password. An unexported variable is a refusal naming that variable — never
an assumed empty password.

### `unencrypted`

`true` for a pair generated with `-W`, without a password. A key with no
password is acceptable in development and not in a release, and calling a key
that has a password unencrypted fails loudly in real `minisign`.

### `base-url`

Where the artefacts will live. `release` composes each URL as
`<base-url>/<version>/<file>` — so `--artifact key=path` is enough, without
repeating the URL for each one.

`ship` **refuses before the build** when the section exists without a
`base-url`: spending a whole compilation to fail at the last step is the waste
that refusal exists to prevent.

### `manifest`

Where to write `latest.json`.

### `endpoint`

Where the **installed app** asks for the manifest — with the placeholders the
updater resolves (`{{target}}`, `{{arch}}`, `{{current_version}}`). It has to
be https. It is not the `base-url`: that one is where artefacts are downloaded
from; this one is who answers with the `latest.json`. It lives here so that
`dovetail build` can embed it in the app along with the key: a staging build
points at a staging host by changing this file, not the app.

### `public-key`

The matching public key, **the key itself — not a path**. It is mandatory when
an `update` section exists. `dovetail build` embeds it in the app as
`--dart-define=dovetail.update.public_key` (single-line base64, the form
`keygen` prints), along with `dovetail.update.endpoint`,
`dovetail.update.base_url`, `dovetail.identifier` and `dovetail.version` (from
`pubspec.yaml`) — and it says what it embedded. One file decides who the app
trusts, what `release` signs with, and what `probe` verifies.

It is deliberately not a path: `keys/` is gitignored, so a path would point at
a file that does not exist in a clone, and the check that matters most would
depend on whoever cloned having the key. The public key is public by
definition; it is the secret one that stays out.

And it is mandatory because, while it was not, it was the easiest check to turn
off: you simply did not write the line. That is how a release once went out
signed with a development key that the app — compiled to trust another one —
refuses. A development key with a production address is the combination that
produces a publishable, useless artefact.

It is **two lines** — the comment and the key — so in YAML it goes in a `|`
block, as in the example above. The single-line alternative is the base64 Tauri
keeps in `tauri.conf.json`, which is also accepted; the key on its own, without
the comment, is **not**. On the command line, `dovetail release --public-key
<file or key>` plays the same role for anyone without a `dovetail.yaml`.

---

## `sign`

```yaml
sign:
  macos:
    identity-env: DOVETAIL_MACOS_IDENTITY
    entitlements: macos/Runner/Release.entitlements
    notarize: false
  windows:
    certificate-env: DOVETAIL_WINDOWS_CERTIFICATE
    password-env: DOVETAIL_WINDOWS_CERTIFICATE_PASSWORD
    timestamp-url: http://timestamp.digicert.com
```

With no credential, the signing step **says the artefact is left unsigned** and
carries on, instead of pretending — except with `notarize: true`, which is
declaring a real release: then `ship` demands signature and notarisation, and
refuses **before the build** whatever is missing.

### `sign.macos`

Apple's signing block: `identity-env`, `entitlements` and `notarize`.

#### `macos.identity-env`

Name of the variable holding the Developer ID. `sign` reads that variable, or
`APPLE_SIGNING_IDENTITY`, which always applies and wins when both exist (empty
counts as absent — a secret that does not exist in CI becomes an empty string).
With neither, the artefact goes out unsigned, with the reason said out loud.

#### `macos.entitlements`

Path to the app's `.entitlements`, which `ship` forwards to the `.app`'s
signing step (never to the `.dmg`'s: entitlements belong to code, not to an
image). Omitted, `sign` applies the plist the Xcode project signs in Release —
the `CODE_SIGN_ENTITLEMENTS` from `macos/Runner.xcodeproj/project.pbxproj`,
with `macos/Runner/Release.entitlements` as the fallback — and prints which.
This is not a detail: `codesign --force` without `--entitlements` replaces
Xcode's signature and erases the entitlements the build had, `app-sandbox`
included; and it is what removes the `get-task-allow` Xcode leaves in Release
and that notarisation rejects. A bundle with a nested binary may need different
entitlements per relative path — that is what `sign --entitlements-for` is for.

#### `macos.notarize`

`true` is declaring a real release. `ship` passes `--require-signature
--notarize` to **both** macOS steps — the `.app` first, so the ticket is
stapled to it (whoever drags the app out of the image opens an app with a
ticket, even offline), and the `.dmg` afterwards, because that is what gets
downloaded and what Gatekeeper evaluates on mount. And it refuses **before the
build**, in `--dry-run` too, if the identity is not exported or no credential
group is complete: `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`, or
`APPLE_API_KEY_ID` + `APPLE_API_ISSUER` + `APPLE_API_KEY_PATH`. `doctor` says
the same thing, as `missing signing`.

`false`, which is what `init` writes, keeps a local build working: with no
credential, the step says the artefact is left unsigned and carries on. In a
standalone `sign`, `--notarize` without credentials says nothing was submitted;
with `--require-signature` alongside, it refuses.

### `sign.windows`

The Authenticode block: `certificate-env`, `password-env` and `timestamp-url`.
The two named variables feed `WINDOWS_CERTIFICATE_FILE` and
`WINDOWS_CERTIFICATE_PASSWORD`, which the signer reads, when those are not
defined; the yaml's `timestamp-url` applies when `WINDOWS_TIMESTAMP_URL` is
not. The MSI's UpgradeCode is not configurable: it is derived from the
`identifier` (UUID v5), stable across releases — changing the identifier is
changing product, and for Windows Installer too.

#### `windows.certificate-env`

Name of the variable holding the path to the `.pfx`/`.p12`. A certificate in a
file is signed by `osslsigncode` on **any** host, Windows included; `signtool`
only comes in when the certificate is in the machine's store, pointed at by
`WINDOWS_CERTIFICATE_THUMBPRINT` with no file at all — and that variable has no
key in the yaml. The yaml's `timestamp-url` is only applied when there is a
certificate to stamp; on its own it would make a local build with no
certificate be refused as half-configured.

#### `windows.password-env`

Name of the variable holding the certificate's password.

#### `windows.timestamp-url`

An RFC3161 server. **There is no default here, on purpose:** a signature
without a timestamp stops being valid the day the certificate expires, and
choosing a server on the user's behalf is choosing who they depend on.

---

## `service`

The privileged helper. Without it there is no kill switch, and no package used
to install one: the systemd unit, the polkit policy and the maintenance scripts
existed and the packaging command could not reach them.

```yaml
service:
  name: demo-helper.service
  description: Privileged helper for the tunnel
  exec-start: /usr/lib/demo/demo-helper
  capabilities: [CAP_NET_ADMIN]
  runtime-directory: demo
  state-directory: demo
  logs-directory: demo
  purge-paths: [/var/lib/demo]
  polkit:
    action: com.example.demo.manage
    vendor: Example Ltd
    description: Manage the connection
    message: Authentication is required to change the connection
```

Declaring this section **refuses the AppImage format**: an AppImage installs
nothing, so there is no unit, no helper and no kill switch — and what comes out
is not a degraded product, it is a window that cannot connect.

### `name`, `description`, `exec-start`

The unit file's name, what shows up in `systemctl status`, and the binary that
comes up.

### `capabilities`

They go into `CapabilityBoundingSet` **and** `AmbientCapabilities`. An ambient
capability outside the bounding set is discarded silently, and the helper comes
up without the privilege it needs — a failure that only appears on the first
connection.

### `runtime-directory`, `state-directory`, `logs-directory`

They become `RuntimeDirectory=`, `StateDirectory=` and `LogsDirectory=`.
systemd creates and cleans each one with the right owner, which is less
installation code than creating them by hand.

Each accepts a name, or a name with a permission:

```yaml
service:
  state-directory:
    name: demo
    mode: '0700'
```

`mode` is `0750` when unstated. An **absolute** path here is refused: systemd
reads these names as relative to `/run`, `/var/lib` and `/var/log`, so an
absolute one is a directory nothing creates.

### `purge-paths`

What the `.deb`'s `postrm --purge` and the `.rpm`'s `%postun` delete.
Uninstalling without purging leaves state behind; purging has to delete, and
deleting an undeclared path is what nobody wants an uninstaller to do.

### `service.polkit`

The authorisation policy. Without it the helper exists and nothing can ask it
to act — `action`, `vendor`, `description` and `message`.

#### `polkit.action`

The action has to live **inside the `identifier`'s namespace**, because polkit
names the file after the namespace and **ignores an action declared outside
it** — which fails as "it asked for a password and did nothing".

#### `polkit.vendor`, `polkit.description`, `polkit.message`

Who signs the policy, the action's label, and the sentence the authentication
dialog shows. `message` is the text a person reads before typing an
administrator password; it is worth writing.

---

## What `init` deduces, and what it does not invent

It reads the `macos/`, `windows/` and `linux/` directories that exist to build
`targets`, `AppInfo.xcconfig` for the `identifier`, and `pubspec.yaml` for the
`name`. It does not invent `update`, `sign` or `service`: all three depend on a
decision — where the key lives, whose the certificate is, whether a helper
exists — and an invented value there is worse than an absent field.
