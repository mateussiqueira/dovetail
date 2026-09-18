use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct ApiErrorPayload {
    pub message: Option<String>,
    pub error: Option<String>,
    #[serde(rename = "statusCode")]
    pub status_code: Option<u16>,
    pub code: Option<String>,
    #[serde(rename = "activeConnections")]
    pub active_connections: Option<u32>,
}

impl ApiErrorPayload {
    pub fn best_message(&self) -> Option<String> {
        self.message.clone().or_else(|| self.error.clone())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("falha de transporte HTTP: {0}")]
    Transport(#[source] reqwest::Error),

    #[error("nao autorizado ({status})")]
    Unauthorized {
        status: u16,
        body: Option<ApiErrorPayload>,
    },

    #[error("sem permissao ({status})")]
    Forbidden {
        status: u16,
        body: Option<ApiErrorPayload>,
    },

    #[error("bloqueado por excesso de tentativas ({status})")]
    TooManyRequests {
        status: u16,
        body: Option<ApiErrorPayload>,
    },

    #[error("requisicao invalida ({status})")]
    BadRequest {
        status: u16,
        body: Option<ApiErrorPayload>,
    },

    #[error("erro do servidor ({status})")]
    Server {
        status: u16,
        body: Option<ApiErrorPayload>,
    },

    #[error("falha ao desserializar resposta: {0}")]
    Decode(#[source] reqwest::Error),

    #[error("falha no armazenamento de token: {0}")]
    TokenStore(String),

    #[error("nenhum token de acesso disponivel (login necessario)")]
    MissingToken,

    #[error("conta ainda nao confirmada; verifique seu e-mail")]
    AccountNotConfirmed,

    #[error("este perfil nao tem acesso ao aplicativo do cliente")]
    RoleNotAllowed,

    #[error("{message}")]
    AlreadyConnected {
        message: String,
        active_connections: u32,
    },

    #[error("erro interno do cliente HTTP: {0}")]
    Internal(String),
}

impl ApiError {
    pub fn is_retryable(&self) -> bool {
        match self {
            ApiError::Transport(e) => e.is_timeout() || e.is_connect() || e.is_request(),
            ApiError::Server { .. } => true,
            _ => false,
        }
    }

    pub fn status(&self) -> Option<u16> {
        match self {
            ApiError::Unauthorized { status, .. }
            | ApiError::Forbidden { status, .. }
            | ApiError::TooManyRequests { status, .. }
            | ApiError::BadRequest { status, .. }
            | ApiError::Server { status, .. } => Some(*status),
            _ => None,
        }
    }

    pub fn body(&self) -> Option<&ApiErrorPayload> {
        match self {
            ApiError::Unauthorized { body, .. }
            | ApiError::Forbidden { body, .. }
            | ApiError::TooManyRequests { body, .. }
            | ApiError::BadRequest { body, .. }
            | ApiError::Server { body, .. } => body.as_ref(),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ApiError;
    use reqwest::StatusCode;

    #[test]
    fn o_429_nao_e_requisicao_invalida() {
        let erro = ApiError::TooManyRequests {
            status: 429,
            body: None,
        };

        assert!(matches!(
            erro,
            ApiError::TooManyRequests { status: 429, .. }
        ));
        assert!(!matches!(erro, ApiError::BadRequest { .. }));
    }

    #[test]
    fn o_bloqueio_nao_entra_no_backoff() {
        assert!(!ApiError::TooManyRequests {
            status: 429,
            body: None
        }
        .is_retryable());
        assert!(ApiError::Server {
            status: 500,
            body: None
        }
        .is_retryable());
    }

    #[test]
    fn o_status_e_o_corpo_ficam_disponiveis() {
        let erro = ApiError::Unauthorized {
            status: 401,
            body: None,
        };
        assert_eq!(erro.status(), Some(401));
        assert!(erro.body().is_none());
        assert_eq!(StatusCode::UNAUTHORIZED.as_u16(), 401);
    }
}
