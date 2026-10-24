use windows_service::service::{ServiceErrorControl, ServiceInfo, ServiceStartType, ServiceType};

pub(crate) fn helper_request(name: &str, display: &str, image: &str) -> ServiceInfo {
    let image = image
        .strip_prefix('"')
        .and_then(|path| path.strip_suffix('"'))
        .unwrap_or(image);
    ServiceInfo {
        name: name.into(),
        display_name: display.into(),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::OnDemand,
        error_control: ServiceErrorControl::Normal,
        executable_path: image.into(),
        launch_arguments: vec![],
        dependencies: vec![],
        account_name: None,
        account_password: None,
    }
}
