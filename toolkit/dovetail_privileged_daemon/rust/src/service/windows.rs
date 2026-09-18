use std::ffi::{OsStr, OsString};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};
use windows_service::service::{
    Service, ServiceAccess, ServiceAction, ServiceActionType, ServiceControl, ServiceControlAccept,
    ServiceDependency, ServiceErrorControl, ServiceExitCode, ServiceFailureActions,
    ServiceFailureResetPeriod, ServiceInfo, ServiceStartType, ServiceState, ServiceStatus,
    ServiceType,
};
use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
use windows_service::service_dispatcher;
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

static CODIGO_DO_SERVICO: AtomicI32 = AtomicI32::new(exit_codes::OK);

static SERVICE_MAIN: std::sync::OnceLock<fn(Vec<OsString>)> = std::sync::OnceLock::new();

windows_service::define_windows_service!(ffi_service_main, service_main);

fn service_main(args: Vec<OsString>) {
    if let Some(f) = SERVICE_MAIN.get() {
        f(args);
    }
}

struct FalhaSetup {
    codigo: i32,
    mensagem: String,
}

fn falha(codigo: i32, mensagem: impl Into<String>) -> FalhaSetup {
    FalhaSetup {
        codigo,
        mensagem: mensagem.into(),
    }
}

fn codigo_do_erro(err: &windows_service::Error) -> Option<i32> {
    match err {
        windows_service::Error::Winapi(e) => e.raw_os_error(),
        _ => None,
    }
}

pub fn run_service<A: DaemonApp>() -> i32 {
    let _ = SERVICE_MAIN.set(service_main_inner::<A>);
    match service_dispatcher::start(A::IDENTITY.windows_name, ffi_service_main) {
        Ok(()) => CODIGO_DO_SERVICO.load(Ordering::SeqCst),
        Err(err) => {
            tracing::warn!(
                ?err,
                "nao foi possivel anexar ao SCM; rodando em foreground (dev)"
            );
            match crate::run_foreground::<A>() {
                Ok(()) => exit_codes::OK,
                Err(e) => {
                    tracing::error!(?e, "loop em primeiro plano terminou com erro");
                    exit_codes::FAILED
                }
            }
        }
    }
}

fn service_main_inner<A: DaemonApp>(_args: Vec<OsString>) {
    match run::<A>() {
        Ok(()) => CODIGO_DO_SERVICO.store(exit_codes::OK, Ordering::SeqCst),
        Err(err) => {
            tracing::error!(?err, "service_main terminou com erro");
            CODIGO_DO_SERVICO.store(exit_codes::FAILED, Ordering::SeqCst);
        }
    }
}

fn status(
    estado: ServiceState,
    aceita: ServiceControlAccept,
    saida: ServiceExitCode,
) -> ServiceStatus {
    ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: estado,
        controls_accepted: aceita,
        exit_code: saida,
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    }
}

fn run<A: DaemonApp>() -> anyhow::Result<()> {
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let stop_tx_handler = stop_tx.clone();

    let event_handler = move |control| -> ServiceControlHandlerResult {
        match control {
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            ServiceControl::Stop | ServiceControl::Shutdown => {
                let _ = stop_tx_handler.send(());
                ServiceControlHandlerResult::NoError
            }
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    let status_handle = service_control_handler::register(A::IDENTITY.windows_name, event_handler)?;

    let mut pendente = status(
        ServiceState::StartPending,
        ServiceControlAccept::empty(),
        ServiceExitCode::Win32(0),
    );
    pendente.checkpoint = 1;
    pendente.wait_hint = Duration::from_secs(20);
    status_handle.set_service_status(pendente.clone())?;

    let worker = std::thread::Builder::new()
        .name("dovetail-daemon-io".into())
        .spawn(move || -> anyhow::Result<()> {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()?;
            runtime.block_on(async move {
                let shutdown = async move {
                    let _ = tokio::task::spawn_blocking(move || stop_rx.recv()).await;
                };
                crate::server::run::<A, _>(std::sync::Arc::new(A::default()), shutdown).await
            })
        })?;

    let limite = Instant::now() + Duration::from_secs(20);
    let mut pronto = false;
    let mut checkpoint = 1u32;
    while Instant::now() < limite {
        if endpoint_pronto::<A>() {
            pronto = true;
            break;
        }
        if worker.is_finished() {
            break;
        }
        checkpoint += 1;
        pendente.checkpoint = checkpoint;
        let _ = status_handle.set_service_status(pendente.clone());
        std::thread::sleep(Duration::from_millis(250));
    }

    if pronto {
        status_handle.set_service_status(status(
            ServiceState::Running,
            ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
            ServiceExitCode::Win32(0),
        ))?;
        tracing::info!("servico em execucao");
    } else {
        tracing::error!("o endpoint local nao ficou disponivel; encerrando o servico");
        let _ = stop_tx.send(());
    }

    let resultado = match worker.join() {
        Ok(r) => r,
        Err(_) => Err(anyhow::anyhow!(
            "a thread de I/O do helper entrou em panico"
        )),
    };

    let saida = match (&resultado, pronto) {
        (Ok(()), true) => ServiceExitCode::Win32(0),
        (Ok(()), false) => ServiceExitCode::ServiceSpecific(exit_codes::START_TIMEOUT as u32),
        (Err(_), _) => ServiceExitCode::ServiceSpecific(exit_codes::FAILED as u32),
    };
    let _ = status_handle.set_service_status(status(
        ServiceState::Stopped,
        ServiceControlAccept::empty(),
        saida,
    ));

    resultado
}

fn endpoint_pronto<A: DaemonApp>() -> bool {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::System::Pipes::WaitNamedPipeW;

    let nome: Vec<u16> = OsStr::new(A::ENDPOINT)
        .encode_wide()
        .chain(std::iter::once(0))
        .collect();
    // SAFETY: nome e null-terminado e valido durante a chamada.
    unsafe { WaitNamedPipeW(nome.as_ptr(), 1) != 0 }
}

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

fn iniciar_e_aguardar(service: &Service, codigo_acesso_negado: i32) -> Result<(), FalhaSetup> {
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

pub fn stop_service<A: DaemonApp>() -> i32 {
    match parar_e_aguardar::<A>() {
        Ok(()) => exit_codes::OK,
        Err(f) => {
            tracing::error!(codigo = f.codigo, mensagem = %f.mensagem, "falha ao parar o servico");
            f.codigo
        }
    }
}

fn parar_e_aguardar<A: DaemonApp>() -> Result<(), FalhaSetup> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|e| falha(exit_codes::FAILED, format!("OpenSCManager falhou: {e:?}")))?;

    let service = match manager.open_service(
        A::IDENTITY.windows_name,
        ServiceAccess::STOP | ServiceAccess::QUERY_STATUS,
    ) {
        Ok(s) => s,
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_DOES_NOT_EXIST) => {
            tracing::info!("servico nao registrado; nada a parar");
            return Ok(());
        }
        Err(e) => {
            return Err(falha(
                exit_codes::FAILED,
                format!("OpenService falhou: {e:?}"),
            ))
        }
    };

    match service.stop() {
        Ok(_) => tracing::info!("ControlService(STOP) aceito"),
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_NOT_ACTIVE) => {
            tracing::info!("servico ja estava parado");
            return Ok(());
        }
        Err(e) => {
            return Err(falha(
                exit_codes::FAILED,
                format!("ControlService falhou: {e:?}"),
            ))
        }
    }

    let limite = Instant::now() + Duration::from_secs(15);
    loop {
        match service.query_status() {
            Ok(st) if st.current_state == ServiceState::Stopped => {
                tracing::info!("servico confirmado em STOPPED");
                return Ok(());
            }
            Ok(_) => {}
            Err(e) => tracing::warn!(?e, "QueryServiceStatus falhou"),
        }
        if Instant::now() >= limite {
            return Err(falha(
                exit_codes::FAILED,
                "o servico nao chegou a STOPPED em 15 s",
            ));
        }
        std::thread::sleep(Duration::from_millis(300));
    }
}

pub fn unregister_service<A: DaemonApp>() -> i32 {
    if let Err(f) = parar_e_aguardar::<A>() {
        tracing::warn!(mensagem = %f.mensagem, "seguindo com a remocao mesmo sem parar o servico");
    }
    match remover::<A>() {
        Ok(()) => {
            tracing::info!("servico removido do SCM");
            exit_codes::OK
        }
        Err(f) => {
            tracing::error!(codigo = f.codigo, mensagem = %f.mensagem, "falha ao remover o servico");
            f.codigo
        }
    }
}

fn remover<A: DaemonApp>() -> Result<(), FalhaSetup> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|e| falha(exit_codes::FAILED, format!("OpenSCManager falhou: {e:?}")))?;

    let service = match manager.open_service(A::IDENTITY.windows_name, ServiceAccess::DELETE) {
        Ok(s) => s,
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_DOES_NOT_EXIST) => return Ok(()),
        Err(e) => {
            return Err(falha(
                exit_codes::FAILED,
                format!("OpenService falhou: {e:?}"),
            ))
        }
    };

    service
        .delete()
        .map_err(|e| falha(exit_codes::FAILED, format!("DeleteService falhou: {e:?}")))
}

pub fn repair_service<A: DaemonApp>() -> i32 {
    match reparar::<A>() {
        Ok(()) => exit_codes::OK,
        Err(f) => {
            tracing::error!(codigo = f.codigo, mensagem = %f.mensagem, "falha ao reparar o servico");
            f.codigo
        }
    }
}

fn reparar<A: DaemonApp>() -> Result<(), FalhaSetup> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|e| {
            let codigo = if codigo_do_erro(&e) == Some(ERROR_ACCESS_DENIED) {
                exit_codes::NEEDS_ELEVATION
            } else {
                exit_codes::FAILED
            };
            falha(codigo, format!("OpenSCManager falhou: {e:?}"))
        })?;

    let service = match manager.open_service(
        A::IDENTITY.windows_name,
        ServiceAccess::START | ServiceAccess::QUERY_STATUS,
    ) {
        Ok(s) => s,
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_DOES_NOT_EXIST) => {
            return Err(falha(
                exit_codes::NOT_INSTALLED,
                "o servico nao esta registrado; a instalacao do app esta incompleta",
            ));
        }
        Err(e) if codigo_do_erro(&e) == Some(ERROR_ACCESS_DENIED) => {
            return Err(falha(
                exit_codes::NEEDS_ELEVATION,
                "sem permissao para iniciar o servico; e preciso reparar com elevacao",
            ));
        }
        Err(e) => {
            return Err(falha(
                exit_codes::FAILED,
                format!("OpenService falhou: {e:?}"),
            ))
        }
    };

    if let Ok(st) = service.query_status() {
        if st.current_state == ServiceState::Running {
            tracing::info!("servico ja esta em execucao; nada a reparar");
            return Ok(());
        }
    }

    iniciar_e_aguardar(&service, exit_codes::NEEDS_ELEVATION)
}

pub fn query_status<A: DaemonApp>() -> i32 {
    let manager = match ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
    {
        Ok(m) => m,
        Err(_) => return exit_codes::UNKNOWN,
    };

    match manager.open_service(A::IDENTITY.windows_name, ServiceAccess::QUERY_STATUS) {
        Ok(s) => match s.query_status() {
            Ok(st) => match st.current_state {
                ServiceState::Running => exit_codes::OK,
                ServiceState::StartPending | ServiceState::ContinuePending => exit_codes::STARTING,
                _ => exit_codes::STOPPED,
            },
            Err(_) => exit_codes::UNKNOWN,
        },
        Err(e) if codigo_do_erro(&e) == Some(ERROR_SERVICE_DOES_NOT_EXIST) => {
            exit_codes::NOT_INSTALLED
        }
        Err(_) => exit_codes::UNKNOWN,
    }
}
