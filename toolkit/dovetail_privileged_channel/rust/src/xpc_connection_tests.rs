use std::time::Duration;

use tokio::time::timeout;

use crate::xpc_connection::XpcConnection;

#[tokio::test]
async fn a_client_of_a_service_launchd_does_not_know_sees_the_connection_close() {
    let mut client = XpcConnection::mach_service("com.example.dovetail.absent").unwrap();
    client.send(b"hello");
    let got = timeout(Duration::from_secs(5), client.recv())
        .await
        .unwrap();
    assert_eq!(got, None);
}

#[test]
fn a_service_name_with_a_nul_byte_is_refused_before_it_reaches_launchd() {
    let refused = XpcConnection::mach_service("com.example\0helper");
    assert!(refused.is_err());
}
