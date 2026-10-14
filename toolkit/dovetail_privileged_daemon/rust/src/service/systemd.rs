use crate::exit_codes;

pub(crate) struct Ran {
    pub(crate) success: bool,
    pub(crate) stdout: String,
}

pub(crate) trait Host {
    fn is_root(&self) -> bool;
    fn systemctl(&mut self, args: &[&str]) -> Option<Ran>;
}

pub(crate) fn install(host: &mut impl Host, unit: &str) -> i32 {
    if !host.is_root() {
        tracing::error!(unit, "habilitar a unit exige root");
        return exit_codes::NEEDS_ELEVATION;
    }
    change(
        host,
        &["enable", "--now", unit],
        exit_codes::REGISTER_FAILED,
    )
}

pub(crate) fn uninstall(host: &mut impl Host, unit: &str) -> i32 {
    if !host.is_root() {
        return exit_codes::NEEDS_ELEVATION;
    }
    if status(host, unit) == exit_codes::NOT_INSTALLED {
        return exit_codes::OK;
    }
    change(host, &["disable", "--now", unit], exit_codes::FAILED)
}

pub(crate) fn stop(host: &mut impl Host, unit: &str) -> i32 {
    if !host.is_root() {
        return exit_codes::NEEDS_ELEVATION;
    }
    if status(host, unit) == exit_codes::NOT_INSTALLED {
        return exit_codes::OK;
    }
    change(host, &["stop", unit], exit_codes::FAILED)
}

pub(crate) fn repair(host: &mut impl Host, unit: &str) -> i32 {
    if status(host, unit) == exit_codes::NOT_INSTALLED {
        return exit_codes::NOT_INSTALLED;
    }
    if !host.is_root() {
        return exit_codes::NEEDS_ELEVATION;
    }
    change(host, &["restart", unit], exit_codes::START_FAILED)
}

pub(crate) fn status(host: &mut impl Host, unit: &str) -> i32 {
    match host.systemctl(&["show", "--property=LoadState,ActiveState", unit]) {
        Some(ran) if ran.success => state(&ran.stdout),
        _ => exit_codes::UNKNOWN,
    }
}

fn state(show: &str) -> i32 {
    let value = |key: &str| {
        show.lines()
            .find_map(|line| line.strip_prefix(key)?.strip_prefix('='))
    };
    if value("LoadState") == Some("not-found") {
        return exit_codes::NOT_INSTALLED;
    }
    match value("ActiveState") {
        Some("active" | "reloading" | "refreshing") => exit_codes::OK,
        Some("activating") => exit_codes::STARTING,
        Some(_) => exit_codes::STOPPED,
        None => exit_codes::UNKNOWN,
    }
}

fn change(host: &mut impl Host, args: &[&str], failure: i32) -> i32 {
    match host.systemctl(args) {
        Some(ran) if ran.success => exit_codes::OK,
        _ => {
            tracing::error!(comando = %args.join(" "), "systemctl nao concluiu a operacao");
            failure
        }
    }
}
