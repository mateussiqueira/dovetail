use super::systemd::{install, repair, status, stop, uninstall};
use super::systemd_fixture::{Systemd, ACTIVE, INACTIVE, SHOW, UNIT};
use crate::exit_codes;

const UNKNOWN_UNIT: &str = "LoadState=not-found\nActiveState=inactive\n";

#[test]
fn a_unit_on_its_way_up_is_starting() {
    let mut systemd = Systemd::showing("LoadState=loaded\nActiveState=activating\n");
    assert_eq!(status(&mut systemd, UNIT), exit_codes::STARTING);
}

#[test]
fn an_inactive_or_a_failed_unit_is_stopped() {
    let mut inactive = Systemd::showing(INACTIVE);
    let mut failed = Systemd::showing("LoadState=loaded\nActiveState=failed\n");
    assert_eq!(status(&mut inactive, UNIT), exit_codes::STOPPED);
    assert_eq!(status(&mut failed, UNIT), exit_codes::STOPPED);
}

#[test]
fn a_unit_systemd_does_not_know_is_not_installed_and_leaves_nothing_to_remove() {
    let mut systemd = Systemd::showing(UNKNOWN_UNIT);
    assert_eq!(status(&mut systemd, UNIT), exit_codes::NOT_INSTALLED);
    assert_eq!(repair(&mut systemd, UNIT), exit_codes::NOT_INSTALLED);
    assert_eq!(uninstall(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(stop(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(systemd.calls, [SHOW, SHOW, SHOW, SHOW]);
}

#[test]
fn without_root_no_mode_changes_the_unit() {
    let mut systemd = Systemd::as_a_user(ACTIVE);
    assert_eq!(install(&mut systemd, UNIT), exit_codes::NEEDS_ELEVATION);
    assert_eq!(uninstall(&mut systemd, UNIT), exit_codes::NEEDS_ELEVATION);
    assert_eq!(stop(&mut systemd, UNIT), exit_codes::NEEDS_ELEVATION);
    assert_eq!(repair(&mut systemd, UNIT), exit_codes::NEEDS_ELEVATION);
    assert_eq!(systemd.calls, [SHOW]);
}

#[test]
fn without_systemctl_the_state_is_unknown_and_the_install_fails() {
    let mut systemd = Systemd::missing();
    assert_eq!(status(&mut systemd, UNIT), exit_codes::UNKNOWN);
    assert_eq!(install(&mut systemd, UNIT), exit_codes::REGISTER_FAILED);
}
