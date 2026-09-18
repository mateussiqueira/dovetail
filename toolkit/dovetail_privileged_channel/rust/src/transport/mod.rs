use crate::endpoint::Endpoint;

#[cfg(all(unix, not(target_os = "macos")))]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(windows)]
mod windows;

#[cfg(all(unix, not(target_os = "macos")))]
pub use linux::LinuxListener as Listener;
#[cfg(target_os = "macos")]
pub use macos::MacListener as Listener;
#[cfg(windows)]
pub use windows::WindowsListener as Listener;

#[cfg(unix)]
pub type Stream = tokio::net::UnixStream;

#[cfg(windows)]
pub type Stream = tokio::net::windows::named_pipe::NamedPipeServer;

pub async fn bind(endpoint: &Endpoint) -> anyhow::Result<Listener> {
    Listener::bind(endpoint).await
}
