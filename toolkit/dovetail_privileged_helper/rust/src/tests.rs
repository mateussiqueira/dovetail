use std::cell::Cell;
use std::io;
use windows_service::service::{
    ServiceDependency, ServiceErrorControl, ServiceInfo, ServiceStartType, ServiceType,
};

use crate::{register, ExistingService, Registrar, RegistrationFailure};

struct Fake {
    error: i32,
    reconfigured: Cell<bool>,
}

impl Registrar for Fake {
    type Handle = (u32, usize);

    fn create(&self, info: &ServiceInfo) -> windows_service::Result<Self::Handle> {
        if self.error != 0 {
            return Err(windows_service::Error::Winapi(
                io::Error::from_raw_os_error(self.error),
            ));
        }
        Ok((info.start_type.to_raw(), info.dependencies.len()))
    }

    fn reconfigure(&self, info: &ServiceInfo) -> Result<Self::Handle, RegistrationFailure> {
        self.reconfigured.set(true);
        Ok((info.start_type.to_raw(), info.dependencies.len()))
    }
}

fn request(start_type: ServiceStartType) -> ServiceInfo {
    ServiceInfo {
        name: "contract-service".into(),
        display_name: "Contract service".into(),
        service_type: ServiceType::OWN_PROCESS,
        start_type,
        error_control: ServiceErrorControl::Normal,
        executable_path: "C:\\Program Files\\Contract\\helper.exe".into(),
        launch_arguments: vec![],
        dependencies: vec![ServiceDependency::Service("contract-dependency".into())],
        account_name: None,
        account_password: None,
    }
}

#[test]
fn app_rejects_existing_service_without_reconfiguring_its_policy() {
    let backend = Fake {
        error: 1073,
        reconfigured: Cell::new(false),
    };
    let result = register(
        &backend,
        &request(ServiceStartType::OnDemand),
        ExistingService::Reject,
    );
    assert!(matches!(result, Err(RegistrationFailure::Create(_))));
    assert!(!backend.reconfigured.get());
}

#[test]
fn daemon_reconfigures_existing_service_with_supplied_start_type_and_dependencies() {
    let backend = Fake {
        error: 1073,
        reconfigured: Cell::new(false),
    };
    let result = register(
        &backend,
        &request(ServiceStartType::AutoStart),
        ExistingService::Reconfigure,
    )
    .unwrap();
    assert_eq!(result, (ServiceStartType::AutoStart.to_raw(), 1));
    assert!(backend.reconfigured.get());
}

#[test]
fn access_denial_is_not_mistaken_for_an_existing_service() {
    let backend = Fake {
        error: 5,
        reconfigured: Cell::new(false),
    };
    let result = register(
        &backend,
        &request(ServiceStartType::AutoStart),
        ExistingService::Reconfigure,
    );
    assert!(matches!(result, Err(RegistrationFailure::Create(_))));
    assert!(!backend.reconfigured.get());
}

#[test]
fn new_service_keeps_the_callers_start_mode_without_reconfiguration() {
    let backend = Fake {
        error: 0,
        reconfigured: Cell::new(false),
    };
    let result = register(
        &backend,
        &request(ServiceStartType::OnDemand),
        ExistingService::Reject,
    )
    .unwrap();
    assert_eq!(result, (ServiceStartType::OnDemand.to_raw(), 1));
    assert!(!backend.reconfigured.get());
}
