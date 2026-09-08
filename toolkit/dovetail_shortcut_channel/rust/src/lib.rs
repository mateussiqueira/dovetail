//! O atalho global, do lado do Rust.
//!
//! As camadas seguem o padrao dos projetos de optimas: `domain` e o
//! vocabulario (que backend existe, que status um chamador recebe) e nao
//! depende de ninguem; `infra` toca a biblioteca de hotkey, o ambiente e
//! a thread do laco de eventos; `presentation` e a superficie `extern "C"`
//! que o Dart chama. Este arquivo e a fachada.
mod domain;
mod infra;
mod presentation;

pub use domain::backend::Backend;
pub use domain::status::Status;
pub use infra::backend_probe::detect;
pub use infra::hotkey_parser::parse;

/// A superficie `extern "C"` continua saindo pela raiz da crate: e o que
/// o Dart carrega por nome de simbolo, e o que o exemplo de sessao chama.
/// Mover o codigo para `presentation` nao pode mover o nome.
pub use presentation::shortcut_ffi::*;
