#![cfg(windows)]

mod failure;
mod native;
mod registrar;
mod registration;

pub use failure::RegistrationFailure;
pub use native::ScmRegistrar;
pub use registrar::Registrar;
pub use registration::{register, ExistingService};

#[cfg(test)]
mod tests;
