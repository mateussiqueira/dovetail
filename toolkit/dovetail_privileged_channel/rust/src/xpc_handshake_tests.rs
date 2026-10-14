use std::time::Duration;

use tokio::time::timeout;

use crate::envelope::{Request, RespPayload, Response};
use crate::framing::{framer, recv_frame, send_frame};
use crate::handshake::{Frame, PeerCheck};
use crate::handshake_client::{client_handshake, ClientConfig};
use crate::handshake_server::{server_handshake, ServerConfig};
use crate::xpc_listener::XpcListener;

const WAIT: Duration = Duration::from_secs(5);

fn client() -> ClientConfig {
    ClientConfig {
        client_major: 1,
        client_minor: 0,
        client_version: "0.1.0".into(),
    }
}

fn server() -> ServerConfig {
    ServerConfig {
        server_major: 1,
        server_minor: 0,
        helper_version: "0.1.0".into(),
        peer_check: PeerCheck {
            method: "xpc+codesign".into(),
            subject: "pid=1".into(),
        },
    }
}

#[tokio::test]
async fn the_handshake_and_a_request_cross_an_xpc_connection_unchanged() {
    let mut listener = XpcListener::anonymous(None);
    let mut app = framer(listener.connect());
    let app_side = async {
        let shake = client_handshake::<u32, u32, _>(&mut app, client(), [1; 16]).await;
        let request = Frame::<u32, u32>::Request(Request { id: 9, cmd: 41 });
        send_frame(&mut app, &request).await.unwrap();
        let reply = recv_frame::<u32, u32, _>(&mut app).await.unwrap();
        (shake.unwrap(), reply)
    };
    let daemon_side = async {
        let mut daemon = framer(listener.accept().await.unwrap());
        let shake = server_handshake::<u32, u32, _>(&mut daemon, server(), [7; 16]).await;
        let request = match recv_frame::<u32, u32, _>(&mut daemon).await.unwrap() {
            Some(Frame::Request(request)) => request,
            other => panic!("expected a request, got {other:?}"),
        };
        let payload = RespPayload::ok(request.cmd + 1);
        let response = Frame::<u32, u32>::Response(Response {
            id: request.id,
            payload,
        });
        send_frame(&mut daemon, &response).await.unwrap();
        shake.unwrap()
    };
    let ((app_shake, reply), daemon_shake) =
        timeout(WAIT, async { tokio::join!(app_side, daemon_side) })
            .await
            .unwrap();
    assert!(daemon_shake.accepted);
    assert_eq!(app_shake.server_hello.peer_check.method, "xpc+codesign");
    let response = match reply {
        Some(Frame::Response(response)) => response,
        other => panic!("expected a response, got {other:?}"),
    };
    assert_eq!(response.id, 9);
    assert!(matches!(response.payload, RespPayload::Ok { ok: 42 }));
}
