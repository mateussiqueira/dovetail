import 'dart:math' as math;
import 'dart:ui';

import 'package:dovetail_platform_channel/src/panel/panel_spec.dart';

abstract final class PanelGeometry {
  static PanelPlacement place({
    required Offset anchor,
    required Size size,
    required Rect workArea,
    double gap = 8,
  }) {
    final double maxWidth = math.max(workArea.width - gap * 2, 1);
    final double maxHeight = math.max(workArea.height - gap * 2, 1);
    final Size fitted = Size(
      math.min(size.width, maxWidth),
      math.min(size.height, maxHeight),
    );
    final bool shrunk = fitted != size;

    final PanelSide side = _side(anchor, fitted, workArea, gap);

    final double top = _clamp(
      _topFor(side, anchor, fitted, gap),
      workArea.top + gap,
      workArea.bottom - gap - fitted.height,
    );
    final double left = _clamp(
      anchor.dx - fitted.width / 2,
      workArea.left + gap,
      workArea.right - gap - fitted.width,
    );

    return PanelPlacement(
      bounds: Rect.fromLTWH(left, top, fitted.width, fitted.height),
      side: side,
      shrunk: shrunk,
    );
  }

  static PanelSide _side(Offset anchor, Size size, Rect workArea, double gap) {
    final double roomBelow = workArea.bottom - anchor.dy - gap * 2;
    final double roomAbove = anchor.dy - workArea.top - gap * 2;

    if (roomBelow >= size.height) {
      return PanelSide.below;
    }
    if (roomAbove >= size.height) {
      return PanelSide.above;
    }
    return roomBelow >= roomAbove ? PanelSide.below : PanelSide.above;
  }

  static double _topFor(PanelSide side, Offset anchor, Size size, double gap) =>
      side == PanelSide.below ? anchor.dy + gap : anchor.dy - gap - size.height;

  static double _clamp(double value, double low, double high) =>
      high < low ? low : math.min(math.max(value, low), high);
}
