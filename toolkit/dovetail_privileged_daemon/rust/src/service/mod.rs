#[cfg(target_os = "macos")]
mod macos;
#[cfg(not(any(windows, target_os = "macos")))]
mod stub;
#[cfg(windows)]
mod windows;

#[cfg(target_os = "macos")]
pub(crate) use macos::{
    query_status, register_service, repair_service, run_service, stop_service, unregister_service,
};
#[cfg(not(any(windows, target_os = "macos")))]
pub(crate) use stub::{
    query_status, register_service, repair_service, run_service, stop_service, unregister_service,
};
#[cfg(windows)]
pub(crate) use windows::{
    query_status, register_service, repair_service, run_service, stop_service, unregister_service,
};
