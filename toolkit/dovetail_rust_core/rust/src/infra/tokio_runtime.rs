use std::future::Future;
use std::sync::OnceLock;

use tokio::runtime::{Builder, Runtime};

use crate::domain::bridge_error::BridgeError;

/// O runtime tokio do processo, construido uma vez. E infra porque e um
/// recurso do sistema: threads. A regra que roda sobre ele mora em `data`.
static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();

pub fn runtime() -> Result<&'static Runtime, BridgeError> {
    RUNTIME
        .get_or_init(|| {
            Builder::new_multi_thread()
                .enable_all()
                .thread_name("rust-bridge")
                .build()
                .map_err(|error| error.to_string())
        })
        .as_ref()
        .map_err(|reason| BridgeError::RuntimeUnavailable(reason.clone()))
}

pub async fn run_on_runtime<T, F>(future: F) -> Result<T, BridgeError>
where
    T: Send + 'static,
    F: Future<Output = T> + Send + 'static,
{
    runtime()?
        .spawn(future)
        .await
        .map_err(|joined| BridgeError::TaskPanicked(joined.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn run_on_runtime_carries_the_value_back() {
        let answer = run_on_runtime(async { 7_u32 }).await.unwrap();

        assert_eq!(answer, 7);
    }

    #[tokio::test]
    async fn run_on_runtime_reports_a_panicking_task_instead_of_unwinding() {
        let outcome = run_on_runtime(async { panic!("boom") }).await;

        assert!(matches!(outcome, Err(BridgeError::TaskPanicked(_))));
    }

    #[tokio::test]
    async fn runtime_is_built_once() {
        let first = runtime().unwrap();
        let second = runtime().unwrap();

        assert!(std::ptr::eq(first, second));
    }
}
