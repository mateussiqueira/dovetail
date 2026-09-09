# Changelog

## 0.1.1 — 2026-09-09

Nada no código mudou. A 0.1.0 foi publicada com o README em português e com
avisos que deixaram de ser verdade no momento em que o pacote saiu — "parte do
dovetail, versionado só localmente" era um deles. A página do pub.dev é
congelada na versão publicada, então esta versão existe para substituir o que
ela mostra.

O que muda: README em inglês no caminho canônico, com o português ao lado em
`README.pt-BR.md` e um seletor de idioma no topo dos dois. A instalação passa a
mostrar a dependência publicada em vez de um caminho para dentro do monorepo.

---

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
