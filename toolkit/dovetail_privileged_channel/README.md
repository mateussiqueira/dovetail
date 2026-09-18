# dovetail_privileged_channel

The **channel** to a privileged component, and the **peer authentication** that
decides who may speak on it. Rust crate, consumed by the helper on one side and
by the app on the other.

`dovetail_privileged_helper` installs the daemon, reports its state and removes
it. It says so itself, under *What is not here*: how the app talks to the
component is the app's business. This crate is that piece, extracted so every
app that declares `service.macos.route: system` does not write it again.

## The line this crate draws

It decides **how the conversation happens** and **who has the right to speak**.
It does not decide **what is said**.

| Stays here (generic) | Stays with the app (vocabulary) |
| --- | --- |
| the OS channel: unix socket, named pipe | the command enum |
| peer authentication per platform | the request and result payloads |
| the frame envelope and the handshake | the product's split-tunnel, keys, addresses |
| framing (length-delimited JSON) and its size ceiling | per-command timeouts |
| the socket directory and file modes | the endpoint address itself |

The envelope is generic over the payload: `Frame<Req, Resp>`, `Request<P>`,
`Response<P>`, `RespPayload<P>`. The app supplies `P`; the crate never names a
command.

## Peer authentication, per platform

| Platform | Mechanism | Verified against |
| --- | --- | --- |
| macOS | `getpeereid` + code signature | *not implemented — see below* |
| Linux | `SO_PEERCRED` | pid/uid/gid (polkit consultation is a placeholder) |
| Windows | SDDL on the pipe + client process path | the helper's own directory |

### The macOS path fails CLOSED in release

This is deliberate and it is carried, not softened.

In **debug**, the peer is accepted by uid and the crate **logs a warning** that
no code signature was checked — the socket is `0666` in a `0755` directory, by
design, so a developer build is reachable by the app.

In **release**, `verify_peer` **refuses every peer**: the code signature check
against the product's `SecRequirement` does not exist yet, and accepting an
unverified peer on a channel that runs as root is worse than having no channel
at all. `cargo test --release` asserts this refusal — if someone ever makes the
release path return `Ok`, that test fails.

The function that must be written to enable release is named in the error
message itself, so the next person does not have to rediscover it.

## Installing

Not on crates.io, on purpose: reach it by git dependency, as the rest of this
toolkit is.

```toml
dovetail_privileged_channel = { git = "https://github.com/mateussiqueira/dovetail", tag = "v0.1.6" }
```

## Using it

```rust
use dovetail_privileged_channel::{bind, framer, recv_frame, send_frame, Endpoint, Frame, Hello};

let endpoint = Endpoint::new("/var/run/myapp/helper.sock");
let mut listener = bind(&endpoint).await?;

let (stream, peer) = listener.accept().await?;
tracing::info!(method = %peer.method, subject = %peer.subject, "peer aceito");

let mut framed = framer(stream);
// Frame<MeuComando, MeuResultado> — o vocabulário é do app.
```

`accept()` returns the `PeerCheck` that authorises the connection, so the caller
can log or audit *who* was allowed in, not just that someone was.

## Scope

Written and exercised on macOS arm64. The Linux and Windows paths are carried
from a working product but are **not exercised on their own targets here** — the
same caveat the rest of this repository carries. An issue with output on those
platforms is the most useful thing this crate can receive.

Part of [dovetail](https://github.com/mateussiqueira/dovetail). MIT.
