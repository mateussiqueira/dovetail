use std::fmt;

/// O que pode dar errado ao atravessar a ponte, do lado do Rust. Domina
/// as duas camadas de baixo sem depender de nenhuma delas: quem constroi
/// o runtime e quem spawna tarefa devolvem ISTO, e nao um erro do tokio.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BridgeError {
    RuntimeUnavailable(String),
    TaskPanicked(String),
}

impl fmt::Display for BridgeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BridgeError::RuntimeUnavailable(reason) => {
                write!(f, "could not start the bridge runtime: {reason}")
            }
            BridgeError::TaskPanicked(reason) => {
                write!(f, "a bridge task did not finish: {reason}")
            }
        }
    }
}

impl std::error::Error for BridgeError {}
