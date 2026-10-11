use std::time::Duration;

use tokio::io::{duplex, AsyncWriteExt};
use tokio::time::timeout;

use crate::envelope::{ErrorBody, ErrorCode, Request, RespPayload, Response};
use crate::framing::{framer, recv_frame, send_frame, RecvError};
use crate::handshake::{Frame, PeerCheck, ServerHello};
use crate::handshake_client::{client_handshake, ClientConfig};
use crate::handshake_error::HandshakeError;
use crate::handshake_server::{server_handshake, ServerConfig};
use crate::limits::{HANDSHAKE_TIMEOUT_MS, MAX_FRAME_BYTES};

type F = Frame<(), ()>;

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

fn frame_cru(corpo: &[u8]) -> Vec<u8> {
    let mut v = (corpo.len() as u32).to_be_bytes().to_vec();
    v.extend_from_slice(corpo);
    v
}

async fn servidor_depois_de(bytes: &[u8]) -> (anyhow::Error, Option<ErrorCode>) {
    let (a, b) = duplex(64 * 1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    lado_cliente.get_mut().write_all(bytes).await.unwrap();
    let handshake = server_handshake::<(), (), _>(&mut lado_servidor, servidor(), [7; 16]);
    let e = timeout(Duration::from_millis(2 * HANDSHAKE_TIMEOUT_MS), handshake)
        .await
        .expect("o servidor tem de desistir sozinho dentro do prazo")
        .unwrap_err();
    drop(lado_servidor);
    match recv_frame::<(), (), _>(&mut lado_cliente).await.unwrap() {
        None => (e, None),
        Some(Frame::ServerHello(sh)) if !sh.accepted => (
            e,
            Some(sh.reject.expect("a recusa tem de levar o codigo").code),
        ),
        outro => panic!("so uma recusa pode chegar ao cliente, veio {outro:?}"),
    }
}

#[tokio::test]
async fn cliente_mudo_estoura_o_prazo_e_nada_vai_no_fio() {
    let (e, recusa) = servidor_depois_de(&[]).await;
    let e: HandshakeError = e.downcast().unwrap();
    assert!(matches!(e, HandshakeError::Timeout), "veio {e}");
    assert_eq!(recusa, None);
}

#[tokio::test]
async fn json_malformado_e_recusado_no_fio_com_malformed_frame() {
    let (e, recusa) = servidor_depois_de(&frame_cru(b"{ isso nao e json")).await;
    let e: RecvError = e.downcast().unwrap();
    assert!(matches!(e, RecvError::Malformed(_)), "veio {e}");
    assert_eq!(recusa, Some(ErrorCode::malformed_frame()));
}

#[tokio::test]
async fn frame_acima_do_teto_e_recusado_no_fio_com_frame_too_large() {
    let cabecalho = (MAX_FRAME_BYTES as u32 + 1).to_be_bytes();
    let (e, recusa) = servidor_depois_de(&cabecalho).await;
    let e: RecvError = e.downcast().unwrap();
    assert!(matches!(e, RecvError::TooLarge), "veio {e}");
    assert_eq!(recusa, Some(ErrorCode::frame_too_large()));
}

#[tokio::test]
async fn resposta_no_lugar_do_hello_e_recusada_com_malformed_frame() {
    let payload = RespPayload::ok(());
    let resposta = serde_json::to_vec(&F::Response(Response { id: 1, payload })).unwrap();
    let (e, recusa) = servidor_depois_de(&frame_cru(&resposta)).await;
    let e: HandshakeError = e.downcast().unwrap();
    assert!(matches!(e, HandshakeError::UnexpectedFrame { .. }), "{e}");
    assert_eq!(recusa, Some(ErrorCode::malformed_frame()));
}

#[tokio::test]
async fn falha_ao_mandar_a_recusa_nao_esconde_o_erro_original() {
    let (a, b) = duplex(1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    let pedido = F::Request(Request { id: 1, cmd: () });
    send_frame(&mut lado_cliente, &pedido).await.unwrap();
    drop(lado_cliente);
    let r = server_handshake::<(), (), _>(&mut lado_servidor, servidor(), [7; 16]).await;
    let e: HandshakeError = r.unwrap_err().downcast().unwrap();
    assert!(matches!(e, HandshakeError::UnexpectedFrame { .. }), "{e}");
}

async fn cliente_contra_a_recusa(reject: Option<ErrorBody>) -> HandshakeError {
    let (a, b) = duplex(64 * 1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    let recusa = F::ServerHello(ServerHello {
        accepted: false,
        proto_major: 1,
        proto_minor: 1,
        helper_version: "0.1.0".into(),
        nonce: [7; 16],
        peer_check: servidor().peer_check,
        reject,
    });
    send_frame(&mut lado_servidor, &recusa).await.unwrap();
    let config = ClientConfig {
        client_major: 1,
        client_minor: 1,
        client_version: "0.1.0".into(),
    };
    let r = client_handshake::<(), (), _>(&mut lado_cliente, config, [1; 16]).await;
    r.unwrap_err().downcast().unwrap()
}

#[tokio::test]
async fn o_cliente_guarda_o_codigo_que_o_servidor_mandou() {
    let corpo = ErrorBody::new(ErrorCode::peer_rejected(), "assinatura nao confere");
    let e = cliente_contra_a_recusa(Some(corpo)).await;
    assert!(e.to_string().contains("assinatura nao confere"), "veio {e}");
    let HandshakeError::Rejected { reject: Some(r) } = e else {
        panic!("esperava Rejected com o motivo");
    };
    assert_eq!(r.code, ErrorCode::peer_rejected());
}

#[tokio::test]
async fn recusa_sem_corpo_diz_que_nao_ha_motivo() {
    let e = cliente_contra_a_recusa(None).await;
    assert!(e.to_string().contains("sem motivo informado"), "veio {e}");
    assert!(matches!(e, HandshakeError::Rejected { reject: None }));
}
