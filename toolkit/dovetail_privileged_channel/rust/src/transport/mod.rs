use std::fmt;
use std::io;

use crate::endpoint::Endpoint;
use crate::handshake::PeerCheck;
#[cfg(any(test, all(unix, not(target_os = "macos"))))]
use crate::peer_policy::{judge, PeerCred, PeerPolicy};

#[cfg(all(unix, not(target_os = "macos")))]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(windows)]
mod windows;

#[cfg(all(unix, not(target_os = "macos")))]
pub use linux::LinuxListener as Listener;
#[cfg(target_os = "macos")]
pub use macos::MacListener as Listener;
#[cfg(windows)]
pub use windows::WindowsListener as Listener;

#[cfg(unix)]
pub type Stream = tokio::net::UnixStream;

#[cfg(windows)]
pub type Stream = tokio::net::windows::named_pipe::NamedPipeServer;

pub async fn bind(endpoint: &Endpoint) -> anyhow::Result<Listener> {
    Listener::bind(endpoint).await
}

#[derive(Debug)]
#[non_exhaustive]
pub enum AcceptError {
    Io(io::Error),
    PeerRefused(anyhow::Error),
}

impl fmt::Display for AcceptError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AcceptError::Io(_) => write!(f, "erro de io ao aceitar conexao"),
            AcceptError::PeerRefused(_) => write!(f, "peer recusado na autenticacao"),
        }
    }
}

impl std::error::Error for AcceptError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            AcceptError::Io(e) => Some(e),
            AcceptError::PeerRefused(e) => Some(e.as_ref()),
        }
    }
}

fn admit<S>(
    stream: S,
    verify: impl FnOnce(&S) -> anyhow::Result<PeerCheck>,
) -> Result<(S, PeerCheck), AcceptError> {
    let peer = verify(&stream).map_err(AcceptError::PeerRefused)?;
    Ok((stream, peer))
}

#[cfg(any(test, windows))]
fn take_connected<S>(pending: &mut Option<S>, outcome: io::Result<()>) -> Result<S, AcceptError> {
    let instance = pending.take().expect("instancia pendente");
    outcome.map_err(AcceptError::Io)?;
    Ok(instance)
}

#[cfg(any(test, all(unix, not(target_os = "macos"))))]
fn admit_by_policy<S>(
    stream: S,
    policy: Option<&PeerPolicy>,
    credentials: impl FnOnce(&S) -> anyhow::Result<PeerCred>,
) -> Result<(S, PeerCheck), AcceptError> {
    admit(stream, |s| judge(policy, credentials(s)?))
}

#[cfg(test)]
mod tests {
    use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};

    use super::*;

    fn the_app() -> PeerCheck {
        PeerCheck {
            method: "peercred".into(),
            subject: "uid=501".into(),
        }
    }

    #[tokio::test]
    async fn a_refused_peer_is_not_an_io_error_and_its_connection_is_closed() {
        let (server, mut client) = duplex(64);
        let refused = admit(server, |_| Err(anyhow::anyhow!("not the app")));
        assert!(
            matches!(refused, Err(AcceptError::PeerRefused(_))),
            "got {refused:?}"
        );
        let read = client.read(&mut [0; 1]).await.unwrap();
        assert_eq!(read, 0, "the refused connection was left open");
    }

    #[tokio::test]
    async fn an_approved_peer_keeps_its_connection_and_its_check() {
        let (server, mut client) = duplex(64);
        let (mut stream, peer) = admit(server, |_| Ok(the_app())).unwrap();
        assert_eq!(peer.subject, "uid=501");
        stream.write_all(b"x").await.unwrap();
        assert_eq!(client.read_u8().await.unwrap(), b'x');
    }

    #[tokio::test]
    async fn a_pipe_instance_that_failed_to_connect_is_closed_not_kept_for_the_next_accept() {
        let (server, mut client) = duplex(64);
        let mut pending = Some(server);
        let failed = take_connected(&mut pending, Err(io::Error::other("connect failed")));
        assert!(matches!(failed, Err(AcceptError::Io(_))), "got {failed:?}");
        assert!(
            pending.is_none(),
            "the failed instance would be connected again"
        );
        let read = client.read(&mut [0; 1]).await.unwrap();
        assert_eq!(read, 0, "the failed instance was left open");
    }

    #[tokio::test]
    async fn a_connected_pipe_instance_goes_to_the_caller_and_leaves_the_listener() {
        let (server, mut client) = duplex(64);
        let mut pending = Some(server);
        let mut stream = take_connected(&mut pending, Ok(())).unwrap();
        assert!(
            pending.is_none(),
            "the next accept would reuse a connected instance"
        );
        stream.write_all(b"x").await.unwrap();
        assert_eq!(client.read_u8().await.unwrap(), b'x');
    }

    fn the_user<S>(_: &S) -> anyhow::Result<PeerCred> {
        Ok(PeerCred {
            pid: 4242,
            uid: 1000,
            gid: 1000,
        })
    }

    #[tokio::test]
    async fn without_a_policy_the_peer_is_refused_not_an_io_error_and_disconnected() {
        let (server, mut client) = duplex(64);
        let refused = admit_by_policy(server, None, the_user);
        assert!(
            matches!(refused, Err(AcceptError::PeerRefused(_))),
            "got {refused:?}"
        );
        let read = client.read(&mut [0; 1]).await.unwrap();
        assert_eq!(read, 0, "the refused connection was left open");
    }

    #[tokio::test]
    async fn a_peer_the_policy_admits_keeps_its_connection() {
        let (server, mut client) = duplex(64);
        let policy = PeerPolicy::default().allow_uid(1000);
        let (mut stream, peer) = admit_by_policy(server, Some(&policy), the_user).unwrap();
        assert_eq!(peer.subject, "pid=4242 uid=1000 gid=1000");
        stream.write_all(b"x").await.unwrap();
        assert_eq!(client.read_u8().await.unwrap(), b'x');
    }
}
