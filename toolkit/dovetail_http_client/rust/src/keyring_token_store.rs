use crate::error::ApiError;
use crate::token_store::TokenStore;

pub struct KeyringTokenStore {
    service: String,
    access_entry: String,
    refresh_entry: String,
}

impl KeyringTokenStore {
    pub fn new(
        service: impl Into<String>,
        access_entry: impl Into<String>,
        refresh_entry: impl Into<String>,
    ) -> Self {
        Self {
            service: service.into(),
            access_entry: access_entry.into(),
            refresh_entry: refresh_entry.into(),
        }
    }

    fn entry(&self) -> Result<keyring::Entry, ApiError> {
        keyring::Entry::new(&self.service, &self.access_entry)
            .map_err(|e| ApiError::TokenStore(e.to_string()))
    }

    fn refresh_entry(&self) -> Result<keyring::Entry, ApiError> {
        keyring::Entry::new(&self.service, &self.refresh_entry)
            .map_err(|e| ApiError::TokenStore(e.to_string()))
    }
}

impl TokenStore for KeyringTokenStore {
    fn get_token(&self) -> Result<Option<String>, ApiError> {
        match self.entry()?.get_password() {
            Ok(token) => Ok(Some(token)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(ApiError::TokenStore(e.to_string())),
        }
    }

    fn set_token(&self, token: &str) -> Result<(), ApiError> {
        self.entry()?
            .set_password(token)
            .map_err(|e| ApiError::TokenStore(e.to_string()))
    }

    fn get_refresh_token(&self) -> Result<Option<String>, ApiError> {
        match self.refresh_entry()?.get_password() {
            Ok(token) => Ok(Some(token)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(ApiError::TokenStore(e.to_string())),
        }
    }

    fn set_refresh_token(&self, token: Option<&str>) -> Result<(), ApiError> {
        let entry = self.refresh_entry()?;
        match token {
            Some(value) => entry
                .set_password(value)
                .map_err(|e| ApiError::TokenStore(e.to_string())),
            None => match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(e) => Err(ApiError::TokenStore(e.to_string())),
            },
        }
    }

    fn clear_token(&self) -> Result<(), ApiError> {
        self.set_refresh_token(None)?;
        match self.entry()?.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(ApiError::TokenStore(e.to_string())),
        }
    }
}

pub struct KeyringSessionStore {
    service: String,
    entry_name: String,
}

impl KeyringSessionStore {
    pub fn new(service: impl Into<String>, entry: impl Into<String>) -> Self {
        Self {
            service: service.into(),
            entry_name: entry.into(),
        }
    }

    fn entry(&self) -> Result<keyring::Entry, ApiError> {
        keyring::Entry::new(&self.service, &self.entry_name)
            .map_err(|e| ApiError::TokenStore(e.to_string()))
    }

    pub fn get(&self) -> Result<Option<String>, ApiError> {
        match self.entry()?.get_password() {
            Ok(v) => Ok(Some(v)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(ApiError::TokenStore(e.to_string())),
        }
    }

    pub fn set(&self, json: &str) -> Result<(), ApiError> {
        self.entry()?
            .set_password(json)
            .map_err(|e| ApiError::TokenStore(e.to_string()))
    }

    pub fn clear(&self) -> Result<(), ApiError> {
        match self.entry()?.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(ApiError::TokenStore(e.to_string())),
        }
    }
}
