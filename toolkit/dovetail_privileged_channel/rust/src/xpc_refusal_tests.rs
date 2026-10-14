use std::ffi::{c_char, c_void, CString};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tokio::time::timeout;

use crate::xpc_ffi::XpcObject;
use crate::xpc_listener::XpcListener;

const WAIT: Duration = Duration::from_secs(5);

extern "C" {
    fn dovetail_xpc_listen(
        service: *const c_char,
        requirement: *const c_char,
        ctx: *mut c_void,
        ctx_free: extern "C" fn(*mut c_void),
        on_peer: extern "C" fn(*mut c_void, XpcObject) -> *mut c_void,
        on_bytes: extern "C" fn(*mut c_void, *const u8, usize),
        peer_free: extern "C" fn(*mut c_void),
    ) -> XpcObject;
}

static FREED: AtomicBool = AtomicBool::new(false);

extern "C" fn mark_freed(_: *mut c_void) {
    FREED.store(true, Ordering::SeqCst);
}

extern "C" fn no_peer(_: *mut c_void, _: XpcObject) -> *mut c_void {
    ptr::null_mut()
}

extern "C" fn no_bytes(_: *mut c_void, _: *const u8, _: usize) {}

extern "C" fn no_free(_: *mut c_void) {}

#[tokio::test]
async fn a_refused_peer_hears_nothing_the_daemon_writes_back() {
    let mut listener = XpcListener::anonymous(Some("anchor apple"));
    let mut peer = listener.connect();
    peer.send(b"hello");
    let mut served = timeout(WAIT, listener.accept()).await.unwrap().unwrap();
    let got = timeout(WAIT, served.recv()).await.unwrap();
    assert_eq!(got, None);
    served.send(b"refusal");
    let heard = timeout(WAIT, peer.recv()).await.unwrap();
    assert_eq!(heard, None);
}

#[test]
fn a_named_service_with_no_requirement_is_refused_by_the_shim() {
    let name = CString::new("com.example.dovetail.unchecked").unwrap();
    let listener = unsafe {
        dovetail_xpc_listen(
            name.as_ptr(),
            ptr::null(),
            ptr::null_mut(),
            mark_freed,
            no_peer,
            no_bytes,
            no_free,
        )
    };
    assert!(listener.is_null());
    assert!(FREED.load(Ordering::SeqCst));
}
