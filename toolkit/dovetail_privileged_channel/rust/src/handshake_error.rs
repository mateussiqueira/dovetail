use std::fmt;

#[derive(Debug)]
pub enum HandshakeError {
    UnexpectedFrame { expected: &'static str, got: String },
    StreamEnded,
    Rejected { reason: String },
    VersionMismatch { client: u16, server: u16 },
    Timeout,
}

impl fmt::Display for HandshakeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnexpectedFrame { expected, got } => {
                write!(
                    f,
                    "frame inesperado no handshake: esperava {expected}, veio {got}"
                )
            }
            Self::StreamEnded => write!(f, "conexao fechada antes do fim do handshake"),
            Self::Rejected { reason } => write!(f, "handshake recusado pelo servidor: {reason}"),
            Self::VersionMismatch { client, server } => {
                write!(
                    f,
                    "protocolo incompativel: cliente {client}, servidor {server}"
                )
            }
            Self::Timeout => write!(f, "handshake nao concluido dentro do prazo"),
        }
    }
}

impl std::error::Error for HandshakeError {}
