use std::fmt;

#[derive(Debug)]
pub enum HandshakeError {
    UnexpectedFrame { expected: &'static str, got: String },
    StreamEnded,
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
        }
    }
}

impl std::error::Error for HandshakeError {}
