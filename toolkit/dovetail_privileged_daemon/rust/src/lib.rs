mod connection;
pub mod exit_codes;
mod logging;
mod mode;
mod server;
mod service;

pub use dovetail_privileged_channel::{ErrorBody, ErrorCode, RespPayload};
pub use mode::Mode;

use std::sync::Arc;

pub struct ServiceIdentity {
    pub windows_name: &'static str,
    pub windows_display: &'static str,
    pub windows_description: &'static str,
    pub macos_label: &'static str,
    pub linux_unit: &'static str,
}

#[async_trait::async_trait]
pub trait DaemonApp: Default + Send + Sync + 'static {
    type Command: serde::Serialize + serde::de::DeserializeOwned + Send + Sync + 'static;
    type Reply: serde::Serialize + serde::de::DeserializeOwned + Send + Sync + 'static;

    const ENDPOINT: &'static str;
    const IDENTITY: ServiceIdentity;
    const VERSION: &'static str;
    const LOG_DIR: &'static str;
    const LOG_FILTER: &'static str = "info";

    fn command_timeout(cmd: &Self::Command) -> std::time::Duration;
    fn validate(cmd: &Self::Command) -> Result<(), String>;

    async fn prepare(&self) -> anyhow::Result<()> {
        Ok(())
    }
    async fn dispatch(&self, cmd: &Self::Command) -> RespPayload<Self::Reply>;
    async fn cleanup(&self) -> anyhow::Result<()> {
        Ok(())
    }
}

pub fn run<A: DaemonApp>() -> i32 {
    let modo = Mode::from_args();
    logging::init(A::LOG_DIR, A::LOG_FILTER, modo.log_file());
    tracing::debug!(?modo, versao = A::VERSION, "helper iniciado");
    executar::<A>(modo)
}

fn executar<A: DaemonApp>(modo: Mode) -> i32 {
    match modo {
        Mode::Cleanup => match cleanup::<A>() {
            Ok(()) => exit_codes::OK,
            Err(err) => {
                tracing::error!(?err, "falha na limpeza de desinstalacao");
                exit_codes::FAILED
            }
        },
        Mode::Foreground => match run_foreground::<A>() {
            Ok(()) => exit_codes::OK,
            Err(err) => {
                tracing::error!(?err, "loop em primeiro plano terminou com erro");
                exit_codes::FAILED
            }
        },
        Mode::Service => service::run_service::<A>(),
        Mode::Install => service::register_service::<A>(),
        Mode::Uninstall => service::unregister_service::<A>(),
        Mode::StopService => service::stop_service::<A>(),
        Mode::Repair => service::repair_service::<A>(),
        Mode::Status => service::query_status::<A>(),
    }
}

fn cleanup<A: DaemonApp>() -> anyhow::Result<()> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    rt.block_on(A::default().cleanup())
}

fn run_foreground<A: DaemonApp>() -> anyhow::Result<()> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    runtime.block_on(async move {
        let shutdown = async {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("sinal de parada recebido; encerrando helper");
        };

        server::run::<A, _>(Arc::new(A::default()), shutdown).await
    })
}
