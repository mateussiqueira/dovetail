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
| macOS 12+ | XPC mach service + `xpc_connection_set_peer_code_signing_requirement`, on every message | the code requirement the product declares; without it, the daemon does not start |
| Linux | `SO_PEERCRED` | the uids and gids the product declares; without them, nobody |
| Windows | SDDL on the pipe + client process path | the helper's own directory |

### On macOS the channel is XPC, and every message is checked

The daemon listens on an XPC mach service named after its launchd label
(`XpcListener::mach_service`), and the app connects to it by that name
(`XpcConnection::mach_service`). The listener gives each peer the code
requirement from the product's `PeerPolicy`, and the system checks the sender
of **every message** against it, not the process that was behind the
connection when it opened. A process that connects, forks and execs a signed
program, or hands the connection to another process, gets nothing through from
the unsigned one: the message is dropped and the connection ends. A requirement
that does not parse refuses every peer, and a daemon whose product declares no
code requirement does not start. The API is from macOS 12, the minimum here.

The protocol does not change: `XpcConnection` is `AsyncRead + AsyncWrite`, each
write leaves as one message, and the framing and the handshake run on it as on
a socket. The app's side:

```rust
let conn = XpcConnection::mach_service("com.example.app.helper")?;
let mut framed = framer(conn);
let shake = client_handshake::<MeuComando, MeuResultado, _>(&mut framed, config, nonce).await?;
```

The launchd property list has to declare the service under `MachServices`.

The proof runs the attack against a real LaunchDaemon, so it needs root and is
`#[ignore]`d: an ad hoc "app" whose `cdhash` the requirement pins, and an
"other" signed under another identifier. The app is heard; the other is not;
and when the other connects, forks and execs the app, neither its message before
the exec nor the forked child's command reaches the daemon, while the exec'd app
is heard. Built as your user, run as root, the clients drop back to your uid:

```sh
cargo build --example xpc_proof
cargo test --test xpc_escalation --no-run
sudo target/debug/deps/xpc_escalation-<hash> --ignored
```

### The macOS socket path checks the peer's code once, at accept

Who may speak is the product's to say here too, as a code requirement in the
same `PeerPolicy`:

```rust
let requirement = "anchor apple generic and identifier \"com.example.app\" \
                   and certificate leaf[subject.OU] = \"TEAMID\"";
let endpoint = Endpoint::new("/var/run/myapp/helper.sock")
    .with_peer_policy(PeerPolicy::default().require_code(requirement));
```

On `accept` the listener reads the peer's audit token (`LOCAL_PEERTOKEN`), asks
the system for the code running in that process
(`SecCodeCopyGuestWithAttributes`) and checks it against the requirement
(`SecCodeCheckValidity`). Code that does not satisfy it, a requirement that
does not parse and a peer that is already gone are refused with
`AcceptError::PeerRefused`, in debug as in release.

What that proves is narrow, and it should be read before relying on it:

- The check runs once per connection, at `accept`, and `LOCAL_PEERTOKEN`
  describes the peer as it is when asked, not as it was when it connected.
  Measured here: a process connected, forked, and exec'd `/bin/sleep`; at
  `accept` the token named sleep, which a requirement for sleep admits, and
  the forked child then sent a request on that connection. Nothing after
  `accept` checks again, so a process can pass the check by exec'ing a
  program the requirement admits and leave the connection to another
  process, forked or handed the descriptor.
- A requirement does not change the socket's modes. A release socket is still
  `0600` in a `0700` directory, so only the helper's owner reaches it, and an
  app that runs as another user cannot connect yet.
- A requirement is only as strong as what it names. A build signed ad hoc has
  no certificate to anchor to, and anyone can sign a program ad hoc with any
  identifier, so `identifier "..."` alone lets in whoever asks; pin the app's
  `cdhash`, computed when the app is built, or anchor to a Developer ID team.

Without a requirement nothing is checked, and the build profile decides, as
before. In **debug** the peer is accepted by uid and the crate **logs a
warning** that no code signature was checked; the socket is `0666` in a `0755`
directory, so a developer build is reachable by the app. In **release** every
peer is **refused**, on a `0600` socket in a `0700` directory: accepting an
unchecked peer on a channel that runs as root is worse than having no channel
at all. `cargo test --release` asserts this refusal, and `verify_peer`, which
has no requirement to check against, follows the same two rules.

### The Linux path refuses every peer until the product declares who may speak

`SO_PEERCRED` says who is on the other end. Who may speak is the product's to
say, with a `PeerPolicy` on the endpoint:

```rust
let endpoint = Endpoint::new("/var/run/myapp/helper.sock")
    .with_peer_policy(PeerPolicy::default().allow_uid(0).allow_gid(app_gid));
```

A peer gets in when its uid or its gid is in the policy. The gid is the one the
peer process runs with, as `SO_PEERCRED` reports it, not its supplementary
groups. Without a policy, `accept` refuses every peer, root included, in debug
as in release: `AcceptError::PeerRefused`, with a reason that names what to
declare. `verify_peer` alone has no policy to judge against, so on Linux it
refuses too. macOS reads only the policy's code requirement, above, and
Windows does not read the policy.

The policy is also what lets the right peer reach the socket. With one, the
socket is `0666` in a `0755` directory: every local user can connect, and the
policy decides who stays. Without one, the socket stays `0600` in a `0700`
directory, since nobody would be let in anyway.

## Installing

Not on crates.io, on purpose: reach it by git dependency, as the rest of this
toolkit is.

```toml
dovetail_privileged_channel = { git = "https://github.com/mateussiqueira/dovetail", tag = "v0.1.11" }
```

`v0.1.11`, the newest tag, carries the transport, the peer authentication and
the framing. What came after it is only on `main` for now — the two handshake
procedures below, the deadline on the server's wait for the `Hello`, the typed
`RecvError` and `SendError`, `random_nonce` and `PeerPolicy` — so until a tag
carries them, pin a commit with `rev`.

## Using it

The helper's side:

```rust
use dovetail_privileged_channel::{
    bind, framer, random_nonce, server_handshake, Endpoint, ServerConfig, PROTOCOL_MAJOR,
    PROTOCOL_MINOR,
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
let nonce = random_nonce()?;
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
caller, and `random_nonce` draws one from the system's generator: `/dev/urandom`,
or `BCryptGenRandom` on Windows. When the generator fails it returns the error,
never a weaker nonce:

```rust
let stream = tokio::net::UnixStream::connect("/var/run/myapp/helper.sock").await?;
let mut framed = framer(stream);
let config = ClientConfig {
    client_major: PROTOCOL_MAJOR,
    client_minor: PROTOCOL_MINOR,
    client_version: "1.4.0".into(),
};
let nonce = random_nonce()?;
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
