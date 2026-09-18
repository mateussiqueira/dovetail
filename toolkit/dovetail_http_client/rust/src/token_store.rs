use crate::error::ApiError;
use std::sync::Mutex;

pub trait TokenStore: Send + Sync {
    fn get_token(&self) -> Result<Option<String>, ApiError>;
    fn set_token(&self, token: &str) -> Result<(), ApiError>;
    fn get_refresh_token(&self) -> Result<Option<String>, ApiError>;
    fn set_refresh_token(&self, token: Option<&str>) -> Result<(), ApiError>;
    fn clear_token(&self) -> Result<(), ApiError>;
}

#[derive(Default)]
pub struct MemoryTokenStore {
    token: Mutex<Option<String>>,
    refresh: Mutex<Option<String>>,
}

impl TokenStore for MemoryTokenStore {
    fn get_token(&self) -> Result<Option<String>, ApiError> {
        Ok(self.token.lock().unwrap().clone())
    }

    fn set_token(&self, token: &str) -> Result<(), ApiError> {
        *self.token.lock().unwrap() = Some(token.to_string());
        Ok(())
    }

    fn get_refresh_token(&self) -> Result<Option<String>, ApiError> {
        Ok(self.refresh.lock().unwrap().clone())
    }

    fn set_refresh_token(&self, token: Option<&str>) -> Result<(), ApiError> {
        *self.refresh.lock().unwrap() = token.map(str::to_string);
        Ok(())
    }

    fn clear_token(&self) -> Result<(), ApiError> {
        *self.token.lock().unwrap() = None;
        *self.refresh.lock().unwrap() = None;
        Ok(())
    }
}
