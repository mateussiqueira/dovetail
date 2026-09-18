use std::path::Path;
use std::process::Command;

use crate::exit_codes;
use crate::DaemonApp;

const DOMINIO: &str = "system";

pub fn run_service<A: DaemonApp>() -> i32 {
    match crate::run_foreground::<A>() {
        Ok(()) => exit_codes::OK,
        Err(err) => {
            tracing::error!(?err, "daemon terminou com erro");
            exit_codes::FAILED
        }
    }
}

fn plist_path<A: DaemonApp>() -> String {
    format!("/Library/LaunchDaemons/{}.plist", A::IDENTITY.macos_label)
}

pub fn register_service<A: DaemonApp>() -> i32 {
    if !sou_root() {
        tracing::error!("registro do LaunchDaemon exige root");
        return exit_codes::NEEDS_ELEVATION;
    }

    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(e) => {
            tracing::error!(erro = %e, "nao foi possivel descobrir o proprio caminho");
            return exit_codes::REGISTER_FAILED;
        }
    };

    let plist = plist_path::<A>();

    if let Err(e) = std::fs::write(&plist, plist_para::<A>(&exe)) {
        tracing::error!(erro = %e, arquivo = %plist, "falha ao escrever o LaunchDaemon");
        return exit_codes::REGISTER_FAILED;
    }

    if let Err(e) = std::fs::set_permissions(&plist, permissoes_de_plist()) {
        tracing::error!(erro = %e, "falha ao ajustar as permissoes do LaunchDaemon");
        return exit_codes::REGISTER_FAILED;
    }

    descarregar::<A>();
    if carregar::<A>() {
        tracing::info!(label = A::IDENTITY.macos_label, "LaunchDaemon registrado");
        exit_codes::OK
    } else {
        exit_codes::REGISTER_FAILED
    }
}

pub fn unregister_service<A: DaemonApp>() -> i32 {
    if !sou_root() {
        return exit_codes::NEEDS_ELEVATION;
    }
    descarregar::<A>();
    let plist = plist_path::<A>();
    match std::fs::remove_file(&plist) {
        Ok(()) => exit_codes::OK,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => exit_codes::OK,
        Err(e) => {
            tracing::error!(erro = %e, "falha ao remover o LaunchDaemon");
            exit_codes::FAILED
        }
    }
}

pub fn stop_service<A: DaemonApp>() -> i32 {
    if !sou_root() {
        return exit_codes::NEEDS_ELEVATION;
    }
    descarregar::<A>();
    exit_codes::OK
}

pub fn repair_service<A: DaemonApp>() -> i32 {
    if !Path::new(&plist_path::<A>()).exists() {
        return exit_codes::NOT_INSTALLED;
    }
    if !sou_root() {
        return exit_codes::NEEDS_ELEVATION;
    }
    descarregar::<A>();
    if carregar::<A>() {
        exit_codes::OK
    } else {
        exit_codes::START_FAILED
    }
}

pub fn query_status<A: DaemonApp>() -> i32 {
    if !Path::new(&plist_path::<A>()).exists() {
        return exit_codes::NOT_INSTALLED;
    }
    let dominio = format!("{DOMINIO}/{}", A::IDENTITY.macos_label);
    match Command::new("launchctl")
        .args(["print", dominio.as_str()])
        .output()
    {
        Ok(saida) if saida.status.success() => {
            let texto = String::from_utf8_lossy(&saida.stdout);
            interpretar_print(&texto)
        }
        Ok(_) => exit_codes::STOPPED,
        Err(e) => {
            tracing::warn!(erro = %e, "launchctl nao executou");
            exit_codes::UNKNOWN
        }
    }
}

fn interpretar_print(texto: &str) -> i32 {
    if texto.contains("state = running") || texto.contains("pid = ") {
        exit_codes::OK
    } else {
        exit_codes::STOPPED
    }
}

fn sou_root() -> bool {
    // SAFETY: geteuid nao tem precondicoes e nunca falha.
    unsafe { libc::geteuid() == 0 }
}

fn permissoes_de_plist() -> std::fs::Permissions {
    use std::os::unix::fs::PermissionsExt;
    std::fs::Permissions::from_mode(0o644)
}

fn carregar<A: DaemonApp>() -> bool {
    let plist = plist_path::<A>();
    if executar(&["bootstrap", DOMINIO, plist.as_str()]) {
        return true;
    }
    tracing::warn!("`launchctl bootstrap` falhou; tentando `load -w`");
    executar(&["load", "-w", plist.as_str()])
}

fn descarregar<A: DaemonApp>() {
    let dominio = format!("{DOMINIO}/{}", A::IDENTITY.macos_label);
    if !executar(&["bootout", dominio.as_str()]) {
        let plist = plist_path::<A>();
        let _ = executar(&["unload", "-w", plist.as_str()]);
    }
}

fn executar(args: &[&str]) -> bool {
    match Command::new("launchctl").args(args).output() {
        Ok(saida) if saida.status.success() => true,
        Ok(saida) => {
            tracing::debug!(
                comando = %format!("launchctl {}", args.join(" ")),
                erro = %String::from_utf8_lossy(&saida.stderr).trim(),
                "launchctl recusou"
            );
            false
        }
        Err(e) => {
            tracing::warn!(erro = %e, "launchctl nao executou");
            false
        }
    }
}

fn plist_para<A: DaemonApp>(exe: &Path) -> String {
    let label = A::IDENTITY.macos_label;
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{}</string>
        <string>--service</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/var/log/{label}.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/{label}.log</string>
</dict>
</plist>
"#,
        exe.display()
    )
}

#[cfg(test)]
mod testes {
    use super::*;
    use crate::{DaemonApp, RespPayload, ServiceIdentity};
    use serde::{Deserialize, Serialize};

    #[derive(Default)]
    struct TestApp;

    #[derive(Debug, Serialize, Deserialize)]
    enum TestCommand {
        Ping,
    }

    #[derive(Debug, Serialize, Deserialize)]
    struct TestReply;

    #[async_trait::async_trait]
    impl DaemonApp for TestApp {
        type Command = TestCommand;
        type Reply = TestReply;

        const ENDPOINT: &'static str = "/tmp/dovetail-test.sock";
        const IDENTITY: ServiceIdentity = ServiceIdentity {
            windows_name: "TestHelper",
            windows_display: "Test Helper",
            windows_description: "Test daemon.",
            macos_label: "io.vcodes.vpnDesktop.helper",
            linux_unit: "test-helper.service",
        };
        const VERSION: &'static str = "0.0.0";
        const LOG_DIR: &'static str = "/tmp/dovetail-test-log";

        fn command_timeout(_cmd: &Self::Command) -> std::time::Duration {
            std::time::Duration::from_secs(1)
        }

        fn validate(_cmd: &Self::Command) -> Result<(), String> {
            Ok(())
        }

        async fn dispatch(&self, _cmd: &Self::Command) -> RespPayload<Self::Reply> {
            RespPayload::ok(TestReply)
        }
    }

    #[test]
    fn o_plist_aponta_para_o_binario_e_pede_o_modo_servico() {
        let texto = plist_para::<TestApp>(Path::new("/usr/local/libexec/myidvpn-helper"));
        assert!(texto.contains("<string>/usr/local/libexec/myidvpn-helper</string>"));
        assert!(texto.contains("<string>--service</string>"));
        assert!(texto.contains(TestApp::IDENTITY.macos_label));
    }

    #[test]
    fn o_plist_carrega_stdout_e_stderr_no_log_do_sistema() {
        let texto = plist_para::<TestApp>(Path::new("/x"));
        let log = format!("/var/log/{}.log", TestApp::IDENTITY.macos_label);
        let linha = format!("<string>{log}</string>");
        assert!(texto.contains("<key>StandardOutPath</key>"));
        assert!(texto.contains("<key>StandardErrorPath</key>"));
        assert_eq!(texto.matches(linha.as_str()).count(), 2);
    }

    #[test]
    fn o_daemon_volta_sozinho_se_cair() {
        let texto = plist_para::<TestApp>(Path::new("/x"));
        assert!(texto.contains("<key>KeepAlive</key>\n    <true/>"));
        assert!(texto.contains("<key>RunAtLoad</key>\n    <true/>"));
    }

    #[test]
    fn so_com_pid_o_daemon_esta_no_ar() {
        assert_eq!(
            interpretar_print("state = running\npid = 412\n"),
            exit_codes::OK
        );
        assert_eq!(interpretar_print("state = waiting\n"), exit_codes::STOPPED);
    }

    #[test]
    fn o_registro_vive_no_diretorio_do_sistema() {
        let plist = plist_path::<TestApp>();
        assert!(plist.starts_with("/Library/LaunchDaemons/"));
        assert!(plist.ends_with(".plist"));
    }
}
