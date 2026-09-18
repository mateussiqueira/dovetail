use std::ffi::OsStr;
use std::time::{Duration, Instant};
use windows_service::service::{
    Service, ServiceAccess, ServiceAction, ServiceActionType,
    ServiceDependency, ServiceErrorControl, ServiceFailureActions,
    ServiceFailureResetPeriod, ServiceInfo, ServiceStartType, ServiceState,
    ServiceType,
};
use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};
use crate::exit_codes;
use crate::DaemonApp;

const ERROR_ACCESS_DENIED: i32 = 5;
const ERROR_SERVICE_DOES_NOT_EXIST: i32 = 1060;
const ERROR_SERVICE_NOT_ACTIVE: i32 = 1062;
const ERROR_SERVICE_DEPENDENCY_FAIL: i32 = 1068;
const ERROR_SERVICE_MARKED_FOR_DELETE: i32 = 1072;
const ERROR_SERVICE_EXISTS: i32 = 1073;
const ERROR_SERVICE_DEPENDENCY_DELETED: i32 = 1075;
const ERROR_SERVICE_ALREADY_RUNNING: i32 = 1056;
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const SVC_SDDL: &str = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;RP;;;IU)";

use super::{codigo_do_erro, falha, FalhaSetup};

pub fn register_service<A: DaemonApp>() -> i32 {
    match registrar::<A>() {
        Ok(()) => {
            tracing::info!("servico registrado e em execucao");
            exit_codes::OK
        }
        Err(f) => {
            tracing::error!(codigo = f.codigo, mensagem = %f.mensagem, "falha ao registrar o servico");
            f.codigo
        }
    }
}

fn registrar<A: DaemonApp>() -> Result<(), FalhaSetup> {
    let exe = std::env::current_exe().map_err(|e| {
        falha(
            exit_codes::REGISTER_FAILED,
            format!("current_exe() falhou: {e}"),
        )
    })?;
    tracing::info!(exe = %exe.display(), servico = A::IDENTITY.windows_name, "registrando servico");

    let manager = ServiceManager::local_computer(
        None::<&str>,
        ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE,
    )
    .map_err(|e| {
        let codigo = if codigo_do_erro(&e) == Some(ERROR_ACCESS_DENIED) {
            exit_codes::SCM_ACCESS_DENIED
        } else {
            exit_codes::REGISTER_FAILED
        };
        falha(codigo, format!("OpenSCManager falhou: {e:?}"))
    })?;

    let info = ServiceInfo {
        name: A::IDENTITY.windows_name.into(),
        display_name: A::IDENTITY.windows_display.into(),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::AutoStart,
        error_control: ServiceErrorControl::Normal,
        executable_path: exe.clone(),
        launch_arguments: vec![],
        dependencies: vec![
            ServiceDependency::Service("BFE".into()),
            ServiceDependency::Service("Nsi".into()),
        ],
        account_name: None,
        account_password: None,
    };

    let acesso = ServiceAccess::CHANGE_CONFIG
        | ServiceAccess::START
        | ServiceAccess::STOP
        | ServiceAccess::QUERY_STATUS;

    let service = match manager.create_service(&info, acesso) {
        Ok(s) => {
            tracing::info!("CreateService: servico criado");
            s
        }
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_EXISTS) => {
            tracing::info!("servico ja existe; reconfigurando via ChangeServiceConfig");
            let s = manager
                .open_service(A::IDENTITY.windows_name, acesso)
                .map_err(|e| {
                    let codigo = if codigo_do_erro(&e) == Some(ERROR_ACCESS_DENIED) {
                        exit_codes::SCM_ACCESS_DENIED
                    } else {
                        exit_codes::REGISTER_FAILED
                    };
                    falha(codigo, format!("OpenService falhou: {e:?}"))
                })?;
            s.change_config(&info).map_err(|e| {
                falha(
                    exit_codes::REGISTER_FAILED,
                    format!("ChangeServiceConfig falhou: {e:?}"),
                )
            })?;
            s
        }
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_MARKED_FOR_DELETE) => {
            return Err(falha(
                exit_codes::REGISTER_FAILED,
                "o servico esta marcado para exclusao (1072); reinicie o Windows e repita",
            ));
        }
        Err(e) => {
            let codigo = if codigo_do_erro(&e) == Some(ERROR_ACCESS_DENIED) {
                exit_codes::SCM_ACCESS_DENIED
            } else {
                exit_codes::REGISTER_FAILED
            };
            return Err(falha(codigo, format!("CreateService falhou: {e:?}")));
        }
    };

    if let Err(e) = service.set_description(A::IDENTITY.windows_description) {
        tracing::warn!(?e, "ChangeServiceConfig2(DESCRIPTION) falhou");
    }

    let acoes = ServiceFailureActions {
        reset_period: ServiceFailureResetPeriod::After(Duration::from_secs(900)),
        reboot_msg: None,
        command: None,
        actions: Some(vec![
            ServiceAction {
                action_type: ServiceActionType::Restart,
                delay: Duration::from_secs(3),
            },
            ServiceAction {
                action_type: ServiceActionType::Restart,
                delay: Duration::from_secs(30),
            },
            ServiceAction {
                action_type: ServiceActionType::Restart,
                delay: Duration::from_secs(600),
            },
        ]),
    };
    if let Err(e) = service.update_failure_actions(acoes) {
        tracing::warn!(?e, "ChangeServiceConfig2(FAILURE_ACTIONS) falhou");
    }
    if let Err(e) = service.set_failure_actions_on_non_crash_failures(true) {
        tracing::warn!(?e, "ChangeServiceConfig2(FAILURE_ACTIONS_FLAG) falhou");
    }

    if let Err(e) = conceder_start_a_usuarios_interativos::<A>() {
        tracing::warn!(erro = %e, "nao foi possivel aplicar a DACL do servico; o reparo exigira UAC");
    }

    iniciar_e_aguardar(&service, exit_codes::SCM_ACCESS_DENIED)
}

fn conceder_start_a_usuarios_interativos<A: DaemonApp>() -> Result<(), String> {
    use std::os::windows::process::CommandExt;

    let saida = std::process::Command::new(caminho_do_sc())
        .arg("sdset")
        .arg(A::IDENTITY.windows_name)
        .arg(SVC_SDDL)
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .map_err(|e| format!("nao foi possivel executar sc.exe: {e}"))?;

    if saida.status.success() {
        tracing::info!("DACL do servico aplicada (start permitido a usuarios interativos)");
        Ok(())
    } else {
        Err(format!(
            "sc sdset retornou {:?}: {}",
            saida.status.code(),
            String::from_utf8_lossy(&saida.stdout).trim()
        ))
    }
}

fn caminho_do_sc() -> std::path::PathBuf {
    let raiz = std::env::var_os("SystemRoot")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from(r"C:\Windows"));
    raiz.join("System32").join("sc.exe")
}

pub(super) fn iniciar_e_aguardar(service: &Service, codigo_acesso_negado: i32) -> Result<(), FalhaSetup> {
    let sem_args: [&OsStr; 0] = [];
    match service.start(&sem_args) {
        Ok(()) => tracing::info!("StartService aceito"),
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_ALREADY_RUNNING) => {
            tracing::info!("servico ja estava em execucao");
        }
        Err(e) => {
            let codigo = match codigo_do_erro(&e) {
                Some(ERROR_SERVICE_DEPENDENCY_FAIL) | Some(ERROR_SERVICE_DEPENDENCY_DELETED) => {
                    exit_codes::MISSING_DEPENDENCY
                }
                Some(ERROR_ACCESS_DENIED) => codigo_acesso_negado,
                _ => exit_codes::START_FAILED,
            };
            return Err(falha(codigo, format!("StartService falhou: {e:?}")));
        }
    }

    let limite = Instant::now() + Duration::from_secs(45);
    loop {
        match service.query_status() {
            Ok(st) => match st.current_state {
                ServiceState::Running => {
                    tracing::info!("servico confirmado em RUNNING");
                    return Ok(());
                }
                ServiceState::StartPending | ServiceState::ContinuePending => {}
                estado => {
                    tracing::error!(?estado, saida = ?st.exit_code, "servico parou durante o start");
                    return Err(falha(
                        exit_codes::START_FAILED,
                        format!(
                            "o servico parou durante o start ({estado:?}, {:?})",
                            st.exit_code
                        ),
                    ));
                }
            },
            Err(e) => tracing::warn!(?e, "QueryServiceStatus falhou"),
        }

        if Instant::now() >= limite {
            return Err(falha(
                exit_codes::START_TIMEOUT,
                "o servico nao ficou RUNNING em 45 s",
            ));
        }
        std::thread::sleep(Duration::from_millis(400));
    }
}
