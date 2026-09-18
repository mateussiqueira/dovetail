use std::time::{Duration, Instant};
use windows_service::service::{
    ServiceAccess, ServiceState,
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

use super::install::iniciar_e_aguardar;
use super::{codigo_do_erro, falha, FalhaSetup};

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
