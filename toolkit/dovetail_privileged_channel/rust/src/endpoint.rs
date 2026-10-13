#[cfg(unix)]
use std::path::PathBuf;

use crate::peer_policy::PeerPolicy;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    address: String,
    peer_policy: Option<PeerPolicy>,
}

impl Endpoint {
    pub fn new(address: impl Into<String>) -> Self {
        Self {
            address: address.into(),
            peer_policy: None,
        }
    }

    pub fn with_peer_policy(mut self, policy: PeerPolicy) -> Self {
        self.peer_policy = Some(policy);
        self
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    pub fn peer_policy(&self) -> Option<&PeerPolicy> {
        self.peer_policy.as_ref()
    }

    #[cfg(unix)]
    pub fn directory(&self) -> Option<PathBuf> {
        PathBuf::from(&self.address)
            .parent()
            .map(|p| p.to_path_buf())
    }

    #[cfg(unix)]
    pub fn is_abstract(&self) -> bool {
        self.address.starts_with('@')
    }
}

#[cfg(test)]
mod testes {
    use super::*;

    #[test]
    fn guarda_o_endereco_como_recebido() {
        let e = Endpoint::new("/var/run/app/helper.sock");
        assert_eq!(e.address(), "/var/run/app/helper.sock");
    }

    #[test]
    fn the_endpoint_has_no_peer_policy_until_one_is_declared() {
        let policy = PeerPolicy::default().allow_uid(1000);
        let bare = Endpoint::new("/var/run/app/helper.sock");
        assert_eq!(bare.peer_policy(), None);
        let declared = bare.with_peer_policy(policy.clone());
        assert_eq!(declared.peer_policy(), Some(&policy));
    }

    #[cfg(unix)]
    #[test]
    fn o_diretorio_e_o_pai_do_socket() {
        let e = Endpoint::new("/var/run/app/helper.sock");
        assert_eq!(e.directory().unwrap(), PathBuf::from("/var/run/app"));
    }

    #[cfg(unix)]
    #[test]
    fn socket_na_raiz_nao_tem_diretorio_de_pai() {
        let e = Endpoint::new("/helper.sock");
        assert_eq!(e.directory().unwrap(), PathBuf::from("/"));
    }
}
