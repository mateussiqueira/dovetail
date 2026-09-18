use tokio::net::windows::named_pipe::ServerOptions;

use crate::endpoint::Endpoint;
use crate::handshake::PeerCheck;
use crate::peer_auth;
use crate::transport::Stream;

pub struct WindowsListener {
    pending: Option<Stream>,
    pipe_name: String,
}

impl WindowsListener {
    pub async fn bind(endpoint: &Endpoint) -> anyhow::Result<Self> {
        let pipe_name = endpoint.address().to_string();
        let pending = create_instance(&pipe_name, true)?;
        Ok(Self {
            pending: Some(pending),
            pipe_name,
        })
    }

    pub async fn accept(&mut self) -> anyhow::Result<(Stream, PeerCheck)> {
        if self.pending.is_none() {
            self.pending = Some(create_instance(&self.pipe_name, false)?);
        }
        let pendente = self.pending.as_mut().expect("instancia pendente");

        pendente.connect().await?;

        let conn = self.pending.take().expect("instancia conectada");

        let peer = peer_auth::verify_peer(&conn)?;
        Ok((conn, peer))
    }
}

const DIREITOS_CLIENTE: &str = "0x12019b";

fn create_instance(pipe_name: &str, first: bool) -> anyhow::Result<Stream> {
    use std::ffi::c_void;
    use std::ptr;

    use windows_sys::Win32::Foundation::{LocalFree, HLOCAL};
    use windows_sys::Win32::Security::Authorization::{
        ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
    };
    use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;

    let sddl: Vec<u16> = format!("D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;{DIREITOS_CLIENTE};;;AU)")
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();

    let mut descritor: *mut c_void = ptr::null_mut();
    // SAFETY: `sddl` termina em NUL e vive ate o fim da chamada; o ponteiro de
    // saida e valido. A funcao aloca com LocalAlloc — liberado no fim.
    let ok = unsafe {
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.as_ptr(),
            SDDL_REVISION_1,
            &mut descritor,
            ptr::null_mut(),
        )
    };
    if ok == 0 || descritor.is_null() {
        return Err(anyhow::anyhow!(
            "nao foi possivel montar o descritor de seguranca do pipe: {}",
            std::io::Error::last_os_error()
        ));
    }

    let mut atributos = SECURITY_ATTRIBUTES {
        nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: descritor,
        bInheritHandle: 0,
    };

    let mut opts = ServerOptions::new();
    opts.first_pipe_instance(first).reject_remote_clients(true);

    // SAFETY: `atributos` aponta para um descritor valido e continua vivo
    // durante a chamada; o tokio so o usa para criar o handle.
    let resultado = unsafe {
        opts.create_with_security_attributes_raw(
            pipe_name,
            &mut atributos as *mut SECURITY_ATTRIBUTES as *mut c_void,
        )
    };

    // SAFETY: `descritor` veio de LocalAlloc na chamada acima e nao e mais usado.
    unsafe { LocalFree(descritor as HLOCAL) };

    Ok(resultado?)
}
