use std::io;
use std::sync::Arc;

use dovetail_privileged_channel::{
    ErrorCode, Frame, RespPayload, Response, MAX_FRAME_BYTES, PROTOCOL_MAJOR,
};
use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};

use crate::connection::{handle_conn, handle_conn_with_generator};
use crate::connection_fixture::Then::{HangUp, Wait};
use crate::connection_fixture::{
    framed, hello, json, peer, refusal, request, server_hello, shown, wire_after, Echo,
};

#[tokio::test]
async fn a_hello_gets_the_smaller_minor_and_the_session_goes_on() {
    let reply = json(Frame::Response(Response {
        id: 1,
        payload: RespPayload::ok(()),
    }));
    let expected = [server_hello(0, None), reply].concat();
    let sent = [hello(PROTOCOL_MAJOR, 0), request()].concat();
    assert_eq!(wire_after(sent, HangUp).await, shown(expected));
}

#[tokio::test]
async fn another_major_is_refused_with_the_daemon_own_version() {
    let code = ErrorCode::version_unsupported();
    let refused = refusal(code, "protocolo major 2 nao suportado (helper fala 1)");
    assert_eq!(wire_after(hello(2, 0), Wait).await, refused);
}

#[tokio::test]
async fn a_request_before_the_hello_is_refused() {
    let code = ErrorCode::handshake_required();
    let refused = refusal(code, "Request recebido antes do Hello");
    assert_eq!(wire_after(request(), Wait).await, refused);
}

#[tokio::test]
async fn malformed_json_is_refused() {
    let code = ErrorCode::malformed_frame();
    let refused = refusal(code, "frame de handshake malformado");
    assert_eq!(wire_after(framed(b"{ not json"), Wait).await, refused);
}

#[tokio::test]
async fn a_frame_above_the_cap_is_refused() {
    let code = ErrorCode::frame_too_large();
    let refused = refusal(code, "frame de handshake acima do teto");
    let header = (MAX_FRAME_BYTES as u32 + 1).to_be_bytes().to_vec();
    assert_eq!(wire_after(header, Wait).await, refused);
}

#[tokio::test]
async fn a_silent_client_is_refused_at_the_deadline() {
    let code = ErrorCode::handshake_required();
    let refused = refusal(code, "handshake nao recebido dentro do prazo");
    assert_eq!(wire_after(Vec::new(), Wait).await, refused);
}

#[tokio::test]
async fn a_stream_that_ends_before_the_hello_is_refused() {
    let code = ErrorCode::handshake_required();
    let refused = refusal(code, "conexao fechada antes do handshake");
    assert_eq!(wire_after(Vec::new(), HangUp).await, refused);
}

#[tokio::test]
async fn a_frame_cut_in_the_middle_is_refused() {
    let code = ErrorCode::handshake_required();
    let refused = refusal(code, "conexao interrompida antes do handshake");
    let cut = [&100u32.to_be_bytes()[..], b"{\"t\""].concat();
    assert_eq!(wire_after(cut, HangUp).await, refused);
}

#[tokio::test]
async fn each_connection_draws_its_nonce_from_the_system() {
    let mut nonces = Vec::new();
    for _ in 0..16 {
        let (mut client, daemon) = duplex(1024);
        tokio::spawn(handle_conn(daemon, peer(), Arc::new(Echo)));
        client.shutdown().await.unwrap();
        let mut wire = Vec::new();
        client.read_to_end(&mut wire).await.unwrap();
        match serde_json::from_slice(&wire[4..]).unwrap() {
            Frame::<(), ()>::ServerHello(answer) => nonces.push(u128::from_le_bytes(answer.nonce)),
            other => panic!("expected a ServerHello, got {other:?}"),
        }
    }
    let rising = nonces.windows(2).all(|pair| pair[0] <= pair[1]);
    assert!(!rising, "nonces that rise like a clock: {nonces:?}");
}

#[tokio::test]
async fn a_failing_generator_closes_the_connection_before_the_handshake() {
    let (mut client, daemon) = duplex(1024);
    let dry: fn() -> io::Result<[u8; 16]> = || Err(io::Error::other("no entropy"));
    let connection = handle_conn_with_generator(daemon, peer(), Arc::new(Echo), dry);
    let served = tokio::spawn(connection);
    let mut wire = Vec::new();
    client.read_to_end(&mut wire).await.unwrap();
    assert_eq!(shown(wire), "", "the daemon answered without a nonce");
    assert!(served.await.unwrap().is_err());
}
