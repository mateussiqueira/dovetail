use std::future::Future;

use tokio::task::JoinHandle;

use crate::domain::abortable_pump::AbortablePump;
use crate::domain::bridge_error::BridgeError;
use crate::infra::tokio_runtime::runtime;

pub struct PumpTask {
    handle: JoinHandle<()>,
}

impl PumpTask {
    pub fn spawn<F>(future: F) -> Result<PumpTask, BridgeError>
    where
        F: Future<Output = ()> + Send + 'static,
    {
        Ok(PumpTask {
            handle: runtime()?.spawn(future),
        })
    }

    pub fn abort(&self) {
        self.handle.abort();
    }

    pub fn is_finished(&self) -> bool {
        self.handle.is_finished()
    }
}

impl AbortablePump for PumpTask {
    fn abort(&self) {
        PumpTask::abort(self);
    }

    fn is_finished(&self) -> bool {
        PumpTask::is_finished(self)
    }
}

impl Drop for PumpTask {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::time::Duration;

    #[test]
    fn dropping_the_task_stops_the_work() {
        let ran = Arc::new(AtomicBool::new(false));
        let flag = ran.clone();

        let task = PumpTask::spawn(async move {
            tokio::time::sleep(Duration::from_secs(30)).await;
            flag.store(true, Ordering::SeqCst);
        })
        .expect("the runtime is available");

        drop(task);
        std::thread::sleep(Duration::from_millis(100));

        assert!(
            !ran.load(Ordering::SeqCst),
            "a dropped task must not go on to finish its work"
        );
    }

    #[test]
    fn abort_is_observable() {
        let task = PumpTask::spawn(async {
            tokio::time::sleep(Duration::from_secs(30)).await;
        })
        .expect("the runtime is available");

        task.abort();
        std::thread::sleep(Duration::from_millis(100));

        assert!(task.is_finished());
    }

    #[test]
    fn a_task_that_completes_reports_finished() {
        let task = PumpTask::spawn(async {}).expect("the runtime is available");
        std::thread::sleep(Duration::from_millis(100));

        assert!(task.is_finished());
    }
}
