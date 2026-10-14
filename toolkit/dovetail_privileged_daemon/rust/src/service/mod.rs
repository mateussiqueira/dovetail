#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
mod stub;
#[cfg(any(test, target_os = "linux"))]
mod systemd;
#[cfg(test)]
mod systemd_fixture;
#[cfg(test)]
mod systemd_state_tests;
#[cfg(test)]
mod systemd_tests;
#[cfg(windows)]
mod windows;

#[cfg(target_os = "linux")]
pub(crate) use linux::{
    query_status, register_service, repair_service, run_service, stop_service, unregister_service,
};
#[cfg(target_os = "macos")]
pub(crate) use macos::{
    plist_path, query_status, register_service, repair_service, run_service, stop_service,
    unregister_service,
};
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
pub(crate) use stub::{
    query_status, register_service, repair_service, run_service, stop_service, unregister_service,
};
#[cfg(windows)]
pub(crate) use windows::{
    query_status, register_service, repair_service, run_service, stop_service, unregister_service,
};
