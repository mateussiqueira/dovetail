use std::sync::OnceLock;

use tokio::sync::broadcast::{self, Receiver, Sender};
use tracing::Level;

use crate::data::line_subscriber::LineSubscriber;
use crate::domain::bridge_error::BridgeError;

static LINES: OnceLock<Result<Sender<String>, String>> = OnceLock::new();

pub fn log_lines() -> Result<Receiver<String>, BridgeError> {
    LINES
        .get_or_init(|| {
            let (sender, _) = broadcast::channel(1024);
            tracing::subscriber::set_global_default(LineSubscriber::new(
                sender.clone(),
                Level::INFO,
            ))
            .map(|()| sender)
            .map_err(|error| error.to_string())
        })
        .as_ref()
        .map(Sender::subscribe)
        .map_err(|reason| BridgeError::LogUnavailable(reason.clone()))
}

#[cfg(test)]
mod tests {
    use tracing::subscriber::NoSubscriber;

    use super::*;

    #[test]
    fn a_process_that_already_has_a_subscriber_gets_a_typed_refusal() {
        tracing::subscriber::set_global_default(NoSubscriber::default()).unwrap();

        let refused = log_lines();

        assert!(matches!(refused, Err(BridgeError::LogUnavailable(_))));
    }
}
