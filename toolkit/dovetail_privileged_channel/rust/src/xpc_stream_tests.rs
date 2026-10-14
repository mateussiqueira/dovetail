use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::time::timeout;

use crate::xpc_listener::XpcListener;

const WAIT: Duration = Duration::from_secs(5);

#[tokio::test]
async fn one_message_is_read_across_two_reads_in_order() {
    let mut listener = XpcListener::anonymous(None);
    let mut peer = listener.connect();
    peer.write_all(b"0123456789").await.unwrap();
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    let mut head = [0u8; 4];
    let mut tail = [0u8; 6];
    timeout(WAIT, served.read_exact(&mut head))
        .await
        .unwrap()
        .unwrap();
    timeout(WAIT, served.read_exact(&mut tail))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(&head, b"0123");
    assert_eq!(&tail, b"456789");
}

#[tokio::test]
async fn bytes_written_in_two_messages_arrive_as_one_stream() {
    let mut listener = XpcListener::anonymous(None);
    let mut peer = listener.connect();
    peer.write_all(b"abc").await.unwrap();
    peer.write_all(b"def").await.unwrap();
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    let mut got = [0u8; 6];
    timeout(WAIT, served.read_exact(&mut got))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(&got, b"abcdef");
}

#[tokio::test]
async fn a_peer_that_goes_away_reads_as_end_of_stream() {
    let mut listener = XpcListener::anonymous(None);
    let mut peer = listener.connect();
    peer.write_all(b"x").await.unwrap();
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    assert_eq!(served.read_u8().await.unwrap(), b'x');
    drop(peer);
    let read = timeout(WAIT, served.read(&mut [0u8; 1]))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(read, 0);
}

#[tokio::test]
async fn the_daemon_learns_the_pid_of_the_process_behind_the_peer() {
    let mut listener = XpcListener::anonymous(None);
    let mut peer = listener.connect();
    peer.write_all(b"x").await.unwrap();
    let served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    assert_eq!(served.pid(), std::process::id() as i32);
}
