use std::ffi::{c_char, CString};
use std::ptr;

use tokio::sync::mpsc::{self, UnboundedReceiver};

use crate::xpc_ffi::{self, XpcObject};

const MACH_SERVICE_PRIVILEGED: u64 = 1 << 1;

pub struct XpcConnection {
    raw: XpcObject,
    inbound: UnboundedReceiver<Vec<u8>>,
}

unsafe impl Send for XpcConnection {}

impl XpcConnection {
    pub(crate) fn adopt(raw: XpcObject, inbound: UnboundedReceiver<Vec<u8>>) -> Self {
        Self { raw, inbound }
    }

    pub fn mach_service(name: &str) -> anyhow::Result<Self> {
        let name = CString::new(name)?;
        Ok(Self::open(
            name.as_ptr(),
            ptr::null_mut(),
            MACH_SERVICE_PRIVILEGED,
        ))
    }

    #[cfg(test)]
    pub(crate) fn to_endpoint(endpoint: XpcObject) -> Self {
        Self::open(ptr::null(), endpoint, 0)
    }

    fn open(service: *const c_char, endpoint: XpcObject, flags: u64) -> Self {
        let (tx, inbound) = mpsc::unbounded_channel();
        let raw = unsafe {
            xpc_ffi::dovetail_xpc_connect(
                service,
                endpoint,
                flags,
                xpc_ffi::sink(tx),
                xpc_ffi::deliver_bytes,
                xpc_ffi::free_boxed::<xpc_ffi::Sink<Vec<u8>>>,
            )
        };
        Self::adopt(raw, inbound)
    }

    pub fn send(&self, bytes: &[u8]) {
        unsafe { xpc_ffi::dovetail_xpc_send(self.raw, bytes.as_ptr(), bytes.len()) };
    }

    pub async fn recv(&mut self) -> Option<Vec<u8>> {
        self.inbound.recv().await
    }
}

impl Drop for XpcConnection {
    fn drop(&mut self) {
        unsafe {
            xpc_ffi::xpc_connection_cancel(self.raw);
            xpc_ffi::xpc_release(self.raw);
        }
    }
}
