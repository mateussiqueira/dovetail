import 'package:flutter_test/flutter_test.dart';

import 'package:dovetail_screenshots/dovetail_screenshots.dart';

void main() {
  testWidgets('ScreenshotFont.materialIcons loads its family', (
    WidgetTester tester,
  ) async {
    await loadScreenshotFonts(<ScreenshotFont>[ScreenshotFont.materialIcons()]);
  });

  testWidgets('a font whose file candidates all miss does not throw', (
    WidgetTester tester,
  ) async {
    await loadScreenshotFonts(<ScreenshotFont>[
      ScreenshotFont.file('missing-monospace', <String>[
        '/does/not/exist/font.ttf',
        '/also/not/here.ttf',
      ]),
    ]);
  });
}
