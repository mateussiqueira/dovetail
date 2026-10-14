use super::systemd::{Host, Ran};

pub(crate) const UNIT: &str = "example-helper.service";
pub(crate) const SHOW: &str = "show --property=LoadState,ActiveState example-helper.service";
pub(crate) const ACTIVE: &str = "LoadState=loaded\nActiveState=active\n";
pub(crate) const INACTIVE: &str = "LoadState=loaded\nActiveState=inactive\n";

pub(crate) struct Systemd {
    pub(crate) root: bool,
    pub(crate) present: bool,
    pub(crate) show: &'static str,
    pub(crate) accepts: bool,
    pub(crate) calls: Vec<String>,
}

impl Systemd {
    pub(crate) fn showing(show: &'static str) -> Self {
        Self {
            root: true,
            present: true,
            show,
            accepts: true,
            calls: Vec::new(),
        }
    }

    pub(crate) fn refusing(show: &'static str) -> Self {
        Self {
            accepts: false,
            ..Self::showing(show)
        }
    }

    pub(crate) fn as_a_user(show: &'static str) -> Self {
        Self {
            root: false,
            ..Self::showing(show)
        }
    }

    pub(crate) fn missing() -> Self {
        Self {
            present: false,
            ..Self::showing(ACTIVE)
        }
    }
}

impl Host for Systemd {
    fn is_root(&self) -> bool {
        self.root
    }

    fn systemctl(&mut self, args: &[&str]) -> Option<Ran> {
        self.calls.push(args.join(" "));
        if !self.present {
            return None;
        }
        let reading = args[0] == "show";
        let stdout = if reading { self.show } else { "" };
        Some(Ran {
            success: reading || self.accepts,
            stdout: stdout.to_string(),
        })
    }
}
