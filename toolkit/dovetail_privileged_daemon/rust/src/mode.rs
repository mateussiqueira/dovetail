#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Service,
    Foreground,
    Install,
    Uninstall,
    StopService,
    Repair,
    Status,
    Cleanup,
}

impl Mode {
    pub fn from_args() -> Self {
        Self::from_iter(std::env::args().skip(1))
    }

    fn from_iter<I>(args: I) -> Self
    where
        I: Iterator<Item = String>,
    {
        for arg in args {
            match arg.as_str() {
                "--install" | "--register-service" => return Mode::Install,
                "--uninstall" | "--unregister-service" => return Mode::Uninstall,
                "--stop-service" | "--stop" => return Mode::StopService,
                "--repair" => return Mode::Repair,
                "--status" => return Mode::Status,
                "--cleanup" => return Mode::Cleanup,
                "--foreground" | "--console" => return Mode::Foreground,
                _ => {}
            }
        }
        Mode::Service
    }

    pub fn log_file(self) -> Option<&'static str> {
        match self {
            Mode::Service | Mode::Foreground => Some("helper.log"),
            Mode::Install | Mode::Uninstall | Mode::StopService | Mode::Repair | Mode::Cleanup => {
                Some("install.log")
            }
            Mode::Status => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn modo(args: &[&str]) -> Mode {
        Mode::from_iter(args.iter().map(|s| s.to_string()))
    }

    #[test]
    fn bandeiras_mapeiam_para_o_modo_correto() {
        assert_eq!(modo(&["--install"]), Mode::Install);
        assert_eq!(modo(&["--register-service"]), Mode::Install);
        assert_eq!(modo(&["--uninstall"]), Mode::Uninstall);
        assert_eq!(modo(&["--unregister-service"]), Mode::Uninstall);
        assert_eq!(modo(&["--stop-service"]), Mode::StopService);
        assert_eq!(modo(&["--stop"]), Mode::StopService);
        assert_eq!(modo(&["--repair"]), Mode::Repair);
        assert_eq!(modo(&["--status"]), Mode::Status);
        assert_eq!(modo(&["--cleanup"]), Mode::Cleanup);
        assert_eq!(modo(&["--foreground"]), Mode::Foreground);
        assert_eq!(modo(&["--console"]), Mode::Foreground);
    }

    #[test]
    fn sem_bandeira_o_modo_e_service() {
        assert_eq!(modo(&[]), Mode::Service);
        assert_eq!(modo(&["--desconhecido"]), Mode::Service);
    }

    #[test]
    fn a_primeira_bandeira_reconhecida_vence() {
        assert_eq!(modo(&["--status", "--cleanup"]), Mode::Status);
        assert_eq!(modo(&["--cleanup", "--install"]), Mode::Cleanup);
    }

    #[test]
    fn log_file_segue_o_modo() {
        assert_eq!(Mode::Service.log_file(), Some("helper.log"));
        assert_eq!(Mode::Foreground.log_file(), Some("helper.log"));
        assert_eq!(Mode::Install.log_file(), Some("install.log"));
        assert_eq!(Mode::Uninstall.log_file(), Some("install.log"));
        assert_eq!(Mode::StopService.log_file(), Some("install.log"));
        assert_eq!(Mode::Repair.log_file(), Some("install.log"));
        assert_eq!(Mode::Cleanup.log_file(), Some("install.log"));
        assert_eq!(Mode::Status.log_file(), None);
    }
}
