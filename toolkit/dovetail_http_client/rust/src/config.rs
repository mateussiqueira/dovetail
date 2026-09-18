use std::time::Duration;

#[derive(Debug, Clone)]
pub struct ClientConfig {
    pub base_url: String,
    pub request_timeout: Duration,
    pub connect_timeout: Duration,
    pub max_retries: u32,
    pub retry_base_delay: Duration,
    pub user_agent: String,
}

impl ClientConfig {
    pub fn new(base_url: impl Into<String>, user_agent: impl Into<String>) -> Self {
        Self {
            base_url: base_url.into(),
            request_timeout: Duration::from_secs(30),
            connect_timeout: Duration::from_secs(10),
            max_retries: 2,
            retry_base_delay: Duration::from_millis(300),
            user_agent: user_agent.into(),
        }
    }

    pub fn with_request_timeout(mut self, timeout: Duration) -> Self {
        self.request_timeout = timeout;
        self
    }

    pub fn with_connect_timeout(mut self, timeout: Duration) -> Self {
        self.connect_timeout = timeout;
        self
    }

    pub fn with_max_retries(mut self, max_retries: u32) -> Self {
        self.max_retries = max_retries;
        self
    }

    pub fn with_retry_base_delay(mut self, delay: Duration) -> Self {
        self.retry_base_delay = delay;
        self
    }
}
