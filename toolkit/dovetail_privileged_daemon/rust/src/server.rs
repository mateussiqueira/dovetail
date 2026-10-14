use std::future::Future;
use std::sync::Arc;
use std::time::{Duration, Instant};

#[cfg(not(target_os = "macos"))]
use dovetail_privileged_channel::bind;
#[cfg(any(test, not(target_os = "macos")))]
use dovetail_privileged_channel::Endpoint;
use dovetail_privileged_channel::{AcceptError, PeerCheck};
#[cfg(target_os = "macos")]
use dovetail_privileged_channel::{PeerPolicy, XpcListener};
use futures::{stream, Stream, StreamExt};

use crate::connection::handle_conn;
use crate::refusal_log::RefusalLog;
use crate::DaemonApp;

const REFUSAL_LOG_WINDOW: Duration = Duration::from_secs(60);

pub async fn run<A, F>(app: Arc<A>, shutdown: F) -> anyhow::Result<()>
where
    A: DaemonApp,
    F: Future<Output = ()>,
{
    app.prepare().await?;

    let incoming = incoming::<A>().await?;
    tracing::info!("helper ouvindo no transporte local do SO");

    accept_loop(
        incoming,
        shutdown,
        |conn, peer| {
            let app = app.clone();
            tokio::spawn(async move {
                if let Err(err) = handle_conn(conn, peer, app).await {
                    tracing::debug!(?err, "conexao encerrada com erro");
                }
            });
        },
        log_refusal,
    )
    .await;

    Ok(())
}

#[cfg(not(target_os = "macos"))]
async fn incoming<A: DaemonApp>() -> anyhow::Result<
    impl Stream<Item = Result<(dovetail_privileged_channel::Stream, PeerCheck), AcceptError>>,
> {
    let listener = bind(&endpoint::<A>()).await?;
    Ok(stream::unfold(listener, |mut listener| async move {
        Some((listener.accept().await, listener))
    }))
}

#[cfg(target_os = "macos")]
async fn incoming<A: DaemonApp>() -> anyhow::Result<
    impl Stream<Item = Result<(dovetail_privileged_channel::XpcConnection, PeerCheck), AcceptError>>,
> {
    let requirement = xpc_requirement(std::env::args(), A::peer_policy())?;
    let listener = XpcListener::mach_service(A::IDENTITY.macos_label, &requirement)?;
    Ok(stream::unfold(listener, |mut listener| async move {
        let conn = listener.accept().await?;
        let peer = PeerCheck {
            method: "xpc+codesign".into(),
            subject: format!("pid={}", conn.pid()),
        };
        Some((Ok((conn, peer)), listener))
    }))
}

#[cfg(target_os = "macos")]
const REQUIREMENT_FLAG: &str = "--peer-requirement";

#[cfg(target_os = "macos")]
fn xpc_requirement(
    mut args: impl Iterator<Item = String>,
    policy: Option<PeerPolicy>,
) -> anyhow::Result<String> {
    let declared = args.find(|arg| arg == REQUIREMENT_FLAG).and(args.next());
    declared
        .or_else(|| {
            policy
                .as_ref()
                .and_then(PeerPolicy::code_requirement)
                .map(str::to_string)
        })
        .ok_or_else(|| {
            anyhow::anyhow!(
                "no macOS o daemon atende por XPC e exige o requisito de assinatura do app \
                 (PeerPolicy::require_code)"
            )
        })
}

#[cfg(any(test, not(target_os = "macos")))]
fn endpoint<A: DaemonApp>() -> Endpoint {
    let endpoint = Endpoint::new(A::ENDPOINT);
    match A::peer_policy() {
        Some(policy) => endpoint.with_peer_policy(policy),
        None => endpoint,
    }
}

fn log_refusal(reason: Option<&anyhow::Error>, silenciadas: u64) {
    match reason {
        Some(reason) => {
            tracing::warn!(motivo = %reason, silenciadas, "peer recusado; conexao fechada")
        }
        None => tracing::warn!(silenciadas, "recusas sem linha propria ate o fim do loop"),
    }
}

async fn accept_loop<C>(
    incoming: impl Stream<Item = Result<(C, PeerCheck), AcceptError>>,
    shutdown: impl Future<Output = ()>,
    mut serve: impl FnMut(C, PeerCheck),
    mut refusal_line: impl FnMut(Option<&anyhow::Error>, u64),
) {
    tokio::pin!(incoming, shutdown);
    let mut falhas_seguidas: u64 = 0;
    let mut recusas = RefusalLog::new(REFUSAL_LOG_WINDOW);
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
                        if let Some(silenciadas) = recusas.refused(Instant::now()) {
                            refusal_line(Some(&reason), silenciadas);
                        }
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
    if recusas.silenced() > 0 {
        refusal_line(None, recusas.silenced());
    }
}

#[cfg(test)]
mod tests {
    use std::io;

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

    #[cfg(target_os = "macos")]
    #[test]
    fn on_macos_the_daemon_serves_xpc_under_the_requirement_the_app_declares() {
        let policy = PeerPolicy::default().require_code("cdhash H\"00\"");
        let requirement = xpc_requirement(no_args(), Some(policy)).unwrap();
        assert_eq!(requirement, "cdhash H\"00\"");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn on_macos_a_policy_without_a_code_requirement_does_not_start_the_daemon() {
        let refused = xpc_requirement(no_args(), Guarded::peer_policy()).unwrap_err();
        assert!(refused.to_string().contains("require_code"), "{refused}");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn on_macos_an_app_without_a_policy_does_not_start_the_daemon() {
        assert!(xpc_requirement(no_args(), Echo::peer_policy()).is_err());
    }

    #[cfg(target_os = "macos")]
    fn no_args() -> std::vec::IntoIter<String> {
        Vec::new().into_iter()
    }

    #[cfg(target_os = "macos")]
    fn launched_with(args: &[&str]) -> std::vec::IntoIter<String> {
        let args: Vec<String> = args.iter().map(|arg| arg.to_string()).collect();
        args.into_iter()
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn on_macos_the_requirement_the_plist_passes_is_the_one_served() {
        let args = launched_with(&[
            "helper",
            "--service",
            "--peer-requirement",
            "cdhash H\"ab\"",
        ]);
        let requirement = xpc_requirement(args, Echo::peer_policy()).unwrap();
        assert_eq!(requirement, "cdhash H\"ab\"");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn on_macos_the_plist_requirement_wins_over_the_one_compiled_in() {
        let policy = PeerPolicy::default().require_code("cdhash H\"00\"");
        let args = launched_with(&["helper", "--peer-requirement", "cdhash H\"ab\""]);
        let requirement = xpc_requirement(args, Some(policy)).unwrap();
        assert_eq!(requirement, "cdhash H\"ab\"");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn on_macos_a_flag_with_no_value_does_not_start_the_daemon() {
        let args = launched_with(&["helper", "--peer-requirement"]);
        assert!(xpc_requirement(args, Echo::peer_policy()).is_err());
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
        accept_loop(
            stream::iter(script),
            std::future::pending(),
            |id, _| served.push((id, started.elapsed())),
            |_, _| {},
        )
        .await;
        served
    }

    async fn refusal_lines(script: Vec<Accepted>) -> Vec<(Option<String>, u64)> {
        let mut lines = Vec::new();
        accept_loop(
            stream::iter(script),
            std::future::pending(),
            |_, _| {},
            |reason, silenced| lines.push((reason.map(ToString::to_string), silenced)),
        )
        .await;
        lines
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

    #[tokio::test]
    async fn a_burst_of_refusals_gets_one_line_and_the_rest_are_counted_when_the_loop_ends() {
        let lines = refusal_lines(vec![refused(), refused(), app(1), refused()]).await;
        assert_eq!(lines, [(Some("not the app".to_string()), 0), (None, 2)]);
    }

    #[tokio::test]
    async fn a_lone_refusal_gets_its_line_and_no_count_at_the_end() {
        let lines = refusal_lines(vec![refused(), app(1)]).await;
        assert_eq!(lines, [(Some("not the app".to_string()), 0)]);
    }
}
