use std::path::Path;

use tokio::net::UnixListener;

use crate::endpoint::Endpoint;
use crate::handshake::PeerCheck;
use crate::peer_auth;
use crate::transport::Stream;

pub struct MacListener {
    inner: UnixListener,
}

#[cfg(debug_assertions)]
const DIR_MODE: u32 = 0o755;
#[cfg(not(debug_assertions))]
const DIR_MODE: u32 = 0o700;

#[cfg(debug_assertions)]
const SOCKET_MODE: u32 = 0o666;
#[cfg(not(debug_assertions))]
const SOCKET_MODE: u32 = 0o600;

impl MacListener {
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
        set_dir_mode(dir)?;
    }
    if p.exists() {
        std::fs::remove_file(p)?;
    }
    Ok(())
}

fn set_dir_mode(dir: &Path) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let perms = std::fs::Permissions::from_mode(DIR_MODE);
    std::fs::set_permissions(dir, perms)?;
    #[cfg(debug_assertions)]
    tracing::warn!(
        caminho = %dir.display(),
        modo = %format!("{DIR_MODE:04o}"),
        "PORTA ABERTA (SO EM DEBUG): o diretorio do socket esta atravessavel por \
         qualquer processo local. Um build de release aplica 0700 e isto nao existe."
    );
    Ok(())
}

fn harden_socket_permissions(path: &str) -> anyhow::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let perms = std::fs::Permissions::from_mode(SOCKET_MODE);
    std::fs::set_permissions(path, perms)?;
    #[cfg(debug_assertions)]
    tracing::warn!(
        caminho = %path,
        modo = %format!("{SOCKET_MODE:04o}"),
        "PORTA ABERTA (SO EM DEBUG): qualquer processo local pode falar com este \
         helper. Em release o socket e 0600 e o peer falha fechado em `peer_auth`."
    );
    Ok(())
}

#[cfg(test)]
mod testes {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn modo_de(path: &Path) -> u32 {
        std::fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn aplica_o_modo_do_perfil_no_diretorio_e_no_socket() {
        let base = std::env::temp_dir().join(format!("dovetail-perm-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(&base).unwrap();

        set_dir_mode(&base).unwrap();
        assert_eq!(modo_de(&base), DIR_MODE);

        let socket = base.join("helper.sock");
        std::fs::write(&socket, b"").unwrap();
        harden_socket_permissions(socket.to_str().unwrap()).unwrap();
        assert_eq!(modo_de(&socket), SOCKET_MODE);

        let _ = std::fs::remove_dir_all(&base);
    }

    #[tokio::test]
    async fn bind_cria_o_socket_no_endereco_dado() {
        let base = std::env::temp_dir().join(format!("dovetail-bind-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        let endpoint = Endpoint::new(base.join("helper.sock").to_str().unwrap().to_string());
        let _listener = MacListener::bind(&endpoint).await.unwrap();
        assert!(Path::new(endpoint.address()).exists());
        assert_eq!(modo_de(&base), DIR_MODE);
        assert_eq!(modo_de(Path::new(endpoint.address())), SOCKET_MODE);
        let _ = std::fs::remove_dir_all(&base);
    }
}
