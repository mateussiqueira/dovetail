use std::ffi::CString;
use std::ptr;
use windows_service::service::{ServiceStartType, ServiceType};

use crate::ffi::{
    DovetailWindowsServiceCreate, DovetailWindowsServiceDelete, DovetailWindowsServiceQuery,
};
use crate::helper_request::helper_request;

#[test]
fn helper_keeps_demand_start_no_dependencies_and_local_system() {
    let info = helper_request("service", "Service", r"C:\Program Files\核\helper.exe");
    assert_eq!(info.start_type, ServiceStartType::OnDemand);
    assert_eq!(info.service_type, ServiceType::OWN_PROCESS);
    assert!(info.dependencies.is_empty());
    assert!(info.launch_arguments.is_empty());
    assert!(info.account_name.is_none());
    assert_eq!(
        info.executable_path.to_str().unwrap(),
        r"C:\Program Files\核\helper.exe"
    );
}

#[test]
fn helper_accepts_a_quoted_binary_path_without_double_quoting() {
    let info = helper_request("service", "Service", r#""C:\Program Files\核\helper.exe""#);
    assert_eq!(
        info.executable_path.to_str().unwrap(),
        r"C:\Program Files\核\helper.exe"
    );
}

#[test]
fn query_null_argument_preserves_the_callers_output() {
    let mut start = 123;
    assert_eq!(
        unsafe { DovetailWindowsServiceQuery(ptr::null(), &mut start) },
        87
    );
    assert_eq!(start, 123);
}

#[test]
fn query_empty_name_clears_output_before_returning_invalid_parameter() {
    let empty = CString::new("").unwrap();
    let mut start = 123;
    assert_eq!(
        unsafe { DovetailWindowsServiceQuery(empty.as_ptr(), &mut start) },
        87
    );
    assert_eq!(start, 0);
}

#[test]
fn invalid_create_and_delete_never_reach_the_service_manager() {
    let empty = CString::new("").unwrap();
    assert_eq!(
        unsafe { DovetailWindowsServiceCreate(empty.as_ptr(), ptr::null(), ptr::null()) },
        87
    );
    assert_eq!(unsafe { DovetailWindowsServiceDelete(empty.as_ptr()) }, 87);
}
