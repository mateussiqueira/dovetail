use std::process::{Command, Stdio};
use std::time::Duration;

use tokio::time::timeout;

use crate::{bind, AcceptError, Endpoint, PeerPolicy};

const NETCAT: &str = "anchor apple and identifier \"com.apple.nc\"";

fn endpoint_requiring_netcat(name: &str) -> Endpoint {
    let dir = std::env::temp_dir().join(format!("dovetail-code-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let address = dir.join("helper.sock").to_str().unwrap().to_string();
    Endpoint::new(address).with_peer_policy(PeerPolicy::default().require_code(NETCAT))
}

fn forget(endpoint: &Endpoint) {
    let _ = std::fs::remove_dir_all(endpoint.directory().unwrap());
}

#[tokio::test]
async fn the_program_the_requirement_names_is_admitted() {
    let endpoint = endpoint_requiring_netcat("admitted");
    let mut listener = bind(&endpoint).await.unwrap();
    let mut netcat = Command::new("/usr/bin/nc")
        .arg("-U")
        .arg(endpoint.address())
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .spawn()
        .unwrap();
    let accepted = timeout(Duration::from_secs(10), listener.accept()).await;
    netcat.kill().unwrap();
    netcat.wait().unwrap();
    forget(&endpoint);
    let (_, peer) = accepted.unwrap().unwrap();
    assert_eq!(peer.method, "peertoken+codesign");
    assert_eq!(peer.subject, format!("pid={}", netcat.id()));
}

#[tokio::test]
async fn a_process_the_requirement_does_not_name_is_refused() {
    let endpoint = endpoint_requiring_netcat("refused");
    let mut listener = bind(&endpoint).await.unwrap();
    let _this_process = tokio::net::UnixStream::connect(endpoint.address())
        .await
        .unwrap();
    let refused = timeout(Duration::from_secs(10), listener.accept()).await;
    forget(&endpoint);
    let reason = match refused.unwrap() {
        Err(AcceptError::PeerRefused(reason)) => reason.to_string(),
        other => panic!("expected PeerRefused, got {other:?}"),
    };
    assert!(reason.contains("nao satisfaz o requisito"), "{reason}");
}
