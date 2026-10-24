use windows_service::service::ServiceInfo;

use crate::{Registrar, RegistrationFailure};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExistingService {
    Reject,
    Reconfigure,
}

pub fn register<R: Registrar>(
    registrar: &R,
    info: &ServiceInfo,
    existing: ExistingService,
) -> Result<R::Handle, RegistrationFailure> {
    match registrar.create(info) {
        Ok(service) => Ok(service),
        Err(windows_service::Error::Winapi(error))
            if error.raw_os_error() == Some(1073) && existing == ExistingService::Reconfigure =>
        {
            registrar.reconfigure(info)
        }
        Err(error) => Err(RegistrationFailure::Create(error)),
    }
}
