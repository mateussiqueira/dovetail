use serde::{Deserialize, Deserializer};
use serde_json::Value;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ApiErrorPayload {
    pub message: Option<String>,
    pub error: Option<String>,
    pub status_code: Option<u16>,
    pub code: Option<String>,
    pub active_connections: Option<u32>,
}

impl ApiErrorPayload {
    pub fn best_message(&self) -> Option<String> {
        self.message.clone().or_else(|| self.error.clone())
    }

    pub fn from_value(value: &Value) -> Self {
        let nested = value.get("message").filter(|m| m.is_object());

        Self {
            message: message_of(value.get("message")),
            error: text(value.get("error")).or_else(|| text(nested.and_then(|m| m.get("error")))),
            status_code: number(value.get("statusCode"))
                .or_else(|| number(nested.and_then(|m| m.get("statusCode")))),
            code: text(value.get("code")).or_else(|| text(nested.and_then(|m| m.get("code")))),
            active_connections: number(value.get("activeConnections"))
                .or_else(|| number(nested.and_then(|m| m.get("activeConnections")))),
        }
    }
}

impl<'de> Deserialize<'de> for ApiErrorPayload {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        Ok(Self::from_value(&Value::deserialize(deserializer)?))
    }
}

fn message_of(field: Option<&Value>) -> Option<String> {
    match field {
        Some(Value::String(text)) => Some(text.clone()),
        Some(Value::Object(object)) => object
            .get("message")
            .and_then(|inner| match inner {
                Value::String(text) => Some(text.clone()),
                Value::Array(items) => join(items),
                _ => None,
            }),
        Some(Value::Array(items)) => join(items),
        _ => None,
    }
}

fn join(items: &[Value]) -> Option<String> {
    let lines: Vec<&str> = items.iter().filter_map(Value::as_str).collect();
    if lines.is_empty() {
        None
    } else {
        Some(lines.join(", "))
    }
}

fn text(field: Option<&Value>) -> Option<String> {
    field.and_then(Value::as_str).map(str::to_string)
}

fn number<T: TryFrom<u64>>(field: Option<&Value>) -> Option<T> {
    field.and_then(Value::as_u64).and_then(|n| T::try_from(n).ok())
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

#[cfg(test)]
mod testes {
    use super::*;

    fn payload(json: &str) -> ApiErrorPayload {
        serde_json::from_str(json).expect("o corpo de erro deve sempre desserializar")
    }

    #[test]
    fn o_formato_plano_continua_valendo() {
        let p = payload(
            r#"{"message":"ja conectado","code":"ALREADY_CONNECTED","statusCode":409,"activeConnections":1}"#,
        );
        assert_eq!(p.message.as_deref(), Some("ja conectado"));
        assert_eq!(p.code.as_deref(), Some("ALREADY_CONNECTED"));
        assert_eq!(p.status_code, Some(409));
        assert_eq!(p.active_connections, Some(1));
    }

    #[test]
    fn o_objeto_aninhado_em_message_entrega_os_mesmos_campos() {
        let p = payload(
            r#"{"statusCode":409,"message":{"message":"ja conectado","code":"ALREADY_CONNECTED","activeConnections":2}}"#,
        );
        assert_eq!(p.message.as_deref(), Some("ja conectado"));
        assert_eq!(p.code.as_deref(), Some("ALREADY_CONNECTED"));
        assert_eq!(p.status_code, Some(409));
        assert_eq!(p.active_connections, Some(2));
    }

    #[test]
    fn o_campo_do_topo_vence_o_aninhado() {
        let p = payload(r#"{"code":"TOPO","message":{"code":"ANINHADO"}}"#);
        assert_eq!(p.code.as_deref(), Some("TOPO"));
    }

    #[test]
    fn a_lista_de_validacao_vira_uma_linha() {
        let p = payload(r#"{"statusCode":400,"message":["email invalido","senha curta"]}"#);
        assert_eq!(p.message.as_deref(), Some("email invalido, senha curta"));
        assert_eq!(p.status_code, Some(400));
    }

    #[test]
    fn a_lista_aninhada_tambem() {
        let p = payload(r#"{"message":{"message":["a","b"]}}"#);
        assert_eq!(p.message.as_deref(), Some("a, b"));
    }

    #[test]
    fn corpo_sem_nenhum_campo_conhecido_nao_derruba_a_desserializacao() {
        let p = payload(r#"{"algo":"outro"}"#);
        assert_eq!(p, ApiErrorPayload::default());
        assert_eq!(p.best_message(), None);
    }

    #[test]
    fn best_message_cai_no_error_quando_nao_ha_message() {
        let p = payload(r#"{"error":"Bad Request"}"#);
        assert_eq!(p.best_message().as_deref(), Some("Bad Request"));
    }

    #[test]
    fn numero_fora_da_faixa_vira_ausente_em_vez_de_erro() {
        let p = payload(r#"{"statusCode":70000}"#);
        assert_eq!(p.status_code, None);
    }
}
