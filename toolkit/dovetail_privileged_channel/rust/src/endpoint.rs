use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    address: String,
}

impl Endpoint {
    pub fn new(address: impl Into<String>) -> Self {
        Self {
            address: address.into(),
        }
    }

    pub fn address(&self) -> &str {
        &self.address
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
