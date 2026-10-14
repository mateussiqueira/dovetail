use super::systemd::{install, repair, status, stop, uninstall};
use super::systemd_fixture::{Systemd, ACTIVE, INACTIVE, SHOW, UNIT};
use crate::exit_codes;

#[test]
fn install_enables_and_starts_the_unit_in_one_call() {
    let mut systemd = Systemd::showing(INACTIVE);
    assert_eq!(install(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(systemd.calls, ["enable --now example-helper.service"]);
}

#[test]
fn an_install_systemd_refuses_is_a_register_failure() {
    let mut systemd = Systemd::refusing(INACTIVE);
    assert_eq!(install(&mut systemd, UNIT), exit_codes::REGISTER_FAILED);
}

#[test]
fn uninstall_disables_and_stops_the_unit() {
    let mut systemd = Systemd::showing(ACTIVE);
    assert_eq!(uninstall(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(
        systemd.calls,
        [SHOW, "disable --now example-helper.service"]
    );
}

#[test]
fn an_uninstall_systemd_refuses_fails() {
    let mut systemd = Systemd::refusing(ACTIVE);
    assert_eq!(uninstall(&mut systemd, UNIT), exit_codes::FAILED);
}

#[test]
fn stop_stops_the_unit_and_leaves_it_enabled() {
    let mut systemd = Systemd::showing(ACTIVE);
    assert_eq!(stop(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(systemd.calls, [SHOW, "stop example-helper.service"]);
}

#[test]
fn a_stop_systemd_refuses_fails() {
    let mut systemd = Systemd::refusing(ACTIVE);
    assert_eq!(stop(&mut systemd, UNIT), exit_codes::FAILED);
}

#[test]
fn repair_restarts_the_unit() {
    let mut systemd = Systemd::showing(INACTIVE);
    assert_eq!(repair(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(systemd.calls, [SHOW, "restart example-helper.service"]);
}

#[test]
fn a_repair_systemd_refuses_is_a_start_failure() {
    let mut systemd = Systemd::refusing(INACTIVE);
    assert_eq!(repair(&mut systemd, UNIT), exit_codes::START_FAILED);
}

#[test]
fn status_reads_the_load_and_the_active_state_and_nothing_else() {
    let mut systemd = Systemd::showing(ACTIVE);
    assert_eq!(status(&mut systemd, UNIT), exit_codes::OK);
    assert_eq!(systemd.calls, [SHOW]);
}
