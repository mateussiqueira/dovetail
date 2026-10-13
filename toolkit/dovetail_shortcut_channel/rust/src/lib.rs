//! O atalho global, do lado do Rust.
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
