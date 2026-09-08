# Changelog

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
