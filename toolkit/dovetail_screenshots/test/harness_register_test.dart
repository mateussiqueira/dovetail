import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dovetail_screenshots/dovetail_screenshots.dart';

enum _Area { home }

enum _State { empty }

Widget _light() => const MaterialApp(
  home: Scaffold(body: Center(child: Text('light'))),
);

void main() {
  final Directory temp = Directory.systemTemp.createTempSync('dovetail_shots');

  final ScreenshotHarness<_Area, _State> harness =
      ScreenshotHarness<_Area, _State>(
        screens: _Area.values,
        states: _State.values,
        outputDirectory: temp.path,
        variants: const <ScreenshotVariant>[
          ScreenshotVariant(name: 'light', build: _light),
        ],
        build: (_, _) => const MaterialApp(
          home: Scaffold(body: Center(child: Text('home'))),
        ),
      );

  harness.register();

  testWidgets('the harness wrote the screen state and variant PNGs', (
    WidgetTester tester,
  ) async {
    final File screenShot = File('${temp.path}/home-empty.png');
    final File variantShot = File('${temp.path}/light.png');
    expect(screenShot.existsSync(), isTrue);
    expect(variantShot.existsSync(), isTrue);
    expect(screenShot.readAsBytesSync().take(8), <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
  });
}
