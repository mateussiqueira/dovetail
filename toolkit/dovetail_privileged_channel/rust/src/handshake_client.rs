use std::time::Duration;

use anyhow::Result;
use serde::de::DeserializeOwned;
use serde::Serialize;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::time::timeout;

use crate::framing::{recv_frame, send_frame, Framer};
use crate::handshake::{Frame, Hello, ServerHello};
use crate::handshake_error::HandshakeError;
use crate::limits::HANDSHAKE_TIMEOUT_MS;

pub struct ClientConfig {
    pub client_major: u16,
    pub client_minor: u16,
    pub client_version: String,
}

#[derive(Debug, Clone)]
pub struct ClientHandshakeResult {
    pub server_hello: ServerHello,
    pub negotiated_minor: u16,
}

pub async fn client_handshake<Req, Resp, S>(
    framed: &mut Framer<S>,
    config: ClientConfig,
    nonce: [u8; 16],
) -> Result<ClientHandshakeResult>
where
    Req: Serialize + DeserializeOwned + std::fmt::Debug,
    Resp: Serialize + DeserializeOwned + std::fmt::Debug,
    S: AsyncRead + AsyncWrite + Unpin,
{
    let hello = Hello {
        proto_major: config.client_major,
        proto_minor: config.client_minor,
        client_version: config.client_version,
        nonce,
    };
    send_frame::<Req, Resp, S>(framed, &Frame::Hello(hello)).await?;

    let next = timeout(
        Duration::from_millis(HANDSHAKE_TIMEOUT_MS),
        recv_frame::<Req, Resp, S>(framed),
    )
    .await
    .map_err(|_| HandshakeError::Timeout)?;
    let server_hello = match next? {
        Some(Frame::ServerHello(sh)) => sh,
        Some(other) => {
            return Err(HandshakeError::UnexpectedFrame {
                expected: "ServerHello",
                got: format!("{other:?}"),
            }
            .into())
        }
        None => return Err(HandshakeError::StreamEnded.into()),
    };

    if !server_hello.accepted {
        let reason = server_hello
            .reject
            .map(|e| e.message)
            .unwrap_or_else(|| "sem motivo informado".into());
        return Err(HandshakeError::Rejected { reason }.into());
    }
    if server_hello.proto_major != config.client_major {
        return Err(HandshakeError::VersionMismatch {
            client: config.client_major,
            server: server_hello.proto_major,
        }
        .into());
    }

    let negotiated_minor = server_hello.proto_minor;
    Ok(ClientHandshakeResult {
        server_hello,
        negotiated_minor,
    })
}
