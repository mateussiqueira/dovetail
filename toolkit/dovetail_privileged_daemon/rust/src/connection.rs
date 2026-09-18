use std::sync::Arc;
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::time::timeout;

use dovetail_privileged_channel::{
    framer, recv_frame, send_frame, ErrorBody, ErrorCode, Frame, Framer, Hello, PeerCheck, Request,
    RespPayload, Response, ServerHello, HANDSHAKE_TIMEOUT_MS, IDLE_TIMEOUT_MS, PROTOCOL_MAJOR,
    PROTOCOL_MINOR,
};

use crate::DaemonApp;

pub(super) async fn handle_conn<A, S>(stream: S, peer: PeerCheck, app: Arc<A>) -> anyhow::Result<()>
where
    A: DaemonApp,
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    let mut framed = framer(stream);

    let hello = match read_hello::<A, S>(&mut framed).await {
        Ok(h) => h,
        Err(reject) => {
            let sh = ServerHello {
                accepted: false,
                proto_major: PROTOCOL_MAJOR,
                proto_minor: PROTOCOL_MINOR,
                helper_version: A::VERSION.to_string(),
                nonce: fresh_nonce(),
                peer_check: peer.clone(),
                reject: Some(reject),
            };
            let _ = send_frame(&mut framed, &Frame::<A::Command, A::Reply>::ServerHello(sh)).await;
            return Ok(());
        }
    };

    if hello.proto_major != PROTOCOL_MAJOR {
        let sh = ServerHello {
            accepted: false,
            proto_major: PROTOCOL_MAJOR,
            proto_minor: PROTOCOL_MINOR,
            helper_version: A::VERSION.to_string(),
            nonce: fresh_nonce(),
            peer_check: peer.clone(),
            reject: Some(ErrorBody::new(
                ErrorCode::version_unsupported(),
                format!(
                    "protocolo major {} nao suportado (helper fala {})",
                    hello.proto_major, PROTOCOL_MAJOR
                ),
            )),
        };
        send_frame(&mut framed, &Frame::<A::Command, A::Reply>::ServerHello(sh)).await?;
        return Ok(());
    }

    let negotiated_minor = hello.proto_minor.min(PROTOCOL_MINOR);
    tracing::info!(
        client_version = %hello.client_version,
        peer_method = %peer.method,
        peer_subject = %peer.subject,
        proto = format!("{}.{}", PROTOCOL_MAJOR, negotiated_minor),
        "handshake aceito"
    );

    let sh = ServerHello {
        accepted: true,
        proto_major: PROTOCOL_MAJOR,
        proto_minor: negotiated_minor,
        helper_version: A::VERSION.to_string(),
        nonce: fresh_nonce(),
        peer_check: peer,
        reject: None,
    };
    send_frame(&mut framed, &Frame::<A::Command, A::Reply>::ServerHello(sh)).await?;

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

async fn read_hello<A, S>(framed: &mut Framer<S>) -> Result<Hello, ErrorBody>
where
    A: DaemonApp,
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    let next = timeout(
        Duration::from_millis(HANDSHAKE_TIMEOUT_MS),
        recv_frame::<A::Command, A::Reply, S>(framed),
    )
    .await;
    let frame = match next {
        Err(_) => {
            return Err(ErrorBody::new(
                ErrorCode::handshake_required(),
                "handshake nao recebido dentro do prazo",
            ))
        }
        Ok(Ok(None)) => {
            return Err(ErrorBody::new(
                ErrorCode::handshake_required(),
                "conexao fechada antes do handshake",
            ))
        }
        Ok(Err(_)) => {
            return Err(ErrorBody::new(
                ErrorCode::frame_too_large(),
                "frame de handshake invalido ou grande demais",
            ))
        }
        Ok(Ok(Some(frame))) => frame,
    };

    match frame {
        Frame::Hello(h) => Ok(h),
        Frame::Request(_) => Err(ErrorBody::new(
            ErrorCode::handshake_required(),
            "Request recebido antes do Hello",
        )),
        _ => Err(ErrorBody::new(
            ErrorCode::malformed_frame(),
            "primeiro frame deve ser Hello",
        )),
    }
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
