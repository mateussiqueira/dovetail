use std::sync::Arc;
use std::time::Duration;

use dovetail_privileged_channel::{
    ErrorBody, ErrorCode, Frame, Hello, PeerCheck, Request, RespPayload, ServerHello,
    HANDSHAKE_TIMEOUT_MS, PROTOCOL_MAJOR, PROTOCOL_MINOR,
};
use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};
use tokio::time::timeout;

use crate::connection::handle_conn_with_nonce;
use crate::{DaemonApp, ServiceIdentity};

pub(crate) const NONCE: [u8; 16] = [7; 16];

#[derive(Default)]
pub(crate) struct Echo;

#[async_trait::async_trait]
impl DaemonApp for Echo {
    type Command = ();
    type Reply = ();
    const ENDPOINT: &'static str = "";
    const IDENTITY: ServiceIdentity = ServiceIdentity {
        windows_name: "",
        windows_display: "",
        windows_description: "",
        macos_label: "",
        linux_unit: "",
    };
    const VERSION: &'static str = "9.9.9";
    const LOG_DIR: &'static str = "";

    fn command_timeout(_: &()) -> Duration {
        Duration::from_secs(1)
    }

    fn validate(_: &()) -> Result<(), String> {
        Ok(())
    }

    async fn dispatch(&self, _: &()) -> RespPayload<()> {
        RespPayload::ok(())
    }
}

pub(crate) enum Then {
    HangUp,
    Wait,
}

pub(crate) fn peer() -> PeerCheck {
    PeerCheck {
        method: "peercred".into(),
        subject: "uid=0".into(),
    }
}

pub(crate) fn framed(body: &[u8]) -> Vec<u8> {
    [&(body.len() as u32).to_be_bytes()[..], body].concat()
}

pub(crate) fn json(frame: Frame<(), ()>) -> Vec<u8> {
    framed(&serde_json::to_vec(&frame).unwrap())
}

pub(crate) fn hello(major: u16, minor: u16) -> Vec<u8> {
    json(Frame::Hello(Hello {
        proto_major: major,
        proto_minor: minor,
        client_version: "0.1.0".into(),
        nonce: [1; 16],
    }))
}

pub(crate) fn request() -> Vec<u8> {
    json(Frame::Request(Request { id: 1, cmd: () }))
}

pub(crate) fn server_hello(proto_minor: u16, reject: Option<ErrorBody>) -> Vec<u8> {
    json(Frame::ServerHello(ServerHello {
        accepted: reject.is_none(),
        proto_major: PROTOCOL_MAJOR,
        proto_minor,
        helper_version: Echo::VERSION.into(),
        nonce: NONCE,
        peer_check: peer(),
        reject,
    }))
}

pub(crate) fn shown(wire: Vec<u8>) -> String {
    wire.escape_ascii().to_string()
}

pub(crate) fn refusal(code: ErrorCode, message: &str) -> String {
    let reject = ErrorBody::new(code, message);
    shown(server_hello(PROTOCOL_MINOR, Some(reject)))
}

pub(crate) async fn wire_after(sent: Vec<u8>, then: Then) -> String {
    let (mut client, daemon) = duplex(256 * 1024);
    let connection = handle_conn_with_nonce(daemon, peer(), Arc::new(Echo), NONCE);
    tokio::spawn(connection);
    client.write_all(&sent).await.unwrap();
    if let Then::HangUp = then {
        client.shutdown().await.unwrap();
    }
    let mut wire = Vec::new();
    let deadline = Duration::from_millis(2 * HANDSHAKE_TIMEOUT_MS);
    timeout(deadline, client.read_to_end(&mut wire))
        .await
        .expect("the daemon answers and closes within twice the handshake deadline")
        .unwrap();
    shown(wire)
}
