//! O nucleo Rust que a ponte usa: o runtime, a bomba de eventos e a
//! tabela que a governa.
//!
//! As camadas seguem o padrao dos projetos de optimas: `domain` nao
//! depende de ninguem, `data` depende so de `domain`, e `infra` e o unico
//! lugar que toca recurso do sistema (aqui, as threads do tokio). Este
//! arquivo e a fachada: quem consome a crate nao precisa saber a camada.
mod data;
mod domain;
mod infra;

pub use data::event_pump::pump;
pub use data::pump_table::Replacement;
pub use domain::abortable_pump::AbortablePump;

/// A tabela com o pump concreto amarrado: e aqui, na fachada, que `data`
/// e `infra` se encontram — e por isso nenhuma das duas conhece a outra.
pub type PumpTable = data::pump_table::PumpTable<infra::runtime_pump_task::PumpTask>;
pub use domain::bridge_error::BridgeError;
pub use infra::runtime_pump_task::PumpTask;
pub use infra::tokio_runtime::{run_on_runtime, runtime};
