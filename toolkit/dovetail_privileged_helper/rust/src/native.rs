use windows_service::service::{Service, ServiceAccess, ServiceInfo};
use windows_service::service_manager::ServiceManager;

use crate::{Registrar, RegistrationFailure};

pub struct ScmRegistrar<'a> {
    manager: &'a ServiceManager,
    access: ServiceAccess,
}

impl<'a> ScmRegistrar<'a> {
    pub fn new(manager: &'a ServiceManager, access: ServiceAccess) -> Self {
        Self { manager, access }
    }
}

impl Registrar for ScmRegistrar<'_> {
    type Handle = Service;

    fn create(&self, info: &ServiceInfo) -> windows_service::Result<Service> {
        self.manager.create_service(info, self.access)
    }

    fn reconfigure(&self, info: &ServiceInfo) -> Result<Service, RegistrationFailure> {
        let service = self
            .manager
            .open_service(&info.name, self.access)
            .map_err(RegistrationFailure::Open)?;
        service
            .change_config(info)
            .map_err(RegistrationFailure::Configure)?;
        Ok(service)
    }
}
