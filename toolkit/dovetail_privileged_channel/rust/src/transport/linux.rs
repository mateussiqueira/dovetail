use std::path::Path;

use tokio::net::UnixListener;

use crate::endpoint::Endpoint;
use crate::handshake::PeerCheck;
use crate::peer_auth;
use crate::peer_policy::{socket_modes, PeerPolicy};
use crate::transport::{admit_by_policy, AcceptError, Stream};

pub struct LinuxListener {
    inner: UnixListener,
    policy: Option<PeerPolicy>,
}

impl LinuxListener {
    pub async fn bind(endpoint: &Endpoint) -> anyhow::Result<Self> {
        let path = endpoint.address().to_string();
        let policy = endpoint.peer_policy().cloned();
        let modes = socket_modes(policy.as_ref());
        prepare_socket_path(&path, modes.directory)?;
        let inner = UnixListener::bind(&path)?;
        set_mode(Path::new(&path), modes.socket)?;
        Ok(Self { inner, policy })
    }

    pub async fn accept(&mut self) -> Result<(Stream, PeerCheck), AcceptError> {
        let (stream, _addr) = self.inner.accept().await.map_err(AcceptError::Io)?;
        admit_by_policy(stream, self.policy.as_ref(), peer_auth::peer_credentials)
    }
}

fn prepare_socket_path(path: &str, directory_mode: u32) -> anyhow::Result<()> {
    let p = Path::new(path);
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir)?;
        set_mode(dir, directory_mode)?;
    }
    if p.exists() {
        std::fs::remove_file(p)?;
    }
    Ok(())
}

fn set_mode(path: &Path, mode: u32) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))?;
    Ok(())
}

#[cfg(test)]
mod testes {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn modo_de(path: &Path) -> u32 {
        std::fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    #[tokio::test]
    async fn without_a_policy_the_socket_stays_with_its_owner() {
        let base = std::env::temp_dir().join(format!("dovetail-linux-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let endpoint = Endpoint::new(base.join("helper.sock").to_str().unwrap().to_string());
        let _listener = LinuxListener::bind(&endpoint).await.unwrap();
        assert_eq!(modo_de(&base), 0o700);
        assert_eq!(modo_de(Path::new(endpoint.address())), 0o600);
        let _ = std::fs::remove_dir_all(&base);
    }

    #[tokio::test]
    async fn with_a_policy_every_local_user_reaches_the_socket() {
        let base = std::env::temp_dir().join(format!("dovetail-policy-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let address = base.join("helper.sock").to_str().unwrap().to_string();
        let policy = PeerPolicy::default().allow_gid(1000);
        let endpoint = Endpoint::new(address).with_peer_policy(policy);
        let _listener = LinuxListener::bind(&endpoint).await.unwrap();
        assert_eq!(modo_de(&base), 0o755);
        assert_eq!(modo_de(Path::new(endpoint.address())), 0o666);
        let _ = std::fs::remove_dir_all(&base);
    }
}
