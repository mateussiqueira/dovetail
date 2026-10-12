use tokio::io::{duplex, AsyncWriteExt};

use crate::envelope::ErrorCode;
use crate::framing::{framer, recv_frame, RecvError};
use crate::handshake::{Frame, PeerCheck};
use crate::handshake_error::HandshakeError;
use crate::handshake_server::{server_handshake, ServerConfig};

fn servidor() -> ServerConfig {
    ServerConfig {
        server_major: 1,
        server_minor: 1,
        helper_version: "0.1.0".into(),
        peer_check: PeerCheck {
            method: "peercred".into(),
            subject: "uid=0".into(),
        },
    }
}

async fn recusa_depois_de_fechar_a_escrita(bytes: &[u8]) -> (anyhow::Error, ErrorCode) {
    let (a, b) = duplex(1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    lado_cliente.get_mut().write_all(bytes).await.unwrap();
    lado_cliente.get_mut().shutdown().await.unwrap();
    let e = server_handshake::<(), (), _>(&mut lado_servidor, servidor(), [7; 16])
        .await
        .unwrap_err();
    drop(lado_servidor);
    match recv_frame::<(), (), _>(&mut lado_cliente).await.unwrap() {
        Some(Frame::ServerHello(sh)) if !sh.accepted => {
            (e, sh.reject.expect("a recusa tem de levar o codigo").code)
        }
        outro => panic!("o cliente ainda le e tem de receber a recusa, veio {outro:?}"),
    }
}

#[tokio::test]
async fn fluxo_que_acaba_antes_do_hello_recebe_handshake_required() {
    let (e, codigo) = recusa_depois_de_fechar_a_escrita(&[]).await;
    let e: HandshakeError = e.downcast().unwrap();
    assert!(matches!(e, HandshakeError::StreamEnded), "veio {e}");
    assert_eq!(codigo, ErrorCode::handshake_required());
}

#[tokio::test]
async fn frame_cortado_no_meio_recebe_handshake_required() {
    let mut cortado = 100u32.to_be_bytes().to_vec();
    cortado.extend_from_slice(b"{\"t\"");
    let (e, codigo) = recusa_depois_de_fechar_a_escrita(&cortado).await;
    let e: RecvError = e.downcast().unwrap();
    assert!(matches!(e, RecvError::Io(_)), "veio {e}");
    assert_eq!(codigo, ErrorCode::handshake_required());
}
