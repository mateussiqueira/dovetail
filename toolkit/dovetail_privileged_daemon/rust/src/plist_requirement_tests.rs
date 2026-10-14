use std::path::PathBuf;

use crate::plist_requirement::{
    argv_is_ignored, requirement_declared_by, requirement_in, requirement_in_plist,
};

const REQUIREMENT: &str = "cdhash H\"0123456789abcdef0123456789abcdef01234567\"";

fn arguments(values: &[&str]) -> std::vec::IntoIter<String> {
    let values: Vec<String> = values.iter().map(|value| value.to_string()).collect();
    values.into_iter()
}

fn plist_declaring(name: &str, requirement: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("{name}-{}.plist", std::process::id()));
    let escaped = requirement.replace('&', "&amp;").replace('"', "&quot;");
    let body = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\
         <key>ProgramArguments</key><array><string>/helper</string>\
         <string>--service</string><string>--peer-requirement</string>\
         <string>{escaped}</string></array></dict></plist>\n"
    );
    std::fs::write(&path, body).unwrap();
    path
}

#[test]
fn the_requirement_is_the_value_after_the_flag() {
    let found = requirement_in(arguments(&["/helper", "--peer-requirement", REQUIREMENT]));
    assert_eq!(found.as_deref(), Some(REQUIREMENT));
}

#[test]
fn a_flag_with_no_value_declares_nothing() {
    assert_eq!(
        requirement_in(arguments(&["/helper", "--peer-requirement"])),
        None
    );
}

#[test]
fn arguments_without_the_flag_declare_nothing() {
    assert_eq!(requirement_in(arguments(&["/helper", "--service"])), None);
}

#[test]
fn the_requirement_is_read_from_the_plist_content() {
    let plist = plist_declaring("dovetail-plist-content", REQUIREMENT);
    let found = requirement_in_plist(&plist);
    std::fs::remove_file(&plist).unwrap();
    assert_eq!(found.as_deref(), Some(REQUIREMENT));
}

#[test]
fn a_plist_the_running_user_wrote_declares_nothing() {
    let plist = plist_declaring("dovetail-plist-untrusted", REQUIREMENT);
    let found = requirement_declared_by(&plist);
    std::fs::remove_file(&plist).unwrap();
    assert_eq!(found, None);
}

#[test]
fn a_command_line_requirement_the_plist_does_not_declare_is_ignored() {
    let argv = arguments(&["/helper", "--peer-requirement", "always"]);
    assert!(argv_is_ignored(argv, Some(REQUIREMENT)));
}

#[test]
fn a_command_line_requirement_with_no_trusted_plist_is_ignored() {
    let argv = arguments(&["/helper", "--peer-requirement", REQUIREMENT]);
    assert!(argv_is_ignored(argv, None));
}

#[test]
fn the_command_line_launchd_passes_from_the_trusted_plist_is_not_reported() {
    let argv = arguments(&["/helper", "--peer-requirement", REQUIREMENT]);
    assert!(!argv_is_ignored(argv, Some(REQUIREMENT)));
}

#[test]
fn a_command_line_without_the_flag_is_not_reported() {
    assert!(!argv_is_ignored(arguments(&["/helper"]), None));
}
