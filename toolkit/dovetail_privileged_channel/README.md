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
dovetail_privileged_channel = { git = "https://github.com/mateussiqueira/dovetail", tag = "v0.1.11" }
```

`v0.1.11`, the newest tag, carries the transport, the peer authentication and
the framing. What came after it is only on `main` for now — the two handshake
procedures below, the deadline on the server's wait for the `Hello`, and the
typed `RecvError` and `SendError` — so until a tag carries them, pin a commit
with `rev`.

## Using it

The helper's side:

```rust
use dovetail_privileged_channel::{
    bind, framer, server_handshake, Endpoint, ServerConfig, PROTOCOL_MAJOR, PROTOCOL_MINOR,
};

let endpoint = Endpoint::new("/var/run/myapp/helper.sock");
let mut listener = bind(&endpoint).await?;

let (stream, peer) = listener.accept().await?;
tracing::info!(method = %peer.method, subject = %peer.subject, "peer aceito");

let mut framed = framer(stream);
// Frame<MeuComando, MeuResultado> — o vocabulário é do app.
let config = ServerConfig {
    server_major: PROTOCOL_MAJOR,
    server_minor: PROTOCOL_MINOR,
    helper_version: "1.4.0".into(),
    peer_check: peer,
};
let shake = server_handshake::<MeuComando, MeuResultado, _>(&mut framed, config, nonce).await?;
if !shake.accepted {
    return Ok(()); // the refusal already went out on the wire
}
```

`accept()` returns the `PeerCheck` that authorises the connection, so the caller
can log or audit *who* was allowed in, not just that someone was.

`server_handshake` waits `HANDSHAKE_TIMEOUT_MS` (3 s) for the client's `Hello`,
and returns `HandshakeError::Timeout` when it does not come. Whatever arrives
instead of a `Hello` is refused **on the wire** before the error returns: a
`ServerHello` with `accepted: false` and `HANDSHAKE_REQUIRED` for a `Request`,
for a deadline that runs out and for a stream that ends before a whole frame,
`FRAME_TOO_LARGE` above `MAX_FRAME_BYTES`, `MALFORMED_FRAME` otherwise — so the
client can tell a refusal from a hang. The refusal is best effort: with nobody
left to read it, the caller still gets the original error. Another protocol
major is refused on the wire as well, with `VERSION_UNSUPPORTED` and the
server's own `proto_minor`, and comes back as `accepted: false`, which is what
the `if` above is for.

The app's side is `client_handshake`. Both take the 16-byte nonce from the
caller:

```rust
let stream = tokio::net::UnixStream::connect("/var/run/myapp/helper.sock").await?;
let mut framed = framer(stream);
let config = ClientConfig {
    client_major: PROTOCOL_MAJOR,
    client_minor: PROTOCOL_MINOR,
    client_version: "1.4.0".into(),
};
let shake = client_handshake::<MeuComando, MeuResultado, _>(&mut framed, config, nonce).await?;
```

It waits the same deadline for the `ServerHello`, and refuses what the server
should not have accepted: a refusal becomes `HandshakeError::Rejected`, carrying
the server's reason, and an accepted answer with another major becomes
`HandshakeError::VersionMismatch`. Underneath both, `send_frame` refuses a frame
above `MAX_FRAME_BYTES` before writing it, and `recv_frame` says which failure it
saw: `RecvError::TooLarge`, `Malformed` or `Io`.

## Scope

Written and exercised on macOS arm64. The Linux and Windows paths are carried
from a working product but are **not exercised on their own targets here** — the
same caveat the rest of this repository carries. An issue with output on those
platforms is the most useful thing this crate can receive.

Part of [dovetail](https://github.com/mateussiqueira/dovetail). MIT.
