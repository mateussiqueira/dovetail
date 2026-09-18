use super::*;

impl ApiClient {
    pub async fn get_bytes(
        &self,
        url: &str,
        max_bytes: usize,
    ) -> Result<(String, Vec<u8>), ApiError> {
        self.bytes_at(url, max_bytes, true).await
    }

    pub async fn get_bytes_unauth(
        &self,
        url: &str,
        max_bytes: usize,
    ) -> Result<(String, Vec<u8>), ApiError> {
        self.bytes_at(url, max_bytes, false).await
    }

    async fn bytes_at(
        &self,
        url: &str,
        max_bytes: usize,
        auth: bool,
    ) -> Result<(String, Vec<u8>), ApiError> {
        let mut req = self.http.get(url);
        if auth {
            let token = self
                .token_store
                .get_token()?
                .ok_or(ApiError::MissingToken)?;
            req = req.bearer_auth(token);
        }

        let resp = req.send().await.map_err(ApiError::Transport)?;

        let status = resp.status();
        if !status.is_success() {
            return Err(Self::map_status_error(status, None));
        }

        if let Some(len) = resp.content_length() {
            if len as usize > max_bytes {
                return Err(ApiError::Internal(
                    "resource exceeds the maximum size".into(),
                ));
            }
        }

        let content_type = resp
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("application/octet-stream")
            .split(';')
            .next()
            .unwrap_or("application/octet-stream")
            .trim()
            .to_ascii_lowercase();

        let bytes = resp.bytes().await.map_err(ApiError::Transport)?;
        if bytes.len() > max_bytes {
            return Err(ApiError::Internal(
                "resource exceeds the maximum size".into(),
            ));
        }

        Ok((content_type, bytes.to_vec()))
    }
}
