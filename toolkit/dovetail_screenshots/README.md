# dovetail_screenshots

> Capture Flutter desktop screens as PNG files across every screen and state
> combination, without `pumpAndSettle` and without the icon fonts missing.

A widget test that screenshots a whole product has two failure modes that look
unrelated and are really one: it hangs, or it renders empty boxes. This package
is the reusable mechanism that closes both, extracted so a consumer declares
only its own screens and states.

## The two defects it closes

**A repeating animation hangs `pumpAndSettle` forever.** An
`AnimationController(..)..repeat()` never settles, so `pumpAndSettle()` never
returns and the suite times out. This package never calls `pumpAndSettle`: it
pumps a bounded number of frames (10, by default) and then captures whatever is
on screen. A spinner is exactly the kind of widget a screenshot has to capture,
and it is exactly the kind that cannot settle.

**An icon renders as an empty box because only the text font was loaded.** In a
widget test the default `MaterialIcons` font is not registered, so every `Icon`
draws nothing. Loading the icon font is the fix, and it is the default: a
harness with no `fonts` declared loads `ScreenshotFont.materialIcons()` on its
own, so the consumer gets it without knowing the fix exists.

## Installation

```yaml
dev_dependencies:
  dovetail_screenshots: ^0.1.0
```

## Usage

The consumer declares the screens and states it owns, and the build function
that turns a pair into a widget:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:dovetail_screenshots/dovetail_screenshots.dart';

enum Screen { home, settings }
enum State { empty, loading, ready }

void main() {
  ScreenshotHarness<Screen, State>(
    screens: Screen.values,
    states: State.values,
    prefix: 'dark',
    outputDirectory: 'build/screenshots',
    build: (screen, state) => _pageFor(screen, state),
  ).register();
}
```

`register()` does the rest: it loads the fonts once, then captures one PNG per
screen × state pair. Each file is named
`${prefix}${screenLabel}-${stateLabel}.png`, where enum values use their
`.name` and everything else uses `toString()`. With `prefix: 'dark'`, the pair
`Screen.home` × `State.empty` becomes `build/screenshots/dark-home-empty.png`.

A variant is a one-off capture that does not come from the screen × state
grid — for example the same screen under a light theme:

```dart
ScreenshotHarness<Screen, State>(
  screens: Screen.values,
  states: State.values,
  variants: const <ScreenshotVariant>[
    ScreenshotVariant(name: 'light-home', build: _lightHome),
  ],
  build: (screen, state) => _pageFor(screen, state),
).register();
```

The variant writes `build/screenshots/light-home.png`.

### Fonts

The `fonts` list tells the harness what to register before capturing. When it is
empty the default is `[ScreenshotFont.materialIcons()]`.

```dart
ScreenshotHarness<Screen, State>(
  fonts: const <ScreenshotFont>[
    ScreenshotFont.assets('Rubik', <String>[
      'fonts/Rubik-Regular.ttf',
      'fonts/Rubik-Bold.ttf',
    ]),
    ScreenshotFont.materialIcons(),
    ScreenshotFont.systemMonospace(),
  ],
  ...
).register();
```

- `ScreenshotFont.assets(family, paths)` loads each path through the asset
  bundle, exactly as `rootBundle.load` would.
- `ScreenshotFont.file(family, candidates)` reads the first candidate that
  exists on disk; if none exists it is not an error.
- `ScreenshotFont.materialIcons()` and `ScreenshotFont.cupertinoIcons()` bundle
  the two icon fonts this package ships.
- `ScreenshotFont.systemMonospace()` loads a monospace font from the first
  system path that exists on macOS, Linux or Windows.

### The three steps, exposed

`register()` is built on three top-level functions, so they are unit-testable
on their own:

```dart
await loadScreenshotFonts(fonts);

await pumpScreenshot(tester, child, boundaryKey: key);
await captureScreenshot(tester, boundaryKey: key, path: 'out/home.png');
```

`pumpScreenshot` mounts a keyed `RepaintBoundary` around the child, sets the
view size and pixel ratio, and pumps the bounded frame count. `captureScreenshot`
renders that boundary to PNG bytes and writes them to `path`. The key is how the
capture finds the harness's own boundary and never an inner one the widget
happens to contain.

## The capture contract

The defaults are the contract, and they stay exact so a product that re-runs
its captures reproduces them byte-identically:

| setting | default |
| --- | --- |
| view size | 1440 × 900 |
| device pixel ratio | 1 |
| capture pixel ratio | 2 |
| settle frames | 10 |
| settle step | 120 ms |

## What does not come in here

This is a mechanism, not a product. It does not know what a screen is, what a
state is, or what a theme is. The consumer declares all of them. Any product
term in the API would be a leak; there is none.

## Development

```bash
flutter pub get
flutter test
flutter analyze
```

Part of [dovetail](https://github.com/mateussiqueira/dovetail). MIT. The bundled
`MaterialIcons-Regular.otf` is Apache 2.0 and `CupertinoIcons.ttf` is MIT.
