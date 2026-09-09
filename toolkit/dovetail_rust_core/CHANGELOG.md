# Changelog

## 0.1.2 — 2026-09-09

Nada no código mudou. O README instruía o consumidor a declarar o crate Rust
por `path`, e um caminho só resolve para quem clonou o repositório — enquanto
o pacote Dart, que exige esse crate, é instalado do pub.dev.

Agora a instrução é a dependência git do repositório público, que o Cargo
resolve sem clone nenhum. Medido: um crate fora desta árvore compilou contra
ele com nada além da linha `git = "https://github.com/mateussiqueira/dovetail"`.

O `publish = false` do `Cargo.toml` deixou de ser decisão herdada e passou a
ter o motivo escrito ao lado: o lado Rust não vai para o crates.io de
propósito, porque um segundo registro para manter em sincronia não compra nada
quando o repositório é MIT e público.

---

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
