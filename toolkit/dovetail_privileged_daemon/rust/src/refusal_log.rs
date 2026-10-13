use std::time::{Duration, Instant};

pub(crate) struct RefusalLog {
    window: Duration,
    last_line: Option<Instant>,
    silenced: u64,
}

impl RefusalLog {
    pub(crate) fn new(window: Duration) -> Self {
        Self {
            window,
            last_line: None,
            silenced: 0,
        }
    }

    pub(crate) fn refused(&mut self, now: Instant) -> Option<u64> {
        if let Some(last_line) = self.last_line {
            if now.saturating_duration_since(last_line) < self.window {
                self.silenced += 1;
                return None;
            }
        }
        self.last_line = Some(now);
        Some(std::mem::take(&mut self.silenced))
    }

    pub(crate) fn silenced(&self) -> u64 {
        self.silenced
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: Duration = Duration::from_secs(60);

    #[test]
    fn the_first_refusal_gets_a_line() {
        let mut log = RefusalLog::new(WINDOW);
        assert_eq!(log.refused(Instant::now()), Some(0));
    }

    #[test]
    fn refusals_inside_the_window_get_no_line_and_are_counted() {
        let start = Instant::now();
        let mut log = RefusalLog::new(WINDOW);
        log.refused(start);
        assert_eq!(log.refused(start + Duration::from_secs(1)), None);
        assert_eq!(log.refused(start + Duration::from_secs(59)), None);
        assert_eq!(log.silenced(), 2);
    }

    #[test]
    fn the_first_refusal_once_the_window_is_over_gets_a_line_with_the_count() {
        let start = Instant::now();
        let mut log = RefusalLog::new(WINDOW);
        log.refused(start);
        log.refused(start + Duration::from_secs(1));
        log.refused(start + Duration::from_secs(2));
        assert_eq!(log.refused(start + WINDOW), Some(2));
        assert_eq!(log.silenced(), 0);
    }

    #[test]
    fn the_next_window_starts_at_the_line_that_closed_the_last_one() {
        let start = Instant::now();
        let mut log = RefusalLog::new(WINDOW);
        log.refused(start);
        log.refused(start + WINDOW + Duration::from_secs(30));
        assert_eq!(log.refused(start + WINDOW * 2), None);
    }
}
