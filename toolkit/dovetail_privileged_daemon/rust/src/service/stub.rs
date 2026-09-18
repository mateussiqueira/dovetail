use crate::exit_codes;
use crate::DaemonApp;

pub fn run_service<A: DaemonApp>() -> i32 {
    match crate::run_foreground::<A>() {
        Ok(()) => exit_codes::OK,
        Err(err) => {
            tracing::error!(?err, "daemon terminou com erro");
            exit_codes::FAILED
        }
    }
}

fn nao_suportado(operacao: &str) -> i32 {
    tracing::error!(
        operacao,
        "operacao de servico nao implementada nesta plataforma"
    );
    exit_codes::UNSUPPORTED_PLATFORM
}

pub fn register_service<A: DaemonApp>() -> i32 {
    nao_suportado("registro do servico")
}
pub fn unregister_service<A: DaemonApp>() -> i32 {
    nao_suportado("remocao do servico")
}
pub fn stop_service<A: DaemonApp>() -> i32 {
    nao_suportado("parada do servico")
}
pub fn repair_service<A: DaemonApp>() -> i32 {
    nao_suportado("reparo do servico")
}
pub fn query_status<A: DaemonApp>() -> i32 {
    exit_codes::UNKNOWN
}
