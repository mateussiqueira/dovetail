**English** · [Português](README.pt-BR.md)

# dovetail_rust_core

> The compatibility layer between Dart and Rust. It does not know what a VPN
> is, what a reseller is, or what your app is.

Every project that puts Flutter in front of a Rust core rewrites the same three
pieces, and gets the same three wrong. This package exists so they are written
once and tested once.

## What it solves

**The tokio bridge.** `flutter_rust_bridge`'s executor is not a tokio reactor.
A crate using `tokio::net` or `tokio::time` — a named pipe, a unix socket, a
timer — breaks if it runs directly on it. `dovetail_rust_core::run_on_runtime`
keeps a multi-thread runtime in a `OnceLock` and spawns on it, returning a
`JoinHandle` any executor can await.

**The slow `broadcast` consumer.** `receiver.recv()` returns
`Err(RecvError::Lagged)` when a subscriber falls behind, and the channel
**stays alive**. Writing `while let Ok(event) = receiver.recv().await` treats
that as end of stream and freezes the screen on the last state received.
`dovetail_rust_core::pump` tolerates `Lagged` and stops only on `Closed`.

**The platform with no binary.** Calling the bridge on Android, iOS or the web
has to produce an error you can read, not a `MissingPluginException` from three
layers down. `RustBridge.isSupported` answers before any native call, and
`ensureInitialized` is idempotent — and allows a retry if the first attempt
fails.

## What it does not do, as a rule

No application business rule goes in here. No domain DTO, no endpoint, no
validation, no dependency on a product crate. If a type in this package knows
the name of an entity in your app, somebody got it wrong.

The typed facade over your Rust core lives in **your** bridge package, which
depends on this one.

## Installation

```yaml
dependencies:
  dovetail_rust_core: ^0.1.0
```

And in your project's FFI crate `Cargo.toml`, from the repository:

```toml
dovetail_rust_core = { git = "https://github.com/mateussiqueira/dovetail" }
```

Pin it to a tag once you care about reproducibility:

```toml
dovetail_rust_core = { git = "https://github.com/mateussiqueira/dovetail", tag = "v0.1.2" }
```

The Rust side is **not on crates.io**, and that is deliberate: it exists to be
consumed by your FFI crate, from a public MIT repository, and a second registry
to keep in sync buys nothing. Cargo resolves a git dependency without you
cloning anything — measured: a crate outside this tree compiled against it with
nothing but the line above.

## Usage

On the Dart side, wrapping the `init` the generator produced for **your**
crate:

```dart
import 'package:dovetail_rust_core/dovetail_rust_core.dart';

final bridge = RustBridge(initializer: RustLib.init);

if (!bridge.isSupported) return;
await bridge.ensureInitialized();
```

A bridge that also holds on mobile declares that:

```dart
final bridge = RustBridge(
  initializer: RustLib.init,
  supportedPlatforms: <TargetPlatform>{...desktopPlatforms, ...mobilePlatforms},
);
```

On the Rust side, in your facade:

```rust
use dovetail_rust_core::{pump, run_on_runtime, runtime};

async fn run<T, E, F>(future: F) -> Result<T, MyFailure>
where
    T: Send + 'static,
    E: Into<MyFailure> + Send + 'static,
    F: std::future::Future<Output = Result<T, E>> + Send + 'static,
{
    match run_on_runtime(future).await {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error.into()),
        Err(bridge) => Err(MyFailure::from(bridge)),
    }
}
```

And for a stream of events:

```rust
runtime()?.spawn(async move {
    pump(source.subscribe(), |event| sink.add(MyEvent::from(event)).is_ok()).await;
});
```

## Surface

| Side | Item | What it is |
|---|---|---|
| Dart | `RustBridge` | platform probe + idempotent init |
| Dart | `UnsupportedPlatformException` | an error that names the platform and the guard to use |
| Dart | `desktopPlatforms` · `mobilePlatforms` | ready-made sets |
| Rust | `runtime()` | the shared tokio runtime |
| Rust | `run_on_runtime` | runs a future on it and returns the value |
| Rust | `pump` | a `broadcast` loop that tolerates lag |
| Rust | `BridgeError` | runtime unavailable, or a task that died |

## Development

```bash
flutter test
```

```bash
cd rust && cargo test
```

This package builds no native code: it is not a plugin, it has no `cargokit`
and no platform folder. What builds Rust is your project's bridge package.
