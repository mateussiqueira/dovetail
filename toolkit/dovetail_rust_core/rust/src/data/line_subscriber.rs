use std::fmt::{Debug, Write};
use std::sync::atomic::{AtomicU64, Ordering};

use tokio::sync::broadcast::Sender;
use tracing::field::{Field, Visit};
use tracing::span::{Attributes, Id, Record};
use tracing::{Event, Level, Metadata, Subscriber};

pub struct LineSubscriber {
    sender: Sender<String>,
    max_level: Level,
    next_span: AtomicU64,
}

impl LineSubscriber {
    pub fn new(sender: Sender<String>, max_level: Level) -> LineSubscriber {
        LineSubscriber {
            sender,
            max_level,
            next_span: AtomicU64::new(1),
        }
    }
}

#[derive(Default)]
struct Line {
    message: String,
    fields: String,
}

impl Visit for Line {
    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "message" {
            self.message.push_str(value);
        } else {
            let _ = write!(self.fields, " {}={value}", field.name());
        }
    }

    fn record_debug(&mut self, field: &Field, value: &dyn Debug) {
        if field.name() == "message" {
            let _ = write!(self.message, "{value:?}");
        } else {
            let _ = write!(self.fields, " {}={value:?}", field.name());
        }
    }
}

impl Subscriber for LineSubscriber {
    fn enabled(&self, metadata: &Metadata<'_>) -> bool {
        *metadata.level() <= self.max_level
    }

    fn new_span(&self, _: &Attributes<'_>) -> Id {
        Id::from_u64(self.next_span.fetch_add(1, Ordering::Relaxed))
    }

    fn record(&self, _: &Id, _: &Record<'_>) {}

    fn record_follows_from(&self, _: &Id, _: &Id) {}

    fn event(&self, event: &Event<'_>) {
        let mut line = Line::default();
        event.record(&mut line);
        let metadata = event.metadata();
        let _ = self.sender.send(format!(
            "{} {}: {}{}",
            metadata.level(),
            metadata.target(),
            line.message,
            line.fields
        ));
    }

    fn enter(&self, _: &Id) {}

    fn exit(&self, _: &Id) {}
}

#[cfg(test)]
mod tests {
    use tokio::sync::broadcast;
    use tracing::subscriber::with_default;

    use super::*;

    #[test]
    fn an_event_becomes_one_line_with_level_target_message_and_fields() {
        let (sender, mut lines) = broadcast::channel(8);

        with_default(LineSubscriber::new(sender, Level::INFO), || {
            tracing::info!(target: "probe", attempt = 2, "hello from rust");
        });

        assert_eq!(
            lines.try_recv().unwrap(),
            "INFO probe: hello from rust attempt=2"
        );
    }

    #[test]
    fn a_text_field_is_written_without_quotes() {
        let (sender, mut lines) = broadcast::channel(8);

        with_default(LineSubscriber::new(sender, Level::INFO), || {
            tracing::warn!(target: "probe", file = "store.json", "slow write");
        });

        assert_eq!(
            lines.try_recv().unwrap(),
            "WARN probe: slow write file=store.json"
        );
    }

    #[test]
    fn an_event_more_verbose_than_the_level_is_dropped() {
        let (sender, mut lines) = broadcast::channel(8);

        with_default(LineSubscriber::new(sender, Level::INFO), || {
            tracing::debug!(target: "probe", "noise");
        });

        assert!(lines.try_recv().is_err());
    }

    #[test]
    fn an_event_inside_a_span_still_becomes_a_line() {
        let (sender, mut lines) = broadcast::channel(8);

        with_default(LineSubscriber::new(sender, Level::INFO), || {
            let span = tracing::info_span!("request");
            let _entered = span.enter();
            tracing::info!(target: "probe", "inside");
        });

        assert_eq!(lines.try_recv().unwrap(), "INFO probe: inside");
    }
}
