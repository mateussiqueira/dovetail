//! The typed channel between the app and the Rust core.
//!
//! Each function here is a repasse: take the core's types, mirror them, and
//! pass them through `support::run`, which runs the future on the dovetail_rust_core
//! runtime. The app never touches `{{name}}_core` directly.

use std::sync::Arc;

use {{name}}_core::CoreHandle;

use crate::support::run;

pub struct RustCore {
    inner: Arc<CoreHandle>,
}

impl RustCore {
    pub async fn start() -> Result<RustCore, String> {
        let handle = run(async { Ok(CoreHandle::new()) }).await?;
        Ok(RustCore {
            inner: Arc::new(handle),
        })
    }

    pub async fn greeting(&self) -> Result<String, String> {
        let core = self.inner.clone();
        run(async move { core.greeting() }).await
    }
}
