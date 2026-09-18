use std::ffi::{OsStr, OsString};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc;
use std::time::{Duration, Instant};
use windows_service::service::{
    ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
    ServiceType,
};
use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
use windows_service::service_dispatcher;

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

mod control;
mod install;

pub use control::{query_status, repair_service, stop_service, unregister_service};
pub use install::register_service;

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
