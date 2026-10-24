use std::ffi::{c_char, CStr};
use windows_service::service::ServiceAccess;
use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};

use crate::helper_request::helper_request;
use crate::{register, ExistingService, RegistrationFailure, ScmRegistrar};

unsafe fn argument(pointer: *const c_char) -> Option<String> {
    if pointer.is_null() {
        return None;
    }
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_string_lossy()
        .into_owned();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn code(result: windows_service::Result<()>) -> i32 {
    match result {
        Ok(()) => 0,
        Err(windows_service::Error::Winapi(error)) => error.raw_os_error().unwrap_or(1),
        Err(_) => 1,
    }
}

#[no_mangle]
pub(crate) unsafe extern "C" fn DovetailWindowsServiceQuery(
    name: *const c_char,
    start_type: *mut i32,
) -> i32 {
    if name.is_null() || start_type.is_null() {
        return 87;
    }
    unsafe {
        start_type.write(0);
    }
    let Some(name) = (unsafe { argument(name) }) else {
        return 87;
    };
    code((|| {
        let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;
        let service = manager.open_service(name, ServiceAccess::QUERY_CONFIG)?;
        let config = service.query_config()?;
        unsafe {
            start_type.write(config.start_type.to_raw() as i32);
        }
        Ok(())
    })())
}

#[no_mangle]
pub(crate) unsafe extern "C" fn DovetailWindowsServiceCreate(
    name: *const c_char,
    display: *const c_char,
    image: *const c_char,
) -> i32 {
    let (Some(name), Some(display), Some(image)) = (
        unsafe { argument(name) },
        unsafe { argument(display) },
        unsafe { argument(image) },
    ) else {
        return 87;
    };
    code((|| {
        let manager =
            ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CREATE_SERVICE)?;
        let registrar = ScmRegistrar::new(&manager, ServiceAccess::CHANGE_CONFIG);
        register(
            &registrar,
            &helper_request(&name, &display, &image),
            ExistingService::Reject,
        )
        .map(|_| ())
        .map_err(|error| match error {
            RegistrationFailure::Create(source)
            | RegistrationFailure::Open(source)
            | RegistrationFailure::Configure(source) => source,
        })
    })())
}

#[no_mangle]
pub(crate) unsafe extern "C" fn DovetailWindowsServiceDelete(name: *const c_char) -> i32 {
    let Some(name) = (unsafe { argument(name) }) else {
        return 87;
    };
    code((|| {
        let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;
        manager.open_service(name, ServiceAccess::DELETE)?.delete()
    })())
}
