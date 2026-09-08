# Changelog

## 0.1.0 — 2026-09-08

A camada de compatibilidade entre Dart e Rust, sem domínio de aplicação.

- `RustBridge`: sonda de plataforma e inicialização idempotente, por instância,
  com nova tentativa permitida após falha.
- `UnsupportedPlatformException`, `desktopPlatforms`, `mobilePlatforms`.
- Rust: `runtime()` e `run_on_runtime()`, a ponte entre um crate baseado em
  tokio e o executor do gerador de bindings.
- Rust: `pump()`, o loop de `broadcast` que tolera `RecvError::Lagged` em vez de
  tratar consumidor lento como fim de stream.
- Rust: `BridgeError`.
