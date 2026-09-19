import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dovetail_screenshots/dovetail_screenshots.dart';

void main() {
  testWidgets('captureScreenshot writes a real PNG file', (
    WidgetTester tester,
  ) async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'dovetail_shots',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final String path = '${temp.path}/home.png';

    await pumpScreenshot(
      tester,
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('home'))),
      ),
      boundaryKey: const ValueKey<String>('capture'),
    );
    await captureScreenshot(
      tester,
      boundaryKey: const ValueKey<String>('capture'),
      path: path,
    );

    final File file = File(path);
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync().take(8), <int>[
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

  testWidgets('a repeating animation does not hang the capture', (
    WidgetTester tester,
  ) async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'dovetail_shots',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    final String path = '${temp.path}/spinner.png';

    await pumpScreenshot(
      tester,
      const _Spinner(),
      boundaryKey: const ValueKey<String>('capture'),
    );
    await captureScreenshot(
      tester,
      boundaryKey: const ValueKey<String>('capture'),
      path: path,
    );

    expect(File(path).existsSync(), isTrue);
  });
}

final class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

final class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: FadeTransition(opacity: controller, child: const Text('spin')),
        ),
      ),
    );
  }
}
