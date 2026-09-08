# Changelog

## 0.1.0 — 2026-09-08

O canal entre o Flutter e o sistema operacional no desktop.

- `DesktopPlatform` com sete superfícies: janela, bandeja, item de login, deep
  link, notificação, abertura externa e informação de bundle.
- `PlatformCapability` e `PlatformCapabilities`: sonda no lugar de ramificação
  por plataforma dentro do app.
- Bandeja com menu como dado selado (`TrayCommand`, `TraySeparator`,
  `TraySubmenu`) e queda explícita do tooltip no Linux.
- `DesktopPlatformChannel.ensureInitialized` como ponto único de boot.
