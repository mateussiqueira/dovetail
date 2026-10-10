use anyhow::Result;
use serde::de::DeserializeOwned;
use serde::Serialize;
use tokio::io::{AsyncRead, AsyncWrite};

use crate::envelope::{ErrorBody, ErrorCode};
use crate::framing::{recv_frame, send_frame, Framer};
use crate::handshake::{Frame, Hello, PeerCheck, ServerHello};
use crate::handshake_error::HandshakeError;

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
    let hello = match recv_frame::<Req, Resp, S>(framed).await? {
        Some(Frame::Hello(h)) => h,
        Some(other) => {
            return Err(HandshakeError::UnexpectedFrame {
                expected: "Hello",
                got: format!("{other:?}"),
            }
            .into())
        }
        None => return Err(HandshakeError::StreamEnded.into()),
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
