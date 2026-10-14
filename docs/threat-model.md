**English** · [Português](pt-BR/threat-model.md)

# Threat model

What dovetail defends, against whom, and where it stops. Every mitigation names the code that does it and the test that proves it; a defence with no test is a [known gap](#known-gaps), not a mitigation. Measured on `main` at `70e3507`: everything ran on macOS arm64, Linux only in containers, and the Windows code has never run.

To report a vulnerability, read [`SECURITY.md`](../SECURITY.md). Paths are relative to `toolkit/`; `channel/` stands for `dovetail_privileged_channel/rust/src/` and `daemon/` for `dovetail_privileged_daemon/rust/src/`.

## Who it defends against

| attacker | holds |
|---|---|
| local | an account or a process on the machine, without admin rights |
| network | the path between the app and the update host |
| update host | the server or mirror that answers the updater, or a certificate for its name |
| dependency | a Dart package or Rust crate that the app or the toolkit pulls in |

Out of scope: an attacker who is already root or administrator, physical access, and what the app's own commands mean. The channel decides *who* may speak to the daemon; the app's `DaemonApp::validate` decides *what* may be said.

## 1. Third-party packages in the app process

Nothing separates packages inside the app: every Dart package and Rust crate it links runs with the app's rights. Capabilities and CSP contain web content, and dovetail renders none, so there is nothing for them to contain here. What dovetail does is keep whatever needs more than the app's rights out of that process.

| mitigation | code | test |
|---|---|---|
| privileged work runs in a separate daemon, and every caller passes the peer check of section 2 | `daemon/server.rs` | the tests of section 2, starting with `the_policy_the_app_declares_reaches_the_endpoint` in the same file |
| the release tooling, which handles the signing keys, never links into the app | `dovetail/lib/dovetail.dart` | `dovetail/test/barrel_test.dart`: "it should not reach the packages that only run in the pipeline" |
| on macOS the app keeps the App Sandbox of Flutter's template, and the embedded daemon is signed with its own entitlements, never the app's | `dovetail_cli/lib/src/command/sign_command.dart` | `dovetail_cli/test/sign_command_test.dart`: "the declared entitlements of an embedded component should reach codesign for that binary, and not the app's"; `../tool/ci/prove_service.sh`, assertion 6 |

## 2. The privileged daemon and its channel

The daemon runs as root or SYSTEM, and the app reaches it through a local socket or a named pipe. The channel judges the peer at `accept`, before reading a byte from it.

| mitigation | code | test |
|---|---|---|
| macOS: the peer's code must satisfy the requirement the product declares | `channel/transport/macos.rs:41-45`, `channel/code_signature.rs` | `channel/code_signature_tests.rs` (2) |
| macOS: a release build with no requirement refuses every peer | `channel/peer_auth.rs:139-146` | `em_release_o_peer_e_recusado_sem_codesign`, same file, under `cargo test --release` |
| macOS: a release socket is `0600` in a `0700` directory, so only the daemon's owner reaches it | `channel/transport/macos.rs:16-24` | `aplica_o_modo_do_perfil_no_diretorio_e_no_socket`, same file |
| Linux: a peer gets in only when its uid or gid is in the `PeerPolicy`; with no policy nobody does, root included | `channel/peer_policy.rs:44-61` | `without_a_policy_even_root_is_refused_and_told_what_to_declare`, `a_policy_that_names_neither_the_uid_nor_the_gid_refuses_the_peer`, same file |
| Linux: the socket opens to other users only when a policy decides who stays | `channel/peer_policy.rs:70-81` | `channel/transport/linux.rs` (2) |
| the daemon hands the app's policy to the channel before it binds | `daemon/server.rs` | `the_policy_the_app_declares_reaches_the_endpoint`, same file |
| a refused peer is disconnected and does not hold up the next one | `channel/transport/mod.rs:58-64`, `daemon/server.rs` | `a_refused_peer_is_not_an_io_error_and_its_connection_is_closed`; `the_app_is_served_without_waiting_behind_a_refused_peer` |
| a client that does not finish the handshake within 3 s, or sends a frame above 64 KiB, is refused on the wire | `channel/limits.rs`, `channel/handshake_server.rs` | `daemon/connection_tests.rs`: `a_silent_client_is_refused_at_the_deadline`, `a_frame_above_the_cap_is_refused` |
| a burst of refusals writes one log line a minute, not one per refusal | `daemon/refusal_log.rs` | the 4 tests in the same file |

## 3. The update channel

| mitigation | code | test |
|---|---|---|
| an artefact reaches the installer only after its minisign signature verifies against the public key the app hands to `UpdateFlow` | `dovetail_updater/lib/src/flow/update_flow.dart` | `update_flow_test.dart`: "should refuse an artefact whose bytes were altered" |
| a signature from another key, or with its trusted comment edited, is refused | `dovetail_updater/lib/src/minisign/minisign_verifier.dart` | `minisign_test.dart`: "should refuse a key that did not make it", "should refuse a trusted comment that was edited after signing" |
| the endpoint and every redirect must be https | `dovetail_updater/lib/src/endpoint/endpoint_template.dart`, `dovetail_updater/lib/src/fetch/http_artifact_fetcher.dart` | `manifest_test.dart`: "should refuse an endpoint that is not https"; `http_artifact_fetcher_test.dart`: "should refuse anything that is not https" |
| an older version is refused unless the caller asks for it | `dovetail_updater/lib/src/policy/update_policy.dart` | `manifest_test.dart`: "an older version should be refused, not merely skipped" |
| a malformed manifest or signature is refused, never a crash | `dovetail_updater/lib/src/manifest/manifest_parser.dart`, `dovetail_updater/lib/src/minisign/` | `fuzz_manifest_test.dart`, `fuzz_minisign_test.dart` |

## 4. The build chain

| mitigation | code | test |
|---|---|---|
| the CLI installs or updates an SDK only with a minisign signature from the key built into it | `dovetail_cli/lib/src/sdk/sdk_channel.dart` | `sdk_channel_test.dart`: "a channel without the minisig should refuse", "a tarball signed by another key should refuse" |
| half a signing credential is fatal even on a local build, and an unset password is never read as empty | `dovetail_signer/lib/src/policy/signing_policy.dart` | `signing_policy_test.dart`: "a half configured set should be fatal even on a local build", "an unset password should be fatal instead of assumed empty" |
| an app and the daemon embedded in it must carry the same Team ID | `dovetail_cli/lib/src/command/sign_command.dart` | `sign_command_test.dart`: "a daemon whose Team ID differs from the app's should be refused, naming both values and where the daemon sits" |
| `keygen` never overwrites an update key pair | `dovetail_cli/lib/src/command/keygen_command.dart` | `keygen_command_test.dart`: "a second run should refuse rather than strand the park" |
| a commit that carries a private key or a known token format is refused | `../scripts/checks/pre_commit.sh` | `../scripts/checks/pre_commit_selftest.sh` |

## Known gaps

Each gap says what contains it today and where it is tracked. Ids such as `m6-install-sig` are rows of the [production roadmap](pt-BR/roadmap-producao.md), in Portuguese.

| gap | contained today by | tracked |
|---|---|---|
| macOS: the socket transport checks the code once, at `accept`, and `LOCAL_PEERTOKEN` describes the process as it is when asked, so a process can pass it by exec'ing an admitted program and leave the connection to a forked child | the daemon serves XPC on macOS, where the system checks the sender of every message against the requirement (`channel/xpc_listener.rs`); the root-only proof is `dovetail_privileged_channel/rust/tests/xpc_escalation.rs` and has not run in CI | the [channel README](../toolkit/dovetail_privileged_channel/README.md) |
| macOS: a debug build of the daemon opens its socket to every local user and, with no requirement declared, admits any peer | the release profile; the debug build logs a warning | by design |
| Linux authenticates the account, not the program: any process of an admitted uid or gid gets in | the uids and gids the product chooses | no issue yet |
| Windows: the pipe admits any local authenticated user, the only check is that the client's executable sits in the daemon's folder, and the `PeerPolicy` is not read. None of it has run | the pipe's SDDL, untested | no issue yet; milestone 3 of the production roadmap covers running it |
| Linux: the daemon's install, remove, stop and repair are a stub that exits `30`, and its status always answers `1` | the `.deb` and `.rpm` maintainer scripts manage the unit | no issue yet |
| the daemon runs `validate` before `dispatch` and bounds each command with `command_timeout` (`daemon/connection.rs:95-110`), but no test proves either | the code alone | no issue yet |
| the manifest is not signed, and the version it announces is not bound to the signature: a host that serves an older signed artefact under a newer number gets it installed, past the downgrade policy | https, and whoever runs the update host | `m5-comentario-ligado` |
| the artefact's file name comes from its URL, and the Linux and Windows installers join it to their scratch directory without refusing a separator or `..` | the bytes written are still the signed artefact | `m5-traversal` |
| the Windows installer has never applied a real update, and the `.deb` and `.rpm` paths are proven up to the command they build | — | milestones 3 and 5 of the production roadmap |
| `tool/sdk/install.sh`, the `curl \| sh` path, checks only a `.sha256` served by the same host and skips it when no hashing tool exists; a CLI built without the release key falls back to that `.sha256` | https | `m6-install-sig` |
| the SDK release key lives on one machine, and the CLI trusts that one key with no list to rotate to | — | `m6-key-custody`, `m6-key-list` |
| no Developer ID, notarisation, Authenticode certificate or GPG key yet | — | milestone 4 of the production roadmap |
| hosted CI does not run, so every gate above runs only on the maintainer's machine | — | `m2-billing` |
| no dependency audit (`cargo audit`, `cargo deny`), no SBOM and no reproducible build | — | no issue yet |
| no least-privilege manifest per package inside the app | the app's own review of what it depends on | no issue yet |
| outside these four boundaries: the single-instance socket and the Windows guard accept any local peer, and a deep link of any scheme reaches an app that declares no allow-list | — | `m3-si-peer-unix`, `m3-si-peer-win`, `m3-deeplink-schemes` |
