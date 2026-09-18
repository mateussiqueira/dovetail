import 'dart:io' show File;
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/services.dart' show FontLoader, rootBundle;

const List<String> _defaultMonospaceCandidates = <String>[
  '/System/Library/Fonts/SFNSMono.ttf',
  '/System/Library/Fonts/Supplemental/Andale Mono.ttf',
  '/System/Library/Fonts/Supplemental/Courier New.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
  '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
  '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
  r'C:\Windows\Fonts\consola.ttf',
  r'C:\Windows\Fonts\cour.ttf',
];

final class ScreenshotFont {
  const ScreenshotFont({
    required this.family,
    this.assets = const <String>[],
    this.files = const <String>[],
  });

  factory ScreenshotFont.assets(String family, List<String> assetPaths) =>
      ScreenshotFont(family: family, assets: assetPaths);

  factory ScreenshotFont.file(String family, List<String> candidatePaths) =>
      ScreenshotFont(family: family, files: candidatePaths);

  factory ScreenshotFont.materialIcons() => const ScreenshotFont(
    family: 'MaterialIcons',
    assets: <String>['fonts/MaterialIcons-Regular.otf'],
  );

  factory ScreenshotFont.cupertinoIcons() => const ScreenshotFont(
    family: 'CupertinoIcons',
    assets: <String>['fonts/CupertinoIcons.ttf'],
  );

  factory ScreenshotFont.systemMonospace({
    List<String> candidates = _defaultMonospaceCandidates,
  }) => ScreenshotFont(family: 'monospace', files: candidates);

  final String family;
  final List<String> assets;
  final List<String> files;
}

Future<void> loadScreenshotFonts(List<ScreenshotFont> fonts) async {
  for (final ScreenshotFont font in fonts) {
    final FontLoader loader = FontLoader(font.family);
    for (final String asset in font.assets) {
      loader.addFont(rootBundle.load(asset));
    }
    for (final String path in font.files) {
      final File file = File(path);
      if (!file.existsSync()) {
        continue;
      }
      final Uint8List bytes = await file.readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      break;
    }
    await loader.load();
  }
}
