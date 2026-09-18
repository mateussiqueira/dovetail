use std::path::Path;

use tokio::net::UnixListener;

use crate::endpoint::Endpoint;
use crate::handshake::PeerCheck;
use crate::peer_auth;
use crate::transport::Stream;

pub struct LinuxListener {
    inner: UnixListener,
}

impl LinuxListener {
    pub async fn bind(endpoint: &Endpoint) -> anyhow::Result<Self> {
        let path = endpoint.address().to_string();
        prepare_socket_path(&path)?;
        let inner = UnixListener::bind(&path)?;
        harden_socket_permissions(&path)?;
        Ok(Self { inner })
    }

    pub async fn accept(&mut self) -> anyhow::Result<(Stream, PeerCheck)> {
        let (stream, _addr) = self.inner.accept().await?;
        let peer = peer_auth::verify_peer(&stream)?;
        Ok((stream, peer))
    }
}

fn prepare_socket_path(path: &str) -> anyhow::Result<()> {
    let p = Path::new(path);
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir)?;
        set_dir_mode_0700(dir)?;
    }
    if p.exists() {
        std::fs::remove_file(p)?;
    }
    Ok(())
}

fn set_dir_mode_0700(dir: &Path) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let perms = std::fs::Permissions::from_mode(0o700);
    std::fs::set_permissions(dir, perms)?;
    Ok(())
}

fn harden_socket_permissions(path: &str) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let perms = std::fs::Permissions::from_mode(0o600);
    std::fs::set_permissions(path, perms)?;
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
    async fn o_linux_nunca_afrouxa_o_socket() {
        let base = std::env::temp_dir().join(format!("dovetail-linux-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let endpoint = Endpoint::new(base.join("helper.sock").to_str().unwrap().to_string());
        let _listener = LinuxListener::bind(&endpoint).await.unwrap();
        assert_eq!(modo_de(&base), 0o700);
        assert_eq!(modo_de(Path::new(endpoint.address())), 0o600);
        let _ = std::fs::remove_dir_all(&base);
    }
}
