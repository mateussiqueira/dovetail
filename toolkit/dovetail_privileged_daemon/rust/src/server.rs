use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use dovetail_privileged_channel::{bind, AcceptError, Endpoint, PeerCheck};
use futures::{stream, Stream, StreamExt};

use crate::connection::handle_conn;
use crate::DaemonApp;

pub async fn run<A, F>(app: Arc<A>, shutdown: F) -> anyhow::Result<()>
where
    A: DaemonApp,
    F: Future<Output = ()>,
{
    app.prepare().await?;

    let listener = bind(&endpoint::<A>()).await?;
    tracing::info!("helper ouvindo no transporte local do SO");

    let incoming = stream::unfold(listener, |mut listener| async move {
        Some((listener.accept().await, listener))
    });
    accept_loop(incoming, shutdown, |conn, peer| {
        let app = app.clone();
        tokio::spawn(async move {
            if let Err(err) = handle_conn(conn, peer, app).await {
                tracing::debug!(?err, "conexao encerrada com erro");
            }
        });
    })
    .await;

    Ok(())
}

fn endpoint<A: DaemonApp>() -> Endpoint {
    let endpoint = Endpoint::new(A::ENDPOINT);
    match A::peer_policy() {
        Some(policy) => endpoint.with_peer_policy(policy),
        None => endpoint,
    }
}

async fn accept_loop<C>(
    incoming: impl Stream<Item = Result<(C, PeerCheck), AcceptError>>,
    shutdown: impl Future<Output = ()>,
    mut serve: impl FnMut(C, PeerCheck),
) {
    tokio::pin!(incoming, shutdown);
    let mut falhas_seguidas: u64 = 0;
    loop {
        tokio::select! {
            _ = &mut shutdown => {
                tracing::info!("encerrando loop de aceitacao");
                break;
            }
            accepted = incoming.next() => {
                match accepted {
                    None => break,
                    Some(Ok((conn, peer))) => {
                        falhas_seguidas = 0;
                        serve(conn, peer);
                    }
                    Some(Err(AcceptError::PeerRefused(reason))) => {
                        tracing::warn!(motivo = %reason, "peer recusado; conexao fechada");
                    }
                    Some(Err(err)) => {
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
}

#[cfg(test)]
mod tests {
    use std::io;
    use std::time::Instant;

    use super::*;
    use crate::connection_fixture::Echo;
    use crate::{PeerPolicy, RespPayload, ServiceIdentity};

    #[derive(Default)]
    struct Guarded;

    #[async_trait::async_trait]
    impl DaemonApp for Guarded {
        type Command = ();
        type Reply = ();
        const ENDPOINT: &'static str = Echo::ENDPOINT;
        const IDENTITY: ServiceIdentity = Echo::IDENTITY;
        const VERSION: &'static str = Echo::VERSION;
        const LOG_DIR: &'static str = Echo::LOG_DIR;

        fn command_timeout(_: &()) -> Duration {
            Duration::from_secs(1)
        }

        fn validate(_: &()) -> Result<(), String> {
            Ok(())
        }

        fn peer_policy() -> Option<PeerPolicy> {
            Some(PeerPolicy::default().allow_uid(0).allow_gid(27))
        }

        async fn dispatch(&self, _: &()) -> RespPayload<()> {
            RespPayload::ok(())
        }
    }

    #[test]
    fn an_app_that_declares_no_policy_binds_an_endpoint_without_one() {
        assert_eq!(endpoint::<Echo>().peer_policy(), None);
    }

    #[test]
    fn the_policy_the_app_declares_reaches_the_endpoint() {
        let declared = PeerPolicy::default().allow_uid(0).allow_gid(27);
        assert_eq!(endpoint::<Guarded>().peer_policy(), Some(&declared));
    }

    const FIRST_BACKOFF: Duration = Duration::from_millis(100);

    type Accepted = Result<(u32, PeerCheck), AcceptError>;

    fn app(id: u32) -> Accepted {
        let peer = PeerCheck {
            method: "peercred".into(),
            subject: "the app".into(),
        };
        Ok((id, peer))
    }

    fn refused() -> Accepted {
        Err(AcceptError::PeerRefused(anyhow::anyhow!("not the app")))
    }

    fn too_many_open_files() -> Accepted {
        Err(AcceptError::Io(io::Error::other("too many open files")))
    }

    async fn serve_in_order(script: Vec<Accepted>) -> Vec<(u32, Duration)> {
        let started = Instant::now();
        let mut served = Vec::new();
        accept_loop(stream::iter(script), std::future::pending(), |id, _| {
            served.push((id, started.elapsed()))
        })
        .await;
        served
    }

    fn ids(served: &[(u32, Duration)]) -> Vec<u32> {
        served.iter().map(|(id, _)| *id).collect()
    }

    #[tokio::test]
    async fn the_app_is_served_without_waiting_behind_a_refused_peer() {
        let served = serve_in_order(vec![refused(), app(1)]).await;
        assert_eq!(ids(&served), [1]);
        let waited = served[0].1;
        assert!(waited < FIRST_BACKOFF, "the app waited {waited:?}");
    }

    #[tokio::test]
    async fn an_io_error_still_backs_off_before_the_next_accept() {
        let served = serve_in_order(vec![too_many_open_files(), app(1)]).await;
        assert_eq!(ids(&served), [1]);
        let waited = served[0].1;
        assert!(waited >= FIRST_BACKOFF, "the backoff took {waited:?}");
    }

    #[tokio::test]
    async fn refusals_do_not_stop_the_loop() {
        let script = vec![refused(), app(1), refused(), refused(), app(2)];
        assert_eq!(ids(&serve_in_order(script).await), [1, 2]);
    }
}
