use std::sync::Arc;
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::time::timeout;

use dovetail_privileged_channel::{
    framer, recv_frame, send_frame, server_handshake, ErrorCode, Frame, PeerCheck, Request,
    RespPayload, Response, ServerConfig, IDLE_TIMEOUT_MS, PROTOCOL_MAJOR, PROTOCOL_MINOR,
};

use crate::DaemonApp;

pub(super) async fn handle_conn<A, S>(stream: S, peer: PeerCheck, app: Arc<A>) -> anyhow::Result<()>
where
    A: DaemonApp,
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    handle_conn_with_nonce(stream, peer, app, fresh_nonce()).await
}

pub(super) async fn handle_conn_with_nonce<A, S>(
    stream: S,
    peer: PeerCheck,
    app: Arc<A>,
    nonce: [u8; 16],
) -> anyhow::Result<()>
where
    A: DaemonApp,
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    let mut framed = framer(stream);

    let config = ServerConfig {
        server_major: PROTOCOL_MAJOR,
        server_minor: PROTOCOL_MINOR,
        helper_version: A::VERSION.to_string(),
        peer_check: peer.clone(),
    };
    let shake = server_handshake::<A::Command, A::Reply, S>(&mut framed, config, nonce).await?;
    if !shake.accepted {
        return Ok(());
    }
    tracing::info!(
        client_version = %shake.client_hello.client_version,
        peer_method = %peer.method,
        peer_subject = %peer.subject,
        proto = format!("{}.{}", PROTOCOL_MAJOR, shake.negotiated_minor),
        "handshake aceito"
    );

    loop {
        let next = timeout(
            Duration::from_millis(IDLE_TIMEOUT_MS),
            recv_frame::<A::Command, A::Reply, S>(&mut framed),
        )
        .await;
        let frame = match next {
            Err(_) => {
                tracing::debug!("idle timeout; fechando conexao");
                break;
            }
            Ok(Ok(None)) => break,
            Ok(Err(err)) => {
                tracing::debug!(?err, "erro de leitura de frame");
                break;
            }
            Ok(Ok(Some(frame))) => frame,
        };

        let req: Request<A::Command> = match frame {
            Frame::Request(r) => r,
            Frame::Hello(_) => {
                tracing::debug!("Hello inesperado apos handshake");
                break;
            }
            _ => break,
        };

        if let Err(msg) = A::validate(&req.cmd) {
            let resp = Response {
                id: req.id,
                payload: RespPayload::erro(ErrorCode::invalid_params(), msg, false),
            };
            send_frame(&mut framed, &Frame::<A::Command, A::Reply>::Response(resp)).await?;
            continue;
        }

        let cmd_timeout = A::command_timeout(&req.cmd);
        let payload = match timeout(cmd_timeout, app.dispatch(&req.cmd)).await {
            Ok(payload) => payload,
            Err(_) => {
                RespPayload::erro(ErrorCode::timeout(), "comando excedeu o tempo limite", true)
            }
        };

        let resp = Response {
            id: req.id,
            payload,
        };
        send_frame(&mut framed, &Frame::<A::Command, A::Reply>::Response(resp)).await?;
    }

    Ok(())
}

fn fresh_nonce() -> [u8; 16] {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let mut n = [0u8; 16];
    n[..16].copy_from_slice(&nanos.to_le_bytes());
    n
}
