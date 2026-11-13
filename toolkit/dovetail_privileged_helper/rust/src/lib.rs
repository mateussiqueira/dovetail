#![cfg(windows)]

mod failure;
#[allow(non_snake_case)]
mod ffi;
mod helper_request;
mod native;
mod registrar;
mod registration;

pub use failure::RegistrationFailure;
pub use native::ScmRegistrar;
pub use registrar::Registrar;
pub use registration::{register, ExistingService};

#[cfg(test)]
mod ffi_tests;
#[cfg(test)]
mod tests;
