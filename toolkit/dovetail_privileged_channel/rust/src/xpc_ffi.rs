use std::ffi::{c_char, c_void};
use std::sync::{Mutex, PoisonError};

use tokio::sync::mpsc::UnboundedSender;

pub(crate) type XpcObject = *mut c_void;
pub(crate) type BytesFn = extern "C" fn(*mut c_void, *const u8, usize);
pub(crate) type FreeFn = extern "C" fn(*mut c_void);

extern "C" {
    pub(crate) fn dovetail_xpc_connect(
        service: *const c_char,
        endpoint: XpcObject,
        flags: u64,
        ctx: *mut c_void,
        on_bytes: BytesFn,
        ctx_free: FreeFn,
    ) -> XpcObject;
    pub(crate) fn dovetail_xpc_send(conn: XpcObject, bytes: *const u8, len: usize);
    pub(crate) fn dovetail_xpc_flush(conn: XpcObject);
    pub(crate) fn xpc_release(object: XpcObject);
    pub(crate) fn xpc_connection_cancel(conn: XpcObject);
}

pub(crate) type Sink<T> = Mutex<Option<UnboundedSender<T>>>;

pub(crate) fn sink<T>(tx: UnboundedSender<T>) -> *mut c_void {
    Box::into_raw(Box::new(Mutex::new(Some(tx)))).cast()
}

pub(crate) fn offer<T>(sink: &Sink<T>, item: Option<T>) -> bool {
    let mut guard = sink.lock().unwrap_or_else(PoisonError::into_inner);
    match (item, guard.as_ref()) {
        (Some(item), Some(tx)) => tx.send(item).is_ok(),
        (Some(_), None) => false,
        (None, _) => guard.take().is_some(),
    }
}

pub(crate) extern "C" fn free_boxed<T>(ctx: *mut c_void) {
    drop(unsafe { Box::from_raw(ctx.cast::<T>()) });
}

pub(crate) extern "C" fn deliver_bytes(ctx: *mut c_void, bytes: *const u8, len: usize) {
    let frame =
        (!bytes.is_null()).then(|| unsafe { std::slice::from_raw_parts(bytes, len) }.to_vec());
    offer(unsafe { &*ctx.cast::<Sink<Vec<u8>>>() }, frame);
}
