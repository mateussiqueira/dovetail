use std::process::Command;

use super::systemd::{self, Host, Ran};
use crate::exit_codes;
use crate::DaemonApp;

struct System;

impl Host for System {
    fn is_root(&self) -> bool {
        unsafe { libc::geteuid() == 0 }
    }

    fn systemctl(&mut self, args: &[&str]) -> Option<Ran> {
        match Command::new("systemctl").args(args).output() {
            Ok(saida) => Some(Ran {
                success: saida.status.success(),
                stdout: String::from_utf8_lossy(&saida.stdout).into_owned(),
            }),
            Err(e) => {
                tracing::warn!(erro = %e, "systemctl nao executou");
                None
            }
        }
    }
}

pub fn run_service<A: DaemonApp>() -> i32 {
    match crate::run_foreground::<A>() {
        Ok(()) => exit_codes::OK,
        Err(err) => {
            tracing::error!(?err, "daemon terminou com erro");
            exit_codes::FAILED
        }
    }
}

pub fn register_service<A: DaemonApp>() -> i32 {
    systemd::install(&mut System, A::IDENTITY.linux_unit)
}

pub fn unregister_service<A: DaemonApp>() -> i32 {
    systemd::uninstall(&mut System, A::IDENTITY.linux_unit)
}

pub fn stop_service<A: DaemonApp>() -> i32 {
    systemd::stop(&mut System, A::IDENTITY.linux_unit)
}

pub fn repair_service<A: DaemonApp>() -> i32 {
    systemd::repair(&mut System, A::IDENTITY.linux_unit)
}

pub fn query_status<A: DaemonApp>() -> i32 {
    systemd::status(&mut System, A::IDENTITY.linux_unit)
}
