use crate::domain::backend::Backend;

/// Le a sessao do usuario para dizer qual backend de atalho existe aqui.
///
/// Separado do enum de proposito: `Backend::for_session` recebe os tres
/// valores e e provavel sem ambiente nenhum — e ha um teste que depende disso
/// (uma sessao Wayland rodando XWayland nao e uma sessao X11). Esta funcao e a
/// unica parte que precisa do processo real, e por isso e a unica que mora em
/// `infra`.
pub fn detect() -> Backend {
    #[cfg(target_os = "windows")]
    {
        Backend::Win32RegisterHotKey
    }
    #[cfg(target_os = "macos")]
    {
        Backend::CarbonEventHotKey
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        Backend::for_session(
            std::env::var("XDG_SESSION_TYPE").ok().as_deref(),
            std::env::var("WAYLAND_DISPLAY").ok().as_deref(),
            std::env::var("DISPLAY").ok().as_deref(),
        )
    }
    #[cfg(not(any(unix, target_os = "windows")))]
    {
        Backend::None
    }
}
