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

O canal entre o Flutter e o sistema operacional no desktop.

- `DesktopPlatform` com sete superfícies: janela, bandeja, item de login, deep
  link, notificação, abertura externa e informação de bundle.
- `PlatformCapability` e `PlatformCapabilities`: sonda no lugar de ramificação
  por plataforma dentro do app.
- Bandeja com menu como dado selado (`TrayCommand`, `TraySeparator`,
  `TraySubmenu`) e queda explícita do tooltip no Linux.
- `DesktopPlatformChannel.ensureInitialized` como ponto único de boot.
