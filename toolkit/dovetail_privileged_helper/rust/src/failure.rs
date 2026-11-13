#[derive(Debug)]
pub enum RegistrationFailure {
    Create(windows_service::Error),
    Open(windows_service::Error),
    Configure(windows_service::Error),
}
