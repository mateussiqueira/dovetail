import 'package:flutter_test/flutter_test.dart';

import 'package:dovetail_screenshots/dovetail_screenshots.dart';

enum _Area { home, settings }

enum _State { empty, loading }

final class _Named {
  const _Named(this.value);

  final String value;

  @override
  String toString() => value;
}

void main() {
  final ScreenshotHarness<_Area, _State> harness =
      ScreenshotHarness<_Area, _State>(
        screens: _Area.values,
        states: _State.values,
        build: (_, _) => throw UnimplementedError(),
      );

  test('fileNameFor uses Enum.name for enum screens and states', () {
    expect(harness.fileNameFor(_Area.home, _State.empty), 'home-empty');
  });

  test('fileNameFor prepends the prefix when one is given', () {
    final ScreenshotHarness<_Area, _State> withPrefix =
        ScreenshotHarness<_Area, _State>(
          screens: _Area.values,
          states: _State.values,
          prefix: 'dark',
          build: (_, _) => throw UnimplementedError(),
        );
    expect(withPrefix.fileNameFor(_Area.home, _State.empty), 'dark-home-empty');
  });

  test('fileNameFor falls back to toString for values that are not enums', () {
    final ScreenshotHarness<_Named, _State> named =
        ScreenshotHarness<_Named, _State>(
          screens: const <_Named>[_Named('vpn')],
          states: _State.values,
          build: (_, _) => throw UnimplementedError(),
        );
    expect(named.fileNameFor(const _Named('vpn'), _State.empty), 'vpn-empty');
  });
}
