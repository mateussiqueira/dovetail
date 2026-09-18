use serde::{Deserialize, Serialize};

use crate::envelope::{ErrorBody, Request, Response};

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum Frame<Req, Resp> {
    Hello(Hello),
    ServerHello(ServerHello),
    Request(Request<Req>),
    Response(Response<Resp>),
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Hello {
    pub proto_major: u16,
    pub proto_minor: u16,
    pub client_version: String,
    pub nonce: [u8; 16],
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerHello {
    pub accepted: bool,
    pub proto_major: u16,
    pub proto_minor: u16,
    pub helper_version: String,
    pub nonce: [u8; 16],
    pub peer_check: PeerCheck,
    pub reject: Option<ErrorBody>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerCheck {
    pub method: String,
    pub subject: String,
}

#[cfg(test)]
mod testes {
    use super::*;
    use crate::envelope::{ErrorCode, RespPayload};

    #[derive(Debug, Serialize, Deserialize, PartialEq)]
    struct Cmd {
        nome: String,
    }

    #[derive(Debug, Serialize, Deserialize, PartialEq)]
    struct Res {
        ok_demais: bool,
    }

    type F = Frame<Cmd, Res>;

    #[test]
    fn o_frame_e_etiquetado_por_t() {
        let f: F = Frame::Hello(Hello {
            proto_major: 1,
            proto_minor: 1,
            client_version: "0.1.0".into(),
            nonce: [0u8; 16],
        });
        let v: serde_json::Value = serde_json::to_value(&f).unwrap();
        assert_eq!(v["t"], "hello");
    }

    #[test]
    fn o_frame_de_pedido_carrega_o_vocabulario_do_app() {
        let f: F = Frame::Request(Request {
            id: 9,
            cmd: Cmd { nome: "p".into() },
        });
        let v: serde_json::Value = serde_json::to_value(&f).unwrap();
        assert_eq!(v["t"], "request");
        assert_eq!(v["id"], 9);
        assert_eq!(v["cmd"]["nome"], "p");
    }

    #[test]
    fn o_frame_de_resposta_achata_o_payload() {
        let f: F = Frame::Response(Response {
            id: 9,
            payload: RespPayload::ok(Res { ok_demais: true }),
        });
        let v: serde_json::Value = serde_json::to_value(&f).unwrap();
        assert_eq!(v["t"], "response");
        assert_eq!(v["ok"]["ok_demais"], true);
    }

    #[test]
    fn server_hello_recusado_carrega_o_motivo() {
        let sh = ServerHello {
            accepted: false,
            proto_major: 1,
            proto_minor: 1,
            helper_version: "0.1.0".into(),
            nonce: [0u8; 16],
            peer_check: PeerCheck {
                method: "peercred".into(),
                subject: "uid=0".into(),
            },
            reject: Some(ErrorBody::new(ErrorCode::PeerRejected, "recusado")),
        };
        let v: serde_json::Value = serde_json::to_value(&sh).unwrap();
        assert_eq!(v["accepted"], false);
        assert_eq!(v["reject"]["code"], "PEER_REJECTED");
    }

    #[test]
    fn ida_e_volta_de_um_pedido() {
        let f: F = Frame::Request(Request {
            id: 1,
            cmd: Cmd { nome: "z".into() },
        });
        let s = serde_json::to_string(&f).unwrap();
        let d: F = serde_json::from_str(&s).unwrap();
        match d {
            Frame::Request(r) => assert_eq!(r.cmd, Cmd { nome: "z".into() }),
            outro => panic!("frame errado: {outro:?}"),
        }
    }
}
