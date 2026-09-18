use crate::config::ClientConfig;
use crate::error::ApiError;
use crate::refresh::TokenRefresher;
use crate::token_store::TokenStore;
use std::sync::Arc;

mod executor;
mod list;
mod multipart;
mod raw_bytes;
mod safe_route;
mod verbs;

pub use list::{extract_list_envelope, extract_list_envelope_with_keys};
pub use multipart::{boundary_for, multipart_body};
pub use safe_route::redact_route;

#[derive(Clone)]
pub struct ApiClient {
    http: reqwest::Client,
    config: ClientConfig,
    pub(crate) token_store: Arc<dyn TokenStore>,
    pub(crate) refresher: Option<Arc<dyn TokenRefresher>>,
    pub(crate) refresh_lock: Arc<tokio::sync::Mutex<()>>,
}

impl ApiClient {
    pub fn new(
        config: ClientConfig,
        token_store: Arc<dyn TokenStore>,
        refresher: Option<Arc<dyn TokenRefresher>>,
    ) -> Result<Self, ApiError> {
        let http = reqwest::Client::builder()
            .user_agent(config.user_agent.clone())
            .timeout(config.request_timeout)
            .connect_timeout(config.connect_timeout)
            .gzip(true)
            .build()
            .map_err(ApiError::Transport)?;

        Ok(Self {
            http,
            config,
            token_store,
            refresher,
            refresh_lock: Arc::new(tokio::sync::Mutex::new(())),
        })
    }

    pub fn token_store(&self) -> &Arc<dyn TokenStore> {
        &self.token_store
    }

    pub fn base_url(&self) -> &str {
        &self.config.base_url
    }

    pub(crate) fn url(&self, path: &str) -> String {
        let base = self.config.base_url.trim_end_matches('/');
        let path = path.trim_start_matches('/');
        format!("{base}/{path}")
    }
}
