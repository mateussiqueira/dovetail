use tokio::io::duplex;

use crate::envelope::{ErrorCode, Request};
use crate::framing::{framer, recv_frame, send_frame};
use crate::handshake::{Frame, Hello, PeerCheck, ServerHello};
use crate::handshake_error::HandshakeError;
use crate::handshake_server::{server_handshake, ServerConfig, ServerHandshakeResult};

type F = Frame<(), ()>;

const NONCE_DO_SERVIDOR: [u8; 16] = [7; 16];

fn servidor(major: u16, minor: u16) -> ServerConfig {
    ServerConfig {
        server_major: major,
        server_minor: minor,
        helper_version: "0.1.0".into(),
        peer_check: PeerCheck {
            method: "peercred".into(),
            subject: "uid=0".into(),
        },
    }
}

fn hello(major: u16, minor: u16) -> Hello {
    Hello {
        proto_major: major,
        proto_minor: minor,
        client_version: "0.1.0".into(),
        nonce: [1; 16],
    }
}

async fn apertar_a_mao(
    cliente: Hello,
    config: ServerConfig,
) -> (ServerHandshakeResult, ServerHello) {
    let (a, b) = duplex(64 * 1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    send_frame(&mut lado_cliente, &F::Hello(cliente))
        .await
        .unwrap();
    let r = server_handshake::<(), (), _>(&mut lado_servidor, config, NONCE_DO_SERVIDOR)
        .await
        .unwrap();
    match recv_frame::<(), (), _>(&mut lado_cliente).await.unwrap() {
        Some(Frame::ServerHello(sh)) => (r, sh),
        outro => panic!("esperava ServerHello, veio {outro:?}"),
    }
}

#[tokio::test]
async fn versoes_iguais_sao_aceitas() {
    let (r, sh) = apertar_a_mao(hello(1, 2), servidor(1, 2)).await;
    assert!(r.accepted);
    assert_eq!(r.negotiated_minor, 2);
    assert!(sh.accepted);
    assert_eq!((sh.proto_major, sh.proto_minor), (1, 2));
    assert!(sh.reject.is_none());
    assert_eq!(sh.nonce, NONCE_DO_SERVIDOR);
}

#[tokio::test]
async fn minor_diferente_negocia_pelo_menor_dos_dois_lados() {
    let (r, sh) = apertar_a_mao(hello(1, 5), servidor(1, 2)).await;
    assert_eq!((r.negotiated_minor, sh.proto_minor), (2, 2));
    let (r, sh) = apertar_a_mao(hello(1, 0), servidor(1, 2)).await;
    assert_eq!((r.negotiated_minor, sh.proto_minor), (0, 0));
}

#[tokio::test]
async fn major_diferente_e_recusado_com_o_motivo() {
    let (r, sh) = apertar_a_mao(hello(2, 1), servidor(1, 1)).await;
    assert!(!r.accepted);
    assert!(!sh.accepted);
    let motivo = sh.reject.expect("a recusa tem de levar o motivo");
    assert_eq!(motivo.code, ErrorCode::version_unsupported());
}

#[tokio::test]
async fn fim_do_fluxo_antes_do_hello() {
    let (a, b) = duplex(1024);
    let mut lado_servidor = framer(b);
    drop(a);
    let e = server_handshake::<(), (), _>(&mut lado_servidor, servidor(1, 1), NONCE_DO_SERVIDOR)
        .await
        .unwrap_err();
    assert!(
        matches!(e.downcast_ref(), Some(HandshakeError::StreamEnded)),
        "veio {e:#}"
    );
}

#[tokio::test]
async fn pedido_antes_do_hello_e_recusado() {
    let (a, b) = duplex(1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    let pedido = F::Request(Request { id: 1, cmd: () });
    send_frame(&mut lado_cliente, &pedido).await.unwrap();
    let e = server_handshake::<(), (), _>(&mut lado_servidor, servidor(1, 1), NONCE_DO_SERVIDOR)
        .await
        .unwrap_err();
    assert!(
        matches!(
            e.downcast_ref(),
            Some(HandshakeError::UnexpectedFrame {
                expected: "Hello",
                ..
            })
        ),
        "veio {e:#}"
    );
}
