**English** · [Português](README.pt-BR.md)

# dovetail_cli

One entry point for the toolkit. What existed out there were loose pieces —
`window_manager`, `tray_manager`, `hotkey_manager`, `auto_updater`, Fastforge —
each from a different author, each with its own configuration. What Tauri has
and Flutter did not is the **single file** and the CLI that reads it.

## `ship`: the whole pipeline, from the config

```bash
dovetail ship --dry-run
```

```
→ build macos
→ sign darwin-universal
→ bundle darwin-universal
→ sign dmg darwin-universal
→ archive darwin-universal
→ release 4.2.0
```

The plan is **data**, not execution — which is why `--dry-run` comes for free
and the command is testable without touching any toolchain. The plan's tests
call neither Flutter, nor `wixl`, nor `codesign`. And whatever the plan already
knows the last step will refuse — a missing `update.public-key`,
`notarize: true` with no identity or credentials exported — it refuses before
the build, in `--dry-run` included.

Three decisions it makes that are worth knowing. On macOS the declared
architectures become **one** universal bundle, published under
`darwin-universal` — the key `releaseFor` resolves when a client asks for
`darwin-aarch64`. On Linux and Windows it is one package per architecture,
because a `.deb` carries only one.

And on macOS there are **two signatures**: the `.app` before packaging,
because a dmg wrapping an unsigned `.app` does not become signed by signing
the dmg afterwards; and the `.dmg` after it is built, because that is what the
user downloads and what Gatekeeper evaluates — and it is the one you notarise.
On Windows and Linux what gets signed is the installer, so the bundle comes
first.

Each artefact's name is not guessed: the plan asks the bundler that will write
it. While it was guessing, the dmg came out as `app_1.0.0_universal.dmg` and
the manifest pointed at `app_1.0.0.dmg` — a file that did not exist.

Targets belonging to another system are set aside. A host whose share of the
matrix lives elsewhere exits 0 doing nothing, because it is a runner with no
work this round, not an error.

Writing this caught five of my own defects, and how each showed up is worth
saying. Two through `--dry-run`, before anything ran: macOS packaged twice into
the same output file, and the architecture went in the wire spelling
(`aarch64`) where `bundle` only accepts Apple's (`arm64`). Three only by
actually running against a real app: `app-dir` pointed at the directory above
the `.app`, the signature came after the dmg, and the predicted name was not
the name the bundler wrote.

## Installing

```bash
dart pub global activate dovetail_cli
```

```bash
$ dovetail --version
dovetail 0.1.0 (macos-arm64, dart 3.12.2)
```

To build the self-contained binary from source instead:

```bash
tool/build_release.sh --install
```

That compiles and leaves the binary in `~/.local/bin`, warning if the
directory is not on the `PATH`. A different path goes as the second argument.

Neither route asks for notarisation or goes through Gatekeeper: a locally
compiled binary does not arrive quarantined. That only matters again when the
file comes over the network.

## Distribution: one binary, no source

The CLI compiles to a self-contained native executable.
`tool/build_release.sh` produces the binary, the tarball and the SHA256, and
refuses to publish if the binary does not report the version `pubspec.yaml`
declares.

```bash
tool/build_release.sh dist
```

What the binary carries compiled in: `dovetail_bundler`, `dovetail_signer`,
`dovetail_updater`, `dovetail_process_runner` and the CLI itself — as machine
code. There is no recoverable Dart source in it. String literals remain, as in
any AOT build: tool names, error messages and the `.wxs` and `.nsi` template
fragments. Those fragments are the command's output anyway, so they are not a
secret the binary keeps.

`tool/dovetail.rb` is the Homebrew formula. It exists because half the problem
of installing is not the binary: it is the `minisign`, the `msitools`, the
`osslsigncode` and the `rpm` the CLI invokes. The formula declares them as
dependencies, and the `caveats` names the two it deliberately does not install
— `flutter`, which you already have, and `makensis`, which you only miss if
you want the NSIS installer alongside the MSI.

**What the binary does not cover.** The runtime packages —
`dovetail_platform_channel`, `dovetail_shortcut_channel`, `dovetail_updater`
and the `dovetail` umbrella — are compiled *inside* the consumer's app. Dart
has no binary format for a pub dependency: a package with no `lib/*.dart`
cannot be imported. Whoever uses the window, the tray, the panel or the
shortcut needs those packages' source; whoever uses only the build, packaging,
signing and publishing pipeline needs none of them.

## The release channel and the installer

The runtime travels in a versioned SDK, served by a channel:

```
<base>/latest                                           → the newest version
<base>/<version>/dovetail-sdk-<version>-<os>-<arch>.tar.gz
<base>/<version>/dovetail-sdk-<version>-<os>-<arch>.tar.gz.sha256
```

The curl|sh path is `tool/sdk/install.sh`:

```bash
curl -fsSL https://<host>/install.sh | sh
```

And the same work exists from inside the binary, for whoever already has it:

```bash
dovetail self-install --base-url https://<host>   # installs the SDK for the binary's version
dovetail self-update  --base-url https://<host>   # switches to the channel's latest
```

The base comes from `--base-url` or from `DOVETAIL_INSTALL_URL`; without
either, the command refuses naming both — an installer that guesses the host
installs whatever the host decides. The download goes over TLS (the updater's
fetcher refuses http) and the tarball is checked against the published
`.sha256` **before** a byte touches disk. `self-update` installs the new
version **beside** the old one and swaps the binary: `sdk/<old>` stays in
place, and an app whose `pubspec_overrides.yaml` points at it keeps resolving —
which is why the SDK is versioned by directory rather than overwritten. A
`latest` that is equal or older exits 0 without touching anything, never a
downgrade. `doctor` reports what it sees: the installed version, and when it
disagrees with the binary's, which command closes the gap.

## dovetail.yaml

`dovetail init` reads the project and writes the file; it does not ask anything
it can find out on its own.

```bash
dovetail init
```

It deduces the targets from the `macos/`, `windows/` and `linux/` directories
that exist, the identifier from `AppInfo.xcconfig` (never from `RunnerTests`,
which is the only `PRODUCT_BUNDLE_IDENTIFIER` in a freshly created
`project.pbxproj`), and the name from `pubspec.yaml`. When the platforms
declare different identifiers it reports both instead of choosing silently —
single instance and deep links anchor on that name, so diverging there is a
defect.

If `dovetail.yaml` already exists the command refuses; `--force` overwrites,
discarding whatever was configured by hand — which is why it is not the
default.

```yaml
identifier: com.example.demo
name: Demo

targets:
  - darwin-aarch64
  - linux-x86_64

update:
  key: keys/update.key
  password-env: DOVETAIL_UPDATE_KEY_PASSWORD
  base-url: https://cdn.example.com/releases
  public-key: |
    untrusted comment: minisign public key 1234567890ABCDEF
    RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
  manifest: dist/latest.json

sign:
  macos:
    identity-env: DOVETAIL_MACOS_IDENTITY
    notarize: false
  windows:
    certificate-env: DOVETAIL_WINDOWS_CERTIFICATE
    timestamp-url: http://timestamp.digicert.com
```

**There is no version field.** It lives in `pubspec.yaml` and is read from
there, without the `+build`. Duplicating it would only create two places to
disagree.

**No identity is written here**, only the name of the variable that carries it
— which is why the file can be committed.

`targets` is validated against the update manifest's own vocabulary. A key the
client never asks for is a release nobody can see, and `darwin-arm64` is
exactly that mistake: `arm64` is how Apple and WiX spell it, `aarch64` is how
the protocol spells it.

### The runtime through the installed SDK

Outside the monorepo the runtime has no `path: ../` to point at: it comes from
an SDK installed at `~/.dovetail/sdk/<version>/packages` (or `$DOVETAIL_HOME`,
when set).

```bash
dovetail init --sdk
```

The flag writes a `pubspec_overrides.yaml` in the app, each runtime package
pointed at the SDK's copy — Dart's native mechanism for resolving outside the
pubspec, the same one the Flutter SDK uses to deliver its own packages. The
preferred version is the binary's own; when that one is not installed, the most
recent serves. With no SDK installed the command refuses **before writing
anything**, and the message names the installer. The paths are local, so the
overrides file is not meant to be committed. The complete model — installation,
the version cycle and `bridge` — is in
[docs/instalador.md](../../docs/instalador.md).

## `upgrade`: the consumer's version cycle

`self-update` swaps the installed SDK without moving the apps: each app carries
a `pubspec_overrides.yaml` whose `path`s point at `sdk/<version>/packages`, and
the old version stays on disk for whoever still uses it. `upgrade` is the
command that re-points that file at the preferred SDK:

```bash
dovetail upgrade
```

With no `pubspec.yaml` in the directory it refuses, because the override
belongs to a project. `doctor` reports the disagreement when it sees an app
whose override points at a version older than the installed one — and `upgrade`
is what closes the gap.

## `update`: the version cycle in one command

`self-update` swaps the SDK and `upgrade` re-points the app — two commands that
travel together in every version cycle. `update` collapses them: it switches
the SDK to the channel's latest and, when the app is given, re-points its
`pubspec_overrides.yaml`:

```bash
dovetail update --base-url https://<host>                # the SDK only
dovetail update --base-url https://<host> --root app     # SDK + app
```

Without `--root` only the SDK changes, and re-pointing the app is left to a
later `upgrade`. With `--root` pointing at a directory with no `pubspec.yaml`
it skips the re-pointing with a warning rather than breaking — the override
belongs to a project. Already being on the latest exits 0 without touching
anything, never a downgrade, and with no SDK on disk for the app to point at,
it refuses naming `self-install`.

## The privileged service

A VPN does not connect without its privileged helper, and no package used to
install one: the systemd unit, the polkit policy and the maintenance scripts
existed and the packaging command could not reach them. Now they come from the
config.

```yaml
service:
  name: demo-helper.service
  description: Privileged helper for the tunnel
  exec-start: /usr/lib/demo/demo-helper
  capabilities: [CAP_NET_ADMIN]
  runtime-directory: demo
  purge-paths: [/var/lib/demo]
  polkit:
    action: com.example.demo.manage
    vendor: Example Ltd
    description: Manage the connection
    message: Authentication is required to change the connection
```

The capabilities go into `CapabilityBoundingSet` **and**
`AmbientCapabilities` — an ambient capability outside the bounding set is
discarded silently, and the helper comes up without the privilege it needs. The
polkit action has to be inside the `identifier`'s namespace, because polkit
names the file after the namespace and ignores an action declared outside it.

## With the config in place

```bash
dovetail doctor
dovetail release --artifact "darwin-aarch64=dist/Demo.dmg"
```

`doctor` without `--target` walks **every** declared target, one report per
target, and exits 1 if any tool is present but broken — worse than absent,
because a build then reports a success it did not earn.

`release` takes the version, the key, the password variable, the manifest's
destination and each artefact's URL (`<base-url>/<version>/<file>`) from the
file, and refuses a platform key that is not in `targets`. The long form
`platformKey=url=path` still applies for when the URL does not follow the
pattern — query string included, which the old form truncated at the first
`=`.

## The pipeline, in the order it runs

```
init      reads the project and writes the dovetail.yaml the others read
new       creates the project from scratch, already wired to dovetail
ship      the whole pipeline, from the config
doctor    can this machine build for that OS and architecture pair?
dev       the bridge never falls behind — watches and regenerates
bridge    generates the ffiPlugin that talks to the product's Rust core
build     compiles what this host can compile, and refuses loudly what it cannot
icon      one PNG becomes .ico, .icns and the Linux theme PNGs
bundle    nsis | msi | dmg | deb | rpm — never signs anything
sign      codesign and notarisation, or Authenticode — never packages anything
keygen    generates the minisign pair and prints the public key
release   signs each artefact and writes the manifest pointing at them
inspect   what the file is, not what its name says
manifest  the manifest alone, when the signature already exists
probe     asks the endpoint whether it serves what the client reads
self-install  installs the SDK's runtime beside the binary, from the release channel
self-update   switches the SDK to the channel's latest, keeping the version apps point at
update        switches the SDK to the latest and re-points the app, in one command
upgrade       re-points the app's pubspec_overrides.yaml at the installed SDK
```

The separation between `bundle` and `sign` is not organisational: signing
happens **after** the build and never inside it. A build that signs is a build
you cannot reproduce without the key.

## `doctor` asks whether the tool works

Not whether it is on the `PATH`. Each probe hands the real binary a real
trivial input and checks the real output: `makensis` compiles a four-line
script and has to produce the `.exe`; `ditto` copies a file and has to produce
the copy; `codesign` reads `/bin/ls`.

Without `--target` it walks every target in `dovetail.yaml`. With one, it asks
about a single one:

```bash
dovetail doctor --target windows --arch arm64
```

```
target: windows/arm64
missing  aarch64-pc-windows-msvc  rustup target add aarch64-pc-windows-msvc
broken   makensis  libc++abi: terminating due to uncaught exception of type std::bad_alloc
missing  wix  compiles the MSI, when one is asked for
broken   signtool  You must specify a key with which to sign.
```

A tool that is present and broken comes out as `broken`, with its own error
text, and the command exits 1 — because a build that reports a success it did
not earn is worse than a build that fails.

That is not hypothetical: on this machine Homebrew's `makensis` aborts with
`std::bad_alloc` on a four-line script, and there is a `signtool` on the `PATH`
that is not Windows's. A presence probe calls both of them ready.

## `bundle` does not need Windows to package for Windows

WiX P/Invokes into `msi.dll`, which is the Windows Installer library — which is
why Tauri's documentation says an **MSI can only be created on Windows**. That
holds for WiX, not for the format: `wixl`, from `msitools`, writes the MSI
database directly.

```bash
brew install msitools
dovetail bundle --target windows --arch x86_64 --windows-format msi \
  --upgrade-code 3F2504E0-4F89-11D3-9A0C-0305E82C3301 ...
```

`MsiBackend.forHost` chooses: `wix` on Windows, `wixl` anywhere else. The
dialect changes with it — `wixl` reads the v3 schema (`<Product>`), and WiX v4
reads its own. Proven here: the MSI comes out with the OLE2 header, `msiinfo`
reads the name, manufacturer and version, and `msiextract` pulls every staged
file out of the embedded CAB.

## `doctor` reports the project before the tools

Without `--target`, it answers first whether the project is ready — and it
distinguishes what is **missing** from what simply was **not configured**:

```
project
  ok       identifier  com.acme.client
  ok       name  Acme Client by Acme Ltd
  ok       version  1.2.0  (from pubspec)
  ok       targets  darwin-x86_64, darwin-aarch64 on this host of 4
  off      update  keys/update.key — no base-url, so every artefact needs its url spelled out
  ok       signing  DOVETAIL_MACOS_IDENTITY, not notarised
  off      service  no privileged helper is installed by the linux packages
```

The distinction is the point. A host that builds none of the declared targets
comes out `off`, not `missing` — it is a runner whose share of the matrix lives
elsewhere, and calling that an error would fail a CI job that is correct. What
comes out `missing` is what prevents publishing: absent config, or a `pubspec`
with no version.

## `sign` does not need Windows to sign for Windows

`signtool` ships with the Windows SDK and exists nowhere else — what answers to
that name on a Mac is `nss`'s JAR signer. The cross-platform path is
`osslsigncode`, and it is what the command uses on any host that is not
Windows.

```bash
dovetail sign --target windows \
  --file dist/setup.exe \
  --certificate keys/publisher.pem \
  --private-key keys/publisher.key \
  --timestamp-url http://timestamp.digicert.com
```

The flags override the environment; without them it reads
`WINDOWS_CERTIFICATE_FILE`, `WINDOWS_PRIVATE_KEY_FILE` and
`WINDOWS_TIMESTAMP_URL`. A PKCS#12 comes in through `--certificate` with no
`--private-key`, and then the password comes from
`WINDOWS_CERTIFICATE_PASSWORD` — empty is never assumed, because
`osslsigncode` asks on the terminal and a question in a pipeline is a build
that hangs instead of failing.

On Windows, with a `WINDOWS_CERTIFICATE_THUMBPRINT`, it still uses the real
`signtool` against the certificate in the store.

## `sign --entitlements-for` for what is nested

A privileged helper, a Network Extension or a login item inside the bundle
needs its own entitlements. Giving it the app's is how a daemon ends up with
the app's sandbox.

```bash
dovetail sign --target macos --bundle build/Example.app \
  --entitlements macos/Release.entitlements \
  --entitlements-for "Contents/Helpers/daemon=macos/Daemon.entitlements"
```

## `build` knows its ceiling

Signing and packaging can be centralised on one machine; **compiling cannot**.
Flutter refuses at the source: `"build windows" only supported on Windows
hosts`. No tool of ours works around that, and `build` refuses before invoking
Flutter, saying which step needs another machine instead of letting the error
surface mid-build.

```bash
dovetail build
```

Without `--target`, it looks at `dovetail.yaml`'s targets and builds what this
host can reach. A host whose share of the matrix is elsewhere exits 0 doing
nothing — not an error, a runner with no work this round.

## `icon` never scales up

From one square PNG of 512px or more come seven sizes in the `.ico`, nine
entries in the `.icns` and eight PNGs in the Linux theme. Both containers are
written in pure Dart, with no external tool.

```bash
dovetail icon --source brand/icon.png --out build/icons --app-id io.example.client
```

Four refusals, and each exists because the failure is silent rather than loud:
a file that is not a PNG, a non-square source (both platforms stretch rather
than refuse), a source below 512px (scaling up gives a blurry icon no reviewer
rejects and every user sees), and asking for the theme icons without
`--app-id` — without it the files land under a name the `.desktop` does not
point at, and the launcher shows no icon at all.

## `inspect` reads the file, not the name

```bash
dovetail inspect dist/*.dmg dist/*.exe dist/*.deb
```

For a macOS bundle or a Mach-O it reports the architectures present, the
signature's state and — the reason the command exists — whether the
architecture in the **name** agrees with the **contents**. Disagreement exits
1: an artefact whose name lies is worse than one that fails to build, because
it gets uploaded.

A bundle where some binaries are fat and some are thin comes out as universal
**only in part**, with the warning that it will not open on every Mac it is
installed on. For `.deb`, `.rpm`, `.msi` and `.exe` it says it **only read the
name**, so that a line that passed is never mistaken for a line that was
verified.

## `keygen` refuses to overwrite

```bash
dovetail keygen --out keys/update.key
```

It generates the minisign pair and prints the public key **in the form the
manifest carries**, to paste straight into the config. It refuses when a pair
already exists at the destination: losing the update private key is not losing
a file, it is losing the update path for every installation in the field, and
the recovery is reinstalling on each machine. It also warns when the
destination is not in `.gitignore`.

## `manifest` for when the signature already exists

```bash
dovetail manifest --version 2.1.0 \
  --release darwin-universal=https://cdn/app.tar.gz=dist/app.tar.gz.minisig \
  --out dist/latest.json
```

`release` signs and writes the manifest in one step; `manifest` is the writing
step alone, for when the signatures came from somewhere else — an HSM, or a
machine that holds the key and does not run the pipeline.

It embeds the **contents** of the `.minisig`, never the path: a path there
would be silently unverifiable on the downloader's machine.

## `probe` asks the endpoint whether it serves

```bash
dovetail probe --url https://api.example.com/manifest/darwin \
  --public-key keys/update.pub --installed 1.0.0 --download
```

The manifest's format is in code, in tests and in prose, and none of that tells
whoever writes the server whether what they uploaded works. This command does —
from outside, over the network, with the **same** `ManifestParser`, the same
`UpdatePolicy` and the same minisign verifier the app loads.

It decodes base64 **before** parsing, with no fallback, because that is what a
client in the field does: accepting both forms is what lets a release go out in
the form nobody reads. With `--public-key` it checks the key id, and it refuses
`--download` without a key, because verifying an artefact against the key that
signed it only proves the two came from the same place.

It exits 0 only when every target passes. Without `--target` it asks about all
three the product publishes, so an endpoint that serves one and five-hundreds
the other two says so without anyone having to ask.

## `new`: a project that already consumes the library

```bash
dovetail new demo
cd demo && flutter pub get && flutter test && dovetail doctor
```

`init` reads a project that already exists and writes the `dovetail.yaml`.
`new` goes the other way: it creates the project from scratch, with the
library already wired in. It writes a `pubspec.yaml` with the
dependency, a `lib/main.dart`, a widget test and a `dovetail.yaml` with the
defaults `doctor` accepts — the same `ConfigTemplate` that `init` uses.

What `new` generates is the complete desktop project, assembled from the SDK's
template (`tool/sdk/templates/app`), not a loose `lib/main.dart`:

```
demo/
├── lib/               clean architecture (the Manguinho refinement the mobile
│   ├── data/            team uses): data → domain → infra → presentation
│   ├── domain/          → main, with presenters as interface + impl
│   ├── infra/           change_notifier_*, DI and routes through weave_di
│   ├── main/
│   ├── presentation/
│   └── shared/
├── core/              the Rust core (crate <name>_core, CoreHandle facade)
├── core_bridge/       the FFI plugin that forwards the core, from the same
│                       template `bridge init` uses — with one example
│                       forwarder and the coverage gate that refuses a grown
│                       core with no forwarder
├── scripts/checks/    the team's two conformance suites, adapted:
│   ├── flutter/         the mobile one (layers, naming, Weave, size),
│   └── rust/            the desktop one (comments, English, size, URLs)
├── .githooks/         pre-commit and pre-push running the gate
├── run_app.sh         both suites' gate + flutter run -d macos
└── Makefile           quality, codegen, tests, run, hooks, build
```

The day-to-day loop in the generated project: `make codegen` regenerates the
bridge when the core grows (the generated Dart is not committed), `make
quality` runs both suites, and `./run_app.sh` refuses to start the app if the
gate fails.

The path to the library is worked out on its own, in this order: inside the
repository it walks up until it finds `toolkit/dovetail/lib/dovetail.dart` and
records the path relative to the new project; outside it — the compiled
binary's case, which has no repo — it points at the installed SDK, as an
absolute path. `--dovetail-path` overrides either, and with none of the three
sources the command refuses naming them, because a scaffold whose path points
nowhere lies on the first `flutter pub get`. The widget test `new` writes
genuinely exercises dovetail's own runtime — a smoke test that only renders the
app would prove Flutter, not the SDK the scaffold promised to wire in.

`weave_di` — the template's DI and routing — resolves by the same rule, and for
a reason worth writing down: it used to be a `git` dependency with the url
`git@weave-di.github.com:`, an **SSH alias** that exists in one machine's
`~/.ssh/config`. Every project this command generated inherited that, so the
first `flutter pub get` from anyone else died on a host DNS does not resolve.
The package is now published on pub.dev under MIT, so the ordinary route is a
hosted version; the SDK copy remains for an offline install. The order is
`--weave-path`, then `$DOVETAIL_WEAVE_PATH`, then the installed SDK; with none
of the three the command refuses **before writing a single byte**, because half
a scaffold is worse than none. A path that exists but has no `pubspec.yaml`
counts as absent, and so does an exported but empty variable — both would
produce a `path:` that only fails later.

No `pubspec.yaml` this command writes carries `git:` — there is a test pinning
that.

The app template resolves like the bridge's: explicit `--template`, then the
installed SDK (`sdk/<version>/templates/app`), then the repo. With none, the
command refuses naming the sources — and the bridge comes from the same place,
because the template and `dovetail_rust_core` have to match.

The name comes from the directory, or from `--name`, and has to start with a
letter and contain only letters, digits and underscores. The default identifier
is `com.example.<name>`, changeable with `--identifier`. A directory that
already exists makes the command refuse rather than overwrite.

`dovetail new --sdk` resolves the runtime from the installed SDK through
`pubspec_overrides.yaml`, instead of a `path` in the pubspec.

## Development

```bash
dart test
```

```bash
dart analyze
```

## `bridge`: the plugin that talks to the core

```bash
dovetail bridge init --core <crate> --name <name> [--out dir] [--template dir]
```

It generates the `ffiPlugin` (Windows/macOS/Linux) that forwards a product's
Rust core to Flutter — the mechanism whose fixture is a real bridge package,
reproduced by the SDK's template. `--core` is the crate's directory (the one
holding its `Cargo.toml`), and the command reads the crate's real name from the
manifest instead of guessing. `dovetail_rust_core` comes from the installed SDK
— the template and the runtime come from the same place, otherwise the
generated project points at one and resolves the other.

The template delivers the mechanics, not the content: `rust/src/api/` comes out
empty (the forwarders belong to the product), `lib/src/rust/` is generated by
the codegen, and there is no `example/`. The generated project's loop is the
fixture's:

```bash
flutter_rust_bridge_codegen generate
cd rust && cargo check
flutter test test/core_coverage_test.dart
```

The last one is the shape gate the template carries: it reads the crate's
`handle.rs` and the calls under `rust/src/api/`, and refuses when the core has
grown a method that no forwarder exposes. With no template at all — neither
`--template` nor an installed SDK — the command refuses naming the installer.

## `dev`: the bridge never falls behind

The trap is in two documents in this repo: you write a method in Rust,
everything compiles, and it **does not exist on the Dart side** — with no error
anywhere, until `verify frb` shouts. `dev` makes the bridge speak first:

```bash
dovetail dev            # refuses if the Dart is behind (naming the method); otherwise watches and regenerates
dovetail dev --check    # the verdict only, without watching
dovetail dev --once     # regenerate now and say what came in
```

It runs inside a package that has a `flutter_rust_bridge.yaml` (or with
`--root` pointing at one). The check generates into a temporary directory with
the real codegen and compares the `debugName`s — it never parses Rust by hand —
so the refusal names exactly the method the Dart does not have, and the tree is
left untouched.

## What cannot be proven on this machine

`bundle --target windows` and `--windows-format msi` have never run: the local
`makensis` is broken and `wix` is not installed. `sign --target windows` has
never signed anything, because there is neither a certificate nor a real
`signtool` here.

What is proven is the composition: the manifest `release` writes is read back
and verified by `dovetail_updater`, and `doctor` reports this machine's six
targets with each probe's real result.
