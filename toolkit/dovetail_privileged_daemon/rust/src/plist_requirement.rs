use std::path::Path;
use std::process::Command;

use crate::plist_trust::system_plist_is_trusted;

const REQUIREMENT_FLAG: &str = "--peer-requirement";
const PLUTIL: &str = "/usr/bin/plutil";

pub(crate) fn requirement_declared_by(system_plist: &Path) -> anyhow::Result<Option<String>> {
    if !system_plist_is_trusted(system_plist) {
        return Ok(None);
    }
    let declared = requirement_in_plist(system_plist)
        .map_err(|err| anyhow::anyhow!("{}: {err}", system_plist.display()))?;
    if declared.is_none() {
        tracing::debug!(plist = %system_plist.display(), "plist confiavel sem --peer-requirement");
    }
    Ok(declared)
}

pub(crate) fn requirement_in_plist(plist: &Path) -> anyhow::Result<Option<String>> {
    program_arguments(plist).map_or(Ok(None), |arguments| requirement_in(arguments.into_iter()))
}

fn program_arguments(plist: &Path) -> Option<Vec<String>> {
    let out = Command::new(PLUTIL)
        .args(["-extract", "ProgramArguments", "json", "-o", "-"])
        .arg(plist)
        .output()
        .ok()?;
    serde_json::from_slice(&out.stdout).ok()
}

pub(crate) fn requirement_in(
    mut arguments: impl Iterator<Item = String>,
) -> anyhow::Result<Option<String>> {
    if !arguments.any(|arg| arg == REQUIREMENT_FLAG) {
        return Ok(None);
    }
    let requirement = arguments.next().ok_or_else(|| {
        anyhow::anyhow!("{REQUIREMENT_FLAG} sem valor; o daemon nao sobe com o plist malformado")
    })?;
    Ok(Some(requirement))
}

pub(crate) fn argv_is_ignored(
    arguments: impl Iterator<Item = String>,
    declared: Option<&str>,
) -> bool {
    requirement_in(arguments)
        .ok()
        .flatten()
        .is_some_and(|argv| Some(argv.as_str()) != declared)
}
