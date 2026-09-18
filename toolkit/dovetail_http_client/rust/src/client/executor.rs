use super::*;
use crate::error::ApiErrorPayload;
use reqwest::{Method, StatusCode};
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::time::Duration;

impl ApiClient {
    pub(super) async fn request<B, R>(
        &self,
        method: Method,
        path: &str,
        body: Option<&B>,
        auth: bool,
    ) -> Result<R, ApiError>
    where
        B: Serialize,
        R: DeserializeOwned,
    {
        let url = self.url(path);

        let bearer = if auth {
            match self.token_store.get_token()? {
                Some(t) => Some(t),
                None => return Err(ApiError::MissingToken),
            }
        } else {
            None
        };

        let json_body = match body {
            Some(b) => Some(serde_json::to_vec(b).map_err(|e| ApiError::Internal(e.to_string()))?),
            None => None,
        };

        let mut bearer = bearer;
        let mut already_refreshed = false;
        let mut attempt: u32 = 0;
        loop {
            let mut req = self.http.request(method.clone(), &url);
            if let Some(ref token) = bearer {
                req = req.bearer_auth(token);
            }
            if let Some(ref bytes) = json_body {
                req = req
                    .header(reqwest::header::CONTENT_TYPE, "application/json")
                    .body(bytes.clone());
            }

            let result = self.execute_once::<R>(req).await;

            match result {
                Ok(value) => return Ok(value),
                Err(err) => {
                    if auth && !already_refreshed && matches!(err, ApiError::Unauthorized { .. }) {
                        already_refreshed = true;
                        if let Some(new_token) = self.refresh_session(bearer.as_deref()).await? {
                            bearer = Some(new_token);
                            continue;
                        }
                        return Err(err);
                    }
                    if err.is_retryable() && attempt < self.config.max_retries {
                        let delay = self.backoff_delay(attempt);
                        tracing::warn!(
                            route = %redact_route(&url),
                            attempt,
                            retry_in_ms = delay.as_millis() as u64,
                            error = %err,
                            "request failed, retrying"
                        );
                        tokio::time::sleep(delay).await;
                        attempt += 1;
                        continue;
                    }
                    return Err(err);
                }
            }
        }
    }

    pub(crate) async fn refresh_session(
        &self,
        used_token: Option<&str>,
    ) -> Result<Option<String>, ApiError> {
        let Some(refresher) = self.refresher.as_ref() else {
            return Ok(None);
        };

        let _lock = self.refresh_lock.lock().await;

        let stored = self.token_store.get_token()?;
        if let (Some(current), Some(used)) = (stored.as_deref(), used_token) {
            if current != used {
                return Ok(Some(current.to_string()));
            }
        }

        match refresher.refresh().await {
            Ok(()) => Ok(self.token_store.get_token()?),
            Err(ApiError::MissingToken) | Err(ApiError::Unauthorized { .. }) => Ok(None),
            Err(e) => Err(e),
        }
    }

    async fn execute_once<R>(&self, req: reqwest::RequestBuilder) -> Result<R, ApiError>
    where
        R: DeserializeOwned,
    {
        let resp = req.send().await.map_err(ApiError::Transport)?;
        let status = resp.status();

        if status.is_success() {
            return resp.json::<R>().await.map_err(ApiError::Decode);
        }

        let body = resp.json::<ApiErrorPayload>().await.ok();
        Err(Self::map_status_error(status, body))
    }

    pub fn map_status_error(status: StatusCode, body: Option<ApiErrorPayload>) -> ApiError {
        let code = status.as_u16();
        match status {
            StatusCode::UNAUTHORIZED => ApiError::Unauthorized { status: code, body },
            StatusCode::FORBIDDEN => ApiError::Forbidden { status: code, body },
            StatusCode::TOO_MANY_REQUESTS => ApiError::TooManyRequests { status: code, body },
            s if s.is_server_error() => ApiError::Server { status: code, body },
            _ => ApiError::BadRequest { status: code, body },
        }
    }

    pub fn map_status_code(code: u16, body: Option<ApiErrorPayload>) -> ApiError {
        match StatusCode::from_u16(code) {
            Ok(status) => Self::map_status_error(status, body),
            Err(_) => ApiError::Internal(format!("invalid status in response: {code}")),
        }
    }

    fn backoff_delay(&self, attempt: u32) -> Duration {
        let factor = 1u32 << attempt.min(6);
        self.config.retry_base_delay * factor
    }
}

#[cfg(test)]
mod tests_status {
    use super::ApiClient;
    use crate::error::ApiError;
    use reqwest::StatusCode;

    fn classify(status: StatusCode) -> ApiError {
        ApiClient::map_status_error(status, None)
    }

    #[test]
    fn the_429_is_not_an_invalid_request() {
        let err = classify(StatusCode::TOO_MANY_REQUESTS);

        assert!(matches!(err, ApiError::TooManyRequests { status: 429, .. }));
        assert!(!matches!(err, ApiError::BadRequest { .. }));
    }

    #[test]
    fn the_throttle_does_not_enter_the_backoff() {
        assert!(!classify(StatusCode::TOO_MANY_REQUESTS).is_retryable());
        assert!(classify(StatusCode::INTERNAL_SERVER_ERROR).is_retryable());
    }

    #[test]
    fn the_other_statuses_did_not_change() {
        assert!(matches!(
            classify(StatusCode::UNAUTHORIZED),
            ApiError::Unauthorized { .. }
        ));
        assert!(matches!(
            classify(StatusCode::FORBIDDEN),
            ApiError::Forbidden { .. }
        ));
        assert!(matches!(
            classify(StatusCode::BAD_REQUEST),
            ApiError::BadRequest { .. }
        ));
        assert!(matches!(
            classify(StatusCode::NOT_FOUND),
            ApiError::BadRequest { .. }
        ));
    }
}
