import 'dart:ui';

import 'package:dovetail_platform_channel/src/window/window_placement.dart';

const Size _minimumVisiblePatch = Size(96, 48);

abstract final class PlacementGuard {
  static WindowPlacement clampToScreens(
    WindowPlacement placement,
    List<Rect> screens,
  ) {
    final Offset? position = placement.position;
    final Size? size = placement.size;

    if (position == null || size == null) {
      return placement;
    }
    if (screens.isEmpty) {
      return _withoutPosition(placement);
    }

    final Rect window = Rect.fromLTWH(
      position.dx,
      position.dy,
      size.width,
      size.height,
    );

    final bool reachable = screens.any(
      (Rect screen) => _visibleEnough(window, screen),
    );

    return reachable ? placement : _withoutPosition(placement);
  }

  static bool _visibleEnough(Rect window, Rect screen) {
    final Rect overlap = window.intersect(screen);
    if (overlap.isEmpty) {
      return false;
    }
    return overlap.width >= _minimumVisiblePatch.width &&
        overlap.height >= _minimumVisiblePatch.height;
  }

  static WindowPlacement _withoutPosition(WindowPlacement placement) =>
      WindowPlacement(
        size: placement.size,
        position: null,
        maximized: placement.maximized,
        restoredSize: placement.restoredSize,
        restoredPosition: null,
      );
}
