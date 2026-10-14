use std::path::Path;

use crate::plist_trust::{closed_to_all_but_root, system_plist_is_trusted};

#[test]
fn a_plist_owned_by_root_and_wheel_and_closed_to_writes_is_trusted() {
    assert!(closed_to_all_but_root(0, 0, 0o100644));
}

#[test]
fn a_plist_owned_by_a_user_is_not_trusted() {
    assert!(!closed_to_all_but_root(501, 0, 0o100644));
}

#[test]
fn a_plist_in_a_group_other_than_wheel_is_not_trusted() {
    assert!(!closed_to_all_but_root(0, 20, 0o100644));
}

#[test]
fn a_plist_the_group_can_write_is_not_trusted() {
    assert!(!closed_to_all_but_root(0, 0, 0o100664));
}

#[test]
fn a_plist_anyone_can_write_is_not_trusted() {
    assert!(!closed_to_all_but_root(0, 0, 0o100646));
}

#[test]
fn a_plist_the_running_user_wrote_is_not_trusted() {
    let path = std::env::temp_dir().join(format!("dovetail-plist-{}.plist", std::process::id()));
    std::fs::write(&path, "<plist/>").unwrap();
    let trusted = system_plist_is_trusted(&path);
    std::fs::remove_file(&path).unwrap();
    assert!(!trusted);
}

#[test]
fn a_missing_system_plist_is_not_trusted() {
    assert!(!system_plist_is_trusted(Path::new(
        "/Library/LaunchDaemons/com.example.dovetail.absent.plist"
    )));
}
