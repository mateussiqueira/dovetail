use super::{
    codigo_do_erro, falha, FalhaSetup, ERROR_ACCESS_DENIED, ERROR_SERVICE_MARKED_FOR_DELETE,
};
use crate::exit_codes;
use dovetail_windows_service::RegistrationFailure;

pub(super) fn map_failure(failure: RegistrationFailure) -> FalhaSetup {
    let (operation, error, access_denied) = match failure {
        RegistrationFailure::Create(error)
            if codigo_do_erro(&error) == Some(ERROR_SERVICE_MARKED_FOR_DELETE) =>
        {
            return falha(
                exit_codes::REGISTER_FAILED,
                "o servico esta marcado para exclusao (1072); reinicie o Windows e repita",
            );
        }
        RegistrationFailure::Create(error) => ("CreateService", error, true),
        RegistrationFailure::Open(error) => ("OpenService", error, true),
        RegistrationFailure::Configure(error) => ("ChangeServiceConfig", error, false),
    };
    let code = if access_denied && codigo_do_erro(&error) == Some(ERROR_ACCESS_DENIED) {
        exit_codes::SCM_ACCESS_DENIED
    } else {
        exit_codes::REGISTER_FAILED
    };
    falha(code, format!("{operation} falhou: {error:?}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn error(code: i32) -> windows_service::Error {
        windows_service::Error::Winapi(std::io::Error::from_raw_os_error(code))
    }

    #[test]
    fn access_denied_keeps_the_registration_stage_exit_code() {
        for (failure, code, operation) in [
            (
                RegistrationFailure::Create(error(5)),
                exit_codes::SCM_ACCESS_DENIED,
                "CreateService",
            ),
            (
                RegistrationFailure::Open(error(5)),
                exit_codes::SCM_ACCESS_DENIED,
                "OpenService",
            ),
            (
                RegistrationFailure::Configure(error(5)),
                exit_codes::REGISTER_FAILED,
                "ChangeServiceConfig",
            ),
        ] {
            let result = map_failure(failure);
            assert_eq!(result.codigo, code);
            assert!(result.mensagem.starts_with(operation));
        }
    }

    #[test]
    fn marked_for_deletion_keeps_the_restart_guidance() {
        let result = map_failure(RegistrationFailure::Create(error(1072)));
        assert_eq!(result.codigo, exit_codes::REGISTER_FAILED);
        assert!(result.mensagem.contains("reinicie o Windows"));
        let result = map_failure(RegistrationFailure::Create(error(87)));
        assert_eq!(result.codigo, exit_codes::REGISTER_FAILED);
        assert!(result.mensagem.starts_with("CreateService"));
    }
}
