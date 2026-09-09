**English** · [Português](pt-BR/quickstart.md)

# Quickstart: from an installed dovetail to the first ship

The five-minute path for someone who has never touched the monorepo.
Everything here comes from the installed `dovetail` binary, plus the SDK it
downloads, without cloning any repository. Prerequisite: Flutter with your
system's desktop target.

> **About the install channel.** dovetail is MIT and the packages are on
> pub.dev, so the normal route is to declare the dependency and be done. What
> this guide describes — `install.sh` and `self-install` — is the signed
> binary channel, and its `<host>` **does not exist yet**: the mechanism is
> tested, the server is what is missing. See **Somewhere to download from** in
> [roadmap.md](roadmap.md).

## 0. The normal route

If all you want is the runtime in an app, this is the whole story:

```yaml
dependencies:
  dovetail: ^0.1.0
```

And the pipeline as a command:

```bash
dart pub global activate dovetail_cli
dovetail --help
```

The rest of this document is the signed-channel route, which gives you a
self-contained AOT binary and a versioned SDK on disk.

## 1. Install

The release channel **is not up yet**. There is no host, no pipeline command
publishes, and `install.sh` refuses without `--base-url`/`$DOVETAIL_INSTALL_URL`
rather than guessing. Until it exists, the real path is pub.dev or the
monorepo; what follows describes the mechanism, which is tested, against a
host that is still missing.

```bash
curl -fsSL https://<host>/install.sh | sh
```

Or, if you already have the binary:

```bash
dovetail self-install --base-url https://<host>
```

Both do the same work and respect `DOVETAIL_HOME` when it is set. The base
comes from `--base-url` or from `DOVETAIL_INSTALL_URL`; without either, the
command refuses and names both — it never guesses the host. What lands on
disk:

```
~/.dovetail/
  bin/dovetail                     the pipeline, AOT, self-contained
  sdk/<version>/packages           the runtime the app imports, versioned by directory
  sdk/<version>/templates/bridge   the template that generates the product bridge
~/.local/bin/dovetail              symlink to the binary
```

Check that the machine is ready:

```bash
dovetail doctor
```

## 2. A new app

```bash
dovetail new --sdk demo
cd demo
flutter test
```

`new` creates the project from scratch, already wired to dovetail: a
`pubspec.yaml`, a `pubspec_overrides.yaml` pointing at the installed SDK, a
`dovetail.yaml` with the defaults `doctor` accepts, and the platform
directories (`macos/`, `windows/`, `linux/`) filled in by the `flutter create`
it runs itself. The `--sdk` flag resolves the runtime through
`pubspec_overrides.yaml` instead of a `path` in the pubspec, so nothing points
inside the monorepo.

## 3. The bridge

If the app talks to a Rust core, generate the FFI plugin:

```bash
dovetail bridge init --core <your-crate> --name my_bridge
```

`--core` is the crate's directory (the one holding its `Cargo.toml`), and the
crate's real name is read from there, never guessed. What comes out is the
`ffiPlugin` for all three systems. From here on the loop is:

1. write the forwarders in `rust/src/api/`
2. `flutter_rust_bridge_codegen generate`
3. `tool/build_xcframework.sh`
4. `cd rust && cargo check`
5. `flutter test test/core_coverage_test.dart`

The last step is the shape gate: it reads the crate's `handle.rs` and the
calls under `rust/src/api/`, and refuses when the core has grown a method
that no forwarder exposes.

## 4. The config

`dovetail.yaml` already comes with the defaults from `new`. The essentials:

```yaml
identifier: com.example.demo
targets:
  - darwin-aarch64
  - linux-x86_64
update:
  key: keys/update.key
  base-url: https://cdn.example.com/releases
  manifest: dist/latest.json
  public-key: |
    untrusted comment: minisign public key 1234567890ABCDEF
    RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
sign:
  macos:
    identity-env: DOVETAIL_MACOS_IDENTITY
```

The key pair comes out of `dovetail keygen`, which prints the `public-key`
line ready to paste; without it `doctor` says `missing update` and `ship`
refuses before the build — because a release signed by a key the app does not
trust is a release only someone who reinstalls can use. There is no version
field: it lives in `pubspec.yaml`. No identity is written here, only the name
of the variable that carries it, so the file can be committed. The complete
key map is in [configuracao.md](configuracao.md).

## 5. Publishing

```bash
dovetail doctor
dovetail ship --dry-run
dovetail ship
```

`doctor` checks the host, the project, the SDK and the `.xcframework`.
`ship --dry-run` prints the plan without running anything — on macOS: build,
sign, bundle, sign dmg, archive and release; elsewhere: build, bundle, sign
and release — and refuses before the build whatever the last step would
refuse. Without the flag, it walks the whole pipeline and writes the manifest.

## 6. Updating

```bash
dovetail self-update   # switches the SDK to the channel's latest
dovetail upgrade       # re-points the app's pubspec_overrides.yaml at the preferred SDK
```

`self-update` installs the new version beside the old one and swaps the
binary, so an app pointed at the previous one keeps resolving. `upgrade`
closes the gap `doctor` reports when it sees an app behind the installed
version. `doctor`'s sections are `project`, `sdk`, `binary`, `app` and `spm`,
each with its own verdict — `binary` compares the `dovetail` answering on the
`PATH` against the one running, by commit and by command set, and names the
ones the installed copy does not have.

## 7. After the five minutes

- [WRITING_THE_APP.md](../WRITING_THE_APP.md): the boundary between what the
  framework decides and what the app decides, the boot order, text, forms,
  shortcuts, updating and publishing.
- [migrar-do-tauri.md](migrar-do-tauri.md): the `tauri.conf.json` map key by
  key, for anyone leaving Tauri.
