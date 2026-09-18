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

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    VersionUnsupported,
    HandshakeRequired,
    PeerRejected,
    FrameTooLarge,
    MalformedFrame,
    InvalidParams,
    Busy,
    NotConnected,
    AlreadyConnected,
    Timeout,
    Internal,
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
            payload: RespPayload::erro(ErrorCode::Busy, "ocupado", true),
        };
        let v: serde_json::Value = serde_json::to_value(&r).unwrap();
        assert_eq!(v["err"]["code"], "BUSY");
        assert_eq!(v["err"]["retryable"], true);
        assert_eq!(v["err"]["message"], "ocupado");
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

    #[test]
    fn o_erro_de_handshake_nao_depende_de_vocabulario() {
        let e = ErrorBody::new(ErrorCode::PeerRejected, "assinatura nao confere");
        assert!(!e.retryable);
        assert_eq!(
            serde_json::to_string(&e).unwrap(),
            r#"{"code":"PEER_REJECTED","message":"assinatura nao confere","retryable":false}"#
        );
    }
}
