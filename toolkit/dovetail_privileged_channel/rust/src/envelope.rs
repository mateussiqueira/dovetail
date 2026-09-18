use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Request<P> {
    pub id: u64,
    pub cmd: P,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Response<P> {
    pub id: u64,
    #[serde(flatten)]
    pub payload: RespPayload<P>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(untagged)]
pub enum RespPayload<P> {
    Ok { ok: P },
    Err { err: ErrorBody },
}

impl<P> RespPayload<P> {
    pub fn ok(value: P) -> Self {
        Self::Ok { ok: value }
    }

    pub fn erro(code: ErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self::Err {
            err: ErrorBody {
                code,
                message: message.into(),
                retryable,
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorBody {
    pub code: ErrorCode,
    pub message: String,
    pub retryable: bool,
}

impl ErrorBody {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            retryable: false,
        }
    }

    pub fn retryable(mut self) -> Self {
        self.retryable = true;
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ErrorCode(String);

impl ErrorCode {
    pub fn new(code: impl Into<String>) -> Self {
        Self(code.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn version_unsupported() -> Self {
        Self::new("VERSION_UNSUPPORTED")
    }

    pub fn handshake_required() -> Self {
        Self::new("HANDSHAKE_REQUIRED")
    }

    pub fn peer_rejected() -> Self {
        Self::new("PEER_REJECTED")
    }

    pub fn frame_too_large() -> Self {
        Self::new("FRAME_TOO_LARGE")
    }

    pub fn malformed_frame() -> Self {
        Self::new("MALFORMED_FRAME")
    }

    pub fn invalid_params() -> Self {
        Self::new("INVALID_PARAMS")
    }

    pub fn busy() -> Self {
        Self::new("BUSY")
    }

    pub fn timeout() -> Self {
        Self::new("TIMEOUT")
    }

    pub fn internal() -> Self {
        Self::new("INTERNAL")
    }
}

#[cfg(test)]
mod testes {
    use super::*;

    #[derive(Debug, Serialize, Deserialize, PartialEq)]
    struct Vocabulario {
        nome: String,
    }

    #[test]
    fn o_envelope_ok_achata_o_payload() {
        let r: Response<Vocabulario> = Response {
            id: 7,
            payload: RespPayload::ok(Vocabulario { nome: "x".into() }),
        };
        assert_eq!(
            serde_json::to_string(&r).unwrap(),
            r#"{"id":7,"ok":{"nome":"x"}}"#
        );
    }

    #[test]
    fn o_envelope_de_erro_carrega_codigo_e_retryable() {
        let r: Response<Vocabulario> = Response {
            id: 1,
            payload: RespPayload::erro(ErrorCode::busy(), "ocupado", true),
        };
        let v: serde_json::Value = serde_json::to_value(&r).unwrap();
        assert_eq!(v["err"]["code"], "BUSY");
        assert_eq!(v["err"]["retryable"], true);
        assert_eq!(v["err"]["message"], "ocupado");
    }

    #[test]
    fn o_codigo_atravessa_como_string_simples() {
        let e = ErrorBody::new(ErrorCode::peer_rejected(), "assinatura nao confere");
        assert_eq!(
            serde_json::to_string(&e).unwrap(),
            r#"{"code":"PEER_REJECTED","message":"assinatura nao confere","retryable":false}"#
        );
    }

    #[test]
    fn o_app_pode_trazer_o_proprio_codigo() {
        let e = ErrorBody::new(ErrorCode::new("ENGINE_FAILURE"), "o motor falhou");
        assert_eq!(
            serde_json::to_string(&e).unwrap(),
            r#"{"code":"ENGINE_FAILURE","message":"o motor falhou","retryable":false}"#
        );
    }

    #[test]
    fn codigo_desconhecido_atravessa_em_vez_de_ser_recusado() {
        let e: ErrorBody =
            serde_json::from_str(r#"{"code":"ALGO_NOVO","message":"m","retryable":true}"#).unwrap();
        assert_eq!(e.code.as_str(), "ALGO_NOVO");
        assert!(e.retryable);
    }

    #[test]
    fn o_pedido_carrega_id_e_vocabulario() {
        let r: Request<Vocabulario> = Request {
            id: 3,
            cmd: Vocabulario { nome: "y".into() },
        };
        assert_eq!(
            serde_json::to_string(&r).unwrap(),
            r#"{"id":3,"cmd":{"nome":"y"}}"#
        );
    }
}
