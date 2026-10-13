//! O nucleo Rust que a ponte usa: o runtime, a bomba de eventos e a
//! tabela que a governa.
mod data;
mod domain;
mod infra;

pub use data::event_pump::pump;
pub use data::line_subscriber::LineSubscriber;
pub use data::pump_table::Replacement;
pub use domain::abortable_pump::AbortablePump;

/// A tabela com o pump concreto amarrado: e aqui, na fachada, que `data`
/// e `infra` se encontram — e por isso nenhuma das duas conhece a outra.
pub type PumpTable = data::pump_table::PumpTable<infra::runtime_pump_task::PumpTask>;
pub use domain::bridge_error::BridgeError;
pub use infra::log_lines::log_lines;
pub use infra::runtime_pump_task::PumpTask;
pub use infra::tokio_runtime::{run_on_runtime, runtime};
