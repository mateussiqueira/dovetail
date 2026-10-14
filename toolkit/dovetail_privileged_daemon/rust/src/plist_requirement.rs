use std::path::Path;
use std::process::Command;

use crate::plist_trust::system_plist_is_trusted;

const REQUIREMENT_FLAG: &str = "--peer-requirement";
const PLUTIL: &str = "/usr/bin/plutil";

pub(crate) fn requirement_declared_by(system_plist: &Path) -> Option<String> {
    if !system_plist_is_trusted(system_plist) {
        return None;
    }
    let declared = requirement_in_plist(system_plist);
    if declared.is_none() {
        tracing::debug!(plist = %system_plist.display(), "plist confiavel sem --peer-requirement");
    }
    declared
}

pub(crate) fn requirement_in_plist(plist: &Path) -> Option<String> {
    let out = Command::new(PLUTIL)
        .args(["-extract", "ProgramArguments", "json", "-o", "-"])
        .arg(plist)
        .output()
        .ok()?;
    let arguments: Vec<String> = serde_json::from_slice(&out.stdout).ok()?;
    requirement_in(arguments.into_iter())
}

pub(crate) fn requirement_in(mut arguments: impl Iterator<Item = String>) -> Option<String> {
    arguments.find(|arg| arg == REQUIREMENT_FLAG)?;
    arguments.next()
}

pub(crate) fn argv_is_ignored(
    arguments: impl Iterator<Item = String>,
    declared: Option<&str>,
) -> bool {
    requirement_in(arguments).is_some_and(|argv| Some(argv.as_str()) != declared)
}
