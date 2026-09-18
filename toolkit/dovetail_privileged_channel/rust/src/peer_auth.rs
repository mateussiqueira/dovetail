use crate::handshake::PeerCheck;
use crate::transport::Stream;

#[cfg(windows)]
pub fn verify_peer(conn: &Stream) -> anyhow::Result<PeerCheck> {
    use std::os::windows::io::AsRawHandle;

    let handle = conn.as_raw_handle();
    let pid = pid_do_cliente(handle)?;
    let exe = caminho_do_executavel(pid)?;

    let esperado = pasta_do_helper()?;
    let pasta_cliente = exe
        .parent()
        .ok_or_else(|| anyhow::anyhow!("caminho do cliente sem diretorio: {}", exe.display()))?;

    if !mesmo_caminho(pasta_cliente, &esperado) {
        anyhow::bail!(
            "cliente rejeitado: {} nao esta em {}",
            exe.display(),
            esperado.display()
        );
    }

    tracing::info!(pid, exe = %exe.display(), "peer autenticado");
    Ok(PeerCheck {
        method: "sddl+caminho".to_string(),
        subject: exe.display().to_string(),
    })
}

#[cfg(windows)]
fn pid_do_cliente(handle: std::os::windows::io::RawHandle) -> anyhow::Result<u32> {
    use windows_sys::Win32::System::Pipes::GetNamedPipeClientProcessId;

    let mut pid: u32 = 0;
    // SAFETY: `handle` e o handle vivo do pipe conectado; `pid` e valido.
    let ok = unsafe { GetNamedPipeClientProcessId(handle as _, &mut pid) };
    if ok == 0 {
        anyhow::bail!(
            "GetNamedPipeClientProcessId falhou: {}",
            std::io::Error::last_os_error()
        );
    }
    Ok(pid)
}

#[cfg(windows)]
fn caminho_do_executavel(pid: u32) -> anyhow::Result<std::path::PathBuf> {
    use windows_sys::Win32::Foundation::CloseHandle;
    use windows_sys::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
    };

    // SAFETY: chamada Win32 direta; o handle e fechado abaixo.
    let processo = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
    if processo.is_null() {
        anyhow::bail!(
            "OpenProcess({pid}) falhou: {}",
            std::io::Error::last_os_error()
        );
    }

    let mut buf = vec![0u16; 32_768];
    let mut tamanho = buf.len() as u32;
    // SAFETY: `buf` comporta `tamanho` u16; a API escreve dentro desse limite.
    let ok = unsafe { QueryFullProcessImageNameW(processo, 0, buf.as_mut_ptr(), &mut tamanho) };
    // SAFETY: handle valido, obtido acima e nao usado depois.
    unsafe { CloseHandle(processo) };

    if ok == 0 {
        anyhow::bail!(
            "QueryFullProcessImageNameW({pid}) falhou: {}",
            std::io::Error::last_os_error()
        );
    }
    buf.truncate(tamanho as usize);
    Ok(std::path::PathBuf::from(String::from_utf16(&buf)?))
}

#[cfg(windows)]
fn pasta_do_helper() -> anyhow::Result<std::path::PathBuf> {
    let eu = std::env::current_exe()?;
    Ok(eu
        .parent()
        .ok_or_else(|| anyhow::anyhow!("helper sem diretorio pai"))?
        .to_path_buf())
}

#[cfg(windows)]
fn mesmo_caminho(a: &std::path::Path, b: &std::path::Path) -> bool {
    match (a.canonicalize(), b.canonicalize()) {
        (Ok(x), Ok(y)) => x == y,
        _ => a
            .to_string_lossy()
            .eq_ignore_ascii_case(&b.to_string_lossy()),
    }
}

#[cfg(target_os = "macos")]
pub fn verify_peer(conn: &Stream) -> anyhow::Result<PeerCheck> {
    use std::os::unix::io::AsRawFd;

    let fd = conn.as_raw_fd();

    let mut uid: libc::uid_t = 0;
    let mut gid: libc::gid_t = 0;
    // SAFETY: fd valido enquanto `conn` viver; ponteiros para locais validos.
    let rc = unsafe { libc::getpeereid(fd, &mut uid, &mut gid) };
    if rc != 0 {
        anyhow::bail!("getpeereid falhou: {}", std::io::Error::last_os_error());
    }

    #[cfg(debug_assertions)]
    {
        let subject = codesign_subject_placeholder(uid)?;
        tracing::warn!(
            uid,
            gid,
            %subject,
            "PEER ACEITO SEM VERIFICACAO DE CODE SIGNATURE (SO EM DEBUG): qualquer \
             binario do uid {uid} entra por este canal. Em release o helper recusa."
        );
        Ok(PeerCheck {
            method: "peercred+codesign".to_string(),
            subject,
        })
    }

    #[cfg(not(debug_assertions))]
    {
        tracing::error!(
            uid,
            gid,
            "peer rejeitado (fail-closed): verificacao de code signature ausente"
        );
        anyhow::bail!(
            "code signature do peer nao verificada: em release o canal falha \
             FECHADO em vez de aceitar o uid {uid} (gid {gid}) sem conferir a \
             assinatura. Implemente, neste arquivo, o pid do peer \
             (LOCAL_PEERPID/getsockopt) + SecCodeCopyGuestWithAttributes + \
             SecCodeCheckValidity contra o SecRequirement do produto, para \
             habilitar o canal em release."
        )
    }
}

#[cfg(all(target_os = "macos", debug_assertions))]
fn codesign_subject_placeholder(uid: libc::uid_t) -> anyhow::Result<String> {
    Ok(format!("uid={uid} (codesign nao verificado - DEV)"))
}

#[cfg(all(unix, not(target_os = "macos")))]
pub fn verify_peer(conn: &Stream) -> anyhow::Result<PeerCheck> {
    use std::os::unix::io::AsRawFd;

    let fd = conn.as_raw_fd();

    let mut cred = libc::ucred {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: fd valido; ponteiros e tamanho corretos para SO_PEERCRED.
    let rc = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            &mut cred as *mut _ as *mut libc::c_void,
            &mut len,
        )
    };
    if rc != 0 {
        anyhow::bail!("SO_PEERCRED falhou: {}", std::io::Error::last_os_error());
    }

    let subject = polkit_authorize_placeholder(&cred)?;

    tracing::info!(
        pid = cred.pid,
        uid = cred.uid,
        gid = cred.gid,
        %subject,
        "peer autenticado (linux)"
    );
    Ok(PeerCheck {
        method: "peercred+polkit".to_string(),
        subject,
    })
}

#[cfg(all(unix, not(target_os = "macos")))]
fn polkit_authorize_placeholder(cred: &libc::ucred) -> anyhow::Result<String> {
    Ok(format!(
        "pid={} uid={} (polkit nao consultado - DEV)",
        cred.pid, cred.uid
    ))
}

#[cfg(all(test, target_os = "macos"))]
mod testes_macos {
    use super::*;

    async fn socket_do_peer() -> Stream {
        let (a, _b) = std::os::unix::net::UnixStream::pair().expect("socketpair");
        a.set_nonblocking(true).expect("nonblocking");
        tokio::net::UnixStream::from_std(a).expect("tokio stream")
    }

    #[cfg(debug_assertions)]
    #[tokio::test]
    async fn em_debug_o_peer_e_aceito_sem_codesign() {
        assert!(
            verify_peer(&socket_do_peer().await).is_ok(),
            "debug recusou o peer; este caminho tem de aceitar e logar"
        );
    }

    #[cfg(not(debug_assertions))]
    #[tokio::test]
    async fn em_release_o_peer_e_recusado_sem_codesign() {
        assert!(
            verify_peer(&socket_do_peer().await).is_err(),
            "release aceitou um peer sem code signature (fail-open)"
        );
    }
}
