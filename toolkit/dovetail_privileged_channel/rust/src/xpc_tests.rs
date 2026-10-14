use std::process::Command;
use std::time::Duration;

use tokio::time::timeout;

use crate::xpc_listener::XpcListener;

const WAIT: Duration = Duration::from_secs(5);

fn this_test_binary_cdhash() -> String {
    let exe = std::env::current_exe().unwrap();
    let out = Command::new("codesign")
        .arg("-dvvv")
        .arg(exe)
        .output()
        .unwrap();
    let text = String::from_utf8_lossy(&out.stderr).to_string();
    let line = text.lines().find(|l| l.starts_with("CDHash=")).unwrap();
    line.trim_start_matches("CDHash=").to_string()
}

#[tokio::test]
async fn a_message_reaches_the_listener_and_its_reply_reaches_the_peer() {
    let mut listener = XpcListener::anonymous(None);
    let mut peer = listener.connect();
    peer.send(b"hello");
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    let got = timeout(WAIT, served.recv()).await.unwrap();
    assert_eq!(got.as_deref(), Some(&b"hello"[..]));
    served.send(b"reply");
    let back = timeout(WAIT, peer.recv()).await.unwrap();
    assert_eq!(back.as_deref(), Some(&b"reply"[..]));
}

#[tokio::test]
async fn a_peer_the_requirement_does_not_name_gets_no_message_through() {
    let mut listener = XpcListener::anonymous(Some("anchor apple"));
    let peer = listener.connect();
    peer.send(b"command");
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    let got = timeout(WAIT, served.recv()).await.unwrap();
    assert_eq!(got, None);
}

#[tokio::test]
async fn a_peer_whose_cdhash_the_requirement_pins_is_heard() {
    let requirement = format!("cdhash H\"{}\"", this_test_binary_cdhash());
    let mut listener = XpcListener::anonymous(Some(&requirement));
    let peer = listener.connect();
    peer.send(b"command");
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    let got = timeout(WAIT, served.recv()).await.unwrap();
    assert_eq!(got.as_deref(), Some(&b"command"[..]));
}

#[tokio::test]
async fn a_requirement_that_does_not_parse_refuses_every_peer() {
    let mut listener = XpcListener::anonymous(Some("not a requirement ("));
    let peer = listener.connect();
    peer.send(b"command");
    let closed = timeout(Duration::from_secs(1), listener.accept()).await;
    assert!(
        closed.is_err(),
        "a peer was accepted under a broken requirement"
    );
}

#[tokio::test]
async fn a_mach_service_launchd_does_not_know_ends_the_accept_stream() {
    let mut listener =
        XpcListener::mach_service("com.example.dovetail.absent", "anchor apple").unwrap();
    let ended = timeout(WAIT, listener.accept()).await.unwrap();
    assert!(ended.is_none());
}
