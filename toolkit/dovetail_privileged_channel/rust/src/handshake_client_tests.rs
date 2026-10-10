use std::time::Duration;

use anyhow::Result;
use tokio::io::duplex;
use tokio::time::timeout;

use crate::framing::{framer, recv_frame, send_frame};
use crate::handshake::{Frame, PeerCheck, ServerHello};
use crate::handshake_client::{client_handshake, ClientConfig, ClientHandshakeResult};
use crate::handshake_error::HandshakeError;
use crate::handshake_server::{server_handshake, ServerConfig};
use crate::limits::HANDSHAKE_TIMEOUT_MS;

fn cliente(major: u16, minor: u16) -> ClientConfig {
    ClientConfig {
        client_major: major,
        client_minor: minor,
        client_version: "0.1.0".into(),
    }
}

fn peer() -> PeerCheck {
    PeerCheck {
        method: "peercred".into(),
        subject: "uid=0".into(),
    }
}

fn servidor(major: u16, minor: u16) -> ServerConfig {
    ServerConfig {
        server_major: major,
        server_minor: minor,
        helper_version: "0.1.0".into(),
        peer_check: peer(),
    }
}

async fn contra_o_servidor(c: ClientConfig, s: ServerConfig) -> Result<ClientHandshakeResult> {
    let (a, b) = duplex(64 * 1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    let (r, servidor) = tokio::join!(
        client_handshake::<(), (), _>(&mut lado_cliente, c, [1; 16]),
        server_handshake::<(), (), _>(&mut lado_servidor, s, [7; 16]),
    );
    servidor.unwrap();
    r
}

async fn contra_um_servidor_que_responde(resposta: Option<ServerHello>) -> HandshakeError {
    let (a, b) = duplex(64 * 1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    let servidor = async move {
        recv_frame::<(), (), _>(&mut lado_servidor).await.unwrap();
        if let Some(sh) = resposta {
            send_frame(&mut lado_servidor, &Frame::<(), ()>::ServerHello(sh))
                .await
                .unwrap();
        }
    };
    let (r, ()) = tokio::join!(
        client_handshake::<(), (), _>(&mut lado_cliente, cliente(1, 1), [1; 16]),
        servidor,
    );
    r.unwrap_err().downcast().unwrap()
}

#[tokio::test]
async fn versoes_iguais_sao_aceitas() {
    let r = contra_o_servidor(cliente(1, 2), servidor(1, 2))
        .await
        .unwrap();
    assert!(r.server_hello.accepted);
    assert_eq!(r.negotiated_minor, 2);
}

#[tokio::test]
async fn minor_diferente_negocia_pelo_menor_dos_dois_lados() {
    let r = contra_o_servidor(cliente(1, 5), servidor(1, 1))
        .await
        .unwrap();
    assert_eq!(r.negotiated_minor, 1);
    let r = contra_o_servidor(cliente(1, 0), servidor(1, 2))
        .await
        .unwrap();
    assert_eq!(r.negotiated_minor, 0);
}

#[tokio::test]
async fn major_diferente_e_recusado_com_o_motivo() {
    let e = contra_o_servidor(cliente(2, 1), servidor(1, 1))
        .await
        .unwrap_err();
    assert!(
        matches!(
            e.downcast_ref(),
            Some(HandshakeError::Rejected { reason }) if reason.contains("major 2")
        ),
        "veio {e:#}"
    );
}

#[tokio::test]
async fn fim_do_fluxo_antes_do_server_hello() {
    let e = contra_um_servidor_que_responde(None).await;
    assert!(matches!(e, HandshakeError::StreamEnded), "veio {e}");
}

#[tokio::test]
async fn servidor_que_aceita_outro_major_e_recusado() {
    let e = contra_um_servidor_que_responde(Some(ServerHello {
        accepted: true,
        proto_major: 2,
        proto_minor: 0,
        helper_version: "9.0.0".into(),
        nonce: [7; 16],
        peer_check: peer(),
        reject: None,
    }))
    .await;
    assert!(
        matches!(
            e,
            HandshakeError::VersionMismatch {
                client: 1,
                server: 2
            }
        ),
        "veio {e}"
    );
}

#[tokio::test]
async fn servidor_mudo_estoura_o_prazo() {
    let (a, b) = duplex(64 * 1024);
    let mut lado_cliente = framer(a);
    let mut lado_servidor = framer(b);
    let (r, _) = timeout(Duration::from_millis(2 * HANDSHAKE_TIMEOUT_MS), async {
        tokio::join!(
            client_handshake::<(), (), _>(&mut lado_cliente, cliente(1, 1), [1; 16]),
            recv_frame::<(), (), _>(&mut lado_servidor),
        )
    })
    .await
    .expect("o cliente tem de desistir sozinho dentro do prazo");
    let e: HandshakeError = r.unwrap_err().downcast().unwrap();
    assert!(matches!(e, HandshakeError::Timeout), "veio {e}");
}
