**English** · [Português](pt-BR/release-simulado.md)

# Simulated release: the whole pipeline without the three things that do not exist yet

> **Context for anyone arriving through the public repository.** This document
> mentions `product/`, which is the private app where the toolkit is
> exercised, and it does not exist in this repository. The mechanism described
> belongs to the toolkit and holds for any app; only the example's path
> belongs to another tree.

A production release needs three things this repository does not have: the
production minisign key, an https host, and a Developer ID with notarisation
credentials. None of them is code. What this document describes is how to run
the **entire** pipeline on one machine with stand-ins that honour the **same
contract**, so that the day of the real release is a matter of swapping values
in `dovetail.yaml` and in the environment — and nothing else.

| missing | stand-in | where it plugs in | what it proves |
|---|---|---|---|
| production key | a throwaway minisign pair (`dovetail keygen --out`) | `update.key`, `update.public-key` | the signature over the bytes, and refusal of a foreign key |
| https host | `tool/serve_dist.dart` on loopback with a private CA | `update.base-url`, `update.endpoint`, `probe --ca` | transport, manifest format, and the `.app.tar.gz` the updater installs |
| Developer ID | the ad hoc identity `-` | `APPLE_SIGNING_IDENTITY=-` | seal ordering, entitlements, `codesign --verify` on the `.app` and the `.dmg` |

What this **cannot** prove, and only the real thing can: Gatekeeper and
notarisation (`spctl` saying `Notarized Developer ID`), DNS and CDN, and the
installed Tauri fleet accepting the update — the new app is a different
binary, with a different key, and the fleet's updater plugin is never called;
the compatibility to honour is the new app's with itself.

## One command

```bash
tool/ci/prove_update.sh --host macos
```

It requires the Release `.app` already built in the product (`dovetail build`
in the app's directory), plus `openssl`, `minisign`, `dart`, `python3` and the
Xcode command line tools (`codesign`, `hdiutil`). It **always** runs the CLI
from the tree, never the one installed on the `PATH` — the installed one may
be several commands behind, and `doctor` says when it is.

What happens, in order:

1. A **staging root** at `$TMPDIR/dovetail-update-stage` with its own
   `dovetail.yaml`: the product's identifier, `base-url` and `endpoint`
   pointing at `https://localhost:8443`, `notarize: false`, and a throwaway
   pair at `keys/staging.key`. The product's own `dovetail.yaml` is not
   touched.
2. `ship --no-build` with `APPLE_SIGNING_IDENTITY=-`: the `.app` copied with
   `ditto` is re-signed inside out with the Release entitlements (which
   removes the `get-task-allow` that Xcode leaves behind and notarisation
   rejects), the `.dmg` is mounted and signed as a flat file, the
   `.app.tar.gz` is produced for the updater, and `release` writes
   `dist/latest.json` pointing at the tar.gz — not at the dmg, which
   `MacosInstaller` cannot open.
3. `codesign --verify --deep --strict` on the `.app` and `--strict` on the
   `.dmg`.
4. A private CA and a leaf for `localhost` come out of `openssl` — the leaf
   with `extendedKeyUsage = serverAuth`, because on macOS Dart delegates trust
   to Apple's Security framework, which demands that of every TLS server
   certificate (`curl` accepts it without; the Dart client refuses with
   "application verification failure"). `tool/serve_dist.dart` serves `dist/`
   over https, answering `/desktop-version/check/<os>` as well — the endpoint
   shape the app queries.
5. `probe` **without** `--ca` must fail at the handshake (the client does not
   accept a certificate it does not know); with `--ca tls/ca.crt --public-key
   keys/staging.pub --target darwin-universal --installed 0.9.0 --download`,
   it must offer the version and verify the tar.gz bytes against the throwaway
   key; and with `--installed` equal to the served version, it must say
   `upToDate` and offer nothing.

## Closing the loop with the app

`probe` is the same parser and verifier the app uses, but it is not the app.
To watch an installed app accept an update from the local host:

- The staging root **is not a Flutter project**: it only carries the copied
  `.app`, the yaml, the keys and the TLS material. The build that embeds the
  staging values happens in the product: its `dovetail.yaml` already carries
  the staging key and the `localhost:8443` endpoint, so `dovetail build`
  there embeds both through `--dart-define`, and the app reads them with
  `String.fromEnvironment`. For that app to accept the stage's manifest, the
  stage has to sign with the **same** key (point the stage yaml's
  `update.key` and `update.public-key` at the product's `keys/update.key`
  instead of the throwaway pair).
- The private CA has to be trusted by the app. Dart's `HttpClient` does not
  read the keychain for extra roots, so the seam is the same one `probe`
  uses: an `HttpArtifactFetcher(client: ProbeCommand.clientTrusting(caPath))`,
  or the equivalent in `makeUpdateWatch(fetcher: ...)` — app code, and
  therefore yours.
- The served artefact's version has to be **greater** than the running app's:
  bump `version:` in `pubspec.yaml` before the second `dovetail build` (that
  is where the build takes `dovetail.version` from; there is no flag for it)
  and publish with a matching `dovetail release --version`, otherwise the
  verdict is `up to date`.
- A sandboxed app needs `com.apple.security.network.client` to reach the
  network; both of the product's `.entitlements` now carry it, and a test in
  the product pins that.

## The day of the real release

Swap values, not code:

| what | where |
|---|---|
| production key | move the staging pair (`keys/update.key`, `keys/update.pub`) out of the way — `keygen` refuses to overwrite on purpose — then `dovetail keygen --out keys/update.key` (with a password, `unencrypted: false`), and the two `update.public-key` lines in `dovetail.yaml` |
| host | `update.base-url` and `update.endpoint` |
| Developer ID | `APPLE_SIGNING_IDENTITY` (or the variable named by `identity-env`) and `sign.macos.notarize: true` |
| notarisation | `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`, or the `APPLE_API_*` trio |

With `notarize: true`, `ship --dry-run` and `doctor` refuse **before the
build** whatever is missing from that list — and the list above is exactly
what they name.
