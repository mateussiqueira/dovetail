use std::time::Duration;

use anyhow::Result;
use serde::de::DeserializeOwned;
use serde::Serialize;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::time::timeout;

use crate::envelope::{ErrorBody, ErrorCode};
use crate::framing::{recv_frame, send_frame, Framer, RecvError};
use crate::handshake::{Frame, Hello, PeerCheck, ServerHello};
use crate::handshake_error::HandshakeError;
use crate::limits::HANDSHAKE_TIMEOUT_MS;

pub struct ServerConfig {
    pub server_major: u16,
    pub server_minor: u16,
    pub helper_version: String,
    pub peer_check: PeerCheck,
}

#[derive(Debug)]
pub struct ServerHandshakeResult {
    pub accepted: bool,
    pub negotiated_minor: u16,
    pub client_hello: Hello,
}

type HelloFailure = (anyhow::Error, Option<ErrorBody>);

pub async fn server_handshake<Req, Resp, S>(
    framed: &mut Framer<S>,
    config: ServerConfig,
    nonce: [u8; 16],
) -> Result<ServerHandshakeResult>
where
    Req: Serialize + DeserializeOwned + std::fmt::Debug,
    Resp: Serialize + DeserializeOwned + std::fmt::Debug,
    S: AsyncRead + AsyncWrite + Unpin,
{
    let hello = match read_hello::<Req, Resp, S>(framed).await {
        Ok(hello) => hello,
        Err((error, None)) => return Err(error),
        Err((error, Some(reject))) => {
            let sh = ServerHello {
                accepted: false,
                proto_major: config.server_major,
                proto_minor: config.server_minor,
                helper_version: config.helper_version,
                nonce,
                peer_check: config.peer_check,
                reject: Some(reject),
            };
            let _ = send_frame::<Req, Resp, S>(framed, &Frame::ServerHello(sh)).await;
            return Err(error);
        }
    };

    let accepted = hello.proto_major == config.server_major;
    let negotiated_minor = hello.proto_minor.min(config.server_minor);
    let reject = (!accepted).then(|| {
        ErrorBody::new(
            ErrorCode::version_unsupported(),
            format!(
                "protocolo major {} nao suportado (helper fala {})",
                hello.proto_major, config.server_major
            ),
        )
    });

    let sh = ServerHello {
        accepted,
        proto_major: config.server_major,
        proto_minor: negotiated_minor,
        helper_version: config.helper_version,
        nonce,
        peer_check: config.peer_check,
        reject,
    };
    send_frame::<Req, Resp, S>(framed, &Frame::ServerHello(sh)).await?;

    Ok(ServerHandshakeResult {
        accepted,
        negotiated_minor,
        client_hello: hello,
    })
}

async fn read_hello<Req, Resp, S>(framed: &mut Framer<S>) -> Result<Hello, HelloFailure>
where
    Req: DeserializeOwned + std::fmt::Debug,
    Resp: DeserializeOwned + std::fmt::Debug,
    S: AsyncRead + AsyncWrite + Unpin,
{
    let deadline = Duration::from_millis(HANDSHAKE_TIMEOUT_MS);
    let next = timeout(deadline, recv_frame::<Req, Resp, S>(framed)).await;
    let (error, code, message): (anyhow::Error, ErrorCode, &str) = match next {
        Err(_) => return Err((HandshakeError::Timeout.into(), None)),
        Ok(Ok(None)) => return Err((HandshakeError::StreamEnded.into(), None)),
        Ok(Err(e @ RecvError::Io(_))) => return Err((e.into(), None)),
        Ok(Err(e @ RecvError::TooLarge)) => (
            e.into(),
            ErrorCode::frame_too_large(),
            "frame de handshake acima do teto",
        ),
        Ok(Err(e @ RecvError::Malformed(_))) => (
            e.into(),
            ErrorCode::malformed_frame(),
            "frame de handshake malformado",
        ),
        Ok(Ok(Some(Frame::Hello(hello)))) => return Ok(hello),
        Ok(Ok(Some(other @ Frame::Request(_)))) => (
            unexpected(&other),
            ErrorCode::handshake_required(),
            "Request recebido antes do Hello",
        ),
        Ok(Ok(Some(other))) => (
            unexpected(&other),
            ErrorCode::malformed_frame(),
            "primeiro frame deve ser Hello",
        ),
    };
    Err((error, Some(ErrorBody::new(code, message))))
}

fn unexpected(frame: &impl std::fmt::Debug) -> anyhow::Error {
    HandshakeError::UnexpectedFrame {
        expected: "Hello",
        got: format!("{frame:?}"),
    }
    .into()
}
