#![allow(dead_code)]

pub const OK: i32 = 0;
pub const UNKNOWN: i32 = 1;
pub const FAILED: i32 = 2;
pub const STARTING: i32 = 3;
pub const STOPPED: i32 = 4;
pub const NOT_INSTALLED: i32 = 5;
pub const NEEDS_ELEVATION: i32 = 6;
pub const SCM_ACCESS_DENIED: i32 = 20;
pub const REGISTER_FAILED: i32 = 21;
pub const MISSING_DEPENDENCY: i32 = 22;
pub const START_TIMEOUT: i32 = 23;
pub const START_FAILED: i32 = 24;
pub const UNSUPPORTED_PLATFORM: i32 = 30;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn os_codigos_de_saida_sao_estaveis() {
        assert_eq!(OK, 0);
        assert_eq!(UNKNOWN, 1);
        assert_eq!(FAILED, 2);
        assert_eq!(STARTING, 3);
        assert_eq!(STOPPED, 4);
        assert_eq!(NOT_INSTALLED, 5);
        assert_eq!(NEEDS_ELEVATION, 6);
        assert_eq!(SCM_ACCESS_DENIED, 20);
        assert_eq!(REGISTER_FAILED, 21);
        assert_eq!(MISSING_DEPENDENCY, 22);
        assert_eq!(START_TIMEOUT, 23);
        assert_eq!(START_FAILED, 24);
        assert_eq!(UNSUPPORTED_PLATFORM, 30);
    }
}
