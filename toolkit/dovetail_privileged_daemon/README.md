# dovetail_privileged_daemon

The generic **privileged daemon skeleton**, extracted from a shipping VPN
client. Any app with a privileged component (a helper that runs as SYSTEM /
root and must be installed once as an OS service) depends on this crate instead
of rewriting, for every product: service installation, the accept loop, request
validation, the run modes and structured logging.

`dovetail_privileged_channel` owns the *channel* and the *peer authentication*;
this crate owns the *daemon* that sits behind that channel. They are versioned
together, so a consumer reaches both through the same git tag.

## What this crate owns

| Piece | Where |
| --- | --- |
| the `DaemonApp` seam an app implements | `lib.rs` |
| run-mode parsing (`--service`, `--install`, `--cleanup`, …) | `mode.rs` |
| the stable exit codes | `exit_codes.rs` |
| rotating file + stderr tracing (4 MiB → `.old`) | `logging.rs` |
| the accept loop with backoff, `prepare()` and the app's peer policy before bind | `server.rs` |
| the framed request loop, handshake, validation, dispatch | `connection.rs` |
| OS service registration (SCM / launchd / systemd) | `service/` |

## The `DaemonApp` seam

An app supplies a struct that implements `DaemonApp`. The crate never names a
command, a reply, or a product. It reads only:

```rust
#[async_trait::async_trait]
pub trait DaemonApp: Default + Send + Sync + 'static {
    type Command: serde::Serialize + serde::de::DeserializeOwned + Send + Sync + 'static;
    type Reply: serde::Serialize + serde::de::DeserializeOwned + Send + Sync + 'static;

    const ENDPOINT: &'static str;
    const IDENTITY: ServiceIdentity;
    const VERSION: &'static str;
    const LOG_DIR: &'static str;
    const LOG_FILTER: &'static str = "info";

    fn command_timeout(cmd: &Self::Command) -> std::time::Duration;
    fn validate(cmd: &Self::Command) -> Result<(), String>;
    fn peer_policy() -> Option<PeerPolicy> { None }

    async fn prepare(&self) -> anyhow::Result<()> { Ok(()) }
    async fn dispatch(&self, cmd: &Self::Command) -> RespPayload<Self::Reply>;
    async fn cleanup(&self) -> anyhow::Result<()> { Ok(()) }
}
```

`prepare()` is the hook for the app-specific residual cleanup that used to live
inside the server startup — anything that must run once before the daemon binds
its socket. `cleanup()` is the uninstall-time path. `dispatch()` is the one
place a validated command becomes a reply.

`peer_policy()` says who may speak to the daemon. The daemon hands it to the
channel's `Endpoint::with_peer_policy` before it binds, and the channel applies
it: on Linux a peer gets in when its uid or its gid is in the policy. The
default is `None`, and with it a Linux helper refuses every peer, root
included, so a product that runs there declares one:

```rust
fn peer_policy() -> Option<PeerPolicy> {
    Some(PeerPolicy::default().allow_uid(0).allow_gid(APP_GID))
}
```

`PeerPolicy` is re-exported here, next to `RespPayload`. On macOS 12 and later
the daemon serves an XPC mach service named after its launchd label, and the
system checks the code of the sender of every message against a code
requirement. The requirement is data the product supplies, not a constant in
this crate. `require_code` in the policy is the one compiled into the daemon.
The `--peer-requirement <requirement>` argument in the launchd property list
(the `arguments` of the macOS service in `dovetail.yaml`) replaces it only when
`/Library/LaunchDaemons/<label>.plist` belongs to `root:wheel` and neither the
group nor others can write it, which is the system route the installer
package takes. The daemon reads the argument from the content of that file,
not from its own command line, so a launch from a property list inside the
app bundle, which whoever can write the app can rewrite, serves the compiled
requirement; when the command line carries a requirement the trusted file
does not, the daemon logs that it ignored it. A trusted file that names
`--peer-requirement` with no value after it is malformed, and the daemon does
not start rather than fall back to the compiled requirement. An ad hoc app
pins its
`cdhash` (one `cdhash` per slice of a universal app, joined by `or`). The
daemon does not start on macOS without a requirement or with one the Security
framework does not compile, and it judges the compiled requirement, not its
text: every alternative an `or` opens must take one of three forms.

- Pinned: a full 20-byte `cdhash`.
- Developer ID: `anchor apple generic and identifier "<app id>" and
  certificate leaf[subject.OU] = "<team id>" and
  certificate 1[field.1.2.840.113635.100.6.2.6] exists and
  certificate leaf[field.1.2.840.113635.100.6.1.13] exists`. The two
  markers name the Developer ID intermediate and a Developer ID Application
  leaf; without them any Apple Development build signed by any member of the
  team passes. The anchor alone admits any Apple-signed program and the
  identifier alone is chosen by whoever signs.
- Mac App Store: `anchor apple generic and identifier "<app id>" and
  certificate leaf[field.1.2.840.113635.100.6.1.9] exists`. That leaf marker
  is only on the certificate Apple re-signs store builds with, so no team
  member can produce it, and the identifier picks the app among them.

The designated requirement `codesign -d -r-` prints for a Developer ID app
joins the last two with `or`, so it passes as is. `always` and `!` are
refused anywhere, and a team that only `exists`, is compared with `>=`
or carries a wildcard does not count. Windows
does not read the policy yet.

The app's `main` is a single call:

```rust
fn main() {
    std::process::exit(dovetail_privileged_daemon::run::<MyDaemon>());
}
```

`run::<A>()` parses `Mode::from_args()`, initialises tracing into `A::LOG_DIR`
with `A::LOG_FILTER`, then dispatches: `Service` runs the OS service entry
(SCM / launchd / systemd), `Foreground` runs the loop with a `ctrl_c` shutdown,
`Cleanup` calls `cleanup()`, and `Install`/`Uninstall`/`StopService`/`Repair`/
`Status` map to the platform service operations. It returns the same exit codes
the product returned before the extraction.

## Service identity

`ServiceIdentity` carries the per-platform names the service operations need:
the Windows SCM name/display/description, the macOS launchd label (plist goes to
`/Library/LaunchDaemons/<label>.plist`, stdout/stderr to
`/var/log/<label>.log`), and the Linux unit name. On Linux the service operations
drive that unit with `systemctl` and never write it: the `.deb` or `.rpm` ships
it. `--install` is `enable --now`, `--uninstall` is `disable --now`, `--stop`
leaves it enabled, `--repair` restarts it and `--status` reads its `LoadState`
and `ActiveState`.

## Versioning

Reach both crates through the same tag; the daemon depends on the channel by a
relative path inside this repository:

```toml
dovetail_privileged_daemon = { git = "https://github.com/mateussiqueira/dovetail", tag = "vX.Y.Z" }
dovetail_privileged_channel = { git = "https://github.com/mateussiqueira/dovetail", tag = "vX.Y.Z" }
```

The daemon crate's `Cargo.toml` pins the channel by relative path so the two
never drift within a tag.

## Scope

Written and exercised on macOS arm64. The Windows path is ported from the
shipping product but is not compiled on the macOS host it is maintained on —
the same caveat the rest of this repository carries. The Linux service operations
were run once against systemd booted in a container; no gate repeats that run.

Part of [dovetail](https://github.com/mateussiqueira/dovetail). MIT.
