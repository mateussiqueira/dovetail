use super::*;
use crate::error::ApiErrorPayload;
use reqwest::Method;
use serde::de::DeserializeOwned;
use serde::Serialize;

impl ApiClient {
    pub async fn get<R>(&self, path: &str) -> Result<R, ApiError>
    where
        R: DeserializeOwned,
    {
        self.request::<(), R>(Method::GET, path, None, true).await
    }

    pub async fn get_unauth<R>(&self, path: &str) -> Result<R, ApiError>
    where
        R: DeserializeOwned,
    {
        self.request::<(), R>(Method::GET, path, None, false).await
    }

    pub async fn post<B, R>(&self, path: &str, body: &B) -> Result<R, ApiError>
    where
        B: Serialize,
        R: DeserializeOwned,
    {
        self.request::<B, R>(Method::POST, path, Some(body), true)
            .await
    }

    pub async fn patch<B, R>(&self, path: &str, body: &B) -> Result<R, ApiError>
    where
        B: Serialize,
        R: DeserializeOwned,
    {
        self.request::<B, R>(Method::PATCH, path, Some(body), true)
            .await
    }

    pub async fn delete_with_body<B, R>(&self, path: &str, body: &B) -> Result<R, ApiError>
    where
        B: Serialize,
        R: DeserializeOwned,
    {
        self.request::<B, R>(Method::DELETE, path, Some(body), true)
            .await
    }

    pub async fn post_unauth<B, R>(&self, path: &str, body: &B) -> Result<R, ApiError>
    where
        B: Serialize,
        R: DeserializeOwned,
    {
        self.request::<B, R>(Method::POST, path, Some(body), false)
            .await
    }

    pub async fn patch_unauth<B, R>(&self, path: &str, body: &B) -> Result<R, ApiError>
    where
        B: Serialize,
        R: DeserializeOwned,
    {
        self.request::<B, R>(Method::PATCH, path, Some(body), false)
            .await
    }

    pub async fn put_no_content<B>(&self, path: &str, body: &B) -> Result<(), ApiError>
    where
        B: Serialize,
    {
        let token = self
            .token_store
            .get_token()?
            .ok_or(ApiError::MissingToken)?;
        let bytes = serde_json::to_vec(body).map_err(|e| ApiError::Internal(e.to_string()))?;

        let resp = self
            .http
            .put(self.url(path))
            .bearer_auth(token)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(bytes)
            .send()
            .await
            .map_err(ApiError::Transport)?;

        let status = resp.status();
        if status.is_success() {
            return Ok(());
        }
        let body = resp.json::<ApiErrorPayload>().await.ok();
        Err(Self::map_status_error(status, body))
    }
}
