use std::ffi::{c_char, c_void, CString};
use std::ptr;
use std::sync::Mutex;

use tokio::sync::mpsc::{self, UnboundedReceiver};

use crate::xpc_connection::XpcConnection;
use crate::xpc_ffi::{self, offer, BytesFn, FreeFn, Sink, XpcObject};

type PeerFn = extern "C" fn(*mut c_void, XpcObject) -> *mut c_void;

extern "C" {
    fn dovetail_xpc_listen(
        service: *const c_char,
        requirement: *const c_char,
        ctx: *mut c_void,
        ctx_free: FreeFn,
        on_peer: PeerFn,
        on_bytes: BytesFn,
        peer_free: FreeFn,
    ) -> XpcObject;
    fn xpc_retain(object: XpcObject) -> XpcObject;
    #[cfg(test)]
    fn xpc_endpoint_create(conn: XpcObject) -> XpcObject;
}

pub struct XpcListener {
    raw: XpcObject,
    incoming: UnboundedReceiver<XpcConnection>,
}

unsafe impl Send for XpcListener {}

struct Accepting {
    peers: Sink<XpcConnection>,
    requirement: Option<CString>,
}

impl XpcListener {
    pub fn mach_service(name: &str, requirement: &str) -> anyhow::Result<Self> {
        let requirement = Some(CString::new(requirement)?);
        Ok(Self::listen(Some(CString::new(name)?), requirement))
    }

    #[cfg(test)]
    pub(crate) fn anonymous(requirement: Option<&str>) -> Self {
        let requirement = requirement.map(|r| CString::new(r).expect("requisito sem NUL"));
        Self::listen(None, requirement)
    }

    fn listen(service: Option<CString>, requirement: Option<CString>) -> Self {
        let (tx, incoming) = mpsc::unbounded_channel();
        let accepting = Box::new(Accepting {
            peers: Mutex::new(Some(tx)),
            requirement,
        });
        let wanted = accepting
            .requirement
            .as_ref()
            .map_or(ptr::null(), |r| r.as_ptr());
        let name = service.as_ref().map_or(ptr::null(), |s| s.as_ptr());
        let raw = unsafe {
            dovetail_xpc_listen(
                name,
                wanted,
                Box::into_raw(accepting).cast(),
                xpc_ffi::free_boxed::<Accepting>,
                admit_peer,
                xpc_ffi::deliver_bytes,
                xpc_ffi::free_boxed::<Sink<Vec<u8>>>,
            )
        };
        Self { raw, incoming }
    }

    pub async fn accept(&mut self) -> Option<XpcConnection> {
        self.incoming.recv().await
    }

    #[cfg(test)]
    pub(crate) fn connect(&self) -> XpcConnection {
        unsafe {
            let endpoint = xpc_endpoint_create(self.raw);
            let conn = XpcConnection::to_endpoint(endpoint);
            xpc_ffi::xpc_release(endpoint);
            conn
        }
    }
}

impl Drop for XpcListener {
    fn drop(&mut self) {
        unsafe {
            xpc_ffi::xpc_connection_cancel(self.raw);
            xpc_ffi::xpc_release(self.raw);
        }
    }
}

extern "C" fn admit_peer(ctx: *mut c_void, peer: XpcObject) -> *mut c_void {
    let accepting = unsafe { &*ctx.cast::<Accepting>() };
    if peer.is_null() {
        offer(&accepting.peers, None);
        return ptr::null_mut();
    }
    let (tx, inbound) = mpsc::unbounded_channel();
    let conn = XpcConnection::adopt(unsafe { xpc_retain(peer) }, inbound);
    if offer(&accepting.peers, Some(conn)) {
        xpc_ffi::sink(tx)
    } else {
        ptr::null_mut()
    }
}
