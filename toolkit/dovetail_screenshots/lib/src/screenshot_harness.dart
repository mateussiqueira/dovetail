import 'dart:io' show File;
import 'dart:typed_data' show ByteData, Uint8List;
import 'dart:ui' as ui show Image, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dovetail_screenshots/src/screenshot_font.dart';
import 'package:dovetail_screenshots/src/screenshot_variant.dart';

typedef ScreenshotBuilder<S, T> = Widget Function(S screen, T state);

String screenLabel(Object value) =>
    value is Enum ? value.name : value.toString();

String stateLabel(Object value) =>
    value is Enum ? value.name : value.toString();

Future<void> pumpScreenshot(
  WidgetTester tester,
  Widget child, {
  required Key boundaryKey,
  Size viewSize = const Size(1440, 900),
  double devicePixelRatio = 1,
  int settleFrames = 10,
  Duration settleStep = const Duration(milliseconds: 120),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: child));

  for (int i = 0; i < settleFrames; i++) {
    await tester.pump(settleStep);
  }
}

Future<void> captureScreenshot(
  WidgetTester tester, {
  required Key boundaryKey,
  required String path,
  double pixelRatio = 2,
}) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    final Uint8List data = bytes!.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data);
  });
}

final class ScreenshotHarness<S extends Object, T extends Object> {
  ScreenshotHarness({
    required this.screens,
    required this.states,
    required this.build,
    this.prefix = '',
    this.outputDirectory = 'build/screenshots',
    this.viewSize = const Size(1440, 900),
    this.devicePixelRatio = 1,
    this.pixelRatio = 2,
    this.settleFrames = 10,
    this.settleStep = const Duration(milliseconds: 120),
    this.fonts = const <ScreenshotFont>[],
    this.variants = const <ScreenshotVariant>[],
  });

  final List<S> screens;
  final List<T> states;
  final ScreenshotBuilder<S, T> build;
  final String prefix;
  final String outputDirectory;
  final Size viewSize;
  final double devicePixelRatio;
  final double pixelRatio;
  final int settleFrames;
  final Duration settleStep;
  final List<ScreenshotFont> fonts;
  final List<ScreenshotVariant> variants;

  final Key _boundaryKey = UniqueKey();

  String fileNameFor(S screen, T state) {
    final String prefixPart = prefix.isEmpty ? '' : '$prefix-';
    return '$prefixPart${screenLabel(screen)}-${stateLabel(state)}';
  }

  void register() {
    final List<ScreenshotFont> declared = fonts.isEmpty
        ? <ScreenshotFont>[ScreenshotFont.materialIcons()]
        : fonts;

    setUpAll(() => loadScreenshotFonts(declared));

    for (final S screen in screens) {
      for (final T state in states) {
        final String name = fileNameFor(screen, state);
        testWidgets(name, (WidgetTester tester) async {
          await pumpScreenshot(
            tester,
            build(screen, state),
            boundaryKey: _boundaryKey,
            viewSize: viewSize,
            devicePixelRatio: devicePixelRatio,
            settleFrames: settleFrames,
            settleStep: settleStep,
          );
          await captureScreenshot(
            tester,
            boundaryKey: _boundaryKey,
            path: '$outputDirectory/$name.png',
            pixelRatio: pixelRatio,
          );
        });
      }
    }

    for (final ScreenshotVariant variant in variants) {
      testWidgets(variant.name, (WidgetTester tester) async {
        await pumpScreenshot(
          tester,
          variant.build(),
          boundaryKey: _boundaryKey,
          viewSize: viewSize,
          devicePixelRatio: devicePixelRatio,
          settleFrames: settleFrames,
          settleStep: settleStep,
        );
        await captureScreenshot(
          tester,
          boundaryKey: _boundaryKey,
          path: '$outputDirectory/${variant.name}.png',
          pixelRatio: pixelRatio,
        );
      });
    }
  }
}
