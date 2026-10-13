use std::io;
#[cfg(unix)]
use std::{fs::File, io::Read, path::Path};

#[cfg(unix)]
pub fn random_nonce() -> io::Result<[u8; 16]> {
    read_nonce(Path::new("/dev/urandom"))
}

#[cfg(unix)]
fn read_nonce(generator: &Path) -> io::Result<[u8; 16]> {
    let mut nonce = [0u8; 16];
    File::open(generator)?.read_exact(&mut nonce)?;
    Ok(nonce)
}

#[cfg(windows)]
pub fn random_nonce() -> io::Result<[u8; 16]> {
    use windows_sys::Win32::Security::Cryptography::{
        BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG,
    };
    let mut nonce = [0u8; 16];
    let status = unsafe {
        BCryptGenRandom(
            std::ptr::null_mut(),
            nonce.as_mut_ptr(),
            nonce.len() as u32,
            BCRYPT_USE_SYSTEM_PREFERRED_RNG,
        )
    };
    if status < 0 {
        let reason = format!("BCryptGenRandom falhou: NTSTATUS {status:#010x}");
        return Err(io::Error::other(reason));
    }
    Ok(nonce)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rising(samples: impl Iterator<Item = u128>) -> bool {
        let samples: Vec<u128> = samples.collect();
        samples.windows(2).all(|pair| pair[0] <= pair[1])
    }

    #[test]
    fn two_nonces_in_a_row_differ() {
        assert_ne!(random_nonce().unwrap(), random_nonce().unwrap());
    }

    #[test]
    fn nonces_do_not_rise_like_a_clock_read_either_way() {
        let nonces: Vec<[u8; 16]> = (0..32).map(|_| random_nonce().unwrap()).collect();
        let little_endian = nonces.iter().map(|n| u128::from_le_bytes(*n));
        let big_endian = nonces.iter().map(|n| u128::from_be_bytes(*n));
        assert!(!rising(little_endian), "{nonces:?}");
        assert!(!rising(big_endian), "{nonces:?}");
    }

    #[cfg(unix)]
    #[test]
    fn a_generator_that_runs_dry_is_an_error() {
        let error = read_nonce(Path::new("/dev/null")).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::UnexpectedEof);
    }

    #[cfg(unix)]
    #[test]
    fn a_missing_generator_is_an_error() {
        let error = read_nonce(Path::new("/no/such/urandom")).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::NotFound);
    }
}
