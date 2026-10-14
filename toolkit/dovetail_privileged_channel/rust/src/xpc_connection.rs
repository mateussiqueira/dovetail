use std::ffi::{c_char, CString};
use std::io;
use std::pin::Pin;
use std::ptr;
use std::task::{ready, Context, Poll};

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::mpsc::{self, UnboundedReceiver};

use crate::xpc_ffi::{self, XpcObject};

const MACH_SERVICE_PRIVILEGED: u64 = 1 << 1;

pub struct XpcConnection {
    raw: XpcObject,
    inbound: UnboundedReceiver<Vec<u8>>,
    pending: Vec<u8>,
}

extern "C" {
    fn xpc_connection_get_pid(conn: XpcObject) -> i32;
}

unsafe impl Send for XpcConnection {}

impl XpcConnection {
    pub(crate) fn adopt(raw: XpcObject, inbound: UnboundedReceiver<Vec<u8>>) -> Self {
        Self {
            raw,
            inbound,
            pending: Vec::new(),
        }
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

    pub fn flush(&self) {
        unsafe { xpc_ffi::dovetail_xpc_flush(self.raw) };
    }

    pub fn pid(&self) -> i32 {
        unsafe { xpc_connection_get_pid(self.raw) }
    }

    pub async fn recv(&mut self) -> Option<Vec<u8>> {
        if !self.pending.is_empty() {
            return Some(std::mem::take(&mut self.pending));
        }
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

impl AsyncRead for XpcConnection {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = &mut *self;
        if this.pending.is_empty() {
            match ready!(this.inbound.poll_recv(cx)) {
                Some(bytes) => this.pending = bytes,
                None => return Poll::Ready(Ok(())),
            }
        }
        let taken = this.pending.len().min(buf.remaining());
        buf.put_slice(&this.pending[..taken]);
        this.pending.drain(..taken);
        Poll::Ready(Ok(()))
    }
}

impl AsyncWrite for XpcConnection {
    fn poll_write(
        self: Pin<&mut Self>,
        _: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        if !buf.is_empty() {
            self.send(buf);
        }
        Poll::Ready(Ok(buf.len()))
    }

    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }
}
