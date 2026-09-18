use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use dovetail_privileged_channel::{bind, Endpoint};

use crate::connection::handle_conn;
use crate::DaemonApp;

pub async fn run<A, F>(app: Arc<A>, shutdown: F) -> anyhow::Result<()>
where
    A: DaemonApp,
    F: Future<Output = ()>,
{
    app.prepare().await?;

    let endpoint = Endpoint::new(A::ENDPOINT);
    let mut listener = bind(&endpoint).await?;
    tracing::info!("helper ouvindo no transporte local do SO");

    tokio::pin!(shutdown);
    let mut falhas_seguidas: u64 = 0;
    loop {
        tokio::select! {
            _ = &mut shutdown => {
                tracing::info!("encerrando loop de aceitacao");
                break;
            }
            accepted = listener.accept() => {
                match accepted {
                    Ok((conn, peer)) => {
                        falhas_seguidas = 0;
                        let app = app.clone();
                        tokio::spawn(async move {
                            if let Err(err) = handle_conn(conn, peer, app).await {
                                tracing::debug!(?err, "conexao encerrada com erro");
                            }
                        });
                    }
                    Err(err) => {
                        falhas_seguidas += 1;
                        let espera = std::cmp::min(100 * falhas_seguidas, 2_000);
                        tracing::warn!(
                            ?err,
                            falhas_seguidas,
                            espera_ms = espera,
                            "falha ao aceitar conexao"
                        );
                        tokio::time::sleep(Duration::from_millis(espera)).await;
                    }
                }
            }
        }
    }

    Ok(())
}
