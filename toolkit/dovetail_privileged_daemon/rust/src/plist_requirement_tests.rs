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
    plist_ending_with(name, &["--peer-requirement", requirement])
}

fn plist_ending_with(name: &str, tail: &[&str]) -> PathBuf {
    let path = std::env::temp_dir().join(format!("{name}-{}.plist", std::process::id()));
    let strings: String = tail
        .iter()
        .map(|value| value.replace('&', "&amp;").replace('"', "&quot;"))
        .map(|value| format!("<string>{value}</string>"))
        .collect();
    let body = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>\
         <key>ProgramArguments</key><array><string>/helper</string>\
         <string>--service</string>{strings}</array></dict></plist>\n"
    );
    std::fs::write(&path, body).unwrap();
    path
}

#[test]
fn the_requirement_is_the_value_after_the_flag() {
    let found = requirement_in(arguments(&["/helper", "--peer-requirement", REQUIREMENT]));
    assert_eq!(found.unwrap().as_deref(), Some(REQUIREMENT));
}

#[test]
fn a_flag_with_no_value_is_refused() {
    let refused = requirement_in(arguments(&["/helper", "--peer-requirement"])).unwrap_err();
    assert!(refused.to_string().contains("sem valor"), "{refused}");
}

#[test]
fn arguments_without_the_flag_declare_nothing() {
    assert_eq!(
        requirement_in(arguments(&["/helper", "--service"])).unwrap(),
        None
    );
}

#[test]
fn the_requirement_is_read_from_the_plist_content() {
    let plist = plist_declaring("dovetail-plist-content", REQUIREMENT);
    let found = requirement_in_plist(&plist);
    std::fs::remove_file(&plist).unwrap();
    assert_eq!(found.unwrap().as_deref(), Some(REQUIREMENT));
}

#[test]
fn a_plist_flag_with_no_value_does_not_start_the_daemon() {
    let plist = plist_ending_with("dovetail-plist-no-value", &["--peer-requirement"]);
    let found = requirement_in_plist(&plist);
    std::fs::remove_file(&plist).unwrap();
    assert!(found.is_err());
}

#[test]
fn a_plist_without_the_flag_declares_nothing() {
    let plist = plist_ending_with("dovetail-plist-no-flag", &[]);
    let found = requirement_in_plist(&plist);
    std::fs::remove_file(&plist).unwrap();
    assert_eq!(found.unwrap(), None);
}

#[test]
fn a_plist_the_running_user_wrote_declares_nothing() {
    let plist = plist_declaring("dovetail-plist-untrusted", REQUIREMENT);
    let found = requirement_declared_by(&plist);
    std::fs::remove_file(&plist).unwrap();
    assert_eq!(found.unwrap(), None);
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
