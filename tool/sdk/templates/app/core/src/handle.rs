//! `CoreHandle` — the facade the bridge passes through to Flutter.

/// The product's Rust core. Grows with the product; the bridge mirrors it,
/// method by method, and `core_bridge/test/core_coverage_test.dart` refuses
/// when this side grows a method the bridge does not expose.
pub struct CoreHandle;

impl CoreHandle {
    pub fn new() -> Self {
        CoreHandle
    }

    pub fn greeting(&self) -> Result<String, String> {
        Ok("Hello from the Rust core".to_string())
    }
}
