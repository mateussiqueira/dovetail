use anyhow::Result;
use futures::{SinkExt, StreamExt};
use serde::de::DeserializeOwned;
use serde::Serialize;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_util::bytes::Bytes;
use tokio_util::codec::{Framed, LengthDelimitedCodec};

use crate::handshake::Frame;
use crate::limits::MAX_FRAME_BYTES;

pub type Framer<S> = Framed<S, LengthDelimitedCodec>;

pub fn framer<S>(stream: S) -> Framer<S>
where
    S: AsyncRead + AsyncWrite,
{
    let mut codec = LengthDelimitedCodec::new();
    codec.set_max_frame_length(MAX_FRAME_BYTES);
    Framed::new(stream, codec)
}

pub async fn send_frame<Req, Resp, S>(
    framed: &mut Framer<S>,
    frame: &Frame<Req, Resp>,
) -> Result<()>
where
    Req: Serialize,
    Resp: Serialize,
    S: AsyncRead + AsyncWrite + Unpin,
{
    let bytes = serde_json::to_vec(frame)?;
    framed.send(Bytes::from(bytes)).await?;
    Ok(())
}

pub async fn recv_frame<Req, Resp, S>(framed: &mut Framer<S>) -> Result<Option<Frame<Req, Resp>>>
where
    Req: DeserializeOwned,
    Resp: DeserializeOwned,
    S: AsyncRead + AsyncWrite + Unpin,
{
    match framed.next().await {
        Some(Ok(bytes)) => Ok(Some(serde_json::from_slice(bytes.as_ref())?)),
        Some(Err(e)) => Err(e.into()),
        None => Ok(None),
    }
}

#[cfg(test)]
mod testes {
    use super::*;
    use crate::envelope::{Request, RespPayload, Response};
    use tokio::io::duplex;
    use tokio::io::AsyncWriteExt;

    #[derive(Debug, Serialize, serde::Deserialize, PartialEq)]
    struct Cmd {
        n: u8,
    }

    #[derive(Debug, Serialize, serde::Deserialize, PartialEq)]
    struct Res {
        m: u8,
    }

    #[tokio::test]
    async fn o_frame_atravessa_o_canal_e_volta() {
        let (a, b) = duplex(64 * 1024);
        let mut lado_a = framer(a);
        let mut lado_b = framer(b);

        let enviado: Frame<Cmd, Res> = Frame::Request(Request {
            id: 42,
            cmd: Cmd { n: 5 },
        });
        send_frame(&mut lado_a, &enviado).await.unwrap();

        let recebido: Frame<Cmd, Res> = recv_frame(&mut lado_b).await.unwrap().unwrap();
        match recebido {
            Frame::Request(r) => {
                assert_eq!(r.id, 42);
                assert_eq!(r.cmd, Cmd { n: 5 });
            }
            outro => panic!("frame errado: {outro:?}"),
        }
    }

    #[tokio::test]
    async fn a_resposta_volta_achatada() {
        let (a, b) = duplex(64 * 1024);
        let mut lado_a = framer(a);
        let mut lado_b = framer(b);

        let resposta: Frame<Cmd, Res> = Frame::Response(Response {
            id: 1,
            payload: RespPayload::ok(Res { m: 9 }),
        });
        send_frame(&mut lado_b, &resposta).await.unwrap();

        let recebido: Option<Frame<Cmd, Res>> = recv_frame(&mut lado_a).await.unwrap();
        match recebido.unwrap() {
            Frame::Response(r) => match r.payload {
                RespPayload::Ok { ok } => assert_eq!(ok, Res { m: 9 }),
                outro => panic!("payload errado: {outro:?}"),
            },
            outro => panic!("frame errado: {outro:?}"),
        }
    }

    #[tokio::test]
    async fn canal_fechado_devolve_none() {
        let (a, b) = duplex(1024);
        let mut lado_a = framer(a);
        drop(b);
        let nenhum: Option<Frame<Cmd, Res>> = recv_frame(&mut lado_a).await.unwrap();
        assert!(nenhum.is_none());
    }

    #[tokio::test]
    async fn payload_maior_que_o_teto_e_recusado() {
        let (mut a, b) = duplex(256 * 1024);
        let mut lado_b = framer(b);
        let grande = vec![b'x'; MAX_FRAME_BYTES + 1];
        a.write_all(&(grande.len() as u32).to_be_bytes())
            .await
            .unwrap();
        a.write_all(&grande).await.unwrap();
        let r: Result<Option<Frame<Cmd, Res>>> = recv_frame(&mut lado_b).await;
        assert!(r.is_err(), "frame acima do teto tem de ser recusado");
    }
}
