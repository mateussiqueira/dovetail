use std::future::Future;
use std::pin::Pin;

use crate::error::ApiError;

pub trait TokenRefresher: Send + Sync {
    fn refresh<'a>(&'a self) -> Pin<Box<dyn Future<Output = Result<(), ApiError>> + Send + 'a>>;
}
