# Changelog

## 0.1.0

O mecanismo de captura de telas do desktop, extraído do app para ser reusável.

- `ScreenshotHarness<S, T>` captura uma tela por combinação screen × state,
  nomeada por `prefix` + `Enum.name` (ou `toString()`), com um
  `ScreenshotVariant` por captura avulsa.
- Fecha dois defeitos universais: o teste que trava porque um
  `AnimationController(..)..repeat()` nunca assenta (`pumpAndSettle` nunca
  retorna) e o ícone que renderiza caixa vazia porque só a fonte de texto foi
  carregada. O harness nunca chama `pumpAndSettle` — bombeia um número limitado
  de frames — e carrega `MaterialIcons` por padrão quando nenhuma fonte é
  declarada.
- `ScreenshotFont` modela fontes por asset, por arquivo do sistema (primeiro que
  existe, nenhum existir não é erro) e com fábricas prontas para `MaterialIcons`,
  `CupertinoIcons` e monospace de sistema.
- `loadScreenshotFonts`, `pumpScreenshot` e `captureScreenshot` expostos como
  funções top-level, de modo que cada passo é testável sem `register()`.
- A API não menciona produto nenhum: as telas e os estados são do consumidor.
