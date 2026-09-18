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
| the accept loop with backoff, `prepare()` before bind | `server.rs` |
| the framed request loop, handshake, validation, dispatch | `connection.rs` |
| OS service registration (SCM / launchd / stub) | `service/` |

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

    async fn prepare(&self) -> anyhow::Result<()> { Ok(()) }
    async fn dispatch(&self, cmd: &Self::Command) -> RespPayload<Self::Reply>;
    async fn cleanup(&self) -> anyhow::Result<()> { Ok(()) }
}
```

`prepare()` is the hook for the app-specific residual cleanup that used to live
inside the server startup — anything that must run once before the daemon binds
its socket. `cleanup()` is the uninstall-time path. `dispatch()` is the one
place a validated command becomes a reply.

The app's `main` is a single call:

```rust
fn main() {
    std::process::exit(dovetail_privileged_daemon::run::<MyDaemon>());
}
```

`run::<A>()` parses `Mode::from_args()`, initialises tracing into `A::LOG_DIR`
with `A::LOG_FILTER`, then dispatches: `Service` runs the OS service entry
(SCM / launchd / stub), `Foreground` runs the loop with a `ctrl_c` shutdown,
`Cleanup` calls `cleanup()`, and `Install`/`Uninstall`/`StopService`/`Repair`/
`Status` map to the platform service operations. It returns the same exit codes
the product returned before the extraction.

## Service identity

`ServiceIdentity` carries the per-platform names the service operations need:
the Windows SCM name/display/description, the macOS launchd label (plist goes to
`/Library/LaunchDaemons/<label>.plist`, stdout/stderr to
`/var/log/<label>.log`), and the Linux unit name.

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
the same caveat the rest of this repository carries.

Part of [dovetail](https://github.com/mateussiqueira/dovetail). MIT.
