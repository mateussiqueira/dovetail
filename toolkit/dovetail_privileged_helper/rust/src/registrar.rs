use windows_service::service::ServiceInfo;

use crate::RegistrationFailure;

pub trait Registrar {
    type Handle;
    fn create(&self, info: &ServiceInfo) -> windows_service::Result<Self::Handle>;
    fn reconfigure(&self, info: &ServiceInfo) -> Result<Self::Handle, RegistrationFailure>;
}
