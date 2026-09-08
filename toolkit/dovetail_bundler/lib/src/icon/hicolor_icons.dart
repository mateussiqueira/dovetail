import 'dart:typed_data';

import 'package:dovetail_bundler/src/icon/icon_source.dart';

final class HicolorIcon {
  const HicolorIcon({required this.installedPath, required this.png});

  final String installedPath;
  final Uint8List png;
}

abstract final class HicolorIcons {
  static const List<int> freedesktopSizes = <int>[
    16,
    24,
    32,
    48,
    64,
    128,
    256,
    512,
  ];

  static const String themeRoot = '/usr/share/icons/hicolor';

  static List<HicolorIcon> fromSource({
    required IconSource source,
    required String appId,
    List<int> sizes = freedesktopSizes,
  }) => <HicolorIcon>[
    for (final int edge in sizes)
      HicolorIcon(
        installedPath: '$themeRoot/${edge}x$edge/apps/$appId.png',
        png: source.pngAt(edge),
      ),
  ];
}
