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

Atalho de teclado que o sistema entrega mesmo sem janela em foco.

- `ShortcutChord`: acorde canônico, com leitura das grafias que outras
  ferramentas escrevem (`Ctrl`, `Cmd`, `Super`, `Option`, `CmdOrCtrl`).
- `ShortcutPolicy`: recusa acorde sem modificador primário, `F12`, a tecla
  Windows no Windows, e Option-sozinho no macOS.
- `SessionProbe`: lê ambiente injetado, e `XDG_SESSION_TYPE` vence um `DISPLAY`
  presente — sob XWayland o `XGrabKey` teria sucesso e nunca disparado.
- `NativeShortcutSurface`: FFI escrita à mão sobre o crate `global-hotkey`, com
  `NativeCallable.listener` levando a tecla até o isolate.
- `DisabledShortcutSurface`: recusa tipada nomeando a sessão, para Wayland.
- Rust: `Registry`, `parse`, `pump`, `Backend`, `Status`.
